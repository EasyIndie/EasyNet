#!/bin/bash

# EasyNet Subscription Generator
# - /sub: base64 encoded URI subscription for Shadowrocket / v2rayN / v2rayNG
# - /clash: Mihomo YAML subscription for Clash Verge Rev / Mihomo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/metadata.sh"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
SUB_FILE="${WEB_ROOT}/sub"
CLASH_FILE="${WEB_ROOT}/clash"
LEGACY_SUB_FILE_ALL="${WEB_ROOT}/sub_full"
LEGACY_CLASH_FILE_ALL="${WEB_ROOT}/clash_full"

SUBSCRIPTION_TMP_DIR="$(mktemp -d /tmp/easynet-subscription.XXXXXX)"
cleanup_subscription_tmp() {
    rm -rf "$SUBSCRIPTION_TMP_DIR"
}
trap cleanup_subscription_tmp EXIT

LINKS_FILE_SAFE="$SUBSCRIPTION_TMP_DIR/links_safe.txt"
CLASH_PROXIES_SAFE="$SUBSCRIPTION_TMP_DIR/clash_proxies_safe.yaml"
CLASH_NAMES_SAFE="$SUBSCRIPTION_TMP_DIR/clash_names_safe.txt"

for file in \
    "$LINKS_FILE_SAFE" \
    "$CLASH_PROXIES_SAFE" \
    "$CLASH_NAMES_SAFE"; do
    > "$file"
done

yaml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
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

append_metadata_clash_proxy() {
    local metadata_file="$1"
    local output_file="$2"

    local name type server port uuid network flow servername client_fingerprint public_key short_id
    local cipher password ip private_key pre_shared_key mtu dns_count dns_item sni network ws_path host
    local obfs obfs_password up down
    local uuid alter_id
    name=$(jq -r '.client.clash.name // empty' "$metadata_file")
    type=$(jq -r '.client.clash.type // empty' "$metadata_file")
    server=$(jq -r '.client.clash.server // empty' "$metadata_file")
    port=$(jq -r '.client.clash.port // empty' "$metadata_file")

    case "$type" in
        vless)
            uuid=$(jq -r '.client.clash.uuid // empty' "$metadata_file")
            network=$(jq -r '.client.clash.network // "tcp"' "$metadata_file")
            flow=$(jq -r '.client.clash.flow // empty' "$metadata_file")
            servername=$(jq -r '.client.clash.servername // empty' "$metadata_file")
            client_fingerprint=$(jq -r '.client.clash."client-fingerprint" // empty' "$metadata_file")
            public_key=$(jq -r '.client.clash."reality-opts"."public-key" // empty' "$metadata_file")
            short_id=$(jq -r '.client.clash."reality-opts"."short-id" // empty' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: vless
    server: "$(yaml_escape "$server")"
    port: $port
    uuid: "$(yaml_escape "$uuid")"
    network: "$(yaml_escape "$network")"
    udp: true
    tls: true
    flow: "$(yaml_escape "$flow")"
    servername: "$(yaml_escape "$servername")"
    client-fingerprint: "$(yaml_escape "$client_fingerprint")"
    reality-opts:
      public-key: "$(yaml_escape "$public_key")"
      short-id: "$(yaml_escape "$short_id")"
EOF
            ;;
        ss)
            cipher=$(jq -r '.client.clash.cipher // empty' "$metadata_file")
            password=$(jq -r '.client.clash.password // empty' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: ss
    server: "$(yaml_escape "$server")"
    port: $port
    cipher: "$(yaml_escape "$cipher")"
    password: "$(yaml_escape "$password")"
    udp: true
EOF
            ;;
        trojan)
            password=$(jq -r '.client.clash.password // empty' "$metadata_file")
            sni=$(jq -r '.client.clash.sni // empty' "$metadata_file")
            network=$(jq -r '.client.clash.network // empty' "$metadata_file")
            ws_path=$(jq -r '.client.clash."ws-opts".path // empty' "$metadata_file")
            host=$(jq -r '.client.clash."ws-opts".headers.Host // empty' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: trojan
    server: "$(yaml_escape "$server")"
    port: $port
    password: "$(yaml_escape "$password")"
    udp: true
    sni: "$(yaml_escape "$sni")"
    network: "$(yaml_escape "$network")"
    ws-opts:
      path: "$(yaml_escape "$ws_path")"
      headers:
        Host: "$(yaml_escape "$host")"
EOF
            ;;
        vmess)
            uuid=$(jq -r '.client.clash.uuid // empty' "$metadata_file")
            alter_id=$(jq -r '.client.clash.alterId // 0' "$metadata_file")
            cipher=$(jq -r '.client.clash.cipher // "auto"' "$metadata_file")
            sni=$(jq -r '.client.clash.servername // empty' "$metadata_file")
            network=$(jq -r '.client.clash.network // "ws"' "$metadata_file")
            ws_path=$(jq -r '.client.clash."ws-opts".path // empty' "$metadata_file")
            host=$(jq -r '.client.clash."ws-opts".headers.Host // empty' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: vmess
    server: "$(yaml_escape "$server")"
    port: $port
    uuid: "$(yaml_escape "$uuid")"
    alterId: $alter_id
    cipher: "$(yaml_escape "$cipher")"
    udp: true
    tls: true
    servername: "$(yaml_escape "$sni")"
    network: "$(yaml_escape "$network")"
    ws-opts:
      path: "$(yaml_escape "$ws_path")"
      headers:
        Host: "$(yaml_escape "$host")"
EOF
            ;;
        wireguard)
            ip=$(jq -r '.client.clash.ip // empty' "$metadata_file")
            private_key=$(jq -r '.client.clash."private-key" // empty' "$metadata_file")
            public_key=$(jq -r '.client.clash."public-key" // empty' "$metadata_file")
            pre_shared_key=$(jq -r '.client.clash."pre-shared-key" // empty' "$metadata_file")
            mtu=$(jq -r '.client.clash.mtu // 1360' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: wireguard
    server: "$(yaml_escape "$server")"
    port: $port
    ip: "$(yaml_escape "$ip")"
    private-key: "$(yaml_escape "$private_key")"
    public-key: "$(yaml_escape "$public_key")"
    pre-shared-key: "$(yaml_escape "$pre_shared_key")"
    udp: true
    mtu: $mtu
    dns:
EOF
            dns_count=$(jq '.client.clash.dns | length' "$metadata_file")
            for (( i=0; i<dns_count; i++ )); do
                dns_item=$(jq -r ".client.clash.dns[$i]" "$metadata_file")
                printf '      - "%s"\n' "$(yaml_escape "$dns_item")" >> "$output_file"
            done
            ;;
        hysteria2)
            password=$(jq -r '.client.clash.password // empty' "$metadata_file")
            sni=$(jq -r '.client.clash.sni // empty' "$metadata_file")
            obfs=$(jq -r '.client.clash.obfs // empty' "$metadata_file")
            obfs_password=$(jq -r '.client.clash."obfs-password" // empty' "$metadata_file")
            up=$(jq -r '.client.clash.up // "100 Mbps"' "$metadata_file")
            down=$(jq -r '.client.clash.down // "100 Mbps"' "$metadata_file")

            cat >> "$output_file" <<EOF
  - name: "$(yaml_escape "$name")"
    type: hysteria2
    server: "$(yaml_escape "$server")"
    port: $port
    password: "$(yaml_escape "$password")"
    sni: "$(yaml_escape "$sni")"
    skip-cert-verify: false
    obfs: "$(yaml_escape "$obfs")"
    obfs-password: "$(yaml_escape "$obfs_password")"
    up: "$(yaml_escape "$up")"
    down: "$(yaml_escape "$down")"
EOF
            ;;
        *)
            log_warn "跳过不支持的 metadata Clash 类型: $type ($metadata_file)"
            return 1
            ;;
    esac
}

load_metadata_nodes() {
    local metadata_file module uri name

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            log_warn "跳过无效 metadata: $metadata_file"
            continue
        fi

        module=$(jq -r '.module' "$metadata_file")
        uri=$(jq -r '.client.uri' "$metadata_file")
        name=$(jq -r '.client.clash.name // .module' "$metadata_file")

        log_info "从 metadata 提取节点: $module"
        echo "$uri" >> "$LINKS_FILE_SAFE"

        if append_metadata_clash_proxy "$metadata_file" "$CLASH_PROXIES_SAFE"; then
            append_proxy_name "$CLASH_NAMES_SAFE" "$name"
        fi

    done < <(metadata_list_files)
}

show_subscription_links() {
    local sub_domain="$1"
    local sub_scheme="$2"
    local sub_port="$3"
    local origin sub_path clash_path sub_url clash_url
    if [ -z "$sub_domain" ]; then
        echo ""
        log_warn "订阅文件已生成，但没有可公开访问的订阅域名，因此不打印订阅链接和订阅二维码。"
        echo "说明："
        echo "- 配置 EASYNET_DOMAIN 或 EASYNET_SUBSCRIPTION_DOMAIN 后，部署流程会自动启用独立订阅承载。"
        echo "- 如果订阅文件由外部 Web 服务托管，可显式设置 EASYNET_SUBSCRIPTION_DOMAIN。"
        return 0
    fi

    origin=$(easynet_subscription_origin "$sub_domain" "$sub_scheme" "$sub_port")
    sub_path="$(easynet_subscription_endpoint "sub")"
    clash_path="$(easynet_subscription_endpoint "clash")"
    sub_url="${origin}${sub_path}"
    clash_url="${origin}${clash_path}"

    echo ""
    echo "========================================"
    echo "  节点订阅链接生成成功！"
    echo "========================================"
    echo "【URI 订阅】适用于 Shadowrocket / v2rayN / v2rayNG："
    echo -e "${GREEN}${sub_url}${NC}"
    if command -v qrencode &> /dev/null; then
        echo ""
        echo "URI 订阅二维码："
        qrencode -t utf8 "$sub_url"
    fi
    echo ""
    echo "【Clash/Mihomo 订阅】适用于 Clash Verge Rev / Mihomo："
    echo -e "${GREEN}${clash_url}${NC}"
    if command -v qrencode &> /dev/null; then
        echo ""
        echo "Clash/Mihomo 订阅二维码："
        qrencode -t utf8 "$clash_url"
    fi
    echo ""
    echo "说明："
    echo "- ${sub_path} 为 URI 聚合订阅"
    echo "- ${clash_path} 为 Mihomo YAML 订阅"
    echo "========================================"
}

load_metadata_nodes

if [ ! -s "$LINKS_FILE_SAFE" ] && [ ! -s "$CLASH_NAMES_SAFE" ]; then
    log_warn "没有找到任何有效的节点配置。"
    exit 0
fi

log_info "生成订阅文件..."
mkdir -p "$WEB_ROOT"
rm -f "$LEGACY_SUB_FILE_ALL" "$LEGACY_CLASH_FILE_ALL"

if [ -s "$LINKS_FILE_SAFE" ]; then
    base64 -w 0 < "$LINKS_FILE_SAFE" > "$SUB_FILE"
    chmod 644 "$SUB_FILE"
fi

generate_clash_config "$CLASH_FILE" "$CLASH_PROXIES_SAFE" "$CLASH_NAMES_SAFE"

show_subscription_links "$(easynet_subscription_domain)" "$(easynet_subscription_scheme)" "$(easynet_subscription_port)"
