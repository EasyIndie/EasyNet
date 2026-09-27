#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"
source "$CORE_DIR/url.sh"

MODULE_NAME="wireguard"
WG_DIR="${WG_DIR:-/etc/amnezia/amneziawg}"
CLIENT_CONFIG_DIR="${CLIENT_CONFIG_DIR:-$WG_DIR/clients}"
CLIENT_NAME="${EASYNET_WIREGUARD_CLIENT:-client1}"

read_conf_value() {
    local key="$1"
    local file="$2"
    grep "^$key" "$file" | sed 's/^[^=]*=[[:space:]]*//' | xargs || true
}

export_wireguard_metadata() {
    local wg_conf="$CLIENT_CONFIG_DIR/$CLIENT_NAME.conf"

    metadata_require_jq

    if [ ! -f "$wg_conf" ]; then
        echo "WireGuard client config not found: $wg_conf" >&2
        return 1
    fi

    local wg_priv_key wg_addr wg_dns wg_pub_key wg_psk wg_endpoint wg_mtu ip_only wg_server wg_port
    local enc_priv enc_pub enc_psk enc_dns uri dns_json metadata_json
    local jc jmin jmax s1 s2 h1 h2 h3 h4

    wg_priv_key=$(read_conf_value "PrivateKey" "$wg_conf")
    wg_addr=$(read_conf_value "Address" "$wg_conf")
    wg_dns=$(read_conf_value "DNS" "$wg_conf")
    wg_pub_key=$(read_conf_value "PublicKey" "$wg_conf")
    wg_psk=$(read_conf_value "PresharedKey" "$wg_conf")
    wg_endpoint=$(read_conf_value "Endpoint" "$wg_conf")
    wg_mtu=$(read_conf_value "MTU" "$wg_conf")

    # AmneziaWG obfuscation parameters (must match the server)
    jc=$(read_conf_value "Jc" "$wg_conf")
    jmin=$(read_conf_value "Jmin" "$wg_conf")
    jmax=$(read_conf_value "Jmax" "$wg_conf")
    s1=$(read_conf_value "S1" "$wg_conf")
    s2=$(read_conf_value "S2" "$wg_conf")
    h1=$(read_conf_value "H1" "$wg_conf")
    h2=$(read_conf_value "H2" "$wg_conf")
    h3=$(read_conf_value "H3" "$wg_conf")
    h4=$(read_conf_value "H4" "$wg_conf")

    # Fallback to AmneziaWG recommended defaults when a legacy conf lacks them.
    jc="${jc:-4}"; jmin="${jmin:-8}"; jmax="${jmax:-80}"
    s1="${s1:-15}"; s2="${s2:-72}"
    h1="${h1:-1001}"; h2="${h2:-1002}"; h3="${h3:-1003}"; h4="${h4:-1004}"

    if [ -z "$wg_priv_key" ] || [ -z "$wg_pub_key" ] || [ -z "$wg_endpoint" ]; then
        echo "WireGuard metadata is incomplete" >&2
        return 1
    fi

    ip_only=$(echo "$wg_addr" | cut -d'/' -f1)
    wg_server="${wg_endpoint%:*}"
    wg_port="${wg_endpoint##*:}"
    wg_mtu="${wg_mtu:-1280}"

    enc_priv=$(urlencode "$wg_priv_key")
    enc_pub=$(urlencode "$wg_pub_key")
    enc_psk=$(urlencode "$wg_psk")
    enc_dns=$(urlencode "$wg_dns")

    # Shadowrocket represents AmneziaWG obfuscation as obfs=amneziawg with an
    # obfsParam JSON blob (all values are strings). Other clients use the
    # individual AWG query params, so we emit both.
    local obfs_param enc_obfs_param
    obfs_param=$(jq -cn \
        --arg jc "$jc" --arg jmin "$jmin" --arg jmax "$jmax" \
        --arg s1 "$s1" --arg s2 "$s2" \
        --arg h1 "$h1" --arg h2 "$h2" --arg h3 "$h3" --arg h4 "$h4" \
        '{jc: $jc, jmin: $jmin, jmax: $jmax, s1: $s1, s2: $s2,
          h1: $h1, h2: $h2, h3: $h3, h4: $h4,
          random_trailers: "false", disable_cookies: "false"}')
    enc_obfs_param=$(urlencode_query "$obfs_param")

    uri="wg://${wg_endpoint}?publicKey=${enc_pub}&privateKey=${enc_priv}&presharedKey=${enc_psk}&ip=${ip_only}&mtu=${wg_mtu}&dns=${enc_dns}&udp=1"
    uri="${uri}&obfs=amneziawg&obfsParam=${enc_obfs_param}"
    uri="${uri}&jc=${jc}&jmin=${jmin}&jmax=${jmax}&s1=${s1}&s2=${s2}&h1=${h1}&h2=${h2}&h3=${h3}&h4=${h4}#EasyNet-WG"

    dns_json=$(printf '%s' "$wg_dns" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')

    # Build Clash metadata. AmneziaWG params live under amnezia-wg-option (mihomo).
    local clash_json amnezia_json
    clash_json=$(jq -n \
        --arg server "$wg_server" \
        --arg private_key "$wg_priv_key" \
        --arg public_key "$wg_pub_key" \
        --arg psk "$wg_psk" \
        --arg ip "$ip_only" \
        --argjson port "$wg_port" \
        --argjson mtu "$wg_mtu" \
        --argjson dns "$dns_json" \
        '{
            name: "EasyNet-WG",
            type: "wireguard",
            server: $server,
            port: $port,
            ip: $ip,
            "private-key": $private_key,
            "public-key": $public_key,
            "pre-shared-key": $psk,
            udp: true,
            mtu: $mtu,
            dns: $dns
        }')

    amnezia_json=$(jq -n \
        --argjson jc "$jc" \
        --argjson jmin "$jmin" \
        --argjson jmax "$jmax" \
        --argjson s1 "$s1" \
        --argjson s2 "$s2" \
        --argjson h1 "$h1" \
        --argjson h2 "$h2" \
        --argjson h3 "$h3" \
        --argjson h4 "$h4" \
        '{
            jc: $jc, jmin: $jmin, jmax: $jmax,
            s1: $s1, s2: $s2,
            h1: $h1, h2: $h2, h3: $h3, h4: $h4
        }')
    clash_json=$(echo "$clash_json" | jq --argjson awg "$amnezia_json" '. + { "amnezia-wg-option": $awg }')

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "wireguard" \
        --arg listen "0.0.0.0" \
        --arg transport "udp" \
        --arg security "amneziawg" \
        --arg server "$wg_server" \
        --arg private_key "$wg_priv_key" \
        --arg public_key "$wg_pub_key" \
        --arg psk "$wg_psk" \
        --arg ip "$ip_only" \
        --arg uri "$uri" \
        --argjson port "$wg_port" \
        --argjson mtu "$wg_mtu" \
        --argjson clash "$clash_json" \
        '{
            schemaVersion: 1,
            "module": $module_name,
            enabled: true,
            protocol: $protocol,
            listen: $listen,
            port: $port,
            transport: $transport,
            security: $security,
            client: {
                uri: $uri,
                clash: $clash
            },
            firewall: [
                { port: $port, proto: "udp" }
            ],
            systemd: {
                services: ["awg-quick@wg0"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_wireguard_metadata
fi
