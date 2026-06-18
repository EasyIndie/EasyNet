#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/uninstall.sh"

MODULE_NAME="wireguard"
WG_DIR="${WG_DIR:-/etc/wireguard}"

main() {
    uninstall_services_for_module "$MODULE_NAME" wg-quick@wg0
    uninstall_delete_firewall_rules "$MODULE_NAME"
    uninstall_remove_path "$WG_DIR" "WireGuard 配置目录"
    uninstall_remove_file "/etc/sysctl.d/wireguard.conf" "WireGuard sysctl 配置"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_apt_purge wireguard wireguard-tools
    uninstall_refresh_runtime_state
    log_info "WireGuard 卸载完成"
}

main "$@"
