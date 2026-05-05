#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"
source "$CORE_DIR/download.sh"

TROJAN_VERSION="${TROJAN_VERSION:-0.10.6}"
CONFIG_DIR="${TROJAN_CONFIG_DIR:-/etc/trojan-go}"
DATA_DIR="${TROJAN_DATA_DIR:-/var/lib/trojan-go}"
PUBLIC_PORT="${EASYNET_TROJAN_PUBLIC_PORT:-443}"
CERT_DIR="${EASYNET_TROJAN_CERT_DIR:-${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}}"
LISTEN="${EASYNET_TROJAN_LISTEN:-127.0.0.1}"
PORT="${EASYNET_TROJAN_PORT:-4444}"

generate_password() {
    openssl rand -hex 16
}

get_domain() {
    if [ -n "$EASYNET_DOMAIN" ]; then
        DOMAIN="$EASYNET_DOMAIN"
        log_info "从环境变量 EASYNET_DOMAIN 读取域名: $DOMAIN"
    else
        read -p "请输入您的域名 (例如: example.com): " DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_error "域名不能为空"
            exit 1
        fi
    fi
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

ensure_trojan_path() {
    local path_file="$CONFIG_DIR/trojan_path.txt"
    local trojan_path

    if [ -n "$EASYNET_TROJAN_WS_PATH" ]; then
        trojan_path="$EASYNET_TROJAN_WS_PATH"
        mkdir -p "$CONFIG_DIR"
        echo "$trojan_path" > "$path_file"
        echo "$trojan_path"
        return
    fi

    if [ -f "$path_file" ]; then
        trojan_path=$(cat "$path_file")
    fi

    if [ -z "$trojan_path" ] || [ "$trojan_path" = "/trojan" ]; then
        trojan_path="/$(openssl rand -hex 16)"
        mkdir -p "$CONFIG_DIR"
        echo "$trojan_path" > "$path_file"
    fi

    echo "$trojan_path"
}

download_trojan() {
    log_info "下载 Trojan-Go..."
    local arch="amd64"
    if [[ $(uname -m) == "aarch64" ]]; then
        arch="arm64"
    fi

    local url="https://github.com/p4gefau1t/trojan-go/releases/download/v${TROJAN_VERSION}/trojan-go-linux-${arch}.zip"
    download_file "$url" /tmp/trojan-go.zip "${EASYNET_TROJAN_GO_SHA256:-}"
    unzip -o /tmp/trojan-go.zip -d /tmp/
    mv /tmp/trojan-go /usr/local/bin/trojan-go
    chmod +x /usr/local/bin/trojan-go
}

configure_trojan() {
    log_info "配置 Trojan-Go..."
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"

    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Trojan-Go 配置，保留密码并按当前模式重写监听配置。"
        PASSWORD=$(jq -r '.password[0]' "$CONFIG_DIR/config.json")
        if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "null" ]; then
            DOMAIN=$(jq -r '.ssl.sni // empty' "$CONFIG_DIR/config.json")
        fi
        existing_path=$(jq -r '.websocket.path // empty' "$CONFIG_DIR/config.json")
        if [ -n "$existing_path" ] && [ "$existing_path" != "null" ] && [ -z "$EASYNET_TROJAN_WS_PATH" ]; then
            echo "$existing_path" > "$CONFIG_DIR/trojan_path.txt"
        fi
    else
        PASSWORD=$(generate_password)
    fi

    PUBLIC_IP=$(get_public_ip)
    TROJAN_PATH=$(ensure_trojan_path)

    cat > "$CONFIG_DIR/config.json" << EOF
{
    "run_type": "server",
    "local_addr": "$LISTEN",
    "local_port": $PORT,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "$CERT_DIR/fullchain.crt",
        "key": "$CERT_DIR/private.key",
        "sni": "$DOMAIN",
        "fallback_port": 80
    },
    "router": {
        "enabled": true,
        "block": [
            "geoip:private"
        ],
        "geoip": "/usr/local/bin/geoip.dat",
        "geosite": "/usr/local/bin/geosite.dat"
    },
    "websocket": {
        "enabled": true,
        "path": "$TROJAN_PATH",
        "host": "$DOMAIN"
    },
    "mux": {
        "enabled": true
    },
    "forward_proxy": {
        "enabled": false
    },
    "mysql": {
        "enabled": false
    },
    "api": {
        "enabled": false
    }
}
EOF

    log_info "配置文件已创建"
}

create_systemd_service() {
    log_info "创建 systemd 服务..."

    cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan-Go Server
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config $CONFIG_DIR/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable trojan-go
    systemctl start trojan-go

}

show_config() {
    local config_url
    config_url="trojan://${PASSWORD}@${DOMAIN}:${PUBLIC_PORT}?security=tls&type=ws&path=${TROJAN_PATH}#EasyNet-Trojan"

    echo ""
    echo "========================================"
    echo "  Trojan-Go 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "域名: $DOMAIN"
    echo "监听地址: $LISTEN"
    echo "监听端口: $PORT"
    echo "公开端口: $PUBLIC_PORT"
    echo "密码: $PASSWORD"
    echo "WebSocket 路径: $TROJAN_PATH"
    echo ""
    echo "客户端配置 URL:"
    echo "$config_url"
    echo ""
    echo "配置二维码:"
    if command -v qrencode &>/dev/null; then
        qrencode -t utf8 "$config_url"
    else
        echo "未安装 qrencode，无法显示二维码。"
    fi
    echo "========================================"
}

main() {
    get_domain
    if [ ! -f "$CERT_DIR/fullchain.crt" ] || [ ! -f "$CERT_DIR/private.key" ]; then
        log_error "Trojan-Go 需要 Edge TLS 证书，请先部署 Edge Gateway。"
        exit 1
    fi
    download_trojan
    configure_trojan
    create_systemd_service
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
