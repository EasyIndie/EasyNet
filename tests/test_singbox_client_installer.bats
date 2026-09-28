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
    rg -q 'check -c' "$INSTALLER"
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

@test "Installer materializes rule sets locally and rewrites remote to local" {
    rg -q "rule-set decompile" "$INSTALLER"
    rg -q 'type: "local"' "$INSTALLER"
    rg -q "rules/manifest.json" "$INSTALLER"
    rg -q "sha256sum" "$INSTALLER"
}

@test "Installer restarts the service after installing a changed config" {
    rg -q "systemctl restart" "$INSTALLER"
    rg -q 'SINGBOX_SERVICE:-easynet-singbox' "$INSTALLER"
    rg -q "cmp -s" "$INSTALLER"
}

@test "Installer guards config shape and degrades when rules are unavailable" {
    rg -q "配置形状异常" "$INSTALLER"
    rg -q 'outbounds \| type == "array"' "$INSTALLER"
    rg -q "本次配置不启用分流规则" "$INSTALLER"
}

@test "Installer update unit can read its env file and write config/rules" {
    # The updater reads the 600-root env file, rewrites the config, materializes
    # rule sets and restarts the service: it must run as root with explicit
    # write paths. DynamicUser + ProtectSystem=full breaks it
    # ("/etc/easynet/singbox-client.env: Permission denied").
    update_unit="$(sed -n '/UPDATE_NAME}.service/,/^EOF/p' "$INSTALLER")"
    ! printf '%s' "$update_unit" | rg -q 'DynamicUser=yes'
    printf '%s' "$update_unit" | rg -q 'ProtectSystem=strict'
    printf '%s' "$update_unit" | rg -q 'ReadWritePaths=\$\{STATE_DIR\} \$\{CONFIG_DIR\}'
}

@test "Client mixed listener is configurable and warns on non-loopback binding" {
    # Documented option
    run rg -q -- '--listen-address' "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 0 ]
    # Validation rejects non-IP values
    run rg -q 'listen-address 只能是 IP 地址' "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 0 ]
    # Warns when binding beyond loopback (open proxy risk)
    run rg -q '开放代理' "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 0 ]
    # Persisted so the daily updater keeps the same bind address
    run rg -q "^SINGBOX_LISTEN='\\\$LISTEN_ADDRESS'" "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 0 ]
}

@test "Client config generator reads the listen address at runtime (not build time)" {
    # The jq block lives inside the quoted updater heredoc, so it must reference
    # the runtime env var with a default, not the installer's shell variable.
    run rg -q 'jq --arg listen "\$\{SINGBOX_LISTEN:-0\.0\.0\.0\}"' "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 0 ]
    # And it must not be hardcoded any more
    run rg -q 'listen: "0\.0\.0\.0"' "$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
    [ "$status" -eq 1 ]
}

# ── 版本固定（pin）───────────────────────────────────────────────────────────
# 客户端安装器运行在用户设备上并以 root 执行：裸拉 latest 等于把上游的任何
# 字节变化直接引入设备（服务端四个组件都有 pin，客户端不能例外）。

@test "Installer pins sing-box version and SHA256 per architecture" {
    rg -q 'PINNED_SINGBOX_VERSION="[0-9]' "$INSTALLER"
    rg -q 'PINNED_SINGBOX_SHA256_LINUX_AMD64="[0-9a-f]{64}"' "$INSTALLER"
    rg -q 'PINNED_SINGBOX_SHA256_LINUX_ARM64="[0-9a-f]{64}"' "$INSTALLER"
    run rg -q 'releases/latest' "$INSTALLER"
    [ "$status" -eq 1 ]
}

@test "Installer pins stay in sync with core/pins.sh (drift guard)" {
    local installer_version pins_version
    installer_version="$(sed -n 's/^PINNED_SINGBOX_VERSION="\(.*\)"$/\1/p' "$INSTALLER" | awk 'NR==1')"
    pins_version="$(bash -c "source \"$PROJECT_ROOT/scripts/core/pins.sh\"; printf '%s' \"\$EASYNET_PIN_SINGBOX_VERSION\"")"
    [ -n "$installer_version" ]
    [ "$installer_version" = "$pins_version" ]

    local arch_var installer_hash pins_hash pins_var
    for arch_var in LINUX_AMD64 LINUX_ARM64; do
        pins_var="EASYNET_PIN_SINGBOX_SHA256_${arch_var}"
        installer_hash="$(sed -n "s/^PINNED_SINGBOX_SHA256_${arch_var}=\"\\(.*\\)\"\$/\\1/p" "$INSTALLER" | awk 'NR==1')"
        pins_hash="$(bash -c "source \"$PROJECT_ROOT/scripts/core/pins.sh\"; printf '%s' \"\$$pins_var\"")"
        [ "$installer_hash" = "$pins_hash" ] || {
            echo "# $arch_var 不一致: installer=$installer_hash pins=$pins_hash" >&3
            return 1
        }
    done
}

@test "Pinned version resolves to the official asset URL and checksum" {
    run bash -c "
        source '$INSTALLER'
        SB_VERSION=\"\$PINNED_SINGBOX_VERSION\"
        SB_SHA256=''
        resolve_singbox_download
        printf '%s\n%s\n' \"\$SINGBOX_URL\" \"\$SB_SHA256\"
    "
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | awk 'NR==1')" == */releases/download/v*/*.tar.gz ]]
    [[ "$(printf '%s' "$output" | sed -n '1p')" == *"sing-box-"*"-linux-"*".tar.gz" ]]
    [[ "$(printf '%s' "$output" | sed -n '2p')" =~ ^[0-9a-f]{64}$ ]]
}

@test "Overriding the version without a checksum is refused" {
    run bash -c "
        source '$INSTALLER'
        SB_VERSION='9.9.9'
        SB_SHA256=''
        SB_SKIP_SHA256='false'
        resolve_singbox_download
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"EASYNET_SINGBOX_INSTALL_SHA256"* ]]
}

@test "Overriding requires nothing when a checksum is supplied" {
    run bash -c "
        source '$INSTALLER'
        SB_VERSION='9.9.9'
        SB_SHA256='$(printf '0%.0s' {1..64})'
        resolve_singbox_download
        printf '%s' \"\$SINGBOX_URL\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"v9.9.9/sing-box-9.9.9-"* ]]
}

@test "Explicit skip flag allows an unverifiable download" {
    run bash -c "
        source '$INSTALLER'
        SB_VERSION='9.9.9'
        SB_SHA256=''
        SB_SKIP_SHA256='true'
        resolve_singbox_download
    "
    [ "$status" -eq 0 ]
}
