#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/metadata.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"

check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        log_info "服务运行中: $service"
    else
        log_warn "服务未运行: $service"
    fi
}

check_rule() {
    local rule="$1"
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "$rule"; then
        log_info "UFW 已放行: $rule"
    else
        log_warn "未确认 UFW 规则: $rule"
    fi
}

check_metadata() {
    local metadata_file module
    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            log_warn "metadata 无效: $metadata_file"
            continue
        fi
        module="$(jq -r '.module' "$metadata_file")"
        log_info "metadata 可用: $module"
        jq -r '.systemd.services[]? // empty' "$metadata_file" | while IFS= read -r service; do
            [ -n "$service" ] && check_service "$service"
        done
        jq -r '.firewall[]? | "\(.port)/\(.proto)"' "$metadata_file" | while IFS= read -r rule; do
            [ -n "$rule" ] && check_rule "$rule"
        done
    done < <(metadata_list_files)
}

check_ports() {
    log_info "当前监听端口:"
    ss -ltnup | grep -E ':(443|8443|4443|4444|8388|51820)\b' || true
}

check_subscription() {
    local sub_url clash_url
    if sub_url="$(easynet_subscription_url sub 2>/dev/null)" && clash_url="$(easynet_subscription_url clash 2>/dev/null)"; then
        log_info "URI 订阅: $sub_url"
        log_info "Clash 订阅: $clash_url"
    else
        log_warn "未发现可公开访问的订阅入口。"
    fi
}

main() {
    check_metadata
    check_ports
    check_subscription
}

main "$@"
