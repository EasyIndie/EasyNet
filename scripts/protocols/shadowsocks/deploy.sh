#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"

CONFIG_DIR="${SHADOWSOCKS_CONFIG_DIR:-/etc/shadowsocks-libev}"

generate_password() {
    openssl rand -hex 16
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

install_shadowsocks() {
    log_info "安装 Shadowsocks-libev..."
    apt install -y shadowsocks-libev
}

configure_shadowsocks() {
    log_info "配置 Shadowsocks-libev..."
    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Shadowsocks 配置，跳过生成新密码，直接使用现有配置。"
        PASSWORD=$(jq -r '.password' "$CONFIG_DIR/config.json")
        PORT=$(jq -r '.server_port' "$CONFIG_DIR/config.json")
        PUBLIC_IP=$(get_public_ip)
    else
        PASSWORD=$(generate_password)
        PORT="${EASYNET_SHADOWSOCKS_PORT:-8388}"
        PUBLIC_IP=$(get_public_ip)

        cat > "$CONFIG_DIR/config.json" << EOF
{
    "server": ["0.0.0.0", "::0"],
    "server_port": $PORT,
    "password": "$PASSWORD",
    "timeout": 60,
    "method": "chacha20-ietf-poly1305"
}
EOF

        log_info "Shadowsocks 配置文件已创建"
    fi
}

create_systemd_service() {
    log_info "创建 systemd 服务..."

    systemctl stop shadowsocks-libev || true
    systemctl disable shadowsocks-libev || true

    cat > /etc/systemd/system/shadowsocks-libev-server.service << 'EOF'
[Unit]
Description=Shadowsocks-libev Server
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json -s 0.0.0.0 -u
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks-libev-server
    systemctl restart shadowsocks-libev-server
}

show_config() {
    local userinfo config_url
    userinfo=$(printf '%s' "chacha20-ietf-poly1305:$PASSWORD" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')
    config_url="ss://${userinfo}@${PUBLIC_IP}:${PORT}#EasyNet-SS"

    echo ""
    echo "========================================"
    echo "  Shadowsocks 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密方式: chacha20-ietf-poly1305"
    echo ""
    echo "SS 链接: $config_url"
    echo ""
    echo "配置二维码:"
    if command -v qrencode &>/dev/null; then
        qrencode -t utf8 "$config_url"
    else
        echo "未安装 qrencode，无法显示二维码。"
    fi
    echo ""
    echo "安全提示: Shadowsocks 仅建议作为兼容或测试方案，抗 DPI 能力低于 Reality/Hysteria2/Trojan-Go。"
    echo "========================================"
}

main() {
    install_shadowsocks
    configure_shadowsocks
    create_systemd_service
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
