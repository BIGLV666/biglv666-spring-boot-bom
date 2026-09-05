# 异步方法生命周期插件

`@AsyncAction` / `@AsyncHandler` 为 Spring Bean 的公开方法提供旁路异步钩子。目标方法本身仍在调用线程同步执行；框架只在其生命周期阶段提交附加任务。


## 使用方式

在业务边界声明动作：

```java
@Service
public class LoginService {

    @AsyncAction("user.login")
    public LoginResult login(LoginRequest request) {
        return doLogin(request);
    }
}
```

在任意 Spring Bean 中声明处理器，无需实现接口：

```java
@Component
public class LoginAsyncHandlers {

    @AsyncHandler(value = "user.login", phase = AsyncPhase.BEFORE, order = 100)
    public void recordAttempt(AsyncEvent event) {
        // BEFORE 仅保证先提交，不保证在 login() 开始前执行完成
    }

    @AsyncHandler(value = "user.login", phase = AsyncPhase.AFTER_SUCCESS, order = 200)
    public void saveLoginLog(AsyncEvent event) {
        // 写数据库、发送通知或更新非关键统计
    }

    @AsyncHandler(value = "user.login", phase = AsyncPhase.AFTER_ERROR)
    public void recordFailure(AsyncEvent event) {
        AsyncError error = event.error();
    }
}
```

处理器必须满足以下签名之一：

```java
public void handle()
public void handle(AsyncEvent event)
```

框架在应用启动时扫描、校验并缓存全部处理器。非法返回值、参数或非公开方法会使应用启动失败，运行期不会重复扫描 Bean 或解析方法。

## 生命周期

| 阶段 | 触发条件 |
|------|----------|
| `BEFORE` | 目标方法执行前提交 |
| `AFTER_SUCCESS` | 目标方法正常返回后提交 |
| `AFTER_ERROR` | 目标方法抛出异常后提交 |
| `AFTER_COMPLETION` | 无论成功或失败，最终都会提交 |

所有处理器均为异步旁路任务：处理器失败、线程池拒绝或事件增强失败都不会修改目标方法的返回值和原始异常。

`order` 只保证同一 `action + phase` 下的任务提交顺序。默认线程池允许并发执行，因此不保证开始顺序或完成顺序。存在业务依赖的步骤应放在同一个处理器中；当前版本不提供串行异步链。

## 事件安全

跨线程只传递不可变 `AsyncEvent`，默认包含：

- 一次调用共享的事件 ID；
- action 和生命周期阶段；
- 目标类名和方法名；
- 开始时间、事件时间和当前耗时；
- 失败时的异常类型和消息摘要；
- 不可修改的扩展数据 Map。

默认不会捕获方法参数、返回值、原始 `Throwable`、AOP JoinPoint、Servlet 请求或响应。这可以避免敏感信息泄露、并发可见性问题和线程池队列长期持有大型对象。

需要 `userId`、`tenantId`、traceId 等数据时，可以注册增强器，在调用线程提取小型快照：

```java
@Bean
public AsyncEventEnricher loginEventEnricher() {
    return (builder, invocation) -> {
        if ("user.login".equals(invocation.getAction())
                && invocation.getPhase() == AsyncPhase.BEFORE) {
            LoginRequest request = (LoginRequest) invocation.getArguments()[0];
            builder.put("username", request.username());
        }
    };
}
```

增强器不得保存 `AsyncInvocation`、参数、返回值或异常引用。`AsyncEvent.data()` 只做 Map 结构的不可变浅拷贝，放入其中的值也应是不可变标量、小型 DTO 或业务 ID。

## 线程池配置

Starter 默认提供独立、有界线程池：

```yaml
api:
  governance:
    async:
      enabled: true
      core-pool-size: 2
      max-pool-size: 8
      queue-capacity: 1000
      keep-alive-seconds: 60
      thread-name-prefix: api-governance-async-
      await-termination-seconds: 5
```

队列满时默认拒绝并记录错误，不在请求线程执行任务。应用关闭时最多等待配置的时间处理已提交任务。

本地线程池不提供任务持久化保证。计费、发券、关键审计等不可丢任务应使用事务 outbox 或消息队列，不能依赖本能力替代可靠消息系统。

## 可替换 SPI

注册对应 Spring Bean 即可替换默认实现：

| SPI | 用途 |
|-----|------|
| `AsyncExecutorProvider` | 提供自定义 Executor |
| `AsyncHandlerExceptionHandler` | 处理 Handler 执行异常 |
| `AsyncTaskRejectionHandler` | 处理 Executor 拒绝 |
| `AsyncEventEnricher` | 在调用线程增加安全事件快照，可注册多个并按 Spring order 执行 |
| `AsyncExecutionListener`（0.5.0 新增） | 观测 Handler 执行结果（成功/失败/拒绝），可注册多个，默认实现为 Micrometer 桥接 |

```java
@Bean
public AsyncExecutorProvider governanceExecutor(Executor applicationExecutor) {
    return () -> applicationExecutor;
}
```

## 启动期交叉校验（0.5.0 新增）

启动时所有 `@AsyncHandler` 引用的 action 必须存在对应的 `@AsyncAction`，否则启动失败
（fail-fast 防呆：action 拼写错误导致的「handler 永不执行」在启动期即暴露）。
如需放行（如先写 handler、后补 action 的开发流程），配置
`api.governance.async.ignore-unmatched-handlers: true`，此时不匹配仅记 warn 日志。

## HTTP 上下文快照（0.5.0 新增）

默认开启的内置 enricher 会把当前请求的元数据快照进事件 `data`：
键 `requestUri`、`httpMethod`、`clientIp`（X-Forwarded-For → X-Real-IP → remoteAddr）。
不捕获请求头、参数与请求体；非 Web 线程不写入任何数据。
可通过 `api.governance.async.web-context-enrichment: false` 关闭。

```java
@AsyncHandler(value = "user.login", phase = AsyncPhase.AFTER_SUCCESS)
public void saveLoginLog(AsyncEvent event) {
    String uri = (String) event.data().get("requestUri");
}
```

## 可观测性（0.5.0 新增）

- **指标**（存在 `MeterRegistry` 时自动注册）：
  `api.governance.async.executions`（Counter，标签 action/outcome ∈ success/failure/rejected）、
  `api.governance.async.execution.duration`（Timer，标签 action/outcome）、
  `api.governance.async.pool.active` / `api.governance.async.pool.queue.size`（Gauge，仅内置线程池）。
  注意保持 action 名数量有限，避免标签基数膨胀；
- **告警**：任务被线程池拒绝时发布 `ASYNC_TASK_REJECTED` 告警（复用告警风暴抑制，需告警已启用）；
- **管理端点**：
  `GET /api-governance/async/handlers` 返回全部已注册 Handler 清单（诊断注册与 action 匹配情况），
  `GET /api-governance/async/status` 返回线程池水位（核心/最大线程数、活跃数、队列水位、完成任务数）。

## Spring AOP 边界

- 仅 Spring Bean 的公开方法有效；
- 同类内部 `this.method()` 自调用不会经过代理；
- `private` 方法不能作为 action 或 handler；
- `BEFORE` 是异步提交点，不能用于鉴权、校验、加锁等必须先完成的逻辑；
- 当前版本不支持 `SERIAL`、`AFTER_COMMIT`、同步 Handler、重试、超时、返回值或任务持久化。
