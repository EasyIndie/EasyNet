#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="hysteria2"
HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_SERVICE="${HYSTERIA2_SERVICE:-hysteria-server.service}"

main() {
    uninstall_services_for_module "$MODULE_NAME" "$HYSTERIA2_SERVICE"
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$HYSTERIA2_CONFIG_DIR" "Hysteria2 配置目录"
    uninstall_remove_file "/usr/local/bin/hysteria" "Hysteria2 可执行文件"
    uninstall_remove_file "/etc/systemd/system/$HYSTERIA2_SERVICE" "Hysteria2 systemd unit"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_refresh_runtime_state
    log_info "Hysteria2 卸载完成"
}

main "$@"
