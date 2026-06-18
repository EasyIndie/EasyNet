#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"

MODULE_NAME="shadowsocks"
CONFIG_DIR="${SHADOWSOCKS_CONFIG_DIR:-/etc/shadowsocks-rust}"

get_public_ip() {
    if [ -n "$EASYNET_PUBLIC_IP" ]; then
        echo "$EASYNET_PUBLIC_IP"
        return
    fi
    curl -s https://ipinfo.io/ip || curl -s https://ifconfig.me || curl -s https://api.ipify.org
}

export_shadowsocks_metadata() {
    local config_file="$CONFIG_DIR/config.json"
    metadata_require_jq

    if [ ! -f "$config_file" ]; then
        echo "Shadowsocks config not found: $config_file" >&2
        return 1
    fi

    local port psk method public_ip userinfo uri metadata_json
    port=$(jq -r '.servers[0].server_port // empty' "$config_file")
    psk=$(jq -r '.servers[0].password // empty' "$config_file")
    method=$(jq -r '.servers[0].method // "2022-blake3-aes-256-gcm"' "$config_file")
    public_ip=$(get_public_ip)

    if [ -z "$port" ] || [ -z "$psk" ] || [ -z "$method" ] || [ -z "$public_ip" ]; then
        echo "Shadowsocks metadata is incomplete" >&2
        return 1
    fi

    userinfo=$(printf '%s:%s' "${method}" "${psk}" | base64 -w 0 | tr '+/' '-_' | sed 's/=*$//')
    uri="ss://${userinfo}@${public_ip}:${port}#EasyNet-SS"

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "ss" \
        --arg listen "0.0.0.0" \
        --arg transport "tcp+udp" \
        --arg security "$method" \
        --arg server "$public_ip" \
        --arg method "$method" \
        --arg password "$psk" \
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
                    name: "EasyNet-SS",
                    type: "ss",
                    server: $server,
                    port: $port,
                    cipher: $method,
                    password: $password,
                    udp: true
                }
            },
            firewall: [
                { port: $port, proto: "tcp" },
                { port: $port, proto: "udp" }
            ],
            systemd: {
                services: ["shadowsocks-rust-server"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_shadowsocks_metadata
fi
