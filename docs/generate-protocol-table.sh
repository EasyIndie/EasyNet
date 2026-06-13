#!/bin/bash
# EasyNet Protocol Support Table Generator
# Reads all protocol manifests and generates a markdown table.
#
# Usage:
#   bash docs/generate-protocol-table.sh          # print to stdout
#   bash docs/generate-protocol-table.sh --update  # update README.md in-place

set -eE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/discovery.sh"

generate_table() {
    local module manifest
    local -a rows

    while IFS= read -r module; do
        [ -z "$module" ] && continue
        if ! discovery_load_manifest "$module" 2>/dev/null; then
            continue
        fi

        local name="${MODULE_DISPLAY_NAME:-$module}"
        local rank="${MODULE_SECURITY_RANK:-99}"
        local port="${MODULE_DEFAULT_PORT:--}"
        local edge="${MODULE_EDGE_MODE:-none}"
        local profiles="${MODULE_PROFILES:--}"

        # Map profiles to readable names
        local profile_labels=""
        for p in $profiles; do
            case "$p" in
                strict)   profile_labels="${profile_labels}strict, " ;;
                balanced) profile_labels="${profile_labels}balanced, " ;;
                compat)   profile_labels="${profile_labels}compat, " ;;
                *)        profile_labels="${profile_labels}${p}, " ;;
            esac
        done
        profile_labels="${profile_labels%, }"

        case "$edge" in
            none)       edge_label="—" ;;
            backend)    edge_label="反向代理" ;;
            shared_tls) edge_label="共享 TLS" ;;
            *)          edge_label="$edge" ;;
        esac

        printf '| %s | %s | %s | %s | %s |\n' \
            "$name" "$rank" "$port" "$edge_label" "$profile_labels"
    done < <(discovery_list_modules)
}

generate_document() {
    cat <<'HEADER'
<!-- EasyNet 协议支持表 — 由 docs/generate-protocol-table.sh 自动生成 -->
<!-- 手动修改无效，请通过修改 protocols/*/manifest.sh 后重新生成 -->

## 支持的协议

| 协议 | 安全等级 | 默认端口 | Edge 模式 | 部署策略 |
|------|:--------:|:--------:|:---------:|----------|
HEADER
    generate_table
    echo ""
}

case "${1:-}" in
    --update|-u)
        log_info "更新 README.md 协议支持表..."
        tmpfile="$(mktemp /tmp/easynet-readme.XXXXXX)"
        trap 'rm -f "$tmpfile"' EXIT

        # Extract everything before the table section
        awk '1;/^## 支持的协议/{exit}' "$PROJECT_ROOT/README.md" > "$tmpfile"
        generate_document >> "$tmpfile"

        # Append everything after the table section
        # Find the next ## after the table start
        awk '/^## 支持的协议/,0' "$PROJECT_ROOT/README.md" | tail -n +2 | \
            awk 'BEGIN{s=0} /^## / && s==1{print; s=2} s==2{print} /^## 支持的协议/{s=1}' >> "$tmpfile" || true

        mv "$tmpfile" "$PROJECT_ROOT/README.md"
        log_info "README.md 已更新"
        ;;
    *)
        generate_document
        ;;
esac
