#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/url.sh"
source "$CORE_DIR/network.sh"
source "$CORE_DIR/display.sh"

# AmneziaWG is a WireGuard fork with DPI-resistant obfuscation. Its tools are a
# drop-in replacement (awg / awg-quick) and it stores configs under
# /etc/amnezia/amneziawg by default.
WG_DIR="${WG_DIR:-/etc/amnezia/amneziawg}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_CONFIG="${WG_CONFIG:-$WG_DIR/${WG_INTERFACE}.conf}"
CLIENT_CONFIG_DIR="${CLIENT_CONFIG_DIR:-$WG_DIR/clients}"
WG_SERVICE="${WG_SERVICE:-awg-quick@${WG_INTERFACE}}"
AWG_BIN="${AWG_BIN:-awg}"

generate_private_key() {
    "$AWG_BIN" genkey
}

generate_public_key() {
    echo "$1" | "$AWG_BIN" pubkey
}

generate_preshared_key() {
    "$AWG_BIN" genpsk
}

install_wireguard() {
    log_info "安装 AmneziaWG..."

    if command -v awg >/dev/null 2>&1 && command -v awg-quick >/dev/null 2>&1; then
        log_info "检测到 AmneziaWG 已安装，跳过安装。"
        return 0
    fi

    if ! command -v add-apt-repository >/dev/null 2>&1 || [ ! -f /etc/debian_version ]; then
        log_error "AmneziaWG 目前仅支持 Debian/Ubuntu（通过 ppa:amnezia/ppa 安装）。"
        exit 1
    fi

    apt update
    apt install -y software-properties-common python3-launchpadlib gnupg2 "linux-headers-$(uname -r)" qrencode
    add-apt-repository -y ppa:amnezia/ppa
    apt update
    apt install -y amneziawg

    if ! command -v awg-quick >/dev/null 2>&1; then
        log_error "AmneziaWG 安装失败：未找到 awg-quick。"
        exit 1
    fi
    log_info "AmneziaWG 安装完成。"
}

enable_ip_forward() {
    log_info "启用 IP 转发..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wireguard.conf
    sysctl -p /etc/sysctl.d/wireguard.conf
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

rand_between() {
    local min="$1" max="$2" span value
    span=$((max - min + 1))
    value=$(openssl rand -hex 4)
    printf '%s' "$(( (16#$value % span) + min ))"
}

# Generate four unique AmneziaWG magic headers (H1-H4) in [5, 2147483647].
generate_amneziawg_headers() {
    local -a values=()
    local value dup i
    while [ "${#values[@]}" -lt 4 ]; do
        value=$(openssl rand -hex 4)
        value=$(( (16#$value % 2147483640) + 5 ))
        dup=0
        i=0
        while [ "$i" -lt "${#values[@]}" ]; do
            if [ "${values[$i]}" = "$value" ]; then
                dup=1
                break
            fi
            i=$((i + 1))
        done
        [ "$dup" -eq 1 ] && continue
        values+=("$value")
    done
    printf '%s\n' "${values[@]}"
}

# Read a single key from an INI-style config (empty when missing).
read_ini_value() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | head -n1 |
        sed 's/^[^=]*=[[:space:]]*//' | tr -d '[:space:]' || true
}

# Read a single key from the server config (empty when missing).
read_server_param() {
    read_ini_value "$WG_CONFIG" "$1"
}

# Resolve AmneziaWG parameters with priority:
#   existing server config > explicit EASYNET_WIREGUARD_* env > newly generated.
# S1/S2/H1-H4 must match on both ends; Jc/Jmin/Jmax may differ but are kept equal.
resolve_amneziawg_params() {
    AWG_JC="$(read_server_param "Jc")"
    AWG_JC="${AWG_JC:-${EASYNET_WIREGUARD_JC:-$(rand_between 4 12)}}"

    AWG_JMIN="$(read_server_param "Jmin")"
    AWG_JMIN="${AWG_JMIN:-${EASYNET_WIREGUARD_JMIN:-8}}"

    AWG_JMAX="$(read_server_param "Jmax")"
    AWG_JMAX="${AWG_JMAX:-${EASYNET_WIREGUARD_JMAX:-80}}"

    AWG_S1="$(read_server_param "S1")"
    AWG_S1="${AWG_S1:-${EASYNET_WIREGUARD_S1:-$(rand_between 15 150)}}"

    AWG_S2="$(read_server_param "S2")"
    if [ -z "$AWG_S2" ]; then
        AWG_S2="${EASYNET_WIREGUARD_S2:-}"
        if [ -z "$AWG_S2" ]; then
            # AmneziaWG requires S1 + 56 != S2
            while :; do
                AWG_S2=$(rand_between 15 150)
                [ "$((AWG_S1 + 56))" -ne "$AWG_S2" ] && break
            done
        fi
    fi

    AWG_H1="$(read_server_param "H1")"
    AWG_H2="$(read_server_param "H2")"
    AWG_H3="$(read_server_param "H3")"
    AWG_H4="$(read_server_param "H4")"
    if [ -z "$AWG_H1" ] || [ -z "$AWG_H2" ] || [ -z "$AWG_H3" ] || [ -z "$AWG_H4" ]; then
        if [ -n "${EASYNET_WIREGUARD_H1:-}" ] && [ -n "${EASYNET_WIREGUARD_H2:-}" ] &&
            [ -n "${EASYNET_WIREGUARD_H3:-}" ] && [ -n "${EASYNET_WIREGUARD_H4:-}" ]; then
            AWG_H1="${EASYNET_WIREGUARD_H1:-}"
            AWG_H2="${EASYNET_WIREGUARD_H2:-}"
            AWG_H3="${EASYNET_WIREGUARD_H3:-}"
            AWG_H4="${EASYNET_WIREGUARD_H4:-}"
        else
            local headers
            headers="$(generate_amneziawg_headers)"
            AWG_H1="$(printf '%s\n' "$headers" | sed -n '1p')"
            AWG_H2="$(printf '%s\n' "$headers" | sed -n '2p')"
            AWG_H3="$(printf '%s\n' "$headers" | sed -n '3p')"
            AWG_H4="$(printf '%s\n' "$headers" | sed -n '4p')"
        fi
    fi
}

configure_server() {
    log_info "配置 AmneziaWG 服务器..."
    mkdir -p "$WG_DIR" "$CLIENT_CONFIG_DIR"

    WG_CONFIG_CHANGED=false

    if [ -f "$WG_CONFIG" ] && grep -q "PrivateKey" "$WG_CONFIG"; then
        log_info "检测到已有的 AmneziaWG 配置，保留服务端密钥与混淆参数。"
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

        resolve_amneziawg_params

        cat > "$WG_CONFIG" << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP
ListenPort = $SERVER_PORT
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
PostUp = iptables -I FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -I FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

        chmod 600 "$WG_CONFIG"
        echo "$SERVER_PUBLIC_KEY" > "$WG_DIR/server_public.key"
        chmod 644 "$WG_DIR/server_public.key"
        WG_CONFIG_CHANGED=true
    fi
}

create_systemd_service() {
    log_info "启用 AmneziaWG 服务..."

    local needs_restart=false old_wg_active=false

    # Migrate away from a previous plain WireGuard deployment. Only do this when
    # the OLD wg-quick service owns the interface, or when no AWG service is
    # running: deleting a live awg-quick interface would drop every client.
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        old_wg_active=true
    fi
    systemctl disable --now "wg-quick@${WG_INTERFACE}" >/dev/null 2>&1 || true
    if ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
        if [ "$old_wg_active" = true ] || ! systemctl is-active --quiet "$WG_SERVICE"; then
            log_info "移除已存在的接口 $WG_INTERFACE（从旧版 WireGuard 迁移）..."
            ip link delete "$WG_INTERFACE" >/dev/null 2>&1 || true
            needs_restart=true
        fi
    fi

    if [ "${WG_CONFIG_CHANGED:-true}" = "true" ] || ! systemctl is-active --quiet "$WG_SERVICE"; then
        needs_restart=true
    fi

    systemctl enable "$WG_SERVICE" >/dev/null 2>&1 || true
    if [ "$needs_restart" = "true" ]; then
        systemctl restart "$WG_SERVICE"
    else
        # Restarting awg-quick tears down the tunnel for every online client.
        log_info "AmneziaWG 配置未变化，跳过重启。"
    fi
}

add_client() {
    local client_name=$1
    local client_id=$2
    CLIENT_CONFIG_FILE="$CLIENT_CONFIG_DIR/$client_name.conf"

    local client_private_key="" pre_shared_key="" client_ip=""

    if [ -f "$CLIENT_CONFIG_FILE" ]; then
        client_private_key=$(read_ini_value "$CLIENT_CONFIG_FILE" "PrivateKey")
        pre_shared_key=$(read_ini_value "$CLIENT_CONFIG_FILE" "PresharedKey")
        client_ip=$(read_ini_value "$CLIENT_CONFIG_FILE" "Address")
        log_info "更新已有客户端配置: $client_name（保留密钥，刷新混淆参数/MTU）"
    else
        log_info "添加客户端: $client_name"
    fi

    [ -n "$client_private_key" ] || client_private_key=$(generate_private_key)
    CLIENT_PUBLIC_KEY=$(generate_public_key "$client_private_key")
    [ -n "$pre_shared_key" ] || pre_shared_key=$(generate_preshared_key)
    [ -n "$client_ip" ] || client_ip="10.0.0.$((client_id + 1))/32"

    SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")
    SERVER_PORT=$(grep ListenPort "$WG_CONFIG" | awk '{print $3}')
    PUBLIC_IP=$(get_public_ip)

    resolve_amneziawg_params

    # Ensure the server has a peer entry for this client.
    if ! grep -Fq "PublicKey = $CLIENT_PUBLIC_KEY" "$WG_CONFIG"; then
        cat >> "$WG_CONFIG" << EOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $pre_shared_key
AllowedIPs = $client_ip
EOF
        WG_CONFIG_CHANGED=true
    fi

    cat > "$CLIENT_CONFIG_FILE" << EOF
[Interface]
PrivateKey = $client_private_key
Address = $client_ip
DNS = 1.1.1.1, 8.8.8.8
MTU = 1280
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $pre_shared_key
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
    local jc jmin jmax s1 s2 h1 h2 h3 h4

    jc=$(read_server_param "Jc")
    jmin=$(read_server_param "Jmin")
    jmax=$(read_server_param "Jmax")
    s1=$(read_server_param "S1")
    s2=$(read_server_param "S2")
    h1=$(read_server_param "H1")
    h2=$(read_server_param "H2")
    h3=$(read_server_param "H3")
    h4=$(read_server_param "H4")

    echo ""
    echo "========================================"
    echo "  AmneziaWG 部署成功"
    echo "========================================"
    echo "服务器 IP: $(get_public_ip)"
    echo "端口: 51820/udp"
    echo "服务器公钥: $(cat "$WG_DIR/server_public.key")"
    echo "混淆参数: Jc=$jc Jmin=$jmin Jmax=$jmax S1=$s1 S2=$s2 H1=$h1 H2=$h2 H3=$h3 H4=$h4"
    echo ""
    echo "客户端配置文件: $wg_conf"
    echo ""
    echo "配置内容如下 (可复制保存为 .conf 文件):"
    echo -e "${YELLOW}⚠️ 以下内容包含您的 WireGuard 私钥和预共享密钥。${NC}"
    echo -e "${YELLOW}   请勿公开分享此链接或配置文件。如怀疑泄露，请重新部署 WireGuard。${NC}"
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

    local obfs_param enc_obfs_param
    obfs_param=$(jq -cn \
        --arg jc "$jc" --arg jmin "$jmin" --arg jmax "$jmax" \
        --arg s1 "$s1" --arg s2 "$s2" \
        --arg h1 "$h1" --arg h2 "$h2" --arg h3 "$h3" --arg h4 "$h4" \
        '{jc: $jc, jmin: $jmin, jmax: $jmax, s1: $s1, s2: $s2,
          h1: $h1, h2: $h2, h3: $h3, h4: $h4,
          random_trailers: "false", disable_cookies: "false"}')
    enc_obfs_param=$(urlencode_query "$obfs_param")

    wg_uri="wg://${wg_endpoint}?publicKey=${enc_pub}&privateKey=${enc_priv}&presharedKey=${enc_psk}&ip=${ip_only}&mtu=${wg_mtu}&dns=${enc_dns}&udp=1"
    wg_uri="${wg_uri}&obfs=amneziawg&obfsParam=${enc_obfs_param}"
    wg_uri="${wg_uri}&jc=${jc}&jmin=${jmin}&jmax=${jmax}&s1=${s1}&s2=${s2}&h1=${h1}&h2=${h2}&h3=${h3}&h4=${h4}#EasyNet-WG"

    echo ""
    echo -e "${YELLOW}⚠️ 安全警告：以下链接包含您的 WireGuard 私钥。${NC}"
    echo -e "${YELLOW}   请勿公开分享此链接。如怀疑泄露，请重新部署 WireGuard。${NC}"
    echo ""
    echo -e "${YELLOW}AmneziaWG 客户端链接 (导入 .conf 文件最可靠):${NC}"
    echo "$wg_uri"

    echo ""
    echo -e "${YELLOW}配置二维码 (请使用 Shadowrocket 或 Clash 扫码):${NC}"
    show_qrcode "$wg_uri" "配置二维码"
    echo ""
    echo "AmneziaWG 需要支持该协议的客户端（Shadowrocket / Clash Verge Rev (mihomo)）。"
    echo "sing-box 暂不支持 AmneziaWG，WireGuard 节点在 sing-box 客户端不可用。"
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
