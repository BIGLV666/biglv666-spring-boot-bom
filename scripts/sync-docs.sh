#!/usr/bin/env bash
# 重新同步各组件仓库的最新文档到本仓库 docs/。
# 前提：本仓库与六个组件仓库同属一个父目录（如 E:\learncard）。
# 同步后请人工 diff docs/INDEX.md 所列文件，并在组件升版时更新 pom.xml 版本属性。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS="$SCRIPT_DIR/../docs"
ROOT="$(cd "$DOCS/.." && cd .. && pwd)"

sync() { # sync <源仓库相对路径> <目标相对路径>
    src="$ROOT/$1"
    dst="$DOCS/$2"
    if [ ! -e "$src" ]; then
        echo "跳过（源不存在）: $1" >&2
        return
    fi
    mkdir -p "$(dirname "$dst/$3")"
    cp "$src" "$dst/$3"
    echo "已同步: $1 -> docs/$2/$3"
}

# auth-kit
sync "auth-kit-spring-boot-starter/README.md"            auth-kit README.md
sync "auth-kit-spring-boot-starter/docs/USAGE.md"        auth-kit USAGE.md
sync "auth-kit-spring-boot-starter/docs/DESIGN.md"       auth-kit DESIGN.md
sync "auth-kit-spring-boot-starter/docs/CONFIGURATION.md" auth-kit CONFIGURATION.md
sync "auth-kit-spring-boot-starter/docs/INTEGRATION.md"  auth-kit INTEGRATION.md

# OutboxPro
sync "OutboxPro/README.md"                               outboxpro README.md
sync "OutboxPro/README-config-example.yml"               outboxpro README-config-example.yml
sync "OutboxPro/docs/OutboxPro-快速开始与公共API.md"       outboxpro "OutboxPro-快速开始与公共API.md"
sync "OutboxPro/docs/OutboxPro-维护手册.md"               outboxpro "OutboxPro-维护手册.md"
sync "OutboxPro/docs/DLQ-README.md"                      outboxpro DLQ-README.md
sync "OutboxPro/outboxpro-example-order/README.md"       outboxpro example-order-README.md

# api-governance
sync "api-governance-spring-boot-starte/README.md"       api-governance README.md
sync "api-governance-spring-boot-starte/README_EN.md"    api-governance README_EN.md
sync "api-governance-spring-boot-starte/ASYNC_ACTIONS.md" api-governance ASYNC_ACTIONS.md
sync "api-governance-spring-boot-starte/examples/api-governance-example/README.md" api-governance example-README.md

# concurrent-guard
sync "concurrent-guard/README.md"                        concurrent-guard README.md

# web-common
sync "web-common-spring-boot-starter/README.md"          web-common README.md
sync "web-common-spring-boot-starter/README.en.md"       web-common README.en.md

# state-kit
sync "state-kit-spring-boot-starter/README.md"           state-kit README.md

# cache-kit
sync "cache-kit-spring-boot-starter/README.md"           cache-kit README.md

echo
echo "同步完成。注意：docs/API-REFERENCE.md 为人工维护的聚合文档，不参与本脚本同步。"
