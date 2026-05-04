#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/url.sh"

WG_DIR="${WG_DIR:-/etc/wireguard}"
WG_CONFIG="$WG_DIR/wg0.conf"
CLIENT_CONFIG_DIR="${CLIENT_CONFIG_DIR:-$WG_DIR/clients}"

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

    if [ -f "$WG_CONFIG" ] && grep -q "PrivateKey" "$WG_CONFIG"; then
        log_info "检测到已有的 WireGuard 配置，跳过生成新密钥，直接使用现有配置。"
        SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key" 2>/dev/null || echo "")
    else
        SERVER_PRIVATE_KEY=$(generate_private_key)
        SERVER_PUBLIC_KEY=$(generate_public_key "$SERVER_PRIVATE_KEY")
        SERVER_PORT="${EASYNET_WIREGUARD_PORT:-51820}"
        SERVER_IP="${EASYNET_WIREGUARD_SERVER_IP:-10.0.0.1/24}"
        PUBLIC_IP=$(get_public_ip)

        DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
        if [[ -z "$DEFAULT_IFACE" ]]; then
            DEFAULT_IFACE="eth0"
        fi

        cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP
ListenPort = $SERVER_PORT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT; iptables -I FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

        chmod 600 "$WG_CONFIG"
        echo "$SERVER_PUBLIC_KEY" > "$WG_DIR/server_public.key"
    fi
}

enable_ip_forward() {
    log_info "启用 IP 转发..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wireguard.conf
    sysctl -p /etc/sysctl.d/wireguard.conf
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

    if [ -f "$CLIENT_CONFIG_FILE" ]; then
        log_info "检测到已有的客户端配置: $client_name，跳过生成。"
        return
    fi

    log_info "添加客户端: $client_name"

    CLIENT_PRIVATE_KEY=$(generate_private_key)
    CLIENT_PUBLIC_KEY=$(generate_public_key "$CLIENT_PRIVATE_KEY")
    PRE_SHARED_KEY=$(generate_preshared_key)
    CLIENT_IP="10.0.0.$((client_id + 1))/32"

    SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")
    SERVER_PORT=$(grep ListenPort "$WG_CONFIG" | awk '{print $3}')
    PUBLIC_IP=$(get_public_ip)

    cat >> "$WG_CONFIG" << EOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRE_SHARED_KEY
AllowedIPs = $CLIENT_IP
EOF

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
    local wg_conf="$CLIENT_CONFIG_DIR/$client_name.conf"
    local wg_priv_key wg_addr wg_dns wg_pub_key wg_psk wg_endpoint wg_mtu
    local enc_priv enc_pub enc_psk enc_dns ip_only wg_uri

    echo ""
    echo "========================================"
    echo "  WireGuard 部署成功"
    echo "========================================"
    echo "服务器 IP: $(get_public_ip)"
    echo "端口: 51820"
    echo "服务器公钥: $(cat "$WG_DIR/server_public.key")"
    echo ""
    echo "客户端配置文件: $wg_conf"
    echo ""
    echo "配置内容如下 (可复制保存为 .conf 文件):"
    cat "$wg_conf"

    wg_priv_key=$(grep "PrivateKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_addr=$(grep "Address" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_dns=$(grep "DNS" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_pub_key=$(grep "PublicKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_psk=$(grep "PresharedKey" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_endpoint=$(grep "Endpoint" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    wg_mtu=$(grep "MTU" "$wg_conf" | sed 's/^[^=]*=[[:space:]]*//' | xargs)

    enc_priv=$(urlencode "$wg_priv_key")
    enc_pub=$(urlencode "$wg_pub_key")
    enc_psk=$(urlencode "$wg_psk")
    enc_dns=$(urlencode "$wg_dns")
    ip_only=$(echo "$wg_addr" | cut -d'/' -f1)
    wg_uri="wg://${wg_endpoint}?publicKey=${enc_pub}&privateKey=${enc_priv}&presharedKey=${enc_psk}&ip=${ip_only}&mtu=${wg_mtu}&dns=${enc_dns}&udp=1#EasyNet-WG"

    echo ""
    echo -e "${YELLOW}WireGuard 客户端链接 (推荐复制此链接导入):${NC}"
    echo "$wg_uri"

    echo ""
    echo -e "${YELLOW}配置二维码 (请使用 Shadowrocket 或 Clash 扫码):${NC}"
    if command -v qrencode &>/dev/null; then
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
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
