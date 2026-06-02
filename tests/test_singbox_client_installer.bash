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

if rg -q "easynet-singbox.service|SERVICE_NAME" "$INSTALLER" \
    && rg -q "ExecStart=.*sing-box run -c" "$INSTALLER" \
    && rg -q "systemctl enable --now" "$INSTALLER"; then
    installer_has_service_flow="true"
else
    installer_has_service_flow="false"
fi
assert_equals "true" "$installer_has_service_flow" "Installer creates and starts a dedicated systemd service"

if rg -q 'start\|stop\|restart\|status\|update' "$INSTALLER" \
    && rg -q 'systemctl start "\$\{SERVICE_NAME\}\.service"' "$INSTALLER" \
    && rg -q 'systemctl stop "\$\{SERVICE_NAME\}\.service"' "$INSTALLER" \
    && rg -q 'systemctl restart "\$\{SERVICE_NAME\}\.service"' "$INSTALLER"; then
    installer_has_control_commands="true"
else
    installer_has_control_commands="false"
fi
assert_equals "true" "$installer_has_control_commands" "Installer supports service control commands"

test_end
