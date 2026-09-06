# 架构设计文档

本文档说明 auth-kit 的内部设计：数据模型、状态流转、关键决策与取舍。适合二开者与想深入理解机制的读者。

## 1. 总体架构

```
                        ┌─────────────────────────────────────┐
   业务代码              │           业务方 Spring Boot 应用      │
─────────────           │                                     │
 AuthKit.login()        │  ┌────────────┐   ┌──────────────┐  │
 AuthKit.checkPermission│  │ AuthManager │  │ AuthInterceptor│ │
        │               │  │   (核心)    │   │  (Web 鉴权)   │  │
        ▼               │  └─────┬──────┘   └──────┬───────┘  │
┌───────────────┐       │        │  AuthContext(ThreadLocal)  │
│  SPI 接口层    │       │        ▼                ▼          │
│ SessionDao    │◄──────┤  ┌─────────────────────────┐       │
│ AttemptStore  │       │  │ SessionDao 实现（可选其一） │       │
│ TokenGenerator│       │  │ RedisSessionDao(生产默认) │       │
│ PermissionProv│       │  │ InMemorySessionDao(降级)  │       │
│ PasswordEncder│       │  └───────────┬─────────────┘       │
└───────────────┘       └──────────────┼──────────────────────┘
                                       ▼
                                 Redis / 内存
```

分层原则：**接口与实现彻底分离**。五条 SPI（SessionDao / AttemptStore / TokenGenerator / PermissionProvider / PasswordEncoder）全部可由业务方注册 Bean 全量替换，自动装配层对所有 Bean 加 `@ConditionalOnMissingBean`。

## 2. 模块结构

```
io.github.biglv666.authkit
├── AuthKit                  # 静态门面（业务代码唯一入口）
├── annotation/              # @RequireLogin @RequirePermission @RequireRole @AuthIgnore @CurrentUser
├── config/                  # AuthKitAutoConfiguration + AuthKitProperties
├── context/                 # CurrentUserArgumentResolver
├── core/                    # AuthManager（核心逻辑）、AuthContext（ThreadLocal）、TokenResolver
├── crypto/                  # BCryptPasswordEncoderAdapter（spring-security-crypto 适配）
├── dao/                     # SessionDao / AttemptStore SPI + 内存/Redis 各两套实现
├── exception/               # NotLoginException(Reason) 等
├── guard/                   # LoginAttemptGuard 防爆破
├── interceptor/             # AuthInterceptor + 注解解析缓存
├── management/              # 在线会话管理端点 + 静态令牌过滤器
├── model/                   # AuthSession / AuthUser / AuthMode / DeviceType
├── spi/                     # PermissionProvider / PasswordEncoder
├── token/                   # TokenGenerator SPI + RandomTokenGenerator
└── webcommon/               # web-common 适配 / 原生 401-403 兜底（二选一装配）
```

## 3. 数据模型与 Redis Key 设计

| key | 类型 | 内容 | TTL |
|---|---|---|---|
| `{prefix}:token:{token}` | Hash | token、userId、device、loginTime、lastActiveTime | 会话绝对有效期（登录时一次确定） |
| `{prefix}:kick:{token}` | String | 踢出原因（KICKED_OUT / BE_REPLACED） | 与会话有效期一致（墓碑） |
| `{prefix}:user:{userId}` | ZSet | member=`device\|token`，score=预期过期时间戳 | 不过期，读时按 score 惰性清理 |
| `{prefix}:attempt:{id}` | String | 登录失败计数 | 锁定窗口（固定窗口计数） |

设计要点：

- **token Hash 是唯一真源**。用户反查索引（ZSet）允许脏数据：过期条目靠 score 范围惰性清理，调用方以 token 会话是否存在为准。
- **全简单类型**，不依赖任何序列化框架（无 JDK 序列化的反序列化风险，无跨版本兼容问题）。
- 设备标识拼进 ZSet member 时用 `|` 分隔，因此**设备标识不能包含 `|`**。

## 4. 状态流转

### 4.1 登录

```
业务代码(已自行验密)
   │ AuthKit.login(userId, device)
   ▼
AuthManager
   ├─ SecureRandom 生成 64 字符 base64url token
   ├─ HSET token:{t} + EXPIRE timeout        ← 绝对有效期在此刻确定
   ├─ ZADD user:{uid} {device}|{t} now+timeout
   └─ 顶号驱逐：ZSET 取同端 tokens → 排除新 token → 按 loginTime 排序
                → 超出 maxSessionsPerDevice 的最旧会话：
                  DEL token:{t} + SET kick:{t}=BE_REPLACED + ZREM
```

### 4.2 请求校验（每次请求）

```
请求 → AuthInterceptor.preHandle
  ├─ 白名单命中(Ant) → 放行（不解析不填充）
  ├─ @AuthIgnore → 放行
  ├─ TokenResolver 提取 token（Header 剥 Bearer 前缀 → Cookie 兜底）
  ├─ checkLogin(token):
  │    ├─ HGETALL token:{t}
  │    │    不存在 → GET kick:{t}
  │    │              ├─ 有墓碑 → 抛 KICKED_OUT / BE_REPLACED
  │    │              └─ 无墓碑 → 抛 TOKEN_INVALID
  │    ├─ now - lastActiveTime > activeTimeout?
  │    │    是 → DEL token + ZREM → 抛 TOKEN_TIMEOUT
  │    └─ HSET lastActiveTime = now    ← 只推进活跃时间，不碰 TTL
  ├─ 注解校验：checkPermissions/checkRoles(userId, …) → PermissionProvider
  │    （权限/角色校验用会话里的 userId 显式传参，不依赖 ThreadLocal）
  ├─ 全部通过 → AuthContext.set(userId, device, token)
  └─ Controller 执行（@CurrentUser 注入 AuthUser）
       请求结束 → afterCompletion → AuthContext.clear()
```

### 4.3 踢人 / 登出

| 操作 | 删会话 | 写墓碑 | 旧端后续请求收到 |
|---|---|---|---|
| `logout()` | ✅ | ❌ | TOKEN_INVALID |
| `kickout(uid, device)` | ✅ | ✅ KICKED_OUT | 「您已被强制下线」 |
| 顶号（自动） | ✅ | ✅ BE_REPLACED | `kicked-out-message` 配置文案 |
| `forceLogout(uid, device)`（管理端） | ✅ | ❌ | TOKEN_INVALID |

墓碑的意义：会话已删后无法区分"本来就不存在"和"被踢"，墓碑用少量 Redis 空间换回了**被踢端可感知的专用错误语义**。

## 5. 性能画像

- **每次请求（命中）**：HGETALL + hasKey + HSET ≈ 3 次 Redis 往返（内嵌在 lettuce 单连接管道能力范围内，未做 pipeline 优化）
- **每次请求（miss）**：额外 1 次 GET 墓碑
- **登录**：HSET + EXPIRE + ZADD + 驱逐期若干读（≤ maxSessionsPerDevice + 1）
- **注解解析**：每个 HandlerMethod 仅首次反射，之后 ConcurrentHashMap 缓存
- 权限数据不做组件级缓存（避免缓存失效难题），由 PermissionProvider 实现方自行决定（建议短 TTL 本地缓存）

## 6. 设计决策记录（含踩坑）

### 6.1 不透明 token + 有状态会话，而非 JWT

踢人下线、同端互斥、滑动续期、强制登出，本质都要求服务端持有会话状态。JWT 是无状态的，实现这些只能靠黑名单补丁——等于用更复杂的机制实现回有状态，还引入签名密钥管理问题。V1.5 的 JWT 模式将作为可选补充并附代价说明。

### 6.2 滑动续期不得延长绝对有效期（踩坑）

初版 `checkLogin` 用 `saveSession` 续期，副作用是把「30 天绝对有效期」也变成了滑动的——永远不过期的会话。修复：`SessionDao` 拆出 `updateLastActiveTime`（Redis 用 HSET 不碰 TTL；内存实现保持原 expireAt）。**活跃度与绝对寿命是两个独立维度**，接口设计必须把这件事显式化。

### 6.3 上下文填充时机（踩坑，安全相关）

Spring 拦截器 `preHandle` 抛异常时，Spring 只会调用它**之前**的拦截器的 `afterCompletion`，不会调它自己的。若在权限校验前就填充 ThreadLocal，校验失败会在工作线程残留脏上下文（线程池复用 → 串号）。修复：**所有校验全部通过后才 `AuthContext.set`**，权限/角色校验改为显式传 userId，不依赖 ThreadLocal。

### 6.4 顶号驱逐必须排除新 token

驱逐候选按 loginTime 排序，同一毫秒内两次登录排序不稳定，可能把刚签发的 token 驱逐掉。修复：候选集显式排除当前新 token，且保证"保留最新的 N 个旧会话"语义。

### 6.5 类级 + 方法级注解取"与"关系，而非覆盖

如果方法级注解覆盖类级，一个 `@RequirePermission("user:read")` 的方法就能意外放宽类级的 `@RequireRole("admin")`。所以两级规则独立保存、独立校验（各自按自己的 mode 判定），都要满足。

### 6.6 @AuthIgnore 仅方法级生效

整类匿名放行几乎必然是事故（新加的方法静默裸奔）。只允许方法级，且代码注释明确安全警告。

### 6.7 未配置 PermissionProvider 时权限校验一律拒绝（fail-closed）

忘记实现 SPI 时，静默放行比 500 严重得多。`loadPermissions` 在 provider 缺失时抛 NotPermissionException。

### 6.8 管理端点 fail-fast

`management.enabled=true` 但未配 `auth-token` 时直接启动失败，而不是带着一个无保护的管理端点上线。

### 6.9 双异常处理器互斥

web-common 适配器与原生 401/403 兜底必须二选一：靠 `@ConditionalOnClass` + `@ConditionalOnMissingClass` 类级条件互斥（bean-name 存在性条件在同类内注册顺序不定，不可靠——踩坑）。

### 6.10 JWT 同秒碰撞（踩坑，安全相关）

JWT 模式初版 claims 只有 uid/dev/iat/exp，秒级时间戳下**同一秒内同用户同设备的两次登录签出完全相同的凭证**——两次登录共享一个 token（会话固定），且顶号逻辑会把"旧凭证"当作"当前凭证"跳过驱逐。修复：payload 加入 `jti`（内部随机 token），凭证唯一性由 SecureRandom 保证。教训：**自签发凭证必须包含不可预测的唯一成分**，时间戳精度不足。

### 6.11 JWT 模式的取舍

自校验（验签不读会话）换来的代价：无滑动续期、无实时活跃数据、登出/踢人必须依赖墓碑黑名单（否则凭证到期前一直有效）。收益：每请求 Redis 往返从 3 次降到 1 次。墓碑/索引统一作用于下发凭证（`TokenCodec.keyOf`），两种模式下踢人/顶号语义完全一致。

### 6.12 OAuth2 的 access_token 就将会话凭证

不做独立令牌体系：`/oauth2/token` 签发的 access_token 直接调用 `AuthManager.login(userId, "OAuth2:{clientId}#随机后缀")` 产生会话凭证。收益巨大：资源端校验、注解鉴权、权限体系、踢人、管理端点对 OAuth2 令牌**零改动全量生效**；device 维度按客户端区分，在线列表可按应用审计。OAuth2 只新增"授权码/刷新令牌"两个短时 KV（共用 `OAuth2KeyValueStore` SPI，授权码用 Redis GETDEL 原子单次消费防重放）。

### 6.13 客户端 SPI 的边界

`IdentityProvider` 只封装协议（跳转地址 + code 换档案），**用户归属归业务**（`OAuth2UserBinder`）——与"不带用户表"同一哲学。SSO 不单独实现：授权服务器（6.12）+ 客户端模式 + 共享 Redis 会话，三者组合即"一次登录处处通行"。

## 7. 并发与一致性说明

- `checkLogin` 非原子（读-判-写三步）：两个并发请求都读到旧 lastActiveTime 并写回，影响仅限活跃时间精度（秒级），可接受。
- 顶号与被顶请求并发：被顶会话可能在校验通过后被删——下次请求即收到 BE_REPLACED。窗口为一个请求周期。
- `forceLogout` 与活跃请求并发：同上，最多多发一个已失效请求。
- ZSet 索引脏读无害：一切以 token Hash 存在性为准。

## 8. 已知边界

| 边界 | 说明 |
|---|---|
| 设备标识含 `\|` | 会破坏 Redis 索引 member 解析 |
| 多实例 + 内存实现 | 会话不共享，仅本地开发 |
| `@Async` / 自建线程池 | ThreadLocal 不传递，需手动携带 AuthContext |
| 权限数据变更 | 实时生效（无组件级缓存），但每次校验都查库，热路径需实现方自加缓存 |
| token 明文存储 | 会话 key 即 token，Redis 被攻破即可用；如需更强可二开 SessionDao 做摘要存储 |
