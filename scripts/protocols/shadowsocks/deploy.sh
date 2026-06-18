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
SS_VERSION="${SS_VERSION:-1.22.0}"

install_shadowsocks() {
    if command -v ssserver &>/dev/null; then
        local inst_ver
        inst_ver=$(ssserver --version 2>&1 | grep -oP '[\d]+\.[\d]+\.[\d]+' || echo "0")
        log_info "检测到已安装的 shadowsocks-rust v${inst_ver}，跳过安装。"
        return
    fi

    # Check if cargo-installed
    if [ -x "$SS_BIN" ]; then
        log_info "检测到 $SS_BIN，跳过安装。"
        return
    fi

    log_info "安装 shadowsocks-rust v${SS_VERSION}..."
    local arch
    arch=$(detect_rust_target)

    local tar_file="shadowsocks-v${SS_VERSION}.${arch}.tar.xz"
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${SS_VERSION}/${tar_file}"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    log_info "下载 $url ..."
    curl -fsSL -o "$tmp_dir/$tar_file" "$url" || {
        log_error "下载 shadowsocks-rust 失败，请检查网络或架构兼容性。"
        exit 1
    }

    if [ -n "${EASYNET_SHADOWSOCKS_INSTALL_SHA256:-}" ]; then
        log_info "校验 SHA256..."
        echo "${EASYNET_SHADOWSOCKS_INSTALL_SHA256}  $tmp_dir/$tar_file" | sha256sum -c
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

    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Shadowsocks 配置，跳过生成新密钥，直接使用现有配置。"
        PSK=$(jq -r '.servers[0].password // empty' "$CONFIG_DIR/config.json")
        PORT=$(jq -r '.servers[0].server_port // empty' "$CONFIG_DIR/config.json")
        METHOD=$(jq -r '.servers[0].method // "2022-blake3-aes-256-gcm"' "$CONFIG_DIR/config.json")
        PUBLIC_IP=$(get_public_ip)
    else
        PSK=$(generate_psk)
        PORT="${EASYNET_SHADOWSOCKS_PORT:-8388}"
        METHOD="2022-blake3-aes-256-gcm"
        PUBLIC_IP=$(get_public_ip)

        cat > "$CONFIG_DIR/config.json" << EOF
{
    "servers": [
        {
            "server": "0.0.0.0",
            "server_port": $PORT,
            "method": "$METHOD",
            "password": "$PSK"
        }
    ]
}
EOF

        chmod 600 "$CONFIG_DIR/config.json"
        log_info "Shadowsocks 2022 配置文件已创建"
    fi
}

create_systemd_service() {
    log_info "创建 systemd 服务..."

    cat > /etc/systemd/system/shadowsocks-rust-server.service << 'EOF'
[Unit]
Description=Shadowsocks-rust Server (2022 Edition)
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
Group=nogroup
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
CapabilityBoundingSet=~
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json -U
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks-rust-server
    systemctl restart shadowsocks-rust-server
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
