#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"

EDGE_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
EDGE_CERT_FILE="${EASYNET_EDGE_CERT_FILE:-$EDGE_CERT_DIR/fullchain.crt}"
EDGE_KEY_FILE="${EASYNET_EDGE_KEY_FILE:-$EDGE_CERT_DIR/private.key}"

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

    log_info "授予 Edge 证书读取权限给服务用户: $user"
    chown root:"$user" "$EDGE_CERT_DIR" "$EDGE_CERT_FILE" "$EDGE_KEY_FILE"
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

    # Always restart nginx (Edge Gateway)
    restart_if_exists nginx

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

    log_info "Edge 证书续期 hook 已完成。"
}

main "$@"
