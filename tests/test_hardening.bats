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
