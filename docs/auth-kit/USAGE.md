# 使用手册：拦截语义与 API 逐个讲解

本文回答三个最常见的问题：默认拦不拦截所有方法？怎么取当前用户 id？每个 API 具体怎么用？

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
