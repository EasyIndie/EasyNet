#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

CONFIG_DIR="/etc/shadowsocks-libev"

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

    # 检查是否是恢复模式（配置已存在）
    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Shadowsocks 配置，跳过生成新密码，直接使用现有配置。"
        PASSWORD=$(jq -r '.password' "$CONFIG_DIR/config.json")
        PORT=$(jq -r '.server_port' "$CONFIG_DIR/config.json")
        PUBLIC_IP=$(get_public_ip)
    else
        PASSWORD=$(generate_password)
        PORT=8388
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
    
    # 停止并禁用默认安装的服务（它可能会覆盖我们的配置）
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
# 强制使用 0.0.0.0 覆盖任何默认绑定，并指定配置文件
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

setup_firewall() {
    log_info "配置防火墙..."
    if command -v ufw &>/dev/null; then
        ufw allow "$PORT/tcp"
        ufw allow "$PORT/udp"
    fi
}

show_config() {
    echo ""
    echo "========================================"
    echo "  Shadowsocks 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
    echo "加密方式: chacha20-ietf-poly1305"
    echo ""
    # SIP002 规范要求使用 URL safe base64，并且最好去掉填充的等号以增加客户端兼容性
    local userinfo=$(python3 -c "import base64; print(base64.urlsafe_b64encode(b'chacha20-ietf-poly1305:$PASSWORD').decode('utf-8').rstrip('='))")
    
    local config_url="ss://${userinfo}@${PUBLIC_IP}:${PORT}#EasyNet-SS"
    echo "SS 链接: $config_url"
    echo ""
    echo "配置二维码:"
    if command -v qrencode &> /dev/null; then
        qrencode -t utf8 "$config_url"
    else
        echo "未安装 qrencode，无法显示二维码。"
    fi
    echo "========================================"
}

main() {
    install_shadowsocks
    configure_shadowsocks
    create_systemd_service
    setup_firewall
    show_config
}

main "$@"
