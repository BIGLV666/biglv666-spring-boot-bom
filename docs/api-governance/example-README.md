# API Governance 示例工程

演示 [api-governance-spring-boot-starter](../../README.md) 0.2.0 全部核心特性的最小可运行工程。
本工程为**独立 Maven 工程**，不参与主仓库构建；请在本目录单独构建运行。

## 运行

```bash
mvnw.cmd spring-boot:run    # Windows（或先在主仓库执行 mvnw install 安装 0.2.0）
./mvnw spring-boot:run      # Linux/macOS
```

启动后访问并观察控制台日志与管理接口：

| 演示点 | 操作 |
|--------|------|
| 自动日志 + 指标 | `curl http://localhost:8080/api/users/1` |
| SpEL 参数维度限流 | 快速访问 `http://localhost:8080/api/users/1`（每个 id 独立 3 次/10 秒配额，第 4 次被限流） |
| 全局限流 | 快速访问 `http://localhost:8080/api/orders`（5 次/10 秒） |
| 慢方法 + 告警 | `curl http://localhost:8080/api/slow`（延迟 1.5s，触发慢方法告警） |
| 自定义拒绝响应 | 被限流时返回自定义 JSON（见 `RejectHandlerConfig`） |
| 自定义告警通知器 | 控制台输出 `[ALERT] ...`（见 `ConsoleAlertNotifier`） |
| Micrometer 指标 | `curl http://localhost:8080/actuator/prometheus \| grep api.governance` |
| 内存指标 | `curl http://localhost:8080/api-governance/metrics` |
| 慢方法聚合 | `curl http://localhost:8080/api-governance/metrics/slow/all` |
| 管理接口鉴权 | `curl -H "X-Governance-Token: demo-token" http://localhost:8080/api-governance/status`（无令牌返回 401） |

## 关键文件

- `DemoApplication.java`：启动类
- `UserController.java`：`@RateLimit(key = "#id")` 参数维度限流
- `OrderController.java`：类级 `@RateLimit` + `@Skip` 健康检查
- `SlowController.java`：慢方法演示
- `RejectHandlerConfig.java`：`RateLimitRejectHandler` 自定义拒绝响应
- `ConsoleAlertNotifier.java`：`GovernanceAlertNotifier` 自定义告警
- `application.yml`：全部 0.2.0 新配置项示例（含管理接口令牌鉴权）
