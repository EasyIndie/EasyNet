#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"
source "$CORE_DIR/url.sh"

MODULE_NAME="wireguard"
WG_DIR="${WG_DIR:-/etc/wireguard}"
CLIENT_CONFIG_DIR="${CLIENT_CONFIG_DIR:-$WG_DIR/clients}"
CLIENT_NAME="${EASYNET_WIREGUARD_CLIENT:-client1}"

read_conf_value() {
    local key="$1"
    local file="$2"
    grep "^$key" "$file" | sed 's/^[^=]*=[[:space:]]*//' | xargs
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
    local wg_obfs jc jmin jmax

    wg_priv_key=$(read_conf_value "PrivateKey" "$wg_conf")
    wg_addr=$(read_conf_value "Address" "$wg_conf")
    wg_dns=$(read_conf_value "DNS" "$wg_conf")
    wg_pub_key=$(read_conf_value "PublicKey" "$wg_conf")
    wg_psk=$(read_conf_value "PresharedKey" "$wg_conf")
    wg_endpoint=$(read_conf_value "Endpoint" "$wg_conf")
    wg_mtu=$(read_conf_value "MTU" "$wg_conf")

    if [ -z "$wg_priv_key" ] || [ -z "$wg_pub_key" ] || [ -z "$wg_endpoint" ]; then
        echo "WireGuard metadata is incomplete" >&2
        return 1
    fi

    ip_only=$(echo "$wg_addr" | cut -d'/' -f1)
    wg_server="${wg_endpoint%:*}"
    wg_port="${wg_endpoint##*:}"
    wg_mtu="${wg_mtu:-1360}"

    # AmneziaWG obfuscation params (client-side, server stays standard WG)
    wg_obfs="${EASYNET_WIREGUARD_OBFS:-true}"
    jc="${EASYNET_WIREGUARD_JC:-5}"
    jmin="${EASYNET_WIREGUARD_JMIN:-50}"
    jmax="${EASYNET_WIREGUARD_JMAX:-1000}"

    enc_priv=$(urlencode "$wg_priv_key")
    enc_pub=$(urlencode "$wg_pub_key")
    enc_psk=$(urlencode "$wg_psk")
    enc_dns=$(urlencode "$wg_dns")
    uri="wg://${wg_endpoint}?publicKey=${enc_pub}&privateKey=${enc_priv}&presharedKey=${enc_psk}&ip=${ip_only}&mtu=${wg_mtu}&dns=${enc_dns}&udp=1"
    if [ "$wg_obfs" = "true" ]; then
        uri="${uri}&jc=${jc}&jmin=${jmin}&jmax=${jmax}"
    fi
    uri="${uri}#EasyNet-WG"

    dns_json=$(printf '%s' "$wg_dns" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')

    # Build Clash metadata; attach obfs fields when enabled
    local clash_json
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

    if [ "$wg_obfs" = "true" ]; then
        clash_json=$(echo "$clash_json" | jq \
            --argjson jc "$jc" \
            --argjson jmin "$jmin" \
            --argjson jmax "$jmax" \
            '. + { jc: $jc, jmin: $jmin, jmax: $jmax }')
    fi

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "wireguard" \
        --arg listen "0.0.0.0" \
        --arg transport "udp" \
        --arg security "wireguard" \
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
                services: ["wg-quick@wg0"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_wireguard_metadata
fi
