#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/download.sh"

CONFIG_DIR="${V2RAY_CONFIG_DIR:-/usr/local/etc/v2ray}"
DATA_DIR="${V2RAY_DATA_DIR:-/var/lib/v2ray}"

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
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
    mkdir -p "$CONFIG_DIR"
    echo "$DOMAIN" > "$CONFIG_DIR/domain.txt"
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

install_v2ray() {
    log_info "安装 V2Ray..."
    run_downloaded_script \
        "https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh" \
        "${EASYNET_V2RAY_INSTALL_SHA256:-}"
}

configure_v2ray() {
    log_info "配置 V2Ray..."
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"

    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "clients" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 V2Ray 配置，保留 UUID 并按 Edge backend 模式重写监听配置。"
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$CONFIG_DIR/config.json")
        if [ -z "$EASYNET_V2RAY_WS_PATH" ]; then
            WS_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "$CONFIG_DIR/config.json")
        fi
    else
        UUID=$(generate_uuid)
    fi

    WS_PATH="${EASYNET_V2RAY_WS_PATH:-${WS_PATH:-/$(openssl rand -hex 16)}}"
    PORT="${EASYNET_V2RAY_PORT:-4443}"
    LISTEN="${EASYNET_V2RAY_LISTEN:-127.0.0.1}"

    cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "$LISTEN",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    log_info "V2Ray 配置文件已创建"
}

create_systemd_service() {
    log_info "验证 V2Ray 配置文件..."
    if ! env V2RAY_LOCATION_ASSET=/usr/local/share/v2ray/ /usr/local/bin/v2ray test -config "$CONFIG_DIR/config.json"; then
        log_error "V2Ray 配置文件验证失败，请检查以上输出！"
        exit 1
    fi

    log_info "启动 V2Ray 服务..."
    systemctl enable v2ray
    if ! systemctl restart v2ray; then
        log_error "V2Ray 服务启动失败，错误日志如下："
        journalctl -u v2ray -n 30 --no-pager
        exit 1
    fi

}

show_config() {
    local public_ip vmess_json vmess_b64 config_url
    public_ip=$(get_public_ip)

    vmess_json=$(jq -cn \
        --arg domain "$DOMAIN" \
        --arg uuid "$UUID" \
        --arg ws_path "$WS_PATH" \
        '{
            v: "2",
            ps: "EasyNet-V2Ray",
            add: $domain,
            port: 443,
            id: $uuid,
            aid: 0,
            net: "ws",
            type: "none",
            host: $domain,
            path: $ws_path,
            tls: "tls",
            sni: $domain
        }')
    vmess_b64=$(printf '%s' "$vmess_json" | base64 | tr -d '\n')
    config_url="vmess://$vmess_b64"

    echo ""
    echo "========================================"
    echo "  V2Ray 部署成功"
    echo "========================================"
    echo "服务器 IP: $public_ip"
    echo "域名: $DOMAIN"
    echo "监听端口: $PORT"
    echo "公开端口: 443"
    echo "UUID: $UUID"
    echo "协议: VMess"
    echo "传输: WebSocket + TLS"
    echo "路径: $WS_PATH"
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
    install_v2ray
    configure_v2ray
    create_systemd_service
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
