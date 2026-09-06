# 使用手册：拦截语义与 API 逐个讲解

本文回答三个最常见的问题：默认拦不拦截所有方法？怎么取当前用户 id？每个 API 具体怎么用？

> V1.0.0 新增：记住我、二级认证 `@RequireSafe`、JWT 可选模式、按设备会话上限，见第 5-8 节。

## 1. 默认拦截语义：注册所有路径，默认不拦任何请求

拦截器注册在 `/**` 上，但对一个方法做什么是**由注解决定的**，分三档：

| 档位 | 条件 | 行为 |
|---|---|---|
| 白名单 | 路径命中 `auth-kit.whitelist`（Ant 风格） | 完全跳过，不解析 token |
| 软解析（默认档） | 方法上**没有任何鉴权注解** | 带有效 token → 填充上下文（`@CurrentUser` 可用）；没带/无效 → 放行 |
| 强制校验 | 方法或类上有 `@RequireLogin` / `@RequirePermission` / `@RequireRole` | 未登录/token 失效/权限不足 → 抛异常 → 401/403 |

三条推论：

1. **零注解 = 所有接口匿名可访问**（但带 token 依然能拿到登录人），安全边界由你用注解逐个画；
2. 权限/角色注解**隐含登录校验**，不用再加 `@RequireLogin`；
3. 类级 + 方法级注解同时存在时**取"与"关系**（两级都要满足，各自按自己的 mode），方法级不会意外放宽类级；`@AuthIgnore` 仅方法级生效，覆盖一切注解。

对比旧式"全局拦截 + 白名单排除"：如果想要默认全拦，在 Controller 类上加 `@RequireLogin`（一次管一类），或像 PaperWise 一样保留业务拦截器做总闸、auth-kit 只管会话（见 [INTEGRATION.md](INTEGRATION.md)）。

### 软解析的意义

没有注解的端点带无效 token 不会被拒——这是故意的（公开接口带个过期 token 不该 403）。但**有效 token 会被解析并填充上下文**，所以"游客可浏览、登录后显示个人化内容"的接口直接写：

```java
@GetMapping("/feed")
public Result<?> feed(@CurrentUser(required = false) AuthUser user) {
    return Result.ok(user == null ? publicFeed() : personalizedFeed(user.getUserIdAsLong()));
}
```

## 2. 取当前用户 id 的四种方式

前提：请求带了有效 token（登录后调用的接口都满足）。推荐顺序从上到下：

```java
// ① 参数注入（Controller 首选，可直接测试、无静态依赖）
@GetMapping("/me")
public Result<ProfileVO> me(@CurrentUser AuthUser user) {
    Long   userId = user.getUserIdAsLong();  // Long 形式
    String uid    = user.getUserId();        // String 形式（组件内部统一用 String）
    String device = user.getDevice();        // 登录设备
}

// ② 静态门面（Service / 任意层可用）
Long userId = AuthKit.getLoginIdAsLong();    // 未登录抛 NotLoginException
String uid  = AuthKit.getLoginId();

// ③ 先判断再取（登录可选逻辑）
if (AuthKit.isLogin()) { Long uid = AuthKit.getLoginIdAsLong(); }

// ④ 登录可选注入（未登录给 null 而不是抛异常）
public Result<?> page(@CurrentUser(required = false) AuthUser user) { ... }
```

注意事项：

- `getLoginId()` 未登录时抛 `NotLoginException`，不确定时先 `isLogin()` 或用 `required = false`；
- 底层是 ThreadLocal，**`@Async` / 自建线程池拿不到**——提交任务前先取出来当参数传：

```java
Long uid = AuthKit.getLoginIdAsLong();          // 主线程取
executor.submit(() -> orderService.process(uid)); // 作为参数传给异步任务
```

## 3. API 逐个讲解（按登录时序）

### 3.1 登录：`AuthKit.login(...)`

业务自己验密，auth-kit 负责签发会话。三个重载只是设备标识形式不同：

```java
AuthKit.login(10001L);                       // 默认设备 "PC"
AuthKit.login(10001L, DeviceType.APP);       // 内置枚举：PC / APP / MINI_PROGRAM / WEB
AuthKit.login(10001L, "HarmonyOS");          // 任意自定义字符串（别包含 |）
```

返回 token 交给前端。副作用：写 Redis 会话 + 反查索引；若该用户该设备已有会话且 `max-sessions-per-device=1`，旧会话被顶（旧端收 BE_REPLACED 语义）。

### 3.2 请求校验：`AuthKit.checkLogin()`

校验当前请求的 token 并推进活跃时间（滑动续期）。拦截器已自动做，业务代码只在"注解管不住的编程式场景"才需要调。

### 3.3 权限/角色校验

注解版（拦截器自动执行）：

```java
@RequirePermission("order:delete")                                  // 单个，等价 ALL
@RequirePermission(value = {"a", "b"}, mode = AuthMode.ALL)          // 全部满足
@RequirePermission(value = {"a", "b"}, mode = AuthMode.ANY)          // 满足其一
@RequireRole("admin")                                                // 角色同构
```

编程版（同一套校验逻辑，供非注解场景）：

```java
AuthKit.checkPermission("order:delete");              // 不满足抛 NotPermissionException
AuthKit.checkPermissions(List.of("a","b"), AuthMode.ANY);
AuthKit.checkRole("admin");
AuthKit.checkRoles(List.of("admin","ops"), AuthMode.ANY);
boolean ok = AuthKit.hasPermission("order:delete");   // 布尔版，不抛异常
```

权限数据来自业务实现的 `PermissionProvider`（见 [CONFIGURATION.md](CONFIGURATION.md) 扩展点一节）。未配置该 Bean 时，权限/角色校验一律拒绝（fail-closed），纯登录制项目不受影响。

### 3.4 登出：`AuthKit.logout()`

销毁当前请求的 Redis 会话。注意 **logout 端点不要放进白名单**——放进白名单后拦截器不解析 token，`AuthKit.logout()` 拿不到当前会话，变成 no-op。

### 3.5 踢人/下线：`kickout` / `forceLogout` / `listSessions`

```java
AuthKit.kickout(10001L, DeviceType.APP);   // 踢 APP 端，旧端收 401「您已被强制下线」
AuthKit.kickout(10001L, null);             // null = 踢全部设备
AuthKit.forceLogout(10001L, null);         // 强制下线：不写墓碑，旧端收「登录凭证无效」
List<AuthSession> sessions = AuthKit.listSessions(10001L, null);  // 在线会话（含设备/登录时间）
```

三个操作都幂等，对已不存在的会话调用返回成功。区分：`kickout` 让旧端**知道自己是被踢的**（写墓碑），`forceLogout` 静默失效（管理端清理场景用）。

### 3.6 防爆破：`LoginAttemptGuard`（Bean 注入后三段式插桩）

```java
@Autowired LoginAttemptGuard loginGuard;

@PostMapping("/login")
public Result<?> login(String username, String password) {
    loginGuard.check(username);              // ① 锁定中 → 抛 LoginLockedException
    User user = userService.verify(username, password);
    if (user == null) {
        loginGuard.recordFailure(username);  // ② 失败累计（第 5 次起锁定 15 分钟）
        return Result.error("用户名或密码错误");
    }
    loginGuard.recordSuccess(username);      // ③ 成功清零
    return Result.ok(Map.of("token", AuthKit.login(user.getId(), DeviceType.APP)));
}
```

计数在 Redis（固定窗口），多实例共享；无 Redis 自动降级内存。`fail-max-attempts<=0` 完全关闭。

## 5. 记住我

```java
String token = AuthKit.login(userId, DeviceType.WEB, true);   // 第三个参数 rememberMe
```

- remember 会话使用 `auth-kit.token.remember-timeout`（默认 30d）作为绝对有效期，普通会话仍用 `timeout`
- 活跃超时判定两种会话一致（长期不活动照样过期）
- 配合 `cookie-name` 配置把 remember token 放 Cookie，实现"关浏览器不丢登录态"

## 6. 二级认证（@RequireSafe）

敏感操作（改密/支付/注销）三步走：

```java
// ① 敏感端点标注解（隐含登录校验）
@RequireSafe
@PostMapping("/change-password")
public Result<?> changePassword() { ... }

// ② 业务方先重新验密，成功后开启安全态
@PostMapping("/verify-password")
public Result<?> verify(String password) {
    if (myEncoder.matches(password, currentUser.getPassword())) {
        AuthKit.openSafe();          // 安全态开启，默认 5 分钟内免二次
        return Result.ok();
    }
    return Result.error("密码错误");
}

// ③ 有效期内访问 @RequireSafe 端点放行；未开启 → NotSafeException（403"需要安全验证"）
AuthKit.isSafe();      // 查询当前安全态
AuthKit.closeSafe();   // 敏感操作完成后主动关闭
```

窗口时长配置 `auth-kit.safe.duration`（默认 5m）。安全态存 Redis（多实例共享），按 **userId** 维度——换设备同样生效。

## 7. JWT 可选模式

```yaml
auth-kit:
  token:
    mode: jwt
    jwt-secret: "至少16字符的强随机密钥"
```

| 维度 | opaque（默认） | jwt |
|---|---|---|
| 凭证 | 64 字符随机串 | HS256 签名 JWT（纯 JDK 实现，零依赖） |
| 每次请求校验 | 读会话（3 次 Redis 往返） | 本地验签 + 查墓碑（1 次 Redis 往返） |
| 滑动续期/活跃超时 | ✅ | ❌（不读会话，无活跃数据） |
| 踢人/顶号/登出 | ✅ | ✅（经由墓碑黑名单，语义完全一致） |
| 在线会话列表 | 实时 | 从凭证 claims 还原（登录时间来自 iat） |
| 密钥泄露影响 | Redis 被攻破才可伪造 | 密钥泄露可伪造任意用户，务必保密并支持轮换 |

凭证唯一性由内部 jti（随机 token）保证——同一秒内同用户同设备重复登录也会得到不同凭证。

## 8. 会话并发治理

```yaml
auth-kit:
  session:
    max-sessions-per-device: 1        # 全局默认
    device-max-sessions:              # 按设备覆盖
      APP: 3                          # APP 允许 3 台
      MINI_PROGRAM: 2
```

管理端点：

```bash
curl -H "X-Auth-Kit-Token: xxx" "http://host/auth-kit/online?userId=10001"          # 在线会话
curl -X DELETE -H "X-Auth-Kit-Token: xxx" "http://host/auth-kit/online/10001?device=APP"  # 强制下线（静默）
curl -X POST  -H "X-Auth-Kit-Token: xxx" "http://host/auth-kit/online/10001/kick"   # 踢人（旧端收"被强制下线"文案）
```

## 9. OAuth2 / SSO

三个能力共用一套会话体系，默认全关、互不依赖：

### 9.1 轻量授权服务器（给别人发令牌）

```yaml
auth-kit:
  oauth2:
    server:
      enabled: true
      login-page: /login              # 未登录时跳业务登录页，登录后回 authorize 地址
      clients:
        app1:
          client-secret: "app1-secret"
          redirect-uris: [ "https://app1.example/cb" ]   # 精确匹配，防开放重定向
          scopes: [ "profile" ]
```

流程：`GET /oauth2/authorize`（已登录签发授权码回跳；未登录跳 login-page）→
`POST /oauth2/token`（`grant_type=authorization_code` 或 `refresh_token`，refresh 轮换）。

**关键设计：签发的 access_token 就是 auth-kit 会话凭证**——第三方应用拿它直接访问你的
受保护接口，现有拦截链/注解/权限校验零改动；device 维度为 `OAuth2:{clientId}`，
管理端点可按应用查看/踢出在线令牌。授权码一次性消费（Redis GETDEL 原子防重放）。

### 9.2 第三方登录（让别人给你发令牌）

```yaml
auth-kit:
  oauth2:
    client:
      enabled: true
      success-redirect: "/sso-done"   # 登录成功落地页（token 附在查询参数）
      providers:
        github:
          client-id: xxx
          client-secret: xxx
          redirect-uri: "https://your-app/oauth2/callback/github"
        wecom:
          corp-id: "ww-xxx"
          corp-secret: xxx
          agent-id: "1000002"
          redirect-uri: "https://your-app/oauth2/callback/wecom"
```

```java
// 唯一必配的 Bean：第三方档案 → 本地 userId（查绑定表，可自动建号）
@Bean
public OAuth2UserBinder oauth2UserBinder() {
    return profile -> userBindService.findUserId(profile.provider(), profile.openId());
}
```

用户入口 `GET /oauth2/login/github` → 平台授权 → 回调 `/oauth2/callback/github`
（state 防 CSRF + 单次消费）→ 绑定 → 签发本站会话。内置 GitHub 与企业微信；
其他平台实现 `IdentityProvider`（authorizeUrl + exchange 两方法）注册 Bean 即接入。

### 9.3 SSO（单点登录）

多应用指向同一 Redis（相同 `session.key-prefix`）即共享会话；配合 9.1，把授权服务器
部署在独立认证域名，各业务应用作为 9.2 的 client 接入，即完成"一次登录、处处通行"。
任一应用登出/被踢，凭证全局失效；应用本地清理可监听 `AuthKitSessionEvent`
（LOGOUT / KICKED_OUT / FORCED_LOGOUT / REPLACED）。

### 3.7 管理端点（现成 HTTP 接口，默认关闭）

```yaml
auth-kit:
  management:
    enabled: true
    auth-token: "换成强随机串"
```

```bash
# 查某人在线会话（token 脱敏显示）
curl -H "X-Auth-Kit-Token: 换成强随机串" \
     "http://host:port/auth-kit/online?userId=10001&device=APP"

# 强制下线
curl -X DELETE -H "X-Auth-Kit-Token: 换成强随机串" \
     "http://host:port/auth-kit/online/10001"
```

令牌错误一律 401 且不回显细节。`base-path`、`auth-header` 均可配置。

## 4. 异常出口：业务代码零 try-catch

注解校验和 `checkXxx` 抛出的异常不用捕获：

| 类路径 | NotLoginException | NotPermissionException / NotRoleException | LoginLockedException |
|---|---|---|---|
| 有 web-common | Result，code=40100（BE_REPLACED 用 `kicked-out-message` 文案） | Result，code=40300 | Result，code=40100 + 锁定文案 |
| 无 web-common | HTTP 401 + `{code:401,message}` | HTTP 403 + `{code:403,message}` | HTTP 401 |

前端凭 NotLoginException 的 reason 字段区分处理，对照表见 [README](../README.md#下线语义对照前端处理指南)。
