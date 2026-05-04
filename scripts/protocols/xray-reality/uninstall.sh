#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="xray-reality"
XRAY_DIR="${XRAY_DIR:-/usr/local/etc/xray}"

main() {
    uninstall_services_for_module "$MODULE_NAME" xray
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$XRAY_DIR" "Xray 配置目录"
    uninstall_remove_file "/usr/local/bin/xray" "Xray 可执行文件"
    uninstall_remove_file "/etc/systemd/system/xray.service" "Xray systemd unit"
    uninstall_remove_path "/usr/local/share/xray" "Xray 资源目录"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_refresh_runtime_state
    log_info "Xray+Reality 卸载完成"
}

main "$@"
