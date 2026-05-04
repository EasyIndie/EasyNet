#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"

TROJAN_VERSION="${TROJAN_VERSION:-0.10.6}"
CONFIG_DIR="${TROJAN_CONFIG_DIR:-/etc/trojan-go}"
DATA_DIR="${TROJAN_DATA_DIR:-/var/lib/trojan-go}"

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
        trojan_path="/$(openssl rand -hex 4)"
        mkdir -p "$CONFIG_DIR"
        echo "$trojan_path" > "$path_file"
    fi

    echo "$trojan_path"
}

install_acme() {
    log_info "安装 ACME.sh 用于申请 SSL 证书..."
    if [ ! -d "$HOME/.acme.sh" ]; then
        curl https://get.acme.sh | sh
    fi
    export PATH="$HOME/.acme.sh:$PATH"
}

issue_certificate() {
    log_info "申请 SSL 证书..."
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "临时停止 nginx 以释放 80 端口..."
        systemctl stop nginx
    fi
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    set +e
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 \
        --pre-hook "systemctl stop nginx" \
        --post-hook "systemctl start nginx"
    local acme_status=$?
    set -e

    if [ $acme_status -ne 0 ] && [ $acme_status -ne 2 ]; then
        log_error "SSL 证书申请失败，请检查域名解析是否正确"
        exit 1
    fi
}

install_certificate() {
    log_info "安装 SSL 证书..."
    mkdir -p /etc/ssl/trojan-go
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/ssl/trojan-go/private.key \
        --fullchain-file /etc/ssl/trojan-go/fullchain.crt

    log_info "重新启动 nginx..."
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        systemctl start nginx
    fi
}

download_trojan() {
    log_info "下载 Trojan-Go..."
    local arch="amd64"
    if [[ $(uname -m) == "aarch64" ]]; then
        arch="arm64"
    fi

    local url="https://github.com/p4gefau1t/trojan-go/releases/download/v${TROJAN_VERSION}/trojan-go-linux-${arch}.zip"
    wget -O /tmp/trojan-go.zip "$url"
    unzip -o /tmp/trojan-go.zip -d /tmp/
    mv /tmp/trojan-go /usr/local/bin/trojan-go
    chmod +x /usr/local/bin/trojan-go
}

configure_trojan() {
    log_info "配置 Trojan-Go..."
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"

    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Trojan-Go 配置，跳过生成新密码，直接使用现有配置。"
        PASSWORD=$(jq -r '.password[0]' "$CONFIG_DIR/config.json")
        DOMAIN=$(jq -r '.ssl.sni' "$CONFIG_DIR/config.json")
        TROJAN_PATH=$(jq -r '.websocket.path' "$CONFIG_DIR/config.json")
        PUBLIC_IP=$(get_public_ip)
        echo "$TROJAN_PATH" > "$CONFIG_DIR/trojan_path.txt"
    else
        PASSWORD=$(generate_password)
        PUBLIC_IP=$(get_public_ip)
        TROJAN_PATH=$(ensure_trojan_path)

        cat > "$CONFIG_DIR/config.json" << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "/etc/ssl/trojan-go/fullchain.crt",
        "key": "/etc/ssl/trojan-go/private.key",
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
    fi

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

    log_info "配置证书自动续期重启钩子..."
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/ssl/trojan-go/private.key \
        --fullchain-file /etc/ssl/trojan-go/fullchain.crt \
        --reloadcmd "systemctl restart trojan-go"
}

show_config() {
    local config_url
    config_url="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&path=${TROJAN_PATH}#EasyNet-Trojan"

    echo ""
    echo "========================================"
    echo "  Trojan-Go 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "域名: $DOMAIN"
    echo "端口: 443"
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
    install_acme
    issue_certificate
    install_certificate
    download_trojan
    configure_trojan
    create_systemd_service
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
