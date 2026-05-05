#!/bin/bash

EASYNET_MAINTENANCE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_MAINTENANCE_CORE_DIR/logging.sh"

JOURNALD_MAX_USE="${EASYNET_JOURNALD_MAX_USE:-500M}"
NGINX_LOGROTATE_FILE="${EASYNET_NGINX_LOGROTATE_FILE:-/etc/logrotate.d/easynet-nginx}"

maintenance_configure_journald() {
    if [ ! -f /etc/systemd/journald.conf ]; then
        return 0
    fi

    if grep -q '^#\?SystemMaxUse=' /etc/systemd/journald.conf; then
        sed -i "s/^#\\?SystemMaxUse=.*/SystemMaxUse=${JOURNALD_MAX_USE}/" /etc/systemd/journald.conf
    else
        echo "SystemMaxUse=${JOURNALD_MAX_USE}" >> /etc/systemd/journald.conf
    fi

    systemctl restart systemd-journald >/dev/null 2>&1 || true
    log_info "journald 日志上限已设置为 ${JOURNALD_MAX_USE}"
}

maintenance_configure_nginx_logrotate() {
    if [ ! -d /etc/logrotate.d ]; then
        return 0
    fi

    cat > "$NGINX_LOGROTATE_FILE" <<'EOF'
/var/log/nginx/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        [ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)
    endscript
}
EOF
    log_info "Nginx logrotate 已配置: $NGINX_LOGROTATE_FILE"
}

maintenance_configure_logs() {
    maintenance_configure_journald
    maintenance_configure_nginx_logrotate
}
