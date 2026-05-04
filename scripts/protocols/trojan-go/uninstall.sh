#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="trojan-go"
CONFIG_DIR="${TROJAN_CONFIG_DIR:-/etc/trojan-go}"
DATA_DIR="${TROJAN_DATA_DIR:-/var/lib/trojan-go}"

main() {
    uninstall_services_for_module "$MODULE_NAME" trojan-go
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$CONFIG_DIR" "Trojan-Go 配置目录"
    uninstall_remove_path "$DATA_DIR" "Trojan-Go 数据目录"
    uninstall_remove_path "/etc/ssl/trojan-go" "Trojan-Go 证书目录"
    uninstall_remove_file "/usr/local/bin/trojan-go" "Trojan-Go 可执行文件"
    uninstall_remove_systemd_unit "trojan-go.service"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_refresh_runtime_state
    log_info "Trojan-Go 卸载完成"
}

main "$@"
