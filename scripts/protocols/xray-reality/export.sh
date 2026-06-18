#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"

MODULE_NAME="xray-reality"
XRAY_DIR="${XRAY_DIR:-/usr/local/etc/xray}"

get_public_ip() {
    if [ -n "$EASYNET_PUBLIC_IP" ]; then
        echo "$EASYNET_PUBLIC_IP"
        return
    fi
    curl -s https://ipinfo.io/ip || curl -s https://ifconfig.me || curl -s https://api.ipify.org
}

export_xray_reality_metadata() {
    local config_file="$XRAY_DIR/config.json"
    local public_key_file="$XRAY_DIR/public.key"

    metadata_require_jq

    if [ ! -f "$config_file" ]; then
        echo "Xray config not found: $config_file" >&2
        return 1
    fi
    if [ ! -f "$public_key_file" ]; then
        echo "Xray public key not found: $public_key_file" >&2
        return 1
    fi

    local uuid port sni short_id public_key public_ip transport xhttp_mode xmux_concurrency uri metadata_json
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    port=$(jq -r '.inbounds[0].port // empty' "$config_file")
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    public_key=$(cat "$public_key_file")
    public_ip=$(get_public_ip)
    transport=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$config_file")
    xhttp_mode=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "$config_file")
    xmux_concurrency=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.xmux.concurrency // 0' "$config_file")

    if [ -z "$uuid" ] || [ -z "$port" ] || [ -z "$sni" ] || [ -z "$public_key" ] || [ -z "$public_ip" ]; then
        echo "Xray Reality metadata is incomplete" >&2
        return 1
    fi

    # Build URI
    if [ "$transport" = "xhttp" ]; then
        uri="vless://$uuid@$public_ip:$port?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&mode=$xhttp_mode&flow=xtls-rprx-vision#EasyNet-Reality"
    else
        uri="vless://$uuid@$public_ip:$port?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
    fi

    # Build Clash metadata; include xhttp-opts when using XHTTP transport
    local clash_json
    clash_json=$(jq -n \
        --arg server "$public_ip" \
        --arg uuid "$uuid" \
        --arg sni "$sni" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        --arg network "$transport" \
        --argjson port "$port" \
        '{
            name: "EasyNet-Reality",
            type: "vless",
            server: $server,
            port: $port,
            uuid: $uuid,
            network: $network,
            udp: true,
            tls: true,
            flow: "xtls-rprx-vision",
            servername: $sni,
            "client-fingerprint": "chrome",
            "reality-opts": {
                "public-key": $public_key,
                "short-id": $short_id
            }
        }')

    # Attach xhttp-opts when transport is xhttp
    if [ "$transport" = "xhttp" ]; then
        local xhttp_opts
        xhttp_opts=$(jq -n \
            --arg mode "$xhttp_mode" \
            --argjson xmux_cc "$xmux_concurrency" \
            '{
                "xhttp-opts": {
                    mode: $mode
                }
            }')
        if [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
            xhttp_opts=$(echo "$xhttp_opts" | jq \
                --argjson xmux_cc "$xmux_concurrency" \
                '.["xhttp-opts"].xmux = { concurrency: $xmux_cc }')
        fi
        clash_json=$(echo "$clash_json" | jq -s '.[0] * .[1]' - <(echo "$xhttp_opts"))
    fi

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "vless" \
        --arg listen "0.0.0.0" \
        --arg transport "$transport" \
        --arg security "reality" \
        --arg server "$public_ip" \
        --arg uuid "$uuid" \
        --arg sni "$sni" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        --arg uri "$uri" \
        --argjson port "$port" \
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
                { port: $port, proto: "tcp" }
            ],
            systemd: {
                services: ["xray"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_xray_reality_metadata
fi
