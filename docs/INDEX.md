# 文档索引（溯源）

本目录的文档**复制自各组件仓库**，内容与复制时点的仓库版本一致；组件文档更新后请运行
`scripts/sync-docs.sh` 重新同步，并人工核对本索引。

> 镜像只保留面向使用者的内容；构建、测试、发布、路线图与内部设计等维护者内容不在本仓库维护。
> 标注的“镜像内容版本”以文件内声明为准，可能落后于组件仓库或 Maven Central 的最新版本；
> 实际可用版本以组件仓库和 Maven Central 为准。

## auth-kit（镜像内容版本 1.0.0，仓库 [BIGLV666/auth-kit-spring-boot-starter](https://github.com/BIGLV666/auth-kit-spring-boot-starter)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `auth-kit/README.md` | `/README.md` | 总览 + 功能矩阵 |
| `auth-kit/USAGE.md` | `/docs/USAGE.md` | 拦截语义与 API 逐讲 |
| `auth-kit/CONFIGURATION.md` | `/docs/CONFIGURATION.md` | 配置项全参考 |
| `auth-kit/INTEGRATION.md` | `/docs/INTEGRATION.md` | 与四件套咬合 + 实战示例 |

> 原 `DESIGN.md`（内部架构、数据模型、设计决策与踩坑记录）属于维护者内容，已移出本镜像。

## OutboxPro（镜像内容版本 1.1.0，仓库 [BIGLV666/OutboxPro](https://github.com/BIGLV666/OutboxPro)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `outboxpro/README.md` | `/README.md` | 总览 + 模块导航 |
| `outboxpro/OutboxPro-快速开始与公共API.md` | `/docs/OutboxPro-快速开始与公共API.md` | 快速开始 + 公共 API |
| `outboxpro/DLQ-README.md` | `/docs/DLQ-README.md` | 死信队列功能说明 |
| `outboxpro/README-config-example.yml` | `/README-config-example.yml` | 全量配置示例 |
| `outboxpro/example-order-README.md` | `/outboxpro-example-order/README.md` | 订单示例运行步骤 |

> 原 `OutboxPro-维护手册.md`（构建、发布、模块维护规则、集成测试与技术债）属于维护者内容，已移出本镜像。

## api-governance（镜像内容版本 0.5.0，仓库 [BIGLV666/api-governance-spring-boot-starter](https://github.com/BIGLV666/api-governance-spring-boot-starter)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `api-governance/README.md` | `/README.md` | 中文主文档 |
| `api-governance/README_EN.md` | `/README_EN.md` | 英文版 |
| `api-governance/ASYNC_ACTIONS.md` | `/ASYNC_ACTIONS.md` | 异步方法生命周期插件专章 |
| `api-governance/example-README.md` | `/examples/api-governance-example/README.md` | 示例工程运行说明 |

## concurrent-guard（镜像内容版本 0.2.0，仓库 [BIGLV666/concurrent-guard](https://github.com/BIGLV666/concurrent-guard)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `concurrent-guard/README.md` | `/README.md` | @Idempotent / @DistributedLock / REPLAY / LockTemplate / 事件 / 指标 |

## web-common（镜像内容版本 0.3.0，仓库 [BIGLV666/web-common-spring-boot-starter](https://github.com/BIGLV666/web-common-spring-boot-starter)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `web-common/README.md` | `/README.md` | 中文主文档 |
| `web-common/README.en.md` | `/README.en.md` | 英文版 |

## state-kit（镜像内容含 0.2.0 新特性，仓库 [BIGLV666/state-kit-spring-boot-starter](https://github.com/BIGLV666/state-kit-spring-boot-starter)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `state-kit/README.md` | `/README.md` | 设计决策 + 快速开始 + yml/DSL 双通道 + CAS 铁律 + 0.2.0 新特性 |

> 依赖示例中仍写 0.1.0，镜像内容版本请以组件仓库和 Maven Central 为准。

## cache-kit（镜像内容版本 0.2.0，仓库 [BIGLV666/cache-kit-spring-boot-starter](https://github.com/BIGLV666/cache-kit-spring-boot-starter)）

| 本仓库文件 | 原始路径 | 内容 |
|---|---|---|
| `cache-kit/README.md` | `/README.md` | 三级缓存总览 + 两种接入模式 + binlog 直连失效 + 配置全参考 + 性能实测 + FAQ |
