#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
}

@test "Installers do not execute curl output directly" {
    run rg -q 'curl .*\|.*sh|curl .*\|.*bash' "$PROJECT_ROOT/scripts"
    [ "$status" -eq 1 ]
    run rg -F -q 'bash -c "$(curl' "$PROJECT_ROOT/scripts"
    [ "$status" -eq 1 ]
    run rg -F -q 'bash <(curl' "$PROJECT_ROOT/scripts"
    [ "$status" -eq 1 ]
}

@test "Installers use shared download helper with optional checksum verification" {
    run rg -q "run_downloaded_script|download_file" "$PROJECT_ROOT/scripts/core/download.sh" "$PROJECT_ROOT/scripts/protocols" "$PROJECT_ROOT/scripts/exposure/edge"
    [ "$status" -eq 0 ]
}

@test "Systemd hardening drop-in uses the full unit name" {
    TMP_DIR="$(mktemp -d)"
    export EASYNET_SYSTEMD_UNIT_DIR="$TMP_DIR/systemd"
    mkdir -p "$EASYNET_SYSTEMD_UNIT_DIR"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/core/maintenance.sh"

    maintenance_apply_systemd_hardening xray
    [ -f "$EASYNET_SYSTEMD_UNIT_DIR/xray.service.d/easynet-hardening.conf" ]
    [ ! -d "$EASYNET_SYSTEMD_UNIT_DIR/xray.d" ]
    grep -q '^ProtectSystem=strict$' "$EASYNET_SYSTEMD_UNIT_DIR/xray.service.d/easynet-hardening.conf"
    # Upstream units may lack Restart=; the drop-in supplies the recovery contract
    grep -q '^Restart=on-failure$' "$EASYNET_SYSTEMD_UNIT_DIR/xray.service.d/easynet-hardening.conf"
    grep -q '^RestartSec=5$' "$EASYNET_SYSTEMD_UNIT_DIR/xray.service.d/easynet-hardening.conf"

    maintenance_apply_systemd_hardening hysteria-server.service "ReadWritePaths=/var/lib/hysteria"
    dropin="$EASYNET_SYSTEMD_UNIT_DIR/hysteria-server.service.d/easynet-hardening.conf"
    [ -f "$dropin" ]
    grep -q '^ReadWritePaths=/var/lib/hysteria$' "$dropin"

    rm -rf "$TMP_DIR"
}

@test "Shadowsocks service keeps its key out of the command line" {
    run rg -q -- '-k \$\{PSK\}|--password' "$PROJECT_ROOT/scripts/protocols/shadowsocks/deploy.sh"
    [ "$status" -eq 1 ]
    run rg -q 'ssserver --config' "$PROJECT_ROOT/scripts/protocols/shadowsocks/deploy.sh"
    [ "$status" -eq 0 ]
    # `CapabilityBoundingSet=~` grants every capability; the empty set drops all.
    run rg -q '^CapabilityBoundingSet=~' "$PROJECT_ROOT/scripts/protocols/shadowsocks/deploy.sh"
    [ "$status" -eq 1 ]
    run rg -q '^CapabilityBoundingSet=$' "$PROJECT_ROOT/scripts/protocols/shadowsocks/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "fail2ban is configured with an sshd jail and does not clobber jail.local" {
    run rg -q 'maintenance_configure_fail2ban' "$PROJECT_ROOT/scripts/core/maintenance.sh" "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q '/etc/fail2ban/jail.d/easynet.local' "$PROJECT_ROOT/scripts/core/maintenance.sh"
    [ "$status" -eq 0 ]
}

@test "Deploy env loader does not use export grep xargs" {
    run rg -q 'export \$\\(grep|xargs\\)' "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Real deployment smoke test script is executable" {
    [ -x "$PROJECT_ROOT/scripts/smoke_test.sh" ]
}

@test "Edge certificate renew hook fixes permissions and restarts dependent services" {
    [ -x "$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh" ]
    rg -q "cert_renew_hook.sh|--reloadcmd.*EDGE_RENEW_HOOK" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    rg -q "hysteria-server.service|fix_edge_cert_permissions|grant_cert_access_to_user" "$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"
}

@test "Long-running log limits are configured for journald and Nginx" {
    rg -q "maintenance_configure_logs|maintenance_configure_nginx_logrotate" "$PROJECT_ROOT/scripts/deploy.sh" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    rg -q "SystemMaxUse|/etc/logrotate.d/easynet-nginx|/var/log/nginx/\\*.log" "$PROJECT_ROOT/scripts/core/maintenance.sh"
}

@test "SSH hardening dry-run renders a drop-in that sorts before cloud-init" {
    run bash "$PROJECT_ROOT/scripts/security/harden_ssh.sh" apply --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | rg -q '^PermitRootLogin prohibit-password$'
    echo "$output" | rg -q '^PasswordAuthentication no$'
    echo "$output" | rg -q '^MaxAuthTries 3$'
    # `10-` must sort before `50-cloud-init.conf`: sshd uses the FIRST value it sees.
    rg -q '10-easynet-hardening' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
    rg -q '50-cloud-init' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
}

@test "SSH hardening refuses to apply when no authorized key exists" {
    rg -q '拒绝加固' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
    rg -q 'count_authorized_keys' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
}

@test "SSH hardening arms an automatic rollback and provides confirm/revert" {
    rg -q 'on-active' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
    rg -q 'cmd_confirm' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
    rg -q 'cmd_revert' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
    rg -q 'sshd -t' "$PROJECT_ROOT/scripts/security/harden_ssh.sh"
}

@test "SSH hardening is opt-in and never called by the deploy pipeline" {
    # deploy.sh must never reference it at all
    run rg -l 'harden_ssh' "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
    # core modules may only *index* it (hub symlink) — never execute it
    run rg -l 'bash .*/harden_ssh\.sh' "$PROJECT_ROOT/scripts/core"
    [ "$status" -eq 1 ]
    run rg -q 'scripts/security/harden_ssh\.sh' "$PROJECT_ROOT/scripts/core/hub.sh"
    [ "$status" -eq 0 ]
}

@test "Edge state tree is root-only (subscription path is the only secret)" {
    run rg -q 'easynet_secure_state_dir' "$PROJECT_ROOT/scripts/core/env.sh"
    [ "$status" -eq 0 ]
    # Called from the two write paths
    run rg -q 'easynet_secure_state_dir' "$PROJECT_ROOT/scripts/deploy.sh" "$PROJECT_ROOT/scripts/generate_subscription.sh"
    [ "$status" -eq 0 ]
    # Prefix file and generated routes are chmod 600 at write time
    run rg -q 'chmod 600 "\$path_file"' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q 'chmod 600 "\$route_file"' "$PROJECT_ROOT/scripts/core/subscription.sh"
    [ "$status" -eq 0 ]
}

@test "easynet_secure_state_dir actually tightens permissions" {
    TMP_STATE="$(mktemp -d)"
    mkdir -p "$TMP_STATE/exposure/edge/routes" "$TMP_STATE/modules"
    echo "/s/abcdef0123456789abcdef0123456789" > "$TMP_STATE/exposure/edge/subscription_path_prefix.txt"
    echo 'location = /x { }' > "$TMP_STATE/exposure/edge/routes/subscription.conf"
    chmod 755 "$TMP_STATE" "$TMP_STATE/exposure" "$TMP_STATE/exposure/edge" "$TMP_STATE/exposure/edge/routes"
    chmod 644 "$TMP_STATE/exposure/edge/subscription_path_prefix.txt" "$TMP_STATE/exposure/edge/routes/subscription.conf"

    EASYNET_STATE_DIR="$TMP_STATE" bash -c ". '$PROJECT_ROOT/scripts/core/env.sh'; easynet_secure_state_dir"

    # stat(1) differs between GNU and BSD, so read modes portably
    mode_of() {
        if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
    }
    local bad="" pair path want got
    for pair in         "$TMP_STATE:700"         "$TMP_STATE/exposure:700"         "$TMP_STATE/exposure/edge:700"         "$TMP_STATE/exposure/edge/routes:700"         "$TMP_STATE/exposure/edge/subscription_path_prefix.txt:600"         "$TMP_STATE/exposure/edge/routes/subscription.conf:600"; do
        path="${pair%:*}"; want="${pair##*:}"
        got="$(mode_of "$path")"
        [ "$got" = "$want" ] || bad="${bad}${path##*/}=${got}(want ${want}) "
    done
    [ -z "$bad" ] || echo "# 权限未收紧: $bad" >&3
    [ -z "$bad" ]
    rm -rf "$TMP_STATE"
}

@test "Masquerade route does not emit duplicate security headers" {
    # Proxied upstream headers must be hidden, otherwise HSTS appears twice with
    # conflicting max-age (invalid per RFC 6797 and a fingerprint).
    run rg -c 'proxy_hide_header Strict-Transport-Security' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$output" = "3" ]
    run rg -q 'proxy_hide_header X-Frame-Options' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q 'proxy_hide_header X-Content-Type-Options' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "Edge server hides the nginx version" {
    run rg -q 'server_tokens off;' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
}
