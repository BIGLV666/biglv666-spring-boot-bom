# auth-kit-spring-boot-starter

轻量级认证鉴权组件：**不透明 token + 有状态会话**，支持踢人下线、同端互斥、滑动续期、登录防爆破。
**不带用户表**——auth-kit 只管认证与校验，用户数据通过 SPI 对接你自己的表。

> 与 Sa-Token 同路线（服务端持有会话状态），但更克制：五条 SPI、五个可选依赖、零配置可跑。
> 与 RuoYi 类平台相反：不内置 user/role/permission 表，不跟业务库打架。

文档导航：[使用手册](docs/USAGE.md)（拦截语义/API 逐个讲解） · [架构设计](docs/DESIGN.md)（数据模型/时序/决策记录） · [配置全参考](docs/CONFIGURATION.md) · [集成指南](docs/INTEGRATION.md)（四件套咬合 + PaperWise 实战）

## 为什么是有状态会话而不是 JWT

踢人下线、同端互斥、滑动续期、强制登出，本质都要求服务端持有会话状态。JWT 无状态，实现这些只能靠黑名单补丁——用更复杂的机制实现回有状态，还引入密钥管理问题。JWT 模式将作为 V1.5 可选补充（附代价说明）。

## 功能矩阵

| 能力 | 说明 |
|---|---|
| 登录/登出/登录态 | `AuthKit.login()` 静态门面；会话含 userId、设备、登录/最后活跃时间 |
| token 签发解析 | SecureRandom 64 字符 base64url；Header（Bearer 前缀）/Cookie 双支持 |
| Redis 会话存储 | `SessionDao` SPI；Hash 存会话 + ZSet 反查索引 + 墓碑记录踢出原因 |
| 内存会话降级 | 无 Redis 自动切换（启动 WARN 提示），仅限本地开发 |
| 滑动续期 + 活跃超时 | 活跃时间自动推进；与绝对有效期**两个独立维度**，互不污染 |
| 踢人下线 | 按 userId（可选设备维度）；被踢端收到 KICKED_OUT 专用语义 |
| 同端互斥/多端上限 | `max-sessions-per-device`：1=顶号 / -1=不限 / n=保留最近 n 个 |
| 注解体系 | `@RequireLogin` `@RequirePermission` `@RequireRole`(ALL/ANY) `@AuthIgnore`，类级+方法级取"与" |
| 鉴权拦截器 | 白名单 Ant 匹配、注解解析缓存、软解析（无注解端点带 token 也能注入上下文） |
| @CurrentUser + AuthContext | 参数解析器注入；校验全过后才填充 ThreadLocal（防串号），afterCompletion 强制清理 |
| 五种下线语义 | NO_TOKEN / TOKEN_INVALID / TOKEN_TIMEOUT / KICKED_OUT / BE_REPLACED |
| 异常统一出口 | 有 web-common → Result(40100/40300)；无 → 原生 401/403 |
| BCrypt + PasswordEncoder SPI | 类路径有 spring-security-crypto 自动提供，否则业务自配 |
| 登录防爆破 | `LoginAttemptGuard` 三段式插桩，Redis 计数、内存降级 |
| 管理端点 | 在线会话查询/强制下线；静态令牌保护，默认关闭，启用必须配令牌 |

## 快速开始

### 1. 引入依赖

```xml
<dependency>
    <groupId>io.github.biglv666</groupId>
    <artifactId>auth-kit-spring-boot-starter</artifactId>
    <version>0.1.0</version>
</dependency>
```

### 2. 实现权限 SPI（唯一必配项）

```java
@Bean
public PermissionProvider permissionProvider() {
    return new PermissionProvider() {
        @Override
        public Set<String> getPermissions(String userId) {
            return permissionMapper.selectCodesByUserId(Long.parseLong(userId)); // 查你自己的表
        }
        @Override
        public Set<String> getRoles(String userId) {
            return roleMapper.selectCodesByUserId(Long.parseLong(userId));
        }
    };
}
```

纯登录制（无权限概念）可不实现——两个方法均有空集默认实现。

### 3. 登录（密码校验由业务完成）

```java
if (passwordEncoder.matches(rawPassword, user.getPassword())) {
    String token = AuthKit.login(user.getId(), DeviceType.APP);
    return Result.ok(Map.of("token", token));
}
```

### 4. Controller 鉴权

```java
@RequirePermission(value = {"order:delete", "order:admin"}, mode = AuthMode.ANY)
@DeleteMapping("/order/{id}")
public void delete(@PathVariable Long id) { ... }

@GetMapping("/me")
public Result<ProfileVO> me(@CurrentUser AuthUser user) {
    return Result.ok(profileService.of(user.getUserIdAsLong()));
}
```

前端携带：`Authorization: Bearer {token}`。

## AuthKit 完整 API

```java
// ── 登录态 ──
AuthKit.login(Object userId)                          // 默认设备 PC，返回 token
AuthKit.login(Object userId, DeviceType deviceType)   // 内置设备类型
AuthKit.login(Object userId, String device)           // 自定义设备标识
AuthKit.logout()                                      // 登出当前请求
AuthKit.logout(String token)                          // 登出指定 token
AuthKit.kickout(Object userId, String device)         // 踢人（device=null 全端），旧端收 KICKED_OUT
AuthKit.kickout(Object userId, DeviceType deviceType)
AuthKit.forceLogout(Object userId, String device)     // 强制下线（无墓碑）
AuthKit.listSessions(Object userId, String device)    // 在线会话列表

// ── 当前登录态（基于 ThreadLocal）──
AuthKit.getLoginId() / getLoginIdAsLong() / isLogin()

// ── 校验 ──
AuthKit.checkLogin()                                  // 校验 + 活跃续期
AuthKit.checkPermission(String permission)
AuthKit.checkPermissions(List<String>, AuthMode)      // ALL / ANY
AuthKit.checkRole(String role)
AuthKit.checkRoles(List<String>, AuthMode)
AuthKit.hasPermission(String) / hasRole(String)       // 布尔版，不抛异常
```

## 架构总览

```
业务代码 ──► AuthKit 门面 ──► AuthManager（核心）
                                │
   注解请求 ──► AuthInterceptor ─┤──► AuthContext(ThreadLocal) ──► @CurrentUser
                                │
                                ▼
                     SessionDao / AttemptStore（SPI）
                     ├── RedisSessionDao（生产默认，自动启用）
                     └── InMemorySessionDao（无 Redis 降级）
```

Redis key 设计与会话状态机详见 [DESIGN.md](docs/DESIGN.md)。

## 配置

零配置可跑（默认：Authorization + Bearer、30d 绝对有效期 + 7d 活跃超时、顶号、防爆破 5 次/15m、白名单 /login 与 /actuator/**）。

常用定制见 [CONFIGURATION.md](docs/CONFIGURATION.md)（全部配置项 + 环境示例 + 扩展点替换），常用两项：

```yaml
auth-kit:
  token:
    timeout: 7d
    active-timeout: 1d
  session:
    max-sessions-per-device: 1
  whitelist:
    - /login
```

## 下线语义对照（前端处理指南）

| reason | 场景 | 前端建议 |
|---|---|---|
| `NO_TOKEN` | 请求未携带 token | 跳转登录 |
| `TOKEN_INVALID` | token 不存在/非法/被强制下线 | 跳转登录 |
| `TOKEN_TIMEOUT` | 超过活跃超时 | 提示后跳转登录 |
| `KICKED_OUT` | 管理员踢人 | 提示「已被强制下线」 |
| `BE_REPLACED` | 同端新登录顶号 | 提示 `kicked-out-message` |

## 扩展点

| SPI | 职责 | 默认实现 | 替换方式 |
|---|---|---|---|
| `SessionDao` | 会话存储 | Redis（自动）/内存（降级） | 注册同类型 Bean |
| `AttemptStore` | 失败计数 | Redis（自动）/内存（降级） | 注册同类型 Bean |
| `TokenGenerator` | token 形态 | SecureRandom 64 字符 | 注册同类型 Bean |
| `PermissionProvider` | 权限数据源 | 无（业务必配） | 注册同类型 Bean |
| `PasswordEncoder` | 密码编码 | BCrypt（需 security-crypto） | 注册同类型 Bean |

## 测试与质量

- **64 个测试全绿**：会话存储契约测试基类让内存/Redis 两套实现跑同一套用例（互为交叉验证）；Redis 用例直连真实 Redis（不可用时自动跳过）
- **可注入时钟**：滑动续期/活跃超时/顶号驱逐用假时钟验证，测试不 sleep
- **真实项目验证**：PaperWise（Boot 3.5 + Redis + MySQL）已完成 JWT→auth-kit 迁移，登录/顶号/登出/伪造 token 全流程实测通过，详见 [INTEGRATION.md](docs/INTEGRATION.md)
- 设计踩坑记录（绝对有效期污染、ThreadLocal 串号、顶号排序不稳等）见 [DESIGN.md 决策记录](docs/DESIGN.md)

## 与四件套的关系

- [web-common](../web-common-spring-boot-starter)：鉴权异常自动映射 Result(40100/40300)，业务零 try-catch
- [api-governance](../api-governance-spring-boot-starte)：管理端静态令牌同思路；治理日志可带 AuthContext 用户上下文
- [concurrent-guard](../concurrent-guard)：幂等注解 + 登录态防重放组合范式
- [OutboxPro](../OutboxPro)：事件 payload 放 operatorId 的约定写法

组合代码示例见 [INTEGRATION.md](docs/INTEGRATION.md)。

## FAQ

**Q：和 Sa-Token 的区别？**
同路线（不透明 token + 服务端会话），本组件更小：核心仅会话模型 + 注解鉴权 + 防爆破，无 OAuth2/二级认证等大模块；且与自家 web-common 的 Result 体系原生咬合。

**Q：为什么不做用户表/注册登录接口？**
starter 内置用户表会跟业务库打架（字段、加密方式、表名都可能冲突）。auth-kit 只管"登录态与校验"，账号体系归业务。

**Q：token 会话在 Redis 里怎么存的？会序列化整个对象吗？**
不会。Hash 存 5 个简单字段，无序列化框架依赖，无反序列化漏洞面。

**Q：权限数据每次校验都查库吗？**
是的（组件不缓存，变更实时生效）。热路径建议在 PermissionProvider 实现里加短 TTL 本地缓存。

**Q：能不引入 Redis 吗？**
能。自动降级内存实现（启动有 WARN），仅适合本地开发/单实例，重启会话丢失。

**Q：异步线程里怎么拿当前用户？**
ThreadLocal 不跨线程传递。提交任务前先 `AuthKit.getLoginId()` 取出，作为参数传给异步任务。

## 已知限制

- 设备标识不能包含 `|`（Redis 索引分隔符）
- `@Async` / 自建线程池场景 ThreadLocal 需手动传递
- 生产环境必须配 Redis，内存实现仅限开发
- token 明文作会话 key，如需抗 Redis 泄露可二开 SessionDao 做摘要存储

## Roadmap

- **V1.5**：记住我（设备级长效 token）、二级认证 `@RequireSafe`、JWT 可选模式（附黑名单代价说明）、会话并发治理（按设备查看/逐个踢出）
- **V2**：`@DataScope` 行级数据权限（MyBatis-Plus 拦截器织入 + 部门树 SPI）、OAuth2/单点登录、WebFlux 支持

## License

Apache License 2.0
