#!/bin/bash

# EasyNet Subscription Generator
# Aggregates all installed proxy protocols into a single base64 encoded subscription file
# that can be imported directly into clients like Clash Verge, V2RayN, Shadowrocket, etc.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

WEB_ROOT="/var/www/html"
SUB_FILE="${WEB_ROOT}/sub"
SUB_FILE_ALL="${WEB_ROOT}/sub_full"
LINKS_FILE_SAFE="/tmp/easynet_links_safe.txt"
LINKS_FILE_ALL="/tmp/easynet_links_all.txt"

# Clear previous links
> "$LINKS_FILE_SAFE"
> "$LINKS_FILE_ALL"

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

PUBLIC_IP=$(get_public_ip)

# Extract links in order of security/obfuscation ranking (Highest to Lowest):
# 1. Xray+Reality
# 2. Trojan-Go
# 3. V2Ray
# 4. Shadowsocks
# 5. WireGuard

# 1. Extract Xray+Reality link (Rank 1: Ultimate Obfuscation)
if [ -f "/usr/local/etc/xray/config.json" ]; then
    log_info "提取 Xray+Reality 配置..."
    X_UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' /usr/local/etc/xray/config.json)
    X_PORT=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/xray/config.json)
    X_SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' /usr/local/etc/xray/config.json)
    X_SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' /usr/local/etc/xray/config.json)
    
    # Public key was saved during deployment
    if [ -f "/usr/local/etc/xray/public.key" ]; then
        X_PBK=$(cat /usr/local/etc/xray/public.key)
        
        if [ -n "$X_UUID" ] && [ -n "$X_PORT" ] && [ -n "$X_SNI" ] && [ -n "$X_PBK" ]; then
            X_LINK="vless://$X_UUID@$PUBLIC_IP:$X_PORT?encryption=none&security=reality&sni=$X_SNI&fp=chrome&pbk=$X_PBK&sid=$X_SID&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
            echo "$X_LINK" >> "$LINKS_FILE_SAFE"
            echo "$X_LINK" >> "$LINKS_FILE_ALL"
        fi
    fi
fi

# 2. Extract Trojan-Go link (Rank 2: Standard HTTPS Obfuscation)
if [ -f "/etc/trojan-go/config.json" ]; then
    log_info "提取 Trojan-Go 配置..."
    DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    PASSWORD=$(jq -r '.password[0] // empty' /etc/trojan-go/config.json)
    TROJAN_PATH=$(jq -r '.websocket.path // empty' /etc/trojan-go/config.json)
    
    if [ -n "$DOMAIN" ] && [ -n "$PASSWORD" ] && [ -n "$TROJAN_PATH" ]; then
        T_LINK="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&path=${TROJAN_PATH}#EasyNet-Trojan"
        echo "$T_LINK" >> "$LINKS_FILE_SAFE"
        echo "$T_LINK" >> "$LINKS_FILE_ALL"
    fi
fi

# 3. Extract V2Ray link (Rank 3: TLS Encapsulation)
if [ -f "/usr/local/etc/v2ray/config.json" ]; then
    log_info "提取 V2Ray 配置..."
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' /usr/local/etc/v2ray/config.json)
    WS_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' /usr/local/etc/v2ray/config.json)
    PORT=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/v2ray/config.json)
    
    DOMAIN=""
    if [ -f "/etc/trojan-go/config.json" ]; then
        DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    fi
    
    if [ -z "$DOMAIN" ] && [ "$PORT" == "443" ]; then
        # This is a bit tricky for standalone v2ray, we might not have domain saved explicitly
        # Let's check TLS config
        CERT_FILE=$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile // empty' /usr/local/etc/v2ray/config.json)
        if [[ "$CERT_FILE" == *"/etc/ssl/v2ray/fullchain.crt"* ]]; then
            # Extract domain from path or assume IP (fallback)
            DOMAIN="$PUBLIC_IP" 
        fi
    fi
    
    if [ -n "$UUID" ] && [ -n "$WS_PATH" ] && [ -n "$DOMAIN" ]; then
        # If it's multiplexed behind Trojan, port is 443 from outside perspective
        EXTERNAL_PORT=443
        vmess_json="{\"v\":\"2\",\"ps\":\"EasyNet-V2Ray\",\"add\":\"$DOMAIN\",\"port\":$EXTERNAL_PORT,\"id\":\"$UUID\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$WS_PATH\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}"
        vmess_b64=$(echo -n "$vmess_json" | base64 -w 0)
        V_LINK="vmess://$vmess_b64"
        echo "$V_LINK" >> "$LINKS_FILE_SAFE"
        echo "$V_LINK" >> "$LINKS_FILE_ALL"
    fi
fi

# 4. Extract Shadowsocks link (Rank 4: Traditional AEAD Encryption)
if [ -f "/etc/shadowsocks-libev/config.json" ]; then
    log_info "提取 Shadowsocks 配置..."
    SS_PORT=$(jq -r '.server_port // empty' /etc/shadowsocks-libev/config.json)
    SS_PASS=$(jq -r '.password // empty' /etc/shadowsocks-libev/config.json)
    SS_METHOD=$(jq -r '.method // empty' /etc/shadowsocks-libev/config.json)
    
    if [ -n "$SS_PORT" ] && [ -n "$SS_PASS" ] && [ -n "$SS_METHOD" ]; then
        userinfo=$(echo -n "${SS_METHOD}:${SS_PASS}" | base64 -w 0)
        echo "ss://${userinfo}@${PUBLIC_IP}:${SS_PORT}#EasyNet-SS" >> "$LINKS_FILE_ALL"
    fi
fi

# 5. Extract WireGuard link
# WireGuard standard URL scheme (wg://) format
if [ -f "/etc/wireguard/clients/client1.conf" ]; then
    log_info "提取 WireGuard 配置..."
    WG_CONF="/etc/wireguard/clients/client1.conf"
    
    # Extract values from the conf file
    WG_PRIV_KEY=$(grep "PrivateKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_ADDR=$(grep "Address" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_DNS=$(grep "DNS" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_PUB_KEY=$(grep "PublicKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_PSK=$(grep "PresharedKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_ENDPOINT=$(grep "Endpoint" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_ALLOWED_IPS=$(grep "AllowedIPs" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_MTU=$(grep "MTU" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    
    # URL encode parameters
    # The standard requires '+' -> '%2B', '=' -> '%3D', but leaves '/' intact
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
    
    if [ -n "$WG_PRIV_KEY" ] && [ -n "$WG_PUB_KEY" ] && [ -n "$WG_ENDPOINT" ]; then
        ENC_PRIV=$(urlencode "$WG_PRIV_KEY")
        ENC_PUB=$(urlencode "$WG_PUB_KEY")
        ENC_PSK=$(urlencode "$WG_PSK")
        ENC_DNS=$(urlencode "$WG_DNS")
        
        # Extract IP without subnet for the 'ip=' field
        IP_ONLY=$(echo "$WG_ADDR" | cut -d'/' -f1)
        
        # Build the standard wg:// URI
        # Format: wg://[EndpointIP]:[Port]?publicKey=...&privateKey=...&presharedKey=...&ip=...&mtu=...&dns=...&udp=1
        WG_URI="wg://${WG_ENDPOINT}?publicKey=${ENC_PUB}&privateKey=${ENC_PRIV}&presharedKey=${ENC_PSK}&ip=${IP_ONLY}&mtu=${WG_MTU}&dns=${ENC_DNS}&udp=1#EasyNet-WG"
        echo "$WG_URI" >> "$LINKS_FILE_ALL"
    fi
fi

# Check if we have any links
if [ ! -s "$LINKS_FILE_ALL" ]; then
    log_warn "没有找到任何有效的节点配置。"
    exit 0
fi

# Generate Subscription file
log_info "生成订阅文件..."
mkdir -p "$WEB_ROOT"
if [ -s "$LINKS_FILE_SAFE" ]; then
    cat "$LINKS_FILE_SAFE" | base64 -w 0 > "$SUB_FILE"
    chmod 644 "$SUB_FILE"
fi

if [ -s "$LINKS_FILE_ALL" ]; then
    cat "$LINKS_FILE_ALL" | base64 -w 0 > "$SUB_FILE_ALL"
    chmod 644 "$SUB_FILE_ALL"
fi

rm -f "$LINKS_FILE_SAFE" "$LINKS_FILE_ALL"

# Provide subscription URL
if [ -f "/etc/trojan-go/config.json" ]; then
    SUB_DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    if [ -n "$SUB_DOMAIN" ]; then
        echo ""
        echo "========================================"
        echo "  节点订阅链接生成成功！"
        echo "========================================"
        echo "【推荐】安全订阅链接 (仅包含防封锁能力强的协议：Xray/Trojan/V2Ray)："
        echo "您可以直接复制以下链接到客户端中进行订阅："
        echo -e "${GREEN}https://${SUB_DOMAIN}/sub${NC}"
        if command -v qrencode &> /dev/null; then
            echo ""
            echo "订阅二维码："
            qrencode -t utf8 "https://${SUB_DOMAIN}/sub"
        fi
        echo ""
        echo "【警告】完整订阅链接 (包含所有协议，包括易被探测的 Shadowsocks/WireGuard)："
        echo "请注意：如果该链接泄漏且不安全的协议被频繁使用，VPS 可能会有被 GFW 封锁的风险！"
        echo -e "${YELLOW}https://${SUB_DOMAIN}/sub_full${NC}"
        if command -v qrencode &> /dev/null; then
            echo ""
            echo "完整订阅二维码："
            qrencode -t utf8 "https://${SUB_DOMAIN}/sub_full"
        fi
        echo ""
        echo "订阅成功后，节点会自动导入到客户端中，无需再手动扫码！"
        echo "========================================"
    fi
fi
