#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"

MODULE_NAME="trojan-go"
CONFIG_DIR="${TROJAN_CONFIG_DIR:-/etc/trojan-go}"

get_public_ip() {
    if [ -n "$EASYNET_PUBLIC_IP" ]; then
        echo "$EASYNET_PUBLIC_IP"
        return
    fi
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

export_trojan_go_metadata() {
    local config_file="$CONFIG_DIR/config.json"
    metadata_require_jq

    if [ ! -f "$config_file" ]; then
        echo "Trojan-Go config not found: $config_file" >&2
        return 1
    fi

    local domain password path port public_ip uri metadata_json
    domain=$(jq -r '.ssl.sni // empty' "$config_file")
    password=$(jq -r '.password[0] // empty' "$config_file")
    path=$(jq -r '.websocket.path // empty' "$config_file")
    port=$(jq -r '.local_port // 443' "$config_file")
    public_ip=$(get_public_ip)

    if [ -z "$domain" ] || [ -z "$password" ] || [ -z "$path" ] || [ -z "$port" ]; then
        echo "Trojan-Go metadata is incomplete" >&2
        return 1
    fi

    uri="trojan://${password}@${domain}:${port}?security=tls&type=ws&path=${path}#EasyNet-Trojan"

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "trojan" \
        --arg listen "0.0.0.0" \
        --arg transport "ws" \
        --arg security "tls" \
        --arg server "$domain" \
        --arg password "$password" \
        --arg sni "$domain" \
        --arg path "$path" \
        --arg uri "$uri" \
        --argjson port "$port" \
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
                clash: {
                    name: "EasyNet-Trojan",
                    type: "trojan",
                    server: $server,
                    port: $port,
                    password: $password,
                    udp: true,
                    sni: $sni,
                    network: "ws",
                    "ws-opts": {
                        path: $path,
                        headers: {
                            Host: $server
                        }
                    }
                }
            },
            firewall: [
                { port: $port, proto: "tcp" }
            ],
            systemd: {
                services: ["trojan-go"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_trojan_go_metadata
fi
