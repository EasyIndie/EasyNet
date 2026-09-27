#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"

EDGE_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
EDGE_CERT_FILE="${EASYNET_EDGE_CERT_FILE:-$EDGE_CERT_DIR/fullchain.crt}"
EDGE_KEY_FILE="${EASYNET_EDGE_KEY_FILE:-$EDGE_CERT_DIR/private.key}"
# acme.sh runs this hook on every `--install-cert` (i.e. every deploy), so we
# must not restart the whole stack unless the certificate really changed.
CERT_FINGERPRINT_FILE="${EASYNET_EDGE_CERT_FINGERPRINT_FILE:-/var/lib/easynet/edge/cert_fingerprint.txt}"

cert_fingerprint() {
    [ -f "$EDGE_CERT_FILE" ] || {
        printf ''
        return 0
    }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$EDGE_CERT_FILE" | awk '{print $1}'
    else
        openssl dgst -sha256 "$EDGE_CERT_FILE" | awk '{print $NF}'
    fi
}

service_exists() {
    systemctl cat "$1" >/dev/null 2>&1 ||
        systemctl list-unit-files "$1" >/dev/null 2>&1
}

service_user() {
    local service="$1"
    systemctl cat "$service" 2>/dev/null |
        awk -F= '/^[[:space:]]*User=/{ gsub(/[[:space:]]/, "", $2); print $2; exit }'
}

grant_cert_access_to_user() {
    local user="$1"
    [ -z "$user" ] && return 0
    [ "$user" = "root" ] && return 0
    id "$user" >/dev/null 2>&1 || return 0

    local group
    group=$(id -gn "$user" 2>/dev/null) || group="$user"
    log_info "授予 Edge 证书读取权限给服务用户: $user (group: $group)"
    chown root:"$group" "$EDGE_CERT_DIR" "$EDGE_CERT_FILE" "$EDGE_KEY_FILE"
    chmod 750 "$EDGE_CERT_DIR"
    chmod 640 "$EDGE_CERT_FILE" "$EDGE_KEY_FILE"
}

fix_edge_cert_permissions() {
    chmod 755 "$EDGE_CERT_DIR"
    chmod 644 "$EDGE_CERT_FILE"
    chmod 600 "$EDGE_KEY_FILE"

    # Dynamically grant cert access to all services that consume Edge certificates
    # by reading systemd services from all deployed modules
    local all_services
    all_services=$(cron_restart_services 2>/dev/null) || true
    if [ -n "$all_services" ]; then
        echo "$all_services" | while IFS= read -r svc; do
            [ -n "$svc" ] && grant_cert_access_to_user "$(service_user "$svc")"
        done
    fi

    # Legacy fallback: ensure hysteria-server gets cert access
    if service_exists hysteria-server.service; then
        grant_cert_access_to_user "$(service_user hysteria-server.service)"
    fi
}

restart_if_exists() {
    local service="$1"
    if service_exists "$service"; then
        systemctl restart "$service" >/dev/null 2>&1 || log_warn "服务重启失败: $service"
    fi
}

main() {
    if [ ! -f "$EDGE_CERT_FILE" ] || [ ! -f "$EDGE_KEY_FILE" ]; then
        log_warn "Edge 证书文件不存在，跳过续期 hook。"
        return 0
    fi

    source "$CORE_DIR/metadata.sh"
    source "$CORE_DIR/cron.sh"
    source "$CORE_DIR/discovery.sh"

    fix_edge_cert_permissions

    # Skip the restart storm when the certificate is byte-identical (the common
    # case: acme.sh --install-cert runs on every deploy, but nothing rotated).
    local fingerprint previous
    fingerprint="$(cert_fingerprint)"
    previous="$(cat "$CERT_FINGERPRINT_FILE" 2>/dev/null || true)"
    if [ -n "$fingerprint" ] && [ "$fingerprint" = "$previous" ]; then
        log_info "Edge 证书未变化，跳过服务重启。"
        return 0
    fi

    # Reload nginx (Edge Gateway): a reload keeps in-flight downloads alive.
    if service_exists nginx; then
        systemctl reload nginx >/dev/null 2>&1 ||
            systemctl restart nginx >/dev/null 2>&1 ||
            log_warn "nginx 重载失败"
    fi

    # Dynamically restart services that use Edge certificates,
    # discovered from metadata across all deployed modules.
    # nginx is excluded since it's restarted separately above.
    local services
    services=$(cron_restart_services 2>/dev/null) || true
    if [ -n "$services" ]; then
        echo "$services" | while IFS= read -r svc; do
            [ -n "$svc" ] && restart_if_exists "$svc"
        done
    fi

    # Legacy fallback: ensure hysteria2 is restarted
    # (in case its metadata is missing)
    restart_if_exists hysteria-server.service

    if [ -n "$fingerprint" ]; then
        mkdir -p "$(dirname "$CERT_FINGERPRINT_FILE")"
        printf '%s' "$fingerprint" > "$CERT_FINGERPRINT_FILE"
    fi

    log_info "Edge 证书续期 hook 已完成。"
}

main "$@"
