#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export INSTALLER="$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
}

@test "sing-box client installer has valid shell syntax" {
    run bash -n "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer detects Raspberry Pi Linux architectures" {
    run rg -q "detect_asset_arch" "$INSTALLER"
    [ "$status" -eq 0 ]
    rg -q "linux-arm64" "$INSTALLER"
    rg -q "linux-armv7" "$INSTALLER"
    rg -q "linux-armv6" "$INSTALLER"
}

@test "Installer cleans temporary download directory without unbound local variables" {
    run rg -q 'trap '\''rm -rf "\$\{tmp_dir:-\}"'\'' RETURN' "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q 'trap '\''rm -rf "\$tmp_dir"'\'' EXIT' "$INSTALLER"
    [ "$status" -eq 1 ]
}

@test "Installer creates checked daily config update flow" {
    rg -q "easynet-singbox-update" "$INSTALLER"
    rg -q "sing-box check -c|\\$SINGBOX_BIN\" check -c" "$INSTALLER"
    rg -q "RandomizedDelaySec" "$INSTALLER"
    rg -q "OnUnitActiveSec=1d" "$INSTALLER"
}

@test "Installer supports mixed and tun modes" {
    rg -q -- "--mode" "$INSTALLER"
    rg -q "SINGBOX_MODE" "$INSTALLER"
    rg -q 'type: "mixed"' "$INSTALLER"
    rg -q 'type: "tun"' "$INSTALLER"
}

@test "Installer configures DNS hijack and domain resolver for tun mode" {
    rg -q 'tag: "remote-dns"' "$INSTALLER"
    rg -q 'detour: "Proxy"' "$INSTALLER"
    rg -q "default_domain_resolver" "$INSTALLER"
}

@test "Installer creates and starts a dedicated systemd service" {
    rg -q "easynet-singbox.service|SERVICE_NAME" "$INSTALLER"
    rg -q "ExecStart=.*sing-box run -c" "$INSTALLER"
    rg -q "systemctl enable --now" "$INSTALLER"
}

@test "Installer supports service control commands" {
    rg -q 'start|stop|restart|status|update|doctor' "$INSTALLER"
    rg -q "switch-mode" "$INSTALLER"
    rg -q "print_status()" "$INSTALLER"
}

@test "Installer can diagnose proxy connectivity and print a conclusion" {
    rg -q "doctor()" "$INSTALLER"
    rg -q "代理连通性测试" "$INSTALLER"
    rg -q "诊断结论" "$INSTALLER"
    rg -q "代理正常" "$INSTALLER"
}

@test "Installer switches mode without reinstalling" {
    rg -q "switch_mode()" "$INSTALLER"
    rg -q "update_saved_mode" "$INSTALLER"
    rg -q "service_stop_wait" "$INSTALLER"
}

@test "Installer stops service and rolls back on mode switch failure" {
    rg -q 'systemctl stop "\$\{SERVICE_NAME\}\.service" \|\| true' "$INSTALLER"
    rg -q "previous_mode" "$INSTALLER"
    rg -q "恢复原模式" "$INSTALLER"
}

@test "Installer covers all 4 target architectures in detect_asset_arch" {
    # Static check that the function maps all expected architectures
    rg -q "linux-arm64" "$INSTALLER"
    rg -q "linux-armv7" "$INSTALLER"
    rg -q "linux-armv6" "$INSTALLER"
    rg -q "linux-amd64" "$INSTALLER"
}

@test "Installer write_state template includes all required env vars" {
    # Verify the env file template includes all required variables
    rg -q "SINGBOX_CONFIG_URL" "$INSTALLER"
    rg -q "SINGBOX_CONFIG_FILE" "$INSTALLER"
    rg -q "SINGBOX_BIN" "$INSTALLER"
    rg -q "SINGBOX_MODE" "$INSTALLER"
}

@test "Installer systemd service template has correct structure" {
    # Verify systemd unit has required directives
    rg -q "DynamicUser=yes" "$INSTALLER"
    rg -q "ProtectSystem=full" "$INSTALLER"
    rg -q "PrivateTmp=yes" "$INSTALLER"
    rg -q "NoNewPrivileges=yes" "$INSTALLER"
    rg -q "Restart=on-failure" "$INSTALLER"
}

@test "Installer update timer uses OnUnitActiveSec for daily schedule" {
    rg -q "OnUnitActiveSec=1d" "$INSTALLER"
    rg -q "RandomizedDelaySec" "$INSTALLER"
    rg -q "Persistent=true" "$INSTALLER"
}
