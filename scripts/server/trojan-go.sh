#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

TROJAN_VERSION="0.10.6"
CONFIG_DIR="/etc/trojan-go"
DATA_DIR="/var/lib/trojan-go"

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

install_acme() {
    log_info "安装 ACME.sh 用于申请 SSL 证书..."
    curl https://get.acme.sh | sh
    export PATH="$HOME/.acme.sh:$PATH"
}

issue_certificate() {
    log_info "申请 SSL 证书..."
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "临时停止 nginx 以释放 80 端口..."
        systemctl stop nginx
    fi
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    
    # 允许申请命令失败（比如证书已存在跳过时会返回 2）
    # 使用 --pre-hook 和 --post-hook 确保自动续期时也能正确停启 Nginx
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
    # 去掉 --reloadcmd，因为 trojan-go 还没安装，等后面配置好了一起启动
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

    # 检查是否是恢复模式（配置已存在）
    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "password" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 Trojan-Go 配置，跳过生成新密码，直接使用现有配置。"
        PASSWORD=$(jq -r '.password[0]' "$CONFIG_DIR/config.json")
        
        # 提取域名和路径供后续使用
        DOMAIN=$(jq -r '.ssl.sni' "$CONFIG_DIR/config.json")
        TROJAN_PATH=$(jq -r '.websocket.path' "$CONFIG_DIR/config.json")
        PUBLIC_IP=$(get_public_ip)
        
        # 兼容处理：如果提取到的依然是旧版默认的 /trojan，则强制重新生成一个随机路径，提高安全性
        if [ "$TROJAN_PATH" == "/trojan" ]; then
            TROJAN_PATH="/$(openssl rand -hex 4)"
            # 更新配置文件中的路径
            jq --arg path "$TROJAN_PATH" '.websocket.path = $path' "$CONFIG_DIR/config.json" > "${CONFIG_DIR}/config.json.tmp" && mv "${CONFIG_DIR}/config.json.tmp" "$CONFIG_DIR/config.json"
            log_info "已将默认的 /trojan 路径升级为随机路径: $TROJAN_PATH"
        fi
        
        # 将读取到（或新生成）的 TROJAN_PATH 保存到文件，以防文件丢失导致两边不一致
        echo "$TROJAN_PATH" > /etc/trojan-go/trojan_path.txt
        
        # 尝试从之前保存的文件中读取 V2Ray 路径，如果没有则重新生成一个以保证 Nginx 配置正确
        if [ -f /etc/trojan-go/v2ray_path.txt ]; then
            V2RAY_PATH=$(cat /etc/trojan-go/v2ray_path.txt)
        else
            V2RAY_PATH="/$(openssl rand -hex 4)"
            echo "$V2RAY_PATH" > /etc/trojan-go/v2ray_path.txt
        fi
    else
        PASSWORD=$(generate_password)
        PUBLIC_IP=$(get_public_ip)
        
        # 从前面 Nginx 阶段生成的文件中读取路径，而不是再次生成
        TROJAN_PATH=$(cat /etc/trojan-go/trojan_path.txt)
        V2RAY_PATH=$(cat /etc/trojan-go/v2ray_path.txt)
        
        # 兼容处理：如果由于某些原因没有读取到，做最后一次兜底
        if [ -z "$TROJAN_PATH" ]; then
            TROJAN_PATH="/$(openssl rand -hex 4)"
            echo "$TROJAN_PATH" > /etc/trojan-go/trojan_path.txt
        fi

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

    # 如果检测到 V2Ray 已经安装且占用了 443 端口（即它是独立部署的），我们需要把它降级为 Trojan 的后端
    if [ -f "/usr/local/etc/v2ray/config.json" ] && grep -q '"port": 443' "/usr/local/etc/v2ray/config.json"; then
        log_info "检测到 V2Ray 已作为独立服务运行在 443 端口。"
        log_info "正在将 V2Ray 降级为 Trojan 的后端 (监听 4443 端口并关闭自带 TLS)..."
        
        # 使用 jq 安全地更新 V2Ray 配置文件
        jq --arg new_path "$V2RAY_PATH" '
            .inbounds[0].port = 4443 |
            .inbounds[0].listen = "127.0.0.1" |
            .inbounds[0].streamSettings.wsSettings.path = $new_path |
            del(.inbounds[0].streamSettings.security) |
            del(.inbounds[0].streamSettings.tlsSettings)
        ' /usr/local/etc/v2ray/config.json > /usr/local/etc/v2ray/config.json.tmp && mv /usr/local/etc/v2ray/config.json.tmp /usr/local/etc/v2ray/config.json
        
        systemctl restart v2ray
        log_info "V2Ray 降级完成，现已接入 Trojan 流量复用。"
    fi
    
    log_info "配置文件已创建"
}

create_systemd_service() {
    log_info "创建 systemd 服务..."
    
    # 如果 443 端口被其他服务（比如独立的 V2Ray 还没来得及释放）占用，稍微等一下或者强制停掉
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        systemctl restart v2ray
        sleep 2
    fi
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

    # 此时服务已启动，可以重新安装一次证书来添加自动重启钩子
    log_info "配置证书自动续期重启钩子..."
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/ssl/trojan-go/private.key \
        --fullchain-file /etc/ssl/trojan-go/fullchain.crt \
        --reloadcmd "systemctl restart trojan-go"
}

setup_nginx_fallback() {
    log_info "配置 Nginx 作为伪装站点与流量分发..."
    apt install -y nginx

    # 获取或生成 V2Ray 路径
    local v2ray_path="/v2ray"
    if [ -f /etc/trojan-go/v2ray_path.txt ]; then
        v2ray_path=$(cat /etc/trojan-go/v2ray_path.txt)
    else
        v2ray_path="/$(openssl rand -hex 4)"
        mkdir -p /etc/trojan-go
        echo "$v2ray_path" > /etc/trojan-go/v2ray_path.txt
    fi
    
    # 获取或生成 Trojan 路径 (与下面 configure_trojan 保持一致)
    local trojan_path="/trojan"
    if [ -f /etc/trojan-go/trojan_path.txt ]; then
        trojan_path=$(cat /etc/trojan-go/trojan_path.txt)
    else
        trojan_path="/$(openssl rand -hex 4)"
        mkdir -p /etc/trojan-go
        echo "$trojan_path" > /etc/trojan-go/trojan_path.txt
    fi

    cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Welcome to nginx!</h1>
</body>
</html>
HTML

    # 配置独立的 Nginx 站点配置，避免覆盖用户的默认配置或影响其他网站
    # 注意：这里不能用 'EOF'（带单引号），否则 $v2ray_path 变量不会被解析
    cat > /etc/nginx/sites-available/easynet-proxy << EOF
server {
    # 监听本地 80 端口，接收从 Trojan 回落的流量
    listen 127.0.0.1:80;
    server_name _;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    # 允许访问订阅文件
    location /sub {
        try_files \$uri =404;
        default_type text/plain;
    }

    location / {
        access_log off;
        try_files \$uri \$uri/ =404;
    }

    location $v2ray_path {
        access_log off;
        allow 127.0.0.1;
        deny all;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:4443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    # 启用配置
    ln -sf /etc/nginx/sites-available/easynet-proxy /etc/nginx/sites-enabled/
    
    # 移除可能冲突的默认配置（如果它是刚刚安装的初始状态或被我们之前版本覆盖过的状态，则安全移除，如果用户改过则保留）
    if [ -f /etc/nginx/sites-enabled/default ]; then
        # 检查是否是我们之前脚本写入的配置（包含 /v2ray 或 try_files $uri $uri/ =404）
        if grep -q "try_files \$uri \$uri/ =404;" /etc/nginx/sites-available/default; then
            log_info "检测到旧版 EasyNet 或 Nginx 默认配置，正在移除以避免冲突..."
            rm -f /etc/nginx/sites-enabled/default
        else
            log_warn "检测到 Nginx default 配置可能被用户自定义过，已跳过移除。如有端口冲突请手动检查。"
        fi
    fi

    systemctl enable nginx
    systemctl restart nginx
}

show_config() {
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
    local config_url="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&path=${TROJAN_PATH}#EasyNet-Trojan"
    
    echo "$config_url"
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
    get_domain
    setup_nginx_fallback
    install_acme
    issue_certificate
    install_certificate
    download_trojan
    configure_trojan
    create_systemd_service
    show_config
}

main "$@"
