#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"
source "$CORE_DIR/env.sh"

EDGE_STATE_DIR="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"

main() {
    uninstall_remove_file "/etc/nginx/sites-enabled/easynet-edge" "EasyNet Edge enabled site"
    uninstall_remove_file "/etc/nginx/sites-available/easynet-edge" "EasyNet Edge site"
    uninstall_remove_file "$WEB_ROOT/sub" "URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash" "Clash 订阅文件"
    uninstall_remove_path "$EDGE_STATE_DIR" "Edge 状态"
    uninstall_remove_path "${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}" "Edge 证书目录"

    if command -v systemctl &>/dev/null; then
        systemctl restart nginx >/dev/null 2>&1 || true
    fi

    log_info "Edge Gateway 清理完成"
}

main "$@"
