#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="v2ray"
CONFIG_DIR="${V2RAY_CONFIG_DIR:-/usr/local/etc/v2ray}"
DATA_DIR="${V2RAY_DATA_DIR:-/var/lib/v2ray}"

main() {
    uninstall_services_for_module "$MODULE_NAME" v2ray
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$CONFIG_DIR" "V2Ray 配置目录"
    uninstall_remove_path "$DATA_DIR" "V2Ray 数据目录"
    uninstall_remove_path "/etc/ssl/v2ray" "V2Ray 证书目录"
    uninstall_remove_file "/usr/local/bin/v2ray" "V2Ray 可执行文件"
    uninstall_remove_file "/usr/local/bin/v2ctl" "V2Ray v2ctl"
    uninstall_remove_path "/usr/local/share/v2ray" "V2Ray 资源目录"
    uninstall_remove_systemd_unit "v2ray.service"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_refresh_runtime_state
    log_info "V2Ray 卸载完成"
}

main "$@"
