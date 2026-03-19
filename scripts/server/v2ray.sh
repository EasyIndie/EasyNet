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

CONFIG_DIR="/usr/local/etc/v2ray"
DATA_DIR="/var/lib/v2ray"

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

install_v2ray() {
    log_info "安装 V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
}

configure_v2ray() {
    log_info "配置 V2Ray..."
    
    # 移除强制依赖 Trojan 证书的报错逻辑
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"

    # 检查是否是恢复模式（配置已存在）
    if [ -f "$CONFIG_DIR/config.json" ] && grep -q "clients" "$CONFIG_DIR/config.json"; then
        log_info "检测到已有的 V2Ray 配置，跳过生成新 UUID，直接使用现有配置。"
        
        # 使用 jq 安全地提取配置
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$CONFIG_DIR/config.json")
        WS_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "$CONFIG_DIR/config.json")
        
        PUBLIC_IP=$(get_public_ip)
        
        # 尝试从 Trojan-Go 配置文件中提取绑定的域名
        if [ -f "/etc/trojan-go/config.json" ]; then
            DOMAIN=$(jq -r '.ssl.sni' /etc/trojan-go/config.json)
        fi
        
        # 检查是否需要更新 Nginx 的伪装路径
        if [ -f /etc/trojan-go/v2ray_path.txt ]; then
            local stored_path=$(cat /etc/trojan-go/v2ray_path.txt)
            if [ "$WS_PATH" != "$stored_path" ] && [ -n "$WS_PATH" ]; then
                log_info "同步 V2Ray 路径到 Nginx 配置..."
                echo "$WS_PATH" > /etc/trojan-go/v2ray_path.txt
            fi
        fi
    else
        UUID=$(generate_uuid)
        PUBLIC_IP=$(get_public_ip)
        
        # 如果 Trojan 存在，V2Ray 作为后端只监听本地 4443 端口，不配置 TLS
        if [ -f "/etc/trojan-go/config.json" ]; then
            log_info "检测到 Trojan-Go 已安装，V2Ray 将作为后端运行 (端口: 4443，无 TLS)"
            DOMAIN=$(jq -r '.ssl.sni' /etc/trojan-go/config.json)
            
            # 兼容处理：如果在恢复模式下没能取到 DOMAIN，再次尝试从之前的步骤或输入中获取
            if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "null" ]; then
                if [ -n "$EASYNET_DOMAIN" ]; then
                    DOMAIN="$EASYNET_DOMAIN"
                    log_info "从环境变量 EASYNET_DOMAIN 读取域名: $DOMAIN"
                else
                    log_warn "未能从 Trojan 配置中提取到域名，请手动输入："
                    read -p "请输入您的域名 (例如: example.com): " DOMAIN
                fi
            fi
            PORT=4443
            LISTEN="127.0.0.1"
            TLS_CONFIG=""
        else
            log_info "未检测到 Trojan-Go，V2Ray 将独立运行 (端口: 443，需配置 TLS)"
            if [ -n "$EASYNET_DOMAIN" ]; then
                DOMAIN="$EASYNET_DOMAIN"
                log_info "从环境变量 EASYNET_DOMAIN 读取域名: $DOMAIN"
            else
                read -p "请输入您的域名 (例如: example.com): " DOMAIN
            fi
            
            if [[ -z "$DOMAIN" ]]; then
                log_error "域名不能为空"
                exit 1
            fi
            
            # 安装 acme.sh 并申请证书
            log_info "为 V2Ray 申请独立 SSL 证书..."
            if [ ! -d "$HOME/.acme.sh" ]; then
                curl https://get.acme.sh | sh
            fi
            export PATH="$HOME/.acme.sh:$PATH"
            
            if systemctl is-active --quiet nginx 2>/dev/null; then
                systemctl stop nginx
            fi
            
            ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
            set +e
            ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 \
                --pre-hook "systemctl stop nginx" \
                --post-hook "systemctl start nginx"
            set -e
            
            mkdir -p /etc/ssl/v2ray
            ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
                --key-file /etc/ssl/v2ray/private.key \
                --fullchain-file /etc/ssl/v2ray/fullchain.crt
                
            PORT=443
            LISTEN="0.0.0.0"
            TLS_CONFIG='"security": "tls",
            "tlsSettings": {
              "certificates": [
                {
                  "certificateFile": "/etc/ssl/v2ray/fullchain.crt",
                  "keyFile": "/etc/ssl/v2ray/private.key"
                }
              ]
            },'
        fi

        # 获取或生成 WebSocket 路径
        WS_PATH="/$(openssl rand -hex 4)"
        if [ -f /etc/trojan-go/v2ray_path.txt ]; then
            WS_PATH=$(cat /etc/trojan-go/v2ray_path.txt)
        fi

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
        $TLS_CONFIG
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
    fi

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
    
    # 如果 V2Ray 独立运行且申请了证书，配置自动重启钩子
    if [ ! -f "/etc/trojan-go/config.json" ]; then
        ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
            --key-file /etc/ssl/v2ray/private.key \
            --fullchain-file /etc/ssl/v2ray/fullchain.crt \
            --reloadcmd "systemctl restart v2ray"
    fi
}

show_config() {
    echo ""
    echo "========================================"
    echo "  V2Ray 部署成功"
    echo "========================================"
    echo "服务器 IP: $PUBLIC_IP"
    echo "域名: $DOMAIN (与 Trojan 相同)"
    echo "端口: 443"
    echo "UUID: $UUID"
    echo "协议: VMess"
    echo "传输: WebSocket + TLS"
    echo "路径: $WS_PATH"
    
    # 动态获取当前配置的 WebSocket 路径，如果没有则默认 /v2ray
    local ws_path="/v2ray"
    if [ -f "$CONFIG_DIR/config.json" ]; then
        ws_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG_DIR/config.json")
    fi
    
    # 动态获取域名，由于在恢复模式或者非交互模式下 DOMAIN 变量可能未传递到此函数，我们需要从文件重新提取
    local final_domain="$DOMAIN"
    if [ -z "$final_domain" ] || [ "$final_domain" == "null" ]; then
        if [ -f "/etc/trojan-go/config.json" ]; then
            final_domain=$(jq -r '.ssl.sni' /etc/trojan-go/config.json)
        fi
    fi
    
    # 构建 vmess:// 链接，注意地址要填域名才能验证 TLS
    # 如果实在无法获取域名，则抛出错误并中止生成，而不是降级为IP
    local host_addr="${final_domain}"
    
    # --- 数据有效性校验开始 ---
    local has_error=false
    
    if [ -z "$host_addr" ] || [ "$host_addr" == "null" ]; then
        log_error "无法构建 V2Ray 客户端配置：未获取到有效的域名 (DOMAIN)。"
        has_error=true
    fi
    
    if [ -z "$UUID" ] || [ "$UUID" == "null" ]; then
        log_error "无法构建 V2Ray 客户端配置：未获取到有效的 UUID。"
        has_error=true
    fi
    
    if [ -z "$ws_path" ] || [ "$ws_path" == "null" ] || [ "$ws_path" == "/" ]; then
        log_error "无法构建 V2Ray 客户端配置：未获取到有效的 WebSocket 路径 (WS_PATH)。"
        has_error=true
    fi
    
    if [ "$has_error" = true ]; then
        log_error "配置参数校验失败，请检查配置文件后重新部署！"
        echo "========================================"
        return 1
    fi
    # --- 数据有效性校验结束 ---
    
    local vmess_json="{\"v\":\"2\",\"ps\":\"EasyNet-V2Ray\",\"add\":\"$host_addr\",\"port\":443,\"id\":\"$UUID\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$host_addr\",\"path\":\"$ws_path\",\"tls\":\"tls\",\"sni\":\"$host_addr\"}"
    # vmess 协议通常使用标准 base64 编码，不去除等号
    local vmess_b64=$(echo -n "$vmess_json" | base64 -w 0)
    local config_url="vmess://$vmess_b64"
    
    echo ""
    echo "客户端配置 URL:"
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
    install_v2ray
    configure_v2ray
    create_systemd_service
    show_config
}

main "$@"
