#!/bin/bash

set -euo pipefail

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
    # Legacy upstream-installer drop-in (Xray-install). It resets and re-sets
    # ExecStart, so a stale copy would silently override our unit if the config
    # path ever changed. Remove it before the hardening drop-in so the now-empty
    # .d directory can be pruned too.
    uninstall_remove_file "/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf" "旧版 Xray 安装脚本 drop-in"
    uninstall_remove_hardening_dropin "xray.service"
    # Legacy upstream-installer template unit (Xray-install created this before we
    # started writing xray.service ourselves). Inert, but it confuses operators.
    uninstall_remove_file "/etc/systemd/system/xray@.service" "旧版 Xray 模板单元"
    uninstall_remove_path "/etc/systemd/system/xray@.service.d" "旧版 Xray 模板单元 drop-in"
    uninstall_remove_path "/usr/local/share/xray" "Xray 资源目录"
    uninstall_remove_module_metadata "$MODULE_NAME"
    uninstall_refresh_runtime_state
    log_info "Xray+Reality 卸载完成"
}

main "$@"
