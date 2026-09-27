#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/download.sh"
source "$CORE_DIR/network.sh"
source "$CORE_DIR/display.sh"
source "$CORE_DIR/crypto.sh"

CONFIG_DIR="${SHADOWSOCKS_CONFIG_DIR:-/etc/shadowsocks-rust}"
SS_BIN="${SS_BIN:-/usr/local/bin/ssserver}"
SS_VERSION="${SS_VERSION:-1.24.0}"

install_shadowsocks() {
    if command -v ssserver &>/dev/null; then
        local inst_ver
        inst_ver=$(ssserver --version 2>&1 | grep -oP '[\d]+\.[\d]+\.[\d]+' || echo "0")
        log_info "检测到已安装的 shadowsocks-rust v${inst_ver}，跳过安装。"
        return
    fi

    # Check if cargo-installed
    if [ -x "$SS_BIN" ]; then
        log_info "检测到 ${SS_BIN}，跳过安装。"
        return
    fi

    log_info "安装 shadowsocks-rust v${SS_VERSION}..."
    local arch
    arch=$(detect_rust_target)

    local tar_file="shadowsocks-v${SS_VERSION}.${arch}.tar.xz"
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${SS_VERSION}/${tar_file}"

    local tmp_dir=""
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir:-}"' RETURN

    log_info "下载 $url ..."
    curl -fsSL -o "$tmp_dir/$tar_file" "$url" || {
        log_error "下载 shadowsocks-rust 失败，请检查网络或架构兼容性。"
        exit 1
    }

    local ss_sha256
    ss_sha256="${EASYNET_SHADOWSOCKS_INSTALL_SHA256:-}"
    if [ -n "$ss_sha256" ]; then
        log_info "校验 SHA256..."
        echo "$ss_sha256  $tmp_dir/$tar_file" | sha256sum -c
    fi

    tar -xJf "$tmp_dir/$tar_file" -C "$tmp_dir"
    local bin_path
    bin_path=$(find "$tmp_dir" -name ssserver -type f | head -1)
    if [ -z "$bin_path" ]; then
        log_error "未在归档中找到 ssserver 二进制文件。"
        exit 1
    fi

    install -m 755 "$bin_path" "$SS_BIN"
    log_info "shadowsocks-rust ssserver 已安装到 $SS_BIN"
}

configure_shadowsocks() {
    log_info "配置 Shadowsocks 2022 Edition..."
    mkdir -p "$CONFIG_DIR"

    local config_file="$CONFIG_DIR/config.json"

    # Preserve the PSK/port across re-deploys.
    if [ -f "$config_file" ] && grep -q "password" "$config_file"; then
        log_info "检测到已有的 Shadowsocks 配置，保留 PSK / 端口。"
        PSK=$(jq -r '.servers[0].password // empty' "$config_file")
        PORT=$(jq -r '.servers[0].server_port // empty' "$config_file")
        METHOD=$(jq -r '.servers[0].method // "2022-blake3-aes-256-gcm"' "$config_file")
    else
        PSK=""
        PORT=""
        METHOD=""
    fi

    [ -n "$PSK" ] || PSK=$(generate_psk)
    [ -n "$PORT" ] || PORT="${EASYNET_SHADOWSOCKS_PORT:-8388}"
    [ -n "$METHOD" ] || METHOD="2022-blake3-aes-256-gcm"
    PUBLIC_IP=$(get_public_ip)

    # Security: the PSK must never appear on the command line (world-readable via
    # /proc/<pid>/cmdline) and the config must not be world-readable. The service
    # runs as nobody:nogroup, so 640 root:nogroup is enough.
    jq -n --argjson port "$PORT" --arg method "$METHOD" --arg psk "$PSK" \
        '{servers: [{server: "0.0.0.0", server_port: $port, method: $method, password: $psk, mode: "tcp_and_udp"}]}' \
        > "$config_file.tmp"
    chown root:nogroup "$config_file.tmp" 2>/dev/null || true
    chmod 640 "$config_file.tmp"

    # Only replace (and later restart) when something actually changed, so a
    # re-deploy does not drop live Shadowsocks sessions.
    SS_CHANGED=false
    if ! cmp -s "$config_file.tmp" "$config_file"; then
        mv "$config_file.tmp" "$config_file"
        SS_CHANGED=true
        log_info "Shadowsocks 2022 配置已写入（640 root:nogroup，密钥仅存于配置文件）"
    else
        rm -f "$config_file.tmp"
        log_info "Shadowsocks 配置未变化。"
    fi
}

create_systemd_service() {
    log_info "创建 systemd 服务..."

    local unit=/etc/systemd/system/shadowsocks-rust-server.service
    local new_unit
    new_unit="$(mktemp)"

    # The PSK is read from the config file only -- never from the command line,
    # which any local user could read via /proc/<pid>/cmdline.
    # `CapabilityBoundingSet=` (empty set) drops all capabilities; note that
    # `CapabilityBoundingSet=~` would mean "grant everything", not "drop all".
    cat > "$new_unit" << 'EOF'
[Unit]
Description=Shadowsocks-rust Server (2022 Edition)
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
Group=nogroup
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectClock=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
ExecStart=/usr/local/bin/ssserver --config /etc/shadowsocks-rust/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    SS_UNIT_CHANGED=false
    if ! cmp -s "$new_unit" "$unit"; then
        install -m 644 "$new_unit" "$unit"
        SS_UNIT_CHANGED=true
    fi
    rm -f "$new_unit"

    systemctl daemon-reload
    systemctl enable shadowsocks-rust-server >/dev/null 2>&1 || true
    if [ "${SS_UNIT_CHANGED:-false}" = "true" ] || [ "${SS_CHANGED:-false}" = "true" ] ||
        ! systemctl is-active --quiet shadowsocks-rust-server; then
        systemctl restart shadowsocks-rust-server
    else
        log_info "Shadowsocks 配置未变化，跳过重启。"
    fi
}

show_config() {
    local userinfo config_url
    userinfo=$(printf '%s:%s' "$METHOD" "$PSK" | base64 -w 0 | tr '+/' '-_' | sed 's/=*$//')
    config_url="ss://${userinfo}@${PUBLIC_IP}:${PORT}#EasyNet-SS"

    echo ""
    echo "========================================"
    echo "  Shadowsocks 2022 Edition 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "PSK: $PSK"
    echo "加密方式: $METHOD"
    echo ""
    echo "SS 链接: $config_url"
    echo ""
    echo "配置二维码:"
    show_qrcode "$config_url" "配置二维码"
    echo ""
    echo "注意: Shadowsocks 2022 Edition 需要客户端支持 2022 加密方式。"
    echo "      Android/v2rayNG/Clash Verge Rev/Shadowrocket 均支持。"
    echo "========================================"
}

main() {
    install_shadowsocks
    configure_shadowsocks
    create_systemd_service
    show_config
}

main "$@"
