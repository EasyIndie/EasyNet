#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="shadowsocks"
CONFIG_DIR="${SHADOWSOCKS_CONFIG_DIR:-/etc/shadowsocks-libev}"

main() {
    uninstall_services_for_module "$MODULE_NAME" shadowsocks-libev-server shadowsocks-libev
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$CONFIG_DIR" "Shadowsocks 配置目录"
    uninstall_remove_systemd_unit "shadowsocks-libev-server.service"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_apt_purge shadowsocks-libev
    uninstall_refresh_runtime_state
    log_info "Shadowsocks 卸载完成"
}

main "$@"
