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

# ── 订阅站镜像（设备自愈）────────────────────────────────────────────────────
# 设备（树莓派等）在国内常无法直连 GitHub release（实测卡死），所以服务端把
# pinned 原包也发布到订阅站；安装器与每日更新都优先走镜像，GitHub 兜底，
# 两个来源都必须通过同一个 pin 哈希。

@test "Installer prefers the subscription mirror, then GitHub" {
    run bash -c "
        source '$INSTALLER'
        CONFIG_URL='https://d.example.com/s/PREFIX/singbox'
        resolve_singbox_download
        printf '%s\n' \"\${SINGBOX_SOURCE_URLS[@]}\"
    "
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
    [ "$(printf '%s\n' "$output" | sed -n 1p)" = "https://d.example.com/s/PREFIX/bin/sing-box-${PINNED_VERSION:-}$(printf '')" ] || \
        [[ "$(printf '%s\n' "$output" | sed -n 1p)" == https://d.example.com/s/PREFIX/bin/sing-box-*.tar.gz ]]
    [[ "$(printf '%s\n' "$output" | sed -n 2p)" == https://github.com/SagerNet/sing-box/releases/download/* ]]
}

@test "Explicit --sing-box-url is used alone (no mirror)" {
    run bash -c "
        source '$INSTALLER'
        CONFIG_URL='https://d.example.com/s/PREFIX/singbox'
        SINGBOX_URL='https://example.net/custom.tar.gz'
        SB_SHA256='$(printf '0%.0s' {1..64})'
        resolve_singbox_download
        printf '%s\n' \"\${SINGBOX_SOURCE_URLS[@]}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.net/custom.tar.gz" ]
}

@test "Mirror can be disabled with EASYNET_SINGBOX_MIRROR=false" {
    run bash -c "
        source '$INSTALLER'
        CONFIG_URL='https://d.example.com/s/PREFIX/singbox'
        EASYNET_SINGBOX_MIRROR=false resolve_singbox_download
        printf '%s\n' \"\${SINGBOX_SOURCE_URLS[@]}\"
    "
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
    [[ "$output" == https://github.com/* ]]
}

@test "Installer writes the pinned version and service name into the client env" {
    local dir="$BATS_TEST_TMPDIR/install"
    mkdir -p "$dir"
    run bash -c "
        source '$INSTALLER'
        INSTALL_DIR='$dir'
        STATE_DIR='$BATS_TEST_TMPDIR/state'
        CONFIG_DIR='$BATS_TEST_TMPDIR/etc-sing-box'
        CONFIG_URL='https://d.example.com/s/P/singbox'
        write_state
        cat '$BATS_TEST_TMPDIR/state/singbox-client.env'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"PINNED_SINGBOX_VERSION=${PINNED_VERSION:-}"* ]]
    [[ "$output" == *"PINNED_SINGBOX_SHA256_LINUX_ARM64="* ]]
    [[ "$output" == *"SINGBOX_SERVICE="* ]]
}

@test "Generated daily updater aligns the sing-box binary version" {
    local dir="$BATS_TEST_TMPDIR/updater"
    mkdir -p "$dir"
    run bash -c "
        source '$INSTALLER'
        INSTALL_DIR='$dir'
        write_update_script
        cat '$dir/easynet-singbox-update'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"align_singbox_binary"* ]]
    # 镜像优先：base/bin/<asset>，随后 GitHub
    [[ "$output" == *'${base}/bin/${asset}'* ]]
    [[ "$output" == *"releases/download/v\${want}/\${asset}"* ]]
    # 二进制变化也要触发重启
    [[ "$output" == *'[ "${bin_changed:-no}" = "yes" ]'* ]]
    # 校验失败只告警、不中断（代理照旧可用）
    [[ "$output" == *"沿用当前版本"* ]]
}

@test "Daily updater upgrades sing-box following the subscription manifest" {
    # 平台限制：更新脚本只处理 Linux 架构（客户端安装器本身只支持 Linux）
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64 | Linux/amd64) arch="linux-amd64" ;;
        Linux/aarch64 | Linux/arm64) arch="linux-arm64" ;;
        *) skip "本平台不是 Linux（更新脚本的架构分支只覆盖 linux-amd64/arm64）" ;;
    esac

    local work="$BATS_TEST_TMPDIR/upd"
    mkdir -p "$work/mirror/bin" "$work/inst" "$work/bin"
    # 伪造订阅站镜像：一个 9.9.9 版本的"原包"（内含 stub sing-box）+ manifest
    printf '#!/bin/sh\necho "sing-box version 9.9.9"\n' > "$work/stub-sing-box"
    chmod +x "$work/stub-sing-box"
    tar -czf "$work/mirror/bin/sing-box-9.9.9-${arch}.tar.gz" -C "$work" stub-sing-box
    if command -v sha256sum >/dev/null 2>&1; then
        sha="$(sha256sum "$work/mirror/bin/sing-box-9.9.9-${arch}.tar.gz" | awk '{print $1}')"
    else
        sha="$(shasum -a 256 "$work/mirror/bin/sing-box-9.9.9-${arch}.tar.gz" | awk '{print $1}')"
    fi
    printf '{"schemaVersion":1,"tool":"sing-box","version":"9.9.9","files":[{"platform":"%s","asset":"sing-box-9.9.9-%s.tar.gz","sha256":"%s","size":1}]}\n' \
        "${arch/-/_}" "$arch" "$sha" > "$work/mirror/bin/manifest.json"

    # 现有二进制（旧版本）+ 从生成的更新脚本里取出 align 函数
    printf '#!/bin/sh\necho "sing-box version 1.0.0"\n' > "$work/bin/sing-box"
    chmod +x "$work/bin/sing-box"
    bash -c "source '$INSTALLER'; INSTALL_DIR='$work/inst'; write_update_script"
    awk '/^align_singbox_binary\(\)/,/^}/' "$work/inst/easynet-singbox-update" > "$work/align.sh"
    grep -q 'align_singbox_binary' "$work/align.sh"

    run bash -c "
        set -u
        SINGBOX_BIN='$work/bin/sing-box'
        SINGBOX_CONFIG_URL='file://$work/mirror/singbox'
        PINNED_SINGBOX_VERSION='1.0.0'
        source '$work/align.sh'
        align_singbox_binary
        printf 'version=%s changed=%s\n' \"\$('$work/bin/sing-box' version | awk '{print \$3}')\" \"\$bin_changed\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"version=9.9.9"* ]]
    [[ "$output" == *"changed=yes"* ]]
}

@test "Daily updater keeps the current binary when the mirror has nothing newer" {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64 | Linux/amd64) arch="linux-amd64" ;;
        Linux/aarch64 | Linux/arm64) arch="linux-arm64" ;;
        *) skip "非 Linux 平台" ;;
    esac
    local work="$BATS_TEST_TMPDIR/upd2"
    mkdir -p "$work/inst" "$work/bin"
    printf '#!/bin/sh\necho "sing-box version 1.14.2"\n' > "$work/bin/sing-box"
    chmod +x "$work/bin/sing-box"
    bash -c "source '$INSTALLER'; INSTALL_DIR='$work/inst'; write_update_script"
    awk '/^align_singbox_binary\(\)/,/^}/' "$work/inst/easynet-singbox-update" > "$work/align.sh"

    # 镜像不可达 + env 里的 pin 与当前版本一致 → 什么都不做
    run bash -c "
        set -u
        SINGBOX_BIN='$work/bin/sing-box'
        SINGBOX_CONFIG_URL='https://127.0.0.1:9/s/P/singbox'
        PINNED_SINGBOX_VERSION='1.14.2'
        source '$work/align.sh'
        align_singbox_binary
        printf 'version=%s changed=%s\n' \"\$('$work/bin/sing-box' version | awk '{print \$3}')\" \"\$bin_changed\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"version=1.14.2"* ]]
    [[ "$output" == *"changed=no"* ]]
}
