#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"
source "$CORE_DIR/url.sh"

MODULE_NAME="hysteria2"
HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_ENV_FILE="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"

export_hysteria2_metadata() {
    metadata_require_jq

    if [ -f "$HYSTERIA2_ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$HYSTERIA2_ENV_FILE"
    fi

    local domain port password obfs_password sni uri metadata_json
    domain="${HYSTERIA2_DOMAIN:-${EASYNET_DOMAIN:-}}"
    port="${HYSTERIA2_PORT:-${EASYNET_HYSTERIA2_PORT:-443}}"
    password="${HYSTERIA2_PASSWORD:-${EASYNET_HYSTERIA2_PASSWORD:-}}"
    obfs_password="${HYSTERIA2_OBFS_PASSWORD:-${EASYNET_HYSTERIA2_OBFS_PASSWORD:-}}"
    sni="${HYSTERIA2_SNI:-$domain}"

    if [ -z "$domain" ] || [ -z "$port" ] || [ -z "$password" ] || [ -z "$obfs_password" ]; then
        echo "Hysteria2 metadata is incomplete" >&2
        return 1
    fi

    uri="hysteria2://$(urlencode "$password")@$domain:$port/?sni=$(urlencode "$sni")&obfs=salamander&obfs-password=$(urlencode "$obfs_password")#EasyNet-Hysteria2"

    metadata_json=$(jq -n \
        --arg module_name "$MODULE_NAME" \
        --arg protocol "hysteria2" \
        --arg listen "0.0.0.0" \
        --arg transport "udp" \
        --arg security "tls+obfs" \
        --arg server "$domain" \
        --arg password "$password" \
        --arg sni "$sni" \
        --arg obfs_password "$obfs_password" \
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
                    name: "EasyNet-Hysteria2",
                    type: "hysteria2",
                    server: $server,
                    port: $port,
                    password: $password,
                    sni: $sni,
                    "skip-cert-verify": false,
                    obfs: "salamander",
                    "obfs-password": $obfs_password,
                    up: "100 Mbps",
                    down: "100 Mbps"
                }
            },
            firewall: [
                { port: $port, proto: "udp" }
            ],
            systemd: {
                services: ["hysteria-server.service"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_hysteria2_metadata
fi
