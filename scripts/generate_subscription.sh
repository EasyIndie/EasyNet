#!/bin/bash

# EasyNet Subscription Generator
# - /sub, /sub_full: base64 encoded URI subscriptions for Shadowrocket / v2rayN / v2rayNG
# - /clash, /clash_full: Mihomo YAML subscriptions for Clash Verge Rev / Mihomo

set -e

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
CLASH_FILE="${WEB_ROOT}/clash"
CLASH_FILE_ALL="${WEB_ROOT}/clash_full"

LINKS_FILE_SAFE="/tmp/easynet_links_safe.txt"
LINKS_FILE_ALL="/tmp/easynet_links_all.txt"
CLASH_PROXIES_SAFE="/tmp/easynet_clash_proxies_safe.yaml"
CLASH_PROXIES_ALL="/tmp/easynet_clash_proxies_all.yaml"
CLASH_NAMES_SAFE="/tmp/easynet_clash_names_safe.txt"
CLASH_NAMES_ALL="/tmp/easynet_clash_names_all.txt"

for file in \
    "$LINKS_FILE_SAFE" "$LINKS_FILE_ALL" \
    "$CLASH_PROXIES_SAFE" "$CLASH_PROXIES_ALL" \
    "$CLASH_NAMES_SAFE" "$CLASH_NAMES_ALL"; do
    > "$file"
done

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

yaml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

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

append_proxy_name() {
    local file="$1"
    local name="$2"
    printf '%s\n' "$name" >> "$file"
}

generate_proxy_list() {
    local names_file="$1"
    local indent="$2"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        printf '%s- "%s"\n' "$indent" "$(yaml_escape "$name")"
    done < "$names_file"
}

generate_clash_config() {
    local output_file="$1"
    local proxies_file="$2"
    local names_file="$3"

    [ ! -s "$names_file" ] && return 0

    cat > "$output_file" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true

proxies:
EOF

    cat "$proxies_file" >> "$output_file"

    cat >> "$output_file" <<EOF

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "Auto"
      - "DIRECT"
EOF

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<EOF
  - name: "Auto"
    type: url-test
    url: "https://cp.cloudflare.com/generate_204"
    interval: 300
    tolerance: 50
    proxies:
EOF

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<EOF

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF

    chmod 644 "$output_file"
}

PUBLIC_IP=$(get_public_ip)

# 1. Xray+Reality
if [ -f "/usr/local/etc/xray/config.json" ]; then
    log_info "提取 Xray+Reality 配置..."
    X_UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' /usr/local/etc/xray/config.json)
    X_PORT=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/xray/config.json)
    X_SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' /usr/local/etc/xray/config.json)
    X_SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' /usr/local/etc/xray/config.json)

    if [ -f "/usr/local/etc/xray/public.key" ]; then
        X_PBK=$(cat /usr/local/etc/xray/public.key)

        if [ -n "$X_UUID" ] && [ -n "$X_PORT" ] && [ -n "$X_SNI" ] && [ -n "$X_PBK" ]; then
            X_LINK="vless://$X_UUID@$PUBLIC_IP:$X_PORT?encryption=none&security=reality&sni=$X_SNI&fp=chrome&pbk=$X_PBK&sid=$X_SID&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
            echo "$X_LINK" >> "$LINKS_FILE_SAFE"
            echo "$X_LINK" >> "$LINKS_FILE_ALL"

            cat >> "$CLASH_PROXIES_SAFE" <<EOF
  - name: "EasyNet-Reality"
    type: vless
    server: "$(yaml_escape "$PUBLIC_IP")"
    port: $X_PORT
    uuid: "$(yaml_escape "$X_UUID")"
    network: tcp
    udp: true
    tls: true
    flow: "xtls-rprx-vision"
    servername: "$(yaml_escape "$X_SNI")"
    client-fingerprint: "chrome"
    reality-opts:
      public-key: "$(yaml_escape "$X_PBK")"
      short-id: "$(yaml_escape "$X_SID")"
EOF
            cat >> "$CLASH_PROXIES_ALL" <<EOF
  - name: "EasyNet-Reality"
    type: vless
    server: "$(yaml_escape "$PUBLIC_IP")"
    port: $X_PORT
    uuid: "$(yaml_escape "$X_UUID")"
    network: tcp
    udp: true
    tls: true
    flow: "xtls-rprx-vision"
    servername: "$(yaml_escape "$X_SNI")"
    client-fingerprint: "chrome"
    reality-opts:
      public-key: "$(yaml_escape "$X_PBK")"
      short-id: "$(yaml_escape "$X_SID")"
EOF
            append_proxy_name "$CLASH_NAMES_SAFE" "EasyNet-Reality"
            append_proxy_name "$CLASH_NAMES_ALL" "EasyNet-Reality"
        fi
    fi
fi

# 2. Trojan-Go
if [ -f "/etc/trojan-go/config.json" ]; then
    log_info "提取 Trojan-Go 配置..."
    DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    PASSWORD=$(jq -r '.password[0] // empty' /etc/trojan-go/config.json)
    TROJAN_PATH=$(jq -r '.websocket.path // empty' /etc/trojan-go/config.json)

    if [ -n "$DOMAIN" ] && [ -n "$PASSWORD" ] && [ -n "$TROJAN_PATH" ]; then
        T_LINK="trojan://${PASSWORD}@${DOMAIN}:443?security=tls&type=ws&path=${TROJAN_PATH}#EasyNet-Trojan"
        echo "$T_LINK" >> "$LINKS_FILE_SAFE"
        echo "$T_LINK" >> "$LINKS_FILE_ALL"

        cat >> "$CLASH_PROXIES_SAFE" <<EOF
  - name: "EasyNet-Trojan"
    type: trojan
    server: "$(yaml_escape "$DOMAIN")"
    port: 443
    password: "$(yaml_escape "$PASSWORD")"
    udp: true
    sni: "$(yaml_escape "$DOMAIN")"
    network: ws
    ws-opts:
      path: "$(yaml_escape "$TROJAN_PATH")"
      headers:
        Host: "$(yaml_escape "$DOMAIN")"
EOF
        cat >> "$CLASH_PROXIES_ALL" <<EOF
  - name: "EasyNet-Trojan"
    type: trojan
    server: "$(yaml_escape "$DOMAIN")"
    port: 443
    password: "$(yaml_escape "$PASSWORD")"
    udp: true
    sni: "$(yaml_escape "$DOMAIN")"
    network: ws
    ws-opts:
      path: "$(yaml_escape "$TROJAN_PATH")"
      headers:
        Host: "$(yaml_escape "$DOMAIN")"
EOF
        append_proxy_name "$CLASH_NAMES_SAFE" "EasyNet-Trojan"
        append_proxy_name "$CLASH_NAMES_ALL" "EasyNet-Trojan"
    fi
fi

# 3. V2Ray
if [ -f "/usr/local/etc/v2ray/config.json" ]; then
    log_info "提取 V2Ray 配置..."
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' /usr/local/etc/v2ray/config.json)
    WS_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' /usr/local/etc/v2ray/config.json)
    PORT=$(jq -r '.inbounds[0].port // empty' /usr/local/etc/v2ray/config.json)

    DOMAIN=""
    if [ -f "/etc/trojan-go/config.json" ]; then
        DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    fi

    if [ -z "$DOMAIN" ] && [ "$PORT" = "443" ]; then
        CERT_FILE=$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile // empty' /usr/local/etc/v2ray/config.json)
        if [[ "$CERT_FILE" == *"/etc/ssl/v2ray/fullchain.crt"* ]]; then
            DOMAIN="$PUBLIC_IP"
        fi
    fi

    if [ -n "$UUID" ] && [ -n "$WS_PATH" ] && [ -n "$DOMAIN" ]; then
        vmess_json="{\"v\":\"2\",\"ps\":\"EasyNet-V2Ray\",\"add\":\"$DOMAIN\",\"port\":443,\"id\":\"$UUID\",\"aid\":0,\"net\":\"ws\",\"type\":\"none\",\"host\":\"$DOMAIN\",\"path\":\"$WS_PATH\",\"tls\":\"tls\",\"sni\":\"$DOMAIN\"}"
        vmess_b64=$(echo -n "$vmess_json" | base64 -w 0)
        V_LINK="vmess://$vmess_b64"
        echo "$V_LINK" >> "$LINKS_FILE_SAFE"
        echo "$V_LINK" >> "$LINKS_FILE_ALL"

        cat >> "$CLASH_PROXIES_SAFE" <<EOF
  - name: "EasyNet-V2Ray"
    type: vmess
    server: "$(yaml_escape "$DOMAIN")"
    port: 443
    uuid: "$(yaml_escape "$UUID")"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: "$(yaml_escape "$DOMAIN")"
    network: ws
    ws-opts:
      path: "$(yaml_escape "$WS_PATH")"
      headers:
        Host: "$(yaml_escape "$DOMAIN")"
EOF
        cat >> "$CLASH_PROXIES_ALL" <<EOF
  - name: "EasyNet-V2Ray"
    type: vmess
    server: "$(yaml_escape "$DOMAIN")"
    port: 443
    uuid: "$(yaml_escape "$UUID")"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: "$(yaml_escape "$DOMAIN")"
    network: ws
    ws-opts:
      path: "$(yaml_escape "$WS_PATH")"
      headers:
        Host: "$(yaml_escape "$DOMAIN")"
EOF
        append_proxy_name "$CLASH_NAMES_SAFE" "EasyNet-V2Ray"
        append_proxy_name "$CLASH_NAMES_ALL" "EasyNet-V2Ray"
    fi
fi

# 4. Shadowsocks
if [ -f "/etc/shadowsocks-libev/config.json" ]; then
    log_info "提取 Shadowsocks 配置..."
    SS_PORT=$(jq -r '.server_port // empty' /etc/shadowsocks-libev/config.json)
    SS_PASS=$(jq -r '.password // empty' /etc/shadowsocks-libev/config.json)
    SS_METHOD=$(jq -r '.method // empty' /etc/shadowsocks-libev/config.json)

    if [ -n "$SS_PORT" ] && [ -n "$SS_PASS" ] && [ -n "$SS_METHOD" ]; then
        userinfo=$(echo -n "${SS_METHOD}:${SS_PASS}" | base64 -w 0)
        echo "ss://${userinfo}@${PUBLIC_IP}:${SS_PORT}#EasyNet-SS" >> "$LINKS_FILE_ALL"

        cat >> "$CLASH_PROXIES_ALL" <<EOF
  - name: "EasyNet-SS"
    type: ss
    server: "$(yaml_escape "$PUBLIC_IP")"
    port: $SS_PORT
    cipher: "$(yaml_escape "$SS_METHOD")"
    password: "$(yaml_escape "$SS_PASS")"
    udp: true
EOF
        append_proxy_name "$CLASH_NAMES_ALL" "EasyNet-SS"
    fi
fi

# 5. WireGuard
if [ -f "/etc/wireguard/clients/client1.conf" ]; then
    log_info "提取 WireGuard 配置..."
    WG_CONF="/etc/wireguard/clients/client1.conf"

    WG_PRIV_KEY=$(grep "PrivateKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_ADDR=$(grep "Address" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_DNS=$(grep "DNS" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_PUB_KEY=$(grep "PublicKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_PSK=$(grep "PresharedKey" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_ENDPOINT=$(grep "Endpoint" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    WG_MTU=$(grep "MTU" "$WG_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)

    if [ -n "$WG_PRIV_KEY" ] && [ -n "$WG_PUB_KEY" ] && [ -n "$WG_ENDPOINT" ]; then
        ENC_PRIV=$(urlencode "$WG_PRIV_KEY")
        ENC_PUB=$(urlencode "$WG_PUB_KEY")
        ENC_PSK=$(urlencode "$WG_PSK")
        ENC_DNS=$(urlencode "$WG_DNS")
        IP_ONLY=$(echo "$WG_ADDR" | cut -d'/' -f1)
        WG_URI="wg://${WG_ENDPOINT}?publicKey=${ENC_PUB}&privateKey=${ENC_PRIV}&presharedKey=${ENC_PSK}&ip=${IP_ONLY}&mtu=${WG_MTU}&dns=${ENC_DNS}&udp=1#EasyNet-WG"
        echo "$WG_URI" >> "$LINKS_FILE_ALL"

        WG_SERVER="${WG_ENDPOINT%:*}"
        WG_PORT="${WG_ENDPOINT##*:}"

        cat >> "$CLASH_PROXIES_ALL" <<EOF
  - name: "EasyNet-WG"
    type: wireguard
    server: "$(yaml_escape "$WG_SERVER")"
    port: $WG_PORT
    ip: "$(yaml_escape "$IP_ONLY")"
    private-key: "$(yaml_escape "$WG_PRIV_KEY")"
    public-key: "$(yaml_escape "$WG_PUB_KEY")"
    pre-shared-key: "$(yaml_escape "$WG_PSK")"
    udp: true
    mtu: ${WG_MTU:-1360}
    dns:
EOF

        IFS=',' read -ra WG_DNS_ITEMS <<< "$WG_DNS"
        for dns_item in "${WG_DNS_ITEMS[@]}"; do
            dns_item="$(echo "$dns_item" | xargs)"
            [ -z "$dns_item" ] && continue
            printf '      - "%s"\n' "$(yaml_escape "$dns_item")" >> "$CLASH_PROXIES_ALL"
        done

        append_proxy_name "$CLASH_NAMES_ALL" "EasyNet-WG"
    fi
fi

if [ ! -s "$LINKS_FILE_ALL" ] && [ ! -s "$CLASH_NAMES_ALL" ]; then
    log_warn "没有找到任何有效的节点配置。"
    exit 0
fi

log_info "生成订阅文件..."
mkdir -p "$WEB_ROOT"

if [ -s "$LINKS_FILE_SAFE" ]; then
    base64 -w 0 < "$LINKS_FILE_SAFE" > "$SUB_FILE"
    chmod 644 "$SUB_FILE"
fi

if [ -s "$LINKS_FILE_ALL" ]; then
    base64 -w 0 < "$LINKS_FILE_ALL" > "$SUB_FILE_ALL"
    chmod 644 "$SUB_FILE_ALL"
fi

generate_clash_config "$CLASH_FILE" "$CLASH_PROXIES_SAFE" "$CLASH_NAMES_SAFE"
generate_clash_config "$CLASH_FILE_ALL" "$CLASH_PROXIES_ALL" "$CLASH_NAMES_ALL"

rm -f \
    "$LINKS_FILE_SAFE" "$LINKS_FILE_ALL" \
    "$CLASH_PROXIES_SAFE" "$CLASH_PROXIES_ALL" \
    "$CLASH_NAMES_SAFE" "$CLASH_NAMES_ALL"

if [ -f "/etc/trojan-go/config.json" ]; then
    SUB_DOMAIN=$(jq -r '.ssl.sni // empty' /etc/trojan-go/config.json)
    if [ -n "$SUB_DOMAIN" ]; then
        echo ""
        echo "========================================"
        echo "  节点订阅链接生成成功！"
        echo "========================================"
        echo "【URI 订阅】适用于 Shadowrocket / v2rayN / v2rayNG："
        echo -e "${GREEN}https://${SUB_DOMAIN}/sub${NC}"
        echo -e "${YELLOW}https://${SUB_DOMAIN}/sub_full${NC}"
        echo ""
        echo "【Clash/Mihomo 订阅】适用于 Clash Verge Rev / Mihomo："
        echo -e "${GREEN}https://${SUB_DOMAIN}/clash${NC}"
        echo -e "${YELLOW}https://${SUB_DOMAIN}/clash_full${NC}"
        if command -v qrencode &> /dev/null; then
            echo ""
            echo "Clash/Mihomo 安全订阅二维码："
            qrencode -t utf8 "https://${SUB_DOMAIN}/clash"
        fi
        echo ""
        echo "说明："
        echo "- /sub 与 /sub_full 为 URI 聚合订阅"
        echo "- /clash 与 /clash_full 为 Mihomo YAML 订阅"
        echo "- 完整订阅包含 Shadowsocks/WireGuard，请按需使用"
        echo "========================================"
    fi
fi
