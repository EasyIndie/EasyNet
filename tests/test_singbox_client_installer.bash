#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "sing-box Client Installer"

INSTALLER="$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"

if bash -n "$INSTALLER"; then
    installer_syntax_ok="true"
else
    installer_syntax_ok="false"
fi
assert_equals "true" "$installer_syntax_ok" "sing-box client installer has valid shell syntax"

if rg -q "detect_asset_arch" "$INSTALLER" \
    && rg -q "linux-arm64" "$INSTALLER" \
    && rg -q "linux-armv7" "$INSTALLER" \
    && rg -q "linux-armv6" "$INSTALLER"; then
    installer_detects_pi_arch="true"
else
    installer_detects_pi_arch="false"
fi
assert_equals "true" "$installer_detects_pi_arch" "Installer detects Raspberry Pi Linux architectures"

if rg -q 'trap '\''rm -rf "\$\{tmp_dir:-\}"'\'' RETURN' "$INSTALLER" \
    && ! rg -q 'trap '\''rm -rf "\$tmp_dir"'\'' EXIT' "$INSTALLER"; then
    installer_cleans_temp_dir_safely="true"
else
    installer_cleans_temp_dir_safely="false"
fi
assert_equals "true" "$installer_cleans_temp_dir_safely" "Installer cleans temporary download directory without unbound local variables"

if rg -q "easynet-singbox-update" "$INSTALLER" \
    && rg -q "sing-box check -c|\\$SINGBOX_BIN\" check -c" "$INSTALLER" \
    && rg -q "RandomizedDelaySec" "$INSTALLER" \
    && rg -q "OnUnitActiveSec=1d" "$INSTALLER"; then
    installer_has_update_flow="true"
else
    installer_has_update_flow="false"
fi
assert_equals "true" "$installer_has_update_flow" "Installer creates checked daily config update flow"

if rg -q -- "--mode" "$INSTALLER" \
    && rg -q "SINGBOX_MODE" "$INSTALLER" \
    && rg -q 'type: "mixed"' "$INSTALLER" \
    && rg -q 'type: "tun"' "$INSTALLER" \
    && rg -q 'auto_route: true' "$INSTALLER" \
    && rg -q 'strict_route: true' "$INSTALLER"; then
    installer_supports_modes="true"
else
    installer_supports_modes="false"
fi
assert_equals "true" "$installer_supports_modes" "Installer supports mixed and tun modes"

if rg -q 'tag: "remote-dns"' "$INSTALLER" \
    && rg -q 'detour: "Proxy"' "$INSTALLER" \
    && rg -q "server_domains" "$INSTALLER" \
    && rg -q 'action: "hijack-dns"' "$INSTALLER" \
    && rg -q "default_domain_resolver" "$INSTALLER" \
    && rg -q 'server: "local-dns"' "$INSTALLER"; then
    installer_tun_handles_dns="true"
else
    installer_tun_handles_dns="false"
fi
assert_equals "true" "$installer_tun_handles_dns" "Installer configures DNS hijack and domain resolver for tun mode"

if rg -q "easynet-singbox.service|SERVICE_NAME" "$INSTALLER" \
    && rg -q "ExecStart=.*sing-box run -c" "$INSTALLER" \
    && rg -q "systemctl enable --now" "$INSTALLER"; then
    installer_has_service_flow="true"
else
    installer_has_service_flow="false"
fi
assert_equals "true" "$installer_has_service_flow" "Installer creates and starts a dedicated systemd service"

if rg -q 'start|stop|restart|status|update|doctor' "$INSTALLER" \
    && rg -q "switch-mode" "$INSTALLER" \
    && rg -q "print_status()" "$INSTALLER" \
    && rg -q "当前模式" "$INSTALLER" \
    && rg -q 'systemctl start "\$\{SERVICE_NAME\}\.service"' "$INSTALLER" \
    && rg -q 'systemctl stop "\$\{SERVICE_NAME\}\.service"' "$INSTALLER" \
    && rg -q 'systemctl restart "\$\{SERVICE_NAME\}\.service"' "$INSTALLER"; then
    installer_has_control_commands="true"
else
    installer_has_control_commands="false"
fi
assert_equals "true" "$installer_has_control_commands" "Installer supports service control commands"

if rg -q "doctor()" "$INSTALLER" \
    && rg -q "7890 监听状态" "$INSTALLER" \
    && rg -q "journalctl -u" "$INSTALLER" \
    && rg -q "jq '.inbounds'" "$INSTALLER" \
    && rg -q "代理连通性测试" "$INSTALLER" \
    && rg -q "诊断结论" "$INSTALLER" \
    && rg -q "代理正常" "$INSTALLER" \
    && rg -q "socks5h://127.0.0.1:7890" "$INSTALLER" \
    && rg -q "EASYNET_SINGBOX_PROBE_URL" "$INSTALLER"; then
    installer_has_doctor="true"
else
    installer_has_doctor="false"
fi
assert_equals "true" "$installer_has_doctor" "Installer can diagnose proxy connectivity and print a conclusion"

if rg -q "update_saved_mode" "$INSTALLER" \
    && rg -q "switch_mode()" "$INSTALLER" \
    && rg -q "service_stop_wait" "$INSTALLER" \
    && rg -q "service_start_checked" "$INSTALLER" \
    && rg -q "grep -q '\\^SINGBOX_MODE='" "$INSTALLER" \
    && rg -q "printf.*SINGBOX_MODE" "$INSTALLER" \
    && rg -q "sing-box 客户端模式已切换为" "$INSTALLER"; then
    installer_can_switch_mode="true"
else
    installer_can_switch_mode="false"
fi
assert_equals "true" "$installer_can_switch_mode" "Installer switches mode without reinstalling"

if rg -q 'systemctl stop "\$\{SERVICE_NAME\}\.service" \|\| true' "$INSTALLER" \
    && rg -q 'systemctl is-active --quiet "\$\{SERVICE_NAME\}\.service"' "$INSTALLER" \
    && rg -q "previous_mode" "$INSTALLER" \
    && rg -q "恢复原模式" "$INSTALLER" \
    && rg -q 'systemctl start "\$\{SERVICE_NAME\}\.service"' "$INSTALLER"; then
    installer_switches_mode_safely="true"
else
    installer_switches_mode_safely="false"
fi
assert_equals "true" "$installer_switches_mode_safely" "Installer stops service and rolls back on mode switch failure"

test_end
