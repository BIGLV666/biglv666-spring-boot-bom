# 集成指南：与四件套咬合 + 实战案例

auth-kit 是「四件套」中的认证层。本文说明它与其他三个组件的组合方式，以及 PaperWise 真实项目的完整接入过程。

## 1. 与 web-common 咬合：鉴权失败统一 Result

类路径存在 web-common 时自动激活 `AuthKitWebCommonExceptionHandler`（优先级最高，业务零 try-catch）：

| 异常 | 映射 |
|---|---|
| NotLoginException | `Result.fail(ResultCode.UNAUTHORIZED=40100)` |
| NotPermissionException / NotRoleException | `Result.fail(ResultCode.FORBIDDEN=40300)` |
| LoginLockedException | `Result.fail(ResultCode.UNAUTHORIZED=40100)` + 锁定文案 |

被顶下线（BE_REPLACED）时 message 使用 `auth-kit.session.kicked-out-message` 配置文案。

类路径没有 web-common 时，自动注册原生兜底：401/403 状态码 + `{code, message}` 简单 JSON。两者互斥装配，业务方也可注册自己的 Handler Bean 全量替换。

注意：web-common 将 spring-boot-starter-validation 声明为 provided 不传递，宿主项目通常已有；若启动报 `NoClassDefFoundError: jakarta/validation/ConstraintViolation`，补一个 validation 依赖即可。

## 2. 与 api-governance 咬合

- **管理端鉴权同思路**：auth-kit 的 `ManagementTokenFilter` 与 api-governance 的 `GovernanceManagementAuthFilter` 是同一模式（OncePerRequestFilter + 配置静态令牌 + 常量时间比较 + 401 不回显细节）。两套管理端点可共存，令牌与路径独立配置。
- **治理日志带用户上下文**：api-governance 若需在日志/指标中记录当前用户，从 `AuthContext.getUserId()` 取（两者都是 ThreadLocal，请求线程内直接可读）。

## 3. 与 concurrent-guard 咬合：防重放组合范式

幂等注解防的是「同一操作重复提交」，登录态防的是「谁在操作」。两者组合的推荐范式：

```java
@RequireLogin                                    // 谁在操作
@PostMapping("/order/pay")
@Idempotent(key = "'pay:' + #userId + ':' + #orderId",  // 同人同单不重复
            ttl = 10, timeUnit = TimeUnit.SECONDS)
public Result<Void> pay(Long orderId) { ... }
```

要点：幂等 key 必须包含登录用户标识（从 AuthContext 取），否则 A 用户的请求会命中 B 用户的幂等锁。防爆破 `LoginAttemptGuard` 则在认证入口（登录接口）与 concurrent-guard 各司其职：前者按标识限次数，后者按操作防重放。

## 4. 与 OutboxPro 咬合：事件操作者约定

事件 payload 中记录操作者的规范写法——发布事件前从认证上下文取：

```java
outboxService.publish(OrderCreatedEvent.builder()
        .orderId(orderId)
        .operatorId(AuthKit.isLogin() ? AuthKit.getLoginIdAsLong() : null)  // 约定字段
        .build());
```

约定 `operatorId` 为可空：系统任务/定时触发的事件没有登录态。消费侧审计时以 operatorId 为准回溯操作链。

## 5. 实战案例：PaperWise 从 JWT 迁移到 auth-kit

[PaperWise](../../PaperWise)（学习卡片平台，Boot 3.5.14 / Java 17 / Redis + MySQL + MyBatis-Plus）原方案为 jjwt HS256 无状态 token。迁移总改动 **5 个文件**，业务 Controller 零改动。

### 5.1 迁移前状态

- 登录：`UserController.login()` 校验 BCrypt 密码后 `jwtUntil.generateToken(userid, username)`
- 鉴权：`LoginInterceptor` 解析 JWT → `request.setAttribute("userid")` + `UserContext`(ThreadLocal)
- 痛点：无法登出（无状态）、无法踢人、无法顶号、密钥泄露即全局沦陷

### 5.2 改动明细

**pom.xml** —— 引入组件（jjwt 保留，迁移期可回滚）：

```xml
<dependency>
    <groupId>io.github.biglv666</groupId>
    <artifactId>auth-kit-spring-boot-starter</artifactId>
    <version>0.1.0</version>
</dependency>
```

**UserController** —— 登录发放会话 token + 补上真实登出：

```java
// 原：String Token = jwtUntil.generateToken(user.getUserid(), username);
String Token = AuthKit.login(user.getUserid(), DeviceType.WEB);   // 同端自动顶号

@PostMapping("/logout")                                            // 新增（JWT 时代做不到）
public Result<String> logout() {
    AuthKit.logout();
    return Result.success("登出成功");
}
```

**LoginInterceptor** —— 校验端委托 auth-kit，保持既有契约（所有业务 Controller 的 `@RequestAttribute Long userid` 不动）：

```java
// 委托 auth-kit：会话校验 + 活跃续期；被踢/被顶/过期有专用错误语义
AuthSession session;
try {
    session = AuthKit.getAuthManager().checkLogin(token);
} catch (NotLoginException e) {
    response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);   // 先 sendError 会吞掉响应体
    response.setContentType("text/plain;charset=UTF-8");
    response.getWriter().write(e.getMessage());
    return false;
}
Long userid = Long.parseLong(session.getUserId());
request.setAttribute("userid", userid);
UserContext.setUserId(userid);
```

**application.yml**：

```yaml
auth-kit:
  token:
    timeout: 7d          # 对齐原 jwt.expiration=604800000
    active-timeout: 1d   # 滑动续期：1 天无活动即失效
  session:
    max-sessions-per-device: 1
  whitelist:             # 对齐原 WebConfig 放行清单
    - /paperwise/user/login
    - /paperwise/user/register
    - /paperwise/user/activation
    - /paperwise/share/**
    - /doc.html
    - /v3/api-docs/**
    - /swagger-ui/**
    - /swagger-ui.html
    - /swagger-resources/**
    - /webjars/**
```

**WebConfig** —— 移除 `/paperwise/user/logout` 的拦截排除（登出需要登录态才能定位会话）。

### 5.3 真实环境实测（localhost + Redis + MySQL）

| 场景 | 请求序列 | 结果 |
|---|---|---|
| 登录 | POST /login（密码校验通过） | ✅ 200，返回 64 字符不透明 token |
| 合法访问 | GET /favorites/getallfavorites + token | ✅ 200，进入 Controller |
| 未登录 | 同上，无 token | ✅ 401「未登录」 |
| 伪造 token | 同上，Bearer fake-token-xyz | ✅ 401「登录凭证无效」 |
| **同端顶号** | 二次登录后用旧 token 访问 | ✅ 401「您的账号在其他设备登录」 |
| **真实登出** | POST /logout 后旧 token 再访问 | ✅ 401（Redis 会话已销毁） |

### 5.4 迁移经验

1. **拦截器委托式接入改动最小**：不改业务 Controller 的取参方式，`LoginInterceptor` 内部把 JWT 解析换成 `checkLogin`，一行契约不变。
2. **白名单要两边对齐**：auth-kit 白名单（软放行）与业务拦截器 exclude 清单保持一致，否则会出现"业务拦截器放行但 auth-kit 软解析失败"的隐性行为差异。
3. **logout 端点必须过拦截器**：从白名单移除，否则 ThreadLocal 无 token，登出变 no-op。
4. **响应体先 setStatus 后 write**：`sendError()` 会提交响应，之后的写入被吞，前端拿到空 body（PaperWise 原有 bug，迁移时修复）。
5. **双拦截器冗余可接受**：auth-kit 拦截器（无注解时软解析）与业务拦截器各跑一次 `checkLogin`，多一次 Redis 往返；追求极致可在业务拦截器改读 `AuthContext`。
