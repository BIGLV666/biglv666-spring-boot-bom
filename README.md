# biglv666 Spring Boot Starter BOM

biglv666 全家桶的**版本对齐清单（Bill of Materials）**：一个纯 `pom` 仓库，把六个组件的全部 artifact 版本收拢到 `<dependencyManagement>`，使用方一次 import 即版本对齐，不再逐个写版本号。

本仓库**不包含任何 Java 代码，也不修改任何组件的代码**——组件各自独立仓库、独立发版，本仓库只做版本收口与文档整合。

## 组件一览

| 组件 | Maven 坐标（`io.github.biglv666`） | 当前版本 | 定位 | 仓库 |
|---|---|---|---|---|
| auth-kit | `auth-kit-spring-boot-starter` | 0.1.0 | 认证鉴权：不透明 token + 有状态会话，踢人下线/同端互斥/滑动续期 | [BIGLV666/auth-kit-spring-boot-starter](https://github.com/BIGLV666/auth-kit-spring-boot-starter) |
| api-governance | `api-governance-spring-boot-starter` | 0.5.0 | API 治理：限流、指标、日志、告警、管理接口，一切皆插件 | [BIGLV666/api-governance-spring-boot-starter](https://github.com/BIGLV666/api-governance-spring-boot-starter) |
| concurrent-guard | `guard-spring-boot-starter` | 0.2.0 | 并发防护：注解式幂等（防重复提交）+ 注解式分布式锁 | [BIGLV666/concurrent-guard](https://github.com/BIGLV666/concurrent-guard) |
| web-common | `web-common-spring-boot-starter` | 0.3.0 | Web 通用封装：统一 Result、分段错误码、全局异常处理 | [BIGLV666/web-common-spring-boot-starter](https://github.com/BIGLV666/web-common-spring-boot-starter) |
| state-kit | `state-kit-spring-boot-starter` | 0.1.0 | 声明式状态流转：yml/DSL 声明规则，CAS 保证并发正确 | [BIGLV666/state-kit-spring-boot-starter](https://github.com/BIGLV666/state-kit-spring-boot-starter) |
| OutboxPro | `outboxpro-spring-boot-starter`（多模块，含 parent 共 10 个 artifact） | 1.1.0 | 事务消息：Outbox 模式 + RabbitMQ 可靠消费 + 死信重放 | [BIGLV666/OutboxPro](https://github.com/BIGLV666/OutboxPro) |

## 使用方式

在宿主工程的 `pom.xml` 里 `import` 本 BOM，然后按需引入组件（不再写版本号）：

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.github.biglv666</groupId>
            <artifactId>biglv666-spring-boot-bom</artifactId>
            <version>1.0.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
        <!-- 你自己的 Spring Boot BOM / 其他第三方 BOM 照常共存 -->
    </dependencies>
</dependencyManagement>

<dependencies>
    <!-- 例：统一返回体 + 认证鉴权 + 幂等/分布式锁，全都不用写版本 -->
    <dependency>
        <groupId>io.github.biglv666</groupId>
        <artifactId>web-common-spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>io.github.biglv666</groupId>
        <artifactId>auth-kit-spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>io.github.biglv666</groupId>
        <artifactId>guard-spring-boot-starter</artifactId>
    </dependency>
</dependencies>
```

> **Spring Boot 版本由你决定**：本 BOM 刻意不 import `spring-boot-dependencies`。六个 starter 的容器依赖都是 `provided`/`optional`，不向使用方传递 Spring Boot 版本；各组件当前在 Boot 3.5.x 基线下编译测试（api-governance/guard 编译基线较低，但运行时跟随宿主）。

> **⚠️ 上架状态（2026-09-05 核验）**：auth-kit `0.1.0` 与 state-kit `0.1.0` **尚未发布到 Maven Central**（两个组件仓库也还没有发布流水线），BOM 先按目标版本收拢；在这两个组件发版并上架之前，`mvn` 解析这两个坐标会报错，CI 的 Central 存在性检查也会标红。发布步骤见各组件仓库（模式与 web-common/concurrent-guard 相同：配 secrets → 打 `v*` 标签）。

## 版本对齐表（组件间交叉依赖）

组件之间存在 `optional` 交叉依赖（类路径检测，缺了不影响核心功能）。**升版时按下表核对**，避免 BOM 收拢的版本与组件内部写死的版本脱节：

| 依赖方 | 被依赖方 | 依赖方当前写死的版本 | 需要跟随的 BOM 属性 |
|---|---|---|---|
| auth-kit | web-common | 0.3.0 | `web-common.version` |
| state-kit | web-common | 0.3.0 | `web-common.version` |
| state-kit | auth-kit | 0.1.0 | `auth-kit.version` |

例如把 web-common 升到 0.4.0 后：本 BOM 改 `web-common.version=0.4.0`，同时 auth-kit、state-kit 仓库的 pom 也要升到 0.4.0 并各自发版，BOM 才能进入下一个版本。

## 发布流程

本仓库通过 **GitHub Actions** 发布到 Maven Central（token 认证 + GPG 签名）：

1. 修改 `pom.xml` 中的版本属性（或 BOM 自身版本）；
2. 提交并打标签：`git tag v1.0.0 && git push origin v1.0.0`；
3. `publish.yml` 自动执行 `mvn deploy -Prelease`，签名后经 `central-publishing-maven-plugin` 上传，`waitUntil=published` 等待 Central 上架；
4. CI（`ci.yml`）在每次 push/PR 时校验：BOM 可解析 + 所有受管版本在 Central 真实存在。

所需 secrets 与各组件仓库相同：`CENTRAL_USERNAME`、`CENTRAL_PASSWORD`、`GPG_PRIVATE_KEY`（base64）、`GPG_PASSPHRASE`。

## 文档导航

所有组件的使用文档、API、枚举已整合进本仓库 `docs/`，推荐阅读顺序：

1. [`docs/API-REFERENCE.md`](docs/API-REFERENCE.md) —— **全家桶聚合 API 参考**：六个组件的注解、核心接口、SPI、枚举值、配置前缀，一页通览；
2. 各组件完整文档（复制自各仓库，含原始 README 与 docs 目录）：

| 组件 | 文档目录 | 亮点文档 |
|---|---|---|
| auth-kit | [`docs/auth-kit/`](docs/auth-kit/) | `USAGE.md`（API 逐讲）、`CONFIGURATION.md`（配置全参考）、`INTEGRATION.md`（四件套咬合） |
| OutboxPro | [`docs/outboxpro/`](docs/outboxpro/) | `OutboxPro-快速开始与公共API.md`、`DLQ-README.md`（死信）、`OutboxPro-维护手册.md` |
| api-governance | [`docs/api-governance/`](docs/api-governance/) | `README.md`（主文档）、`ASYNC_ACTIONS.md`（异步钩子专章） |
| concurrent-guard | [`docs/concurrent-guard/`](docs/concurrent-guard/) | `README.md`（唯一文档，示例齐全） |
| web-common | [`docs/web-common/`](docs/web-common/) | `README.md`（中文主文档）、`README.en.md`（英文版） |
| state-kit | [`docs/state-kit/`](docs/state-kit/) | `README.md`（设计决策 + yml/DSL 双通道） |

各文件的来源仓库与路径见 [`docs/INDEX.md`](docs/INDEX.md)。组件仓库文档更新后，运行 `scripts/sync-docs.sh` 重新同步。

## 推荐组合

- **Web 基础**：web-common（统一返回体/错误码）→ 所有组件的异常都会映射成统一 `Result`；
- **业务后端全家桶**：web-common + auth-kit（登录鉴权）+ guard（幂等防重/分布式锁）+ state-kit（订单等状态机）+ api-governance（限流监控）——这五件互相有咬合点，见 `docs/API-REFERENCE.md` 末尾「组件间集成点」；
- **异步消息**：任意组合 + OutboxPro（事务内发消息不丢）。
