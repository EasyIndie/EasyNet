#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"
source "$CORE_DIR/env.sh"

EDGE_STATE_DIR="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"

main() {
    # 只清理「我们生成的」默认伪装站文件。EASYNET_EDGE_SITE_DIR 带来的自带内容
    # 或用户手工替换的页面属于用户内容，不碰。
    if grep -q '^generated:' "$EDGE_STATE_DIR/camouflage_site.state" 2>/dev/null; then
        uninstall_remove_file "$WEB_ROOT/index.html" "默认伪装站首页"
        uninstall_remove_file "$WEB_ROOT/404.html" "默认伪装站 404 页"
        uninstall_remove_file "$WEB_ROOT/robots.txt" "默认伪装站 robots.txt"
    fi
    uninstall_remove_file "/etc/nginx/sites-enabled/easynet-edge" "EasyNet Edge enabled site"
    uninstall_remove_file "/etc/nginx/sites-available/easynet-edge" "EasyNet Edge site"
    uninstall_remove_file "$WEB_ROOT/sub" "URI 订阅文件"
    uninstall_remove_file "$WEB_ROOT/clash" "Clash 订阅文件"
    uninstall_remove_file "$WEB_ROOT/singbox" "sing-box 配置文件"
    uninstall_remove_file "$WEB_ROOT/easynet-singbox-client.sh" "sing-box 客户端安装脚本"
    uninstall_remove_path "$WEB_ROOT/rules" "sing-box 分流规则集"
    uninstall_remove_path "$EDGE_STATE_DIR" "Edge 状态"
    # Cert fingerprint cache written by cert_renew_hook.sh: it lives outside the
    # Edge state dir, and leaving it behind would make the next reinstall skip the
    # post-renewal service restart.
    uninstall_remove_path "${EASYNET_STATE_DIR:-/var/lib/easynet}/edge" "Edge 证书指纹状态"
    uninstall_remove_path "${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}" "Edge 证书目录"
    uninstall_remove_hardening_dropin "nginx.service"

    # 恢复 Edge 安装时禁用的发行版默认站点（若发行版文件还在）
    if [ -f /etc/nginx/sites-available/default ] && [ ! -e /etc/nginx/sites-enabled/default ]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
        log_info "已恢复 nginx 默认站点"
    fi

    if command -v systemctl &>/dev/null; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
    fi

    log_info "Edge Gateway 清理完成"
}

main "$@"
