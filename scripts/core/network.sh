#!/bin/bash
# EasyNet Network Module
# Network helper functions: public IP detection, DNS resolution.
# Source this file, then call:
#   get_public_ip

get_public_ip() {
    if [ -n "${EASYNET_PUBLIC_IP:-}" ]; then
        echo "$EASYNET_PUBLIC_IP"
        return
    fi
    curl -s https://ipinfo.io/ip || curl -s https://ifconfig.me || curl -s https://api.ipify.org
}

# Resolve the ISO 3166-1 alpha-2 country code for the flag shown by clients
# such as Shadowrocket (node attribute `flag=XX`).
#
# Priority: EASYNET_FLAG override > cached value (only while the server IP is
# unchanged) > ipinfo.io lookup (the same provider used for public IP
# detection). Pass the already-known public IP as $1 to avoid a second lookup.
# Returns an empty string on failure so callers can simply omit the flag.
get_country_code() {
    local ip="${1:-}"
    local code cache_file cached_ip cached_code

    if [ -n "${EASYNET_FLAG:-}" ]; then
        printf '%s' "${EASYNET_FLAG:-}" | tr '[:lower:]' '[:upper:]'
        return 0
    fi

    [ -n "$ip" ] || ip="$(get_public_ip)"
    [ -n "$ip" ] || return 0

    cache_file="${EASYNET_STATE_DIR:-/var/lib/easynet}/country_code"
    if [ -f "$cache_file" ]; then
        cached_ip="$(awk 'NR==1 {print $1}' "$cache_file" 2>/dev/null)"
        cached_code="$(awk 'NR==1 {print $2}' "$cache_file" 2>/dev/null)"
        # Only trust the cache while the server IP is unchanged, so a moved VPS
        # (new IP) re-detects its country automatically.
        if [ "$cached_ip" = "$ip" ] && [[ "$cached_code" =~ ^[A-Za-z]{2}$ ]]; then
            printf '%s' "$cached_code" | tr '[:lower:]' '[:upper:]'
            return 0
        fi
    fi

    code="$(curl -s --max-time 5 "https://ipinfo.io/${ip}/country" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$code" =~ ^[A-Za-z]{2}$ ]]; then
        code="$(printf '%s' "$code" | tr '[:lower:]' '[:upper:]')"
        if mkdir -p "$(dirname "$cache_file")" 2>/dev/null; then
            printf '%s %s' "$ip" "$code" > "$cache_file" 2>/dev/null || true
        fi
        printf '%s' "$code"
    fi
}
