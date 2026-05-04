#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"
source "$CORE_DIR/env.sh"

NGINX_STATE_DIR="${EASYNET_NGINX_STATE_DIR:-$(easynet_nginx_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"

main() {
    uninstall_remove_file "/etc/nginx/sites-enabled/easynet-proxy" "EasyNet Nginx enabled site"
    uninstall_remove_file "/etc/nginx/sites-available/easynet-proxy" "EasyNet Nginx site"
    uninstall_remove_file "$WEB_ROOT/sub" "URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/sub_full" "完整 URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash" "Clash 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash_full" "完整 Clash 订阅文件"
    uninstall_remove_path "$NGINX_STATE_DIR" "Nginx 暴露层状态"

    if command -v systemctl &>/dev/null; then
        systemctl restart nginx >/dev/null 2>&1 || true
    fi

    uninstall_apt_purge nginx
    log_info "Nginx 暴露层清理完成"
}

main "$@"
