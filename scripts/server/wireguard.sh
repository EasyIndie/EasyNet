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

WG_DIR="/etc/wireguard"
WG_CONFIG="$WG_DIR/wg0.conf"
CLIENT_CONFIG_DIR="$WG_DIR/clients"

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

generate_private_key() {
    wg genkey
}

generate_public_key() {
    echo "$1" | wg pubkey
}

generate_preshared_key() {
    wg genpsk
}

install_wireguard() {
    log_info "安装 WireGuard..."
    
    if [[ -f /etc/debian_version ]]; then
        apt update
        apt install -y wireguard wireguard-tools qrencode
    elif [[ -f /etc/redhat-release ]]; then
        dnf install -y wireguard-tools qrencode
    else
        log_error "不支持的操作系统"
        exit 1
    fi
}

configure_server() {
    log_info "配置 WireGuard 服务器..."
    mkdir -p "$WG_DIR" "$CLIENT_CONFIG_DIR"

    # 检查是否是恢复模式（配置已存在）
    if [ -f "$WG_CONFIG" ] && grep -q "PrivateKey" "$WG_CONFIG"; then
        log_info "检测到已有的 WireGuard 配置，跳过生成新密钥，直接使用现有配置。"
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key" 2>/dev/null || echo "")
    else
        SERVER_PRIVATE_KEY=$(generate_private_key)
        SERVER_PUBLIC_KEY=$(generate_public_key "$SERVER_PRIVATE_KEY")
        SERVER_PORT=51820
        SERVER_IP="10.0.0.1/24"
        PUBLIC_IP=$(get_public_ip)
        
        # 自动获取主网卡名称
        DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
        if [[ -z "$DEFAULT_IFACE" ]]; then
            DEFAULT_IFACE="eth0"
        fi

        cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP
ListenPort = $SERVER_PORT
# 针对 UFW DROP 策略的精确放行：允许 wg0 接口的转发，并做 NAT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT; iptables -I FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

        chmod 600 "$WG_CONFIG"
        
        # 将公钥保存到一个临时文件供客户端生成时使用，避免重复计算出错
        echo "$SERVER_PUBLIC_KEY" > "$WG_DIR/server_public.key"
    fi
}

enable_ip_forward() {
    log_info "启用 IP 转发..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wireguard.conf
    sysctl -p /etc/sysctl.d/wireguard.conf
    # 强制立即生效
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

create_systemd_service() {
    log_info "启用 WireGuard 服务..."
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0
}

add_client() {
    local client_name=$1
    local client_id=$2
    CLIENT_CONFIG_FILE="$CLIENT_CONFIG_DIR/$client_name.conf"

    # 如果客户端配置已存在，说明可能是从备份恢复的，直接跳过生成
    if [ -f "$CLIENT_CONFIG_FILE" ]; then
        log_info "检测到已有的客户端配置: $client_name，跳过生成。"
        return
    fi

    log_info "添加客户端: $client_name"

    CLIENT_PRIVATE_KEY=$(generate_private_key)
    CLIENT_PUBLIC_KEY=$(generate_public_key "$CLIENT_PRIVATE_KEY")
    PRE_SHARED_KEY=$(generate_preshared_key)
    CLIENT_IP="10.0.0.$((client_id + 1))/32"
    
    # 直接从我们刚保存的文件中读取服务器公钥，确保100%正确
    SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")
    SERVER_PORT=$(grep ListenPort "$WG_CONFIG" | awk '{print $3}')
    PUBLIC_IP=$(get_public_ip)

    cat >> "$WG_CONFIG" << EOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRE_SHARED_KEY
AllowedIPs = $CLIENT_IP
EOF

    CLIENT_CONFIG_FILE="$CLIENT_CONFIG_DIR/$client_name.conf"
    cat > "$CLIENT_CONFIG_FILE" << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP
DNS = 1.1.1.1, 8.8.8.8
MTU = 1360

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRE_SHARED_KEY
Endpoint = $PUBLIC_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    chmod 600 "$CLIENT_CONFIG_FILE"
    log_info "客户端配置已保存到: $CLIENT_CONFIG_FILE"
}

show_config() {
    local client_name="client1"
    
    echo ""
    echo "========================================"
    echo "  WireGuard 部署成功"
    echo "========================================"
    echo "服务器 IP: $(get_public_ip)"
    echo "端口: 51820"
    echo "服务器公钥: $(cat "$WG_DIR/server_public.key")"
    echo ""
    echo "客户端配置文件: $CLIENT_CONFIG_DIR/$client_name.conf"
    echo ""
    echo "配置内容如下 (可复制保存为 .conf 文件):"
    cat "$CLIENT_CONFIG_DIR/$client_name.conf"
    # URL encode function for WireGuard standard URI
    urlencode() {
        local string="${1}"
        local strlen=${#string}
        local encoded=""
        local pos c o
        for (( pos=0 ; pos<strlen ; pos++ )); do
            c=${string:$pos:1}
            case "$c" in
                [-_.~a-zA-Z0-9/] ) o="${c}" ;;
                * )               printf -v o '%%%02X' "'$c" ;;
            esac
            encoded+="${o}"
        done
        echo "${encoded}"
    }

    local wg_conf="$CLIENT_CONFIG_DIR/$client_name.conf"
    local wg_priv_key=$(grep "PrivateKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_addr=$(grep "Address" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_dns=$(grep "DNS" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_pub_key=$(grep "PublicKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_psk=$(grep "PresharedKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_endpoint=$(grep "Endpoint" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    local wg_mtu=$(grep "MTU" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)

    local enc_priv=$(urlencode "$wg_priv_key")
    local enc_pub=$(urlencode "$wg_pub_key")
    local enc_psk=$(urlencode "$wg_psk")
    local enc_dns=$(urlencode "$wg_dns")
    local ip_only=$(echo "$wg_addr" | cut -d'/' -f1)

    local wg_uri="wg://${wg_endpoint}?publicKey=${enc_pub}&privateKey=${enc_priv}&presharedKey=${enc_psk}&ip=${ip_only}&mtu=${wg_mtu}&dns=${enc_dns}&udp=1#EasyNet-WG"

    echo ""
    echo -e "${YELLOW}WireGuard 客户端链接 (推荐复制此链接导入):${NC}"
    echo "$wg_uri"

    echo ""
    echo -e "${YELLOW}配置二维码 (请使用 Shadowrocket 或 Clash 扫码):${NC}"
    if command -v qrencode &> /dev/null; then
        echo "$wg_uri" | qrencode -t utf8
    else
        echo "未安装 qrencode，无法显示二维码。"
    fi
    echo "========================================"
}

main() {
    install_wireguard
    enable_ip_forward
    configure_server
    add_client "client1" 1
    create_systemd_service
    show_config
}

main "$@"
