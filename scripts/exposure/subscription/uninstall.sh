#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"
source "$CORE_DIR/env.sh"

SUBSCRIPTION_STATE_DIR="${EASYNET_SUBSCRIPTION_STATE_DIR:-$(easynet_subscription_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"

main() {
    uninstall_remove_file "/etc/nginx/sites-enabled/easynet-subscription" "EasyNet 订阅承载 enabled site"
    uninstall_remove_file "/etc/nginx/sites-available/easynet-subscription" "EasyNet 订阅承载 site"
    uninstall_remove_file "$WEB_ROOT/sub" "URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash" "Clash 订阅文件"
    uninstall_remove_file "$WEB_ROOT/sub_full" "旧版完整 URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash_full" "旧版完整 Clash 订阅文件"
    uninstall_remove_path "$SUBSCRIPTION_STATE_DIR" "独立订阅承载状态"
    uninstall_remove_path "${EASYNET_SUBSCRIPTION_CERT_DIR:-/etc/ssl/easynet-subscription}" "独立订阅承载证书目录"

    if command -v systemctl &>/dev/null; then
        systemctl restart nginx >/dev/null 2>&1 || true
    fi

    log_info "独立订阅承载清理完成"
}

main "$@"
