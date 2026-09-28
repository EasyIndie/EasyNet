#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/metadata.sh"
source "$CORE_DIR/url.sh"
source "$CORE_DIR/network.sh"

MODULE_NAME="hysteria2"
HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_ENV_FILE="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"

export_hysteria2_metadata() {
    metadata_require_jq

    if [ -f "${HYSTERIA2_ENV_FILE:-}" ]; then
        # shellcheck disable=SC1090
        source "$HYSTERIA2_ENV_FILE"
    fi

    local domain port password obfs_password sni port_hopping hop_interval hop_interval_max uri metadata_json
    domain="${HYSTERIA2_DOMAIN:-${EASYNET_DOMAIN:-}}"
    port="${HYSTERIA2_PORT:-${EASYNET_HYSTERIA2_PORT:-443}}"
    password="${HYSTERIA2_PASSWORD:-${EASYNET_HYSTERIA2_PASSWORD:-}}"
    obfs_password="${HYSTERIA2_OBFS_PASSWORD:-${EASYNET_HYSTERIA2_OBFS_PASSWORD:-}}"
    sni="${HYSTERIA2_SNI:-$domain}"
    port_hopping="${HYSTERIA2_PORT_HOPPING:-${EASYNET_HYSTERIA2_PORT_HOPPING:-}}"
    hop_interval="${HYSTERIA2_PORT_HOP_INTERVAL:-30s}"
    hop_interval_max="${HYSTERIA2_PORT_HOP_INTERVAL_MAX:-60s}"

    if [ -z "$domain" ] || [ -z "$port" ] || [ -z "$password" ] || [ -z "$obfs_password" ]; then
        echo "Hysteria2 metadata is incomplete" >&2
        return 1
    fi

    # Validate the hopping range once, so the server config, the URI and the
    # client renderers can never disagree about it.
    if [ -n "$port_hopping" ]; then
        if ! [[ "$port_hopping" =~ ^([0-9]{2,5})-([0-9]{2,5})$ ]] \
            || [ "${BASH_REMATCH[1]}" -lt 1 ] || [ "${BASH_REMATCH[2]}" -gt 65535 ] \
            || [ "${BASH_REMATCH[1]}" -ge "${BASH_REMATCH[2]}" ]; then
            echo "忽略无效的端口跳跃范围: $port_hopping" >&2
            port_hopping=""
        fi
    fi

    # Build URI; append port-hopping params when enabled
    local flag_code flag_suffix=""
    flag_code="$(get_country_code)"
    [ -n "$flag_code" ] && flag_suffix="&flag=$flag_code"
    uri="hysteria2://$(urlencode "$password")@$domain:$port/?sni=$(urlencode "$sni")&obfs=salamander&obfs-password=$(urlencode "$obfs_password")"
    if [ -n "$port_hopping" ]; then
        uri="${uri}&porthopping=$(urlencode "$port_hopping")&porthopping-interval=$(urlencode "$hop_interval")"
    fi
    uri="${uri}${flag_suffix}#EasyNet-Hysteria2"

    # Build firewall rules; add port range when hopping is enabled
    local firewall_json
    firewall_json=$(jq -n \
        --argjson port "$port" \
        --arg port_hopping "$port_hopping" \
        '[
            { port: $port, proto: "udp" }
        ] + if $port_hopping != "" then [
            { port: $port_hopping, proto: "udp" }
        ] else [] end')

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
        --arg port_hopping "$port_hopping" \
        --arg hop_interval "$hop_interval" \
        --arg hop_interval_max "$hop_interval_max" \
        --arg uri "$uri" \
        --argjson port "$port" \
        --argjson firewall "$firewall_json" \
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
                    down: "100 Mbps",
                    # Consumed by render_clash.sh (mihomo `ports`) and
                    # render_singbox.jq (`server_ports`); null when hopping is off
                    # so the renderers omit the field entirely.
                    "hop-range": (if $port_hopping == "" then null else $port_hopping end),
                    "hop-interval": (if $port_hopping == "" then null else $hop_interval end),
                    # Upper bound for randomized hopping (sing-box hop_interval_max);
                    # render_singbox.jq omits it when equal to hop-interval.
                    "hop-interval-max": (if $port_hopping == "" then null else $hop_interval_max end)
                }
            },
            firewall: $firewall,
            systemd: {
                services: ["hysteria-server.service"]
            }
        }')

    metadata_write "$MODULE_NAME" "$metadata_json"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export_hysteria2_metadata
fi
