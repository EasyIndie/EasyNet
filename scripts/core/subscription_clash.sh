#!/bin/bash
# EasyNet Clash/Mihomo Subscription Module
# Generates Clash YAML proxies and config from EasyNet metadata.
# Source this file, then call:
#   append_metadata_clash_proxy <metadata.json> <output_proxies.yaml>
#   generate_clash_config <output.yaml> <proxies.yaml> <names.txt>

# Logging guard (may already be defined by the caller)
if ! declare -F log_warn >/dev/null 2>&1; then
    log_warn() { echo "[WARN] $1"; }
fi

# Escape special YAML characters (backslash and double-quote)
yaml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

# Generate a YAML proxy name list from a names file
generate_proxy_list() {
    local names_file="$1"
    local indent="$2"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        printf '%s- "%s"\n' "$indent" "$(yaml_escape "$name")"
    done < "$names_file"
}

# ============================================================
# Clash config generation
# ============================================================

generate_clash_config() {
    local output_file="$1"
    local proxies_file="$2"
    local names_file="$3"

    [ ! -s "$names_file" ] && return 0

    cat > "$output_file" <<'HEADER'
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true

proxies:
HEADER

    cat "$proxies_file" >> "$output_file"

    cat >> "$output_file" <<'GROUPS'
proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "Auto"
      - "DIRECT"
GROUPS

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<'AUTO'
  - name: "Auto"
    type: url-test
    url: "https://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    proxies:
AUTO

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<'RULES'

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
RULES

    chmod 644 "$output_file"
}

# ============================================================
# Per-protocol Clash proxy generators
# ============================================================

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
