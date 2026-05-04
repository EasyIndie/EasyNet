#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"

MODULE_NAME="v2ray"
CONFIG_DIR="${V2RAY_CONFIG_DIR:-/usr/local/etc/v2ray}"

resolve_domain() {
    if [ -n "$EASYNET_DOMAIN" ]; then
        echo "$EASYNET_DOMAIN"
        return
    fi
    if [ -f "$CONFIG_DIR/domain.txt" ]; then
        cat "$CONFIG_DIR/domain.txt"
        return
    fi
    echo ""
}

export_v2ray_metadata() {
    local config_file="$CONFIG_DIR/config.json"
    metadata_require_jq

    if [ ! -f "$config_file" ]; then
        echo "V2Ray config not found: $config_file" >&2
        return 1
    fi

    local uuid ws_path inbound_port listen domain public_port uri vmess_json vmess_b64 metadata_json firewall_json
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    ws_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "$config_file")
    inbound_port=$(jq -r '.inbounds[0].port // empty' "$config_file")
    listen=$(jq -r '.inbounds[0].listen // "0.0.0.0"' "$config_file")
    domain=$(resolve_domain)
    public_port="${EASYNET_V2RAY_PUBLIC_PORT:-443}"

    if [ -z "$uuid" ] || [ -z "$ws_path" ] || [ -z "$domain" ] || [ -z "$public_port" ]; then
        echo "V2Ray metadata is incomplete" >&2
        return 1
    fi

    vmess_json=$(jq -cn \
        --arg domain "$domain" \
        --arg uuid "$uuid" \
        --arg ws_path "$ws_path" \
        --argjson port "$public_port" \
        '{
            v: "2",
            ps: "EasyNet-V2Ray",
            add: $domain,
            port: $port,
            id: $uuid,
            aid: 0,
            net: "ws",
            type: "none",
            host: $domain,
            path: $ws_path,
            tls: "tls",
            sni: $domain
        }')
    vmess_b64=$(printf '%s' "$vmess_json" | base64 | tr -d '\n')
    uri="vmess://$vmess_b64"
    if [ "$listen" = "127.0.0.1" ] || [ "$listen" = "localhost" ]; then
        firewall_json="[]"
    else
        firewall_json=$(jq -cn --argjson port "$inbound_port" '[{ port: $port, proto: "tcp" }]')
    fi

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "vmess" \
        --arg listen "$listen" \
        --arg transport "ws" \
        --arg security "tls" \
        --arg server "$domain" \
        --arg uuid "$uuid" \
        --arg ws_path "$ws_path" \
        --arg uri "$uri" \
        --argjson port "$public_port" \
        --argjson inbound_port "$inbound_port" \
        --argjson firewall "$firewall_json" \
        '{
            schemaVersion: 1,
            "module": $module_name,
            enabled: true,
            protocol: $protocol,
            listen: $listen,
            port: $inbound_port,
            publicPort: $port,
            transport: $transport,
            security: $security,
            client: {
                uri: $uri,
                clash: {
                    name: "EasyNet-V2Ray",
                    type: "vmess",
                    server: $server,
                    port: $port,
                    uuid: $uuid,
                    alterId: 0,
                    cipher: "auto",
                    udp: true,
                    tls: true,
                    servername: $server,
                    network: "ws",
                    "ws-opts": {
                        path: $ws_path,
                        headers: {
                            Host: $server
                        }
                    }
                }
            },
            firewall: $firewall,
            systemd: {
                services: ["v2ray"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_v2ray_metadata
fi
