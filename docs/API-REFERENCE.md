# 全家桶聚合 API 参考

六个组件的公共 API 一页通览：注解、核心接口、SPI、枚举值、配置前缀，以及组件间的集成点。

> 本文为人工维护的聚合文档（不含示例代码，示例见各组件完整文档）。包命名：除 OutboxPro 使用 `org.outboxpro.*` 外，其余组件统一 `io.github.biglv666.<组件名>`。

---

## 1. auth-kit-spring-boot-starter（认证鉴权）

轻量级认证鉴权：不透明 token + 有状态会话（Redis/内存），支持踢人下线、同端互斥、滑动续期、登录防爆破；不带用户表，用户数据经 SPI 对接。

### 注解（`io.github.biglv666.authkit.annotation`，均 RUNTIME）

| 注解 | 目标 | 说明 |
|---|---|---|
| `@RequireLogin` | METHOD/TYPE | 要求登录 |
| `@RequirePermission(value, mode)` | METHOD/TYPE | 权限校验，ALL/ANY |
| `@RequireRole(value, mode)` | METHOD/TYPE | 角色校验，ALL/ANY；类级+方法级取"与" |
| `@AuthIgnore` | 仅 METHOD （事务内延迟到 afterCommit，回滚不失效）| 短路一切校验（匿名放行） |
| `@CurrentUser` | PARAMETER | 注入 `AuthUser`，属性 `required` |

### 核心接口/类

- `core.AuthContext` — ThreadLocal 认证上下文
- `core.AuthManager` — 登录/登出/踢人等核心操作
- `core.TokenResolver` — Header/Cookie token 解析
- `AuthKit` — 静态门面（`AuthKit.login()` 等）
- `model.AuthUser` / `model.AuthSession` — 用户/会话模型
- SPI：`spi.PasswordEncoder`（密码编码）、`spi.PermissionProvider`（权限数据来源）、`dao.SessionDao`（会话存储，Redis/内存双实现）、`dao.AttemptStore`（防爆破计数）、`token.TokenGenerator`
- 异常：`NotLoginException`、`NotPermissionException`、`NotRoleException`、`LoginLockedException`

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `model.AuthMode` | `ALL` / `ANY` | 权限/角色校验模式 |
| `model.DeviceType` | `PC` / `APP` / `MINI_PROGRAM` / `WEB` | 内置设备类型（也接受任意字符串） |
| `exception.NotLoginReason` | `NO_TOKEN` / `TOKEN_INVALID` / `TOKEN_TIMEOUT` / `KICKED_OUT` / `BE_REPLACED` | 五种未登录/下线语义 |

### 配置前缀 `auth-kit`

`enabled`、`whitelist`；`token.*`（header-name/cookie-name/prefix/timeout/activeTimeout/style/store）；`session.*`（max-sessions-per-device、kicked-out-message、key-prefix）；`attempt.*`（enabled、fail-max-attempts、lock-duration）；`management.*`（enabled、auth-token、auth-header、base-path）

---

## 2. api-governance-spring-boot-starter（API 治理）

"一切皆插件"的 API 治理：默认拦截所有 Controller，以前置链+后置链过滤器管道驱动限流、日志、指标统计；支持本地/Redis 限流、令牌桶/滑动窗口、告警 Webhook、后台管理接口与异步方法钩子。

### 注解（`io.github.biglv666.apigovernance`，TYPE+METHOD/RUNTIME/@Inherited）

| 注解 | 说明 |
|---|---|
| `@RateLimit(limit, window, key)` | 覆盖限流阈值；key 支持 SpEL 参数维度限流 |
| `@Skip(reason)` | 完全跳过治理管道 |
| `@NoLog` | 仅关闭日志输出 |
| `@AsyncAction(value)` | 标注被观察的异步方法（`async.annotation`） |
| `@AsyncHandler(value, order)` / `@AsyncHandlers` | 标注异步四阶段处理器方法/聚合容器 |

### 核心接口/SPI

- 治理管道：`filter.Filter`（+`FilterChain`/`FilterContext`）、`filter.PreFilter`、`filter.PostFilter` — 自定义过滤器插件
- 限流：`ratelimit.RateLimiter`、`ratelimit.RateLimitStrategy`（函数接口 `tryAcquire(key,limit,window)`，自定义算法）、`ratelimit.RateLimitKeyResolver`、`ratelimit.RateLimitRejectHandler`；内置 `TokenBucketRateLimiter` / `SlidingWindowRateLimiter` / `FailSafeRateLimiter`
- 告警：`alert.GovernanceAlertNotifier`（SPI，内置 `WebhookAlertNotifier` 支持钉钉/企微/飞书）、`alert.GovernanceAlertEvent`
- 异步钩子 SPI（`async.spi`）：`AsyncExecutorProvider`、`AsyncHandlerExceptionHandler`、`AsyncTaskRejectionHandler`、`AsyncTaskContextPropagator`、`AsyncEventEnricher`、`AsyncExecutionListener`
- 异步模型：`async.AsyncEventBuilder`、`async.event.AsyncEvent`/`AsyncError`、`async.AsyncInvocation`
- 指标：`metrics.ApiMetrics` / `RequestRecord` / `SlidingWindow`
- 管理端点：`management.GovernanceManagementController`（basePath `/api-governance`，静态令牌鉴权）

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `ratelimit.RateLimitAlgorithm` | `TOKEN_BUCKET` / `SLIDING_WINDOW` / `CUSTOM` | 限流算法选择 |
| `async.event.AsyncPhase` | `BEFORE` / `AFTER_SUCCESS` / `AFTER_ERROR` 等 | 异步钩子阶段 |
| `alert.GovernanceAlertEvent.Type` | `SLOW_METHOD` / `RATE_LIMIT_REJECT` / `RATE_LIMITER_FAILURE` / `ASYNC_TASK_REJECTED` | 告警事件类型 |

### 配置前缀 `api.governance`

`enabled`、`include-packages`/`exclude-packages`；`log.*`（slow-threshold-ms 等）；`rate-limit.*`（type/algorithm/default-limit/default-window/status-code/message/fail-strategy/max-entries）；`metrics.*`（window-size/window-seconds/max-apis/micrometer-enabled）；`management.*`（enabled/base-path/auth-token/auth-header/mutations-enabled）；`alert.*`（suppress-interval-ms/webhook.*）；`filters.*`（各内置过滤器开关）；`async.*`；`tracing.*`

---

## 3. guard-spring-boot-starter（concurrent-guard，并发防护）

注解式幂等（防重复提交，Redis setnx+TTL）与注解式分布式锁（Redis/本地），配套拒绝事件 SPI 与 Micrometer 指标。

### 注解（`io.github.biglv666.guard`，METHOD/RUNTIME）

| 注解 | 说明 |
|---|---|
| `@Idempotent(key, ttl, timeUnit, rollbackOnException, message, mode)` | 幂等防重；REJECT/REPLAY 两种模式 |
| `@DistributedLock(key, type, waitTime, leaseTime, timeUnit, acquirePolicy, handler)` | 声明式锁；REDIS/SYNCHRONIZED；THROW/SKIP/CUSTOM |

### 核心接口/SPI

- `lock.LockTemplate` — 程序化 Lambda 加锁 API
- SPI：`idempotent.IdempotentPolicy`（幂等策略，内置 `RedisSetNxIdempotentPolicy`）、`idempotent.ResultCodec`（重放结果序列化，内置 Jackson）、`lock.LockAcquireFallbackHandler`（CUSTOM 锁回退）
- 事件：`event.GuardRejectedEvent`（Spring ApplicationEvent）
- 异常：`IdempotentRejectedException`、`LockAcquireTimeoutException`

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `idempotent.IdempotentMode` | `REJECT` / `REPLAY` | 重复请求处理方式 |
| `lock.LockType` | `REDIS` / `SYNCHRONIZED` | 锁实现类型 |
| `lock.LockAcquirePolicy` | `THROW` / `SKIP` / `CUSTOM` | 获取锁失败策略 |
| `event.GuardEventType` | `IDEMPOTENT_REJECTED` / `IDEMPOTENT_DEGRADED` / `IDEMPOTENT_REPLAYED` / `LOCK_TIMEOUT` | 拒绝事件类型 |

### 配置前缀 `guard`

`enabled`；`idempotent.*`（enabled/key-prefix/fail-open）；`lock.*`（enabled/key-prefix）

---

## 4. web-common-spring-boot-starter（Web 通用封装）

统一 `Result` 返回体 + 分段错误码枚举 + 全局异常处理 + 响应自动包装，引入即生效、零配置。

### 注解（`io.github.biglv666.webcommon.annotation`）

| 注解 | 目标 | 说明 |
|---|---|---|
| `@NoWrap` | METHOD/TYPE | 豁免响应自动包装（文件下载等） |
| `@DefaultErrorCode(value, constant)` | TYPE/@Inherited | 声明式把任意自定义异常类映射到错误码枚举 |
| `@ErrorCodeScan(basePackages, ...)` | @Configuration 类 | 按包扫描注册 ErrorCode 枚举 |
| `@EnableErrorCodeEndpoint` | @Configuration 类 | 开启 `GET /web-common/error-codes` 错误码字典端点 |

### 核心接口/类

- `result.Result<T>` — 统一返回体（`ok()`/`ok(data)`/`fail(...)` 静态工厂）
- `result.ErrorCode` — 错误码接口（`getCode()`/`getMessage()`），业务枚举实现它扩展
- `result.BusinessException` — 业务异常（携带 ErrorCode）
- `result.ParamErrorItem` — 参数校验错误明细项
- `web.GlobalExceptionHandler` / `web.ResultWrapAdvice` / `web.ErrorCodeRegistry` / `web.ErrorCodeDescriptor` / `web.HttpStatusCodeResolver`

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `result.ResultCode` | `SUCCESS(0)` / `PARAM_ERROR(40000)` / `UNAUTHORIZED(40100)` / `FORBIDDEN(40300)` / `NOT_FOUND(40400)` / `CONFLICT(40900)` / `BIZ_ERROR(50000)` / `SERVICE_UNAVAILABLE(50300)` / `SYSTEM_ERROR(500)` | 内置分段错误码 |
| `config.HttpStatusMode` | `ALWAYS_200`（默认）/ `SEMANTIC` | HTTP 状态码模式 |

### 配置前缀 `web-common`

`enabled`、`auto-wrap`、`success-message`、`expose-exception-message`、`http-status-mode`、`error-codes`（错误码枚举类名列表）、`log.*`

---

## 5. state-kit-spring-boot-starter（声明式状态流转）

yml 或 Java DSL 声明流转规则，启动时动态生成状态机 Bean；数据库 CAS 条件更新保证并发正确，status 列唯一写入口；核心零建表零必选依赖。

### 注解

无注解 API（纯接口 + 声明式配置/DSL）。

### 核心接口/类（`io.github.biglv666.statekit`）

| 类型 | 说明 |
|---|---|
| `StateMachine<S, ID>` | 统一入口，框架动态生成 Bean（bean 名=machine 名），唯一方法 `fire(ID id, String event, FireArg... args)` |
| `FireArg` | fire 参数令牌：`param(key,value)`（内存上下文）/ `set(key,value)`（CAS 落库列），二者严格分离 |
| `StateGuard<S,ID>` | 守卫 SPI（CAS 前只读校验，false/异常即拒绝） |
| `StateAction<S,ID>` | 动作 SPI（CAS 成功后同事务执行） |
| `StateTx<S,ID>` | 流转上下文（entityId/event/from/to/param/operatorId/traceId） |
| `define.DefinitionBuilder` + `StateMachine.define(...)` | Java DSL 入口；`MachineDefinition`/`TransitionSpec` |
| `store.StateStore`（默认 `JdbcStateStore`） | 状态存取 SPI |
| `history.HistoryRecorder`（默认 `JdbcHistoryRecorder`，opt-in） | 流转历史记录 SPI |
| `context.OperatorResolver` | 操作人解析（默认对接 auth-kit 的 `AuthKitOperatorResolver`） |
| `history.HistoryQueryService` / `HistoryRecord` / `HistoryEntry` | 历史查询 |
| `event.StateTransitedEvent` | Spring 事件 |
| 异常 | `StateKitException` 基类 + `IllegalTransitionException` / `GuardRejectedException` / `StateConflictException` / `EntityNotFoundException` |

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `ConflictStrategy` | `THROW`（默认）/ `LOG` | CAS 影响行数 0 时的行为 |
| `FireArg.Kind` | `PARAM` / `SET` | fire 参数类别 |

### 配置前缀 `state-kit`

`operator`（auto）；`history.*`（enabled 默认 false、table-name）；`trace.key`（默认 traceId）；`machines.<name>.*`（table/status-column/id-column/id-type/conflict-strategy/transitions[from/event/to/action/guard]）

---

## 6. OutboxPro（事务消息，多模块，`org.outboxpro.*`）

面向 Spring Boot 的事务消息（Transactional Outbox）+ RabbitMQ 可靠消费：业务方只声明事件和写 Handler。V1 范围 MySQL + RabbitMQ + Jackson + Spring JDBC。

### 注解（`org.outboxpro.core.annotation`，TYPE/RUNTIME）

| 注解 | 说明 |
|---|---|
| `@OutboxEvent` | 标注事件载荷类，声明 eventType/exchange/routingKey/schemaVersion |
| `@OutboxHandler` | 标注 Handler 类，声明队列订阅与事件绑定（payloadType/queue/exchange/consumerName/consumeMode/retryPolicy） |
| `@RetryPolicySpec` | Handler 的重试策略覆盖（enabled/maxAttempts/initialDelayMs/multiplier/maxDelayMs） |
| `@NonRetryable` | 标注异常类：不可重试、直接进死信（沿父类层次生效） |

### 核心接口/类

- 生产侧：`core.OutboxProPublisher` — 业务侧发事件唯一入口（事务内写 outbox）；`core.event.EventDefinition`+Builder、`EventRegistry`、`EventRoute`
- 消费侧：`core.handler.OutboxProHandler<T>`（`handle(EventContext<T>)`）、`AnnotatedOutboxHandler` 基类；`core.context.EventContext<T>`（payload/eventId/traceId/envelope）；`core.subscription.OutboxProSubscription`+Builder、`EventBinding`
- 重试：`core.retry.RetryPolicy` / `RetryPolicies`
- SPI（`org.outboxpro.spi`）：`persistence.OutboxRepository`/`InboxRepository`（+`OutboxRecord`/`InboxRecord`/`OutboxQuery`）、`serialization.EventSerializer`、`transport.MessagePublisher`/`TopologyManager`、`observability.MessageLogSink`；死信族：`DeadLetterRepository`/`DeadLetterStrategy`/`DeadLetterAlertNotifier`/`DlqReplayAuthorizer`（+`DeadLetterRecord`/`DeadLetterContext`/`DeadLetterQuery`/`DeadLetterHandlingResult`/`DeadLetterReason(Code)`）
- 内置实现：`OutboxRelay`、`persistence.mysql.Jdbc*Repository`、`transport-rabbit.RabbitMessagePublisher/RabbitConsumerManager/RabbitTopologyManager/DeadLetterCoordinator`、`observability.Slf4j/DatabaseMessageLogSink`

### 枚举

| 枚举 | 取值 | 用途 |
|---|---|---|
| `core.subscription.ConsumeMode` | `BEST_EFFORT` / `RELIABLE` | 消费可靠性模式 |
| `persistence.OutboxStatus` | `PENDING` / `PROCESSING` / `RETRY_WAITING` / `SENT` / `DEAD` | outbox 生命周期 |
| `persistence.InboxStatus` | `RECEIVED` / `SUCCESS` / `FAILED` / `IGNORED` | inbox 幂等记录状态 |
| `spi.deadletter.DeadLetterStatus` | `DISPATCHING` / `PENDING_REPLAY` / `REPLAYING` / `REPLAYED` | 死信管理状态 |
| `spi.deadletter.DeadLetterHandlingMode` | `FRAMEWORK` / `CUSTOM` | 死信处理模式 |
| `spi.observability.MessageStage` | `OUTBOX` / `PUBLISH` / `RECEIVE` / `HANDLER` / `RETRY` / `DEAD_LETTER` / `ACK` | 消息日志阶段 |
| `spi.observability.MessageStatus` | `CREATED` / `PROCESSING` / `SUCCESS` / `FAILED` / `RETRYING` / `DEAD` / `IGNORED` / `ACKED` | 消息日志状态 |

### 配置前缀 `outboxpro`

`enabled`、`producer-name`、`schema-initialize`；`producer.*`（enabled/relay-enabled/batch-size/poll-interval/claim-timeout/confirm-timeout）；`consumer.*`（enabled/concurrency/prefetch/idempotency-enabled）；`retry.*`；`observability.*`（message-log-sink/db-sink.*）；`dlq.*`（handling-mode/ledger.*/replay/alert.*）；`ops.enabled`

---

## 7. cache-kit-spring-boot-starter（三级缓存）

实体元数据驱动的三级缓存：Caffeine（L1）→ Redis（L2，可选）→ DB（loader）read-through。
MyBatis-Plus 项目零注解接入（复用 `@TableName`/`@TableId`）；一致性为秒级最终一致；
binlog 直连失效（0.2.0+）覆盖"绕过应用的写"（DBA 改库、其他服务写入）。

### 注解（`io.github.biglv666.cachekit.annotation`，均 RUNTIME）

| 注解 | 目标 | 说明 |
|---|---|---|
| `@CacheEntity(prefix, ttl)` | TYPE | 声明实体可缓存（非 MP 项目用）；prefix 缺省类名转蛇形 |
| `@CacheId` | FIELD | 主键字段；优先级高于 MP `@TableId` |
| `@CachedQuery(ttl, condition, cacheNull)` | METHOD | 查询拦截：单实体 miss 才执行方法体；`List<实体>` + ID 集合参数走 per-ID 批量解析；主键严格推导（实体实例参数或参数名=主键字段名），条件字段查询强制旁路 |
| `@CacheInvalidate(entity)` | METHOD | 写方法成功后失效缓存 + 广播 + 延迟双删；entity 在参数无法推导时必填 |
| `@CacheHandle(value)` | FIELD | 注入 `EntityCache<T>` 句柄（手动控制场景） |

### 核心接口/类

- `core.EntityCache<T>` — 句柄接口：`get(id, loader)` / `evict(id)`
- `core.TieredEntityCache` — 三级链内核（single-flight 防击穿、null 占位、TTL 抖动）
- `core.CacheKit` — 静态门面：`withDb(...)` 作用域旁路（强一致读）
- `channel.CacheChannel` / `channel.CaffeineChannel` / `channel.RedisChannel` — L1/L2 通道抽象
- `metadata.EntityMetadataRegistry` — 实体元数据惰性解析（MP 注解经反射读取，不硬依赖）
- `core.DoubleDeleteScheduler` / `core.InvalidationPublisher` / `core.InvalidationSubscriber` — 双删与广播
- `binlog.BinlogInvalidationListener` / `BinlogLifecycle` — binlog 直连失效（0.2.0+，optional）

### MP BaseMapper 自动拦截名单

`selectById` / `selectBatchIds` / `updateById` / `deleteById`（零注解自动缓存与失效，批量按 per-ID 拆解 + null 占位）；条件查询永久不缓存。

### 配置前缀 `cache-kit`

`enabled`；`l1.*`（max-entries/ttl）；`l2.*`（ttl/jitter/null-ttl/double-delete-delay）；`broadcast.*`（enabled/topic）；`mp.*`（auto-cache-base-methods）；`tx.*`（evict-after-commit）；`binlog.*`（enabled/host/port/database/username/password/server-id）

---

## 组件间集成点（全家桶咬合关系）

| 集成 | 机制 |
|---|---|
| auth-kit → web-common | `NotLoginException`/`NotPermissionException`/`NotRoleException` 在类路径有 web-common 时自动映射统一 `Result`（40100/40300） |
| state-kit → web-common | 三类状态异常经 `@DefaultErrorCode` 自动映射统一 `Result` |
| state-kit → auth-kit | `OperatorResolver` 默认实现 `AuthKitOperatorResolver` 自动从 `AuthContext` 填充 operatorId |
| state-kit → api-governance / micrometer-tracing | TraceIdResolver 从 MDC 读取治理链路写入的 traceId |
| guard ↔ web-common | 幂等拒绝/锁超时可经 `GuardRejectedEvent` + 全局异常处理映射统一返回体 |
| guard / api-governance / OutboxPro | 定位互补：guard 管请求级并发防护，api-governance 管接口治理与观测，OutboxPro 管事务消息可靠性 |

所有配置前缀互不冲突：`auth-kit` / `api.governance` / `guard` / `web-common` / `state-kit` / `outboxpro`。
