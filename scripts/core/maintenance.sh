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

# Apply a conservative systemd sandbox via drop-in, without touching the
# upstream-generated unit file (so upstream package upgrades stay clean).
# Extra unit directives can be appended with the second argument.
# Usage: maintenance_apply_systemd_hardening <unit> [extra-directives]
maintenance_apply_systemd_hardening() {
    local unit="$1"
    local extra="${2:-}"
    local unit_dir="${EASYNET_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
    local dropin_dir dropin

    [ -n "$unit" ] || return 0

    # systemd only resolves drop-ins from <full-unit-name>.d (e.g. xray.service.d),
    # so normalise a bare name such as "xray" to "xray.service".
    case "$unit" in
        *.*) ;;
        *) unit="${unit}.service" ;;
    esac

    dropin_dir="${unit_dir}/${unit}.d"
    dropin="$dropin_dir/easynet-hardening.conf"

    mkdir -p "$dropin_dir"
    local new_dropin
    new_dropin="$(mktemp)"
    cat > "$new_dropin" << 'EOF'
[Service]
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectClock=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
EOF
    [ -n "$extra" ] && printf '%s\n' "$extra" >> "$new_dropin"
    chmod 644 "$new_dropin"

    # Report whether the sandbox actually changed so callers can avoid
    # restarting a healthy service on every re-deploy.
    SYSTEMD_HARDENING_CHANGED=false
    if ! cmp -s "$new_dropin" "$dropin"; then
        install -m 644 "$new_dropin" "$dropin"
        SYSTEMD_HARDENING_CHANGED=true
    fi
    rm -f "$new_dropin"

    if [ "$SYSTEMD_HARDENING_CHANGED" = true ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        log_info "已应用 systemd 沙箱加固: ${unit}（${dropin}）"
    fi
}

# Install and enable fail2ban with an sshd jail (brute-force protection).
# Uses jail.d/ so a user-managed /etc/fail2ban/jail.local is never overwritten.
maintenance_configure_fail2ban() {
    local admin_ip=""

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "安装 fail2ban（SSH 防暴力破解）..."
        DEBIAN_FRONTEND=noninteractive apt install -y fail2ban >/dev/null 2>&1 || {
            log_warn "fail2ban 安装失败，已跳过。"
            return 0
        }
    fi

    # Never ban the operator running this deployment: remember the source IP of
    # the current SSH session so a mistyped password cannot lock us out.
    if [ -n "${SSH_CLIENT:-}" ]; then
        admin_ip="${SSH_CLIENT%% *}"
    fi
    if [ -n "${EASYNET_FAIL2BAN_IGNORE_IP:-}" ]; then
        admin_ip="${admin_ip:+${admin_ip} }${EASYNET_FAIL2BAN_IGNORE_IP:-}"
    fi

    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/easynet.local << EOF
# Managed by EasyNet - do not edit
[DEFAULT]
# Normal (not aggressive) mode: aggressive adds ddos/extra patterns that also
# match benign "connection closed" events and can ban the operator's own IP.
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1${admin_ip:+ ${admin_ip}}

[sshd]
enabled = true
EOF
    chmod 644 /etc/fail2ban/jail.d/easynet.local

    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
    if systemctl is-active --quiet fail2ban; then
        log_info "fail2ban 已启用（sshd jail，maxretry=5，bantime=1h）"
    else
        log_warn "fail2ban 未能启动，请检查 journalctl -u fail2ban。"
    fi
}
