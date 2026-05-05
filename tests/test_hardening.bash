#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Deployment Hardening"

if rg -q 'curl .*\|.*sh|curl .*\|.*bash' "$PROJECT_ROOT/scripts" ||
    rg -F -q 'bash -c "$(curl' "$PROJECT_ROOT/scripts" ||
    rg -F -q 'bash <(curl' "$PROJECT_ROOT/scripts"; then
    direct_remote_shell="true"
else
    direct_remote_shell="false"
fi
assert_equals "false" "$direct_remote_shell" "Installers do not execute curl output directly"

if rg -q "run_downloaded_script|download_file" "$PROJECT_ROOT/scripts/core/download.sh" "$PROJECT_ROOT/scripts/protocols" "$PROJECT_ROOT/scripts/exposure/edge"; then
    download_helper_used="true"
else
    download_helper_used="false"
fi
assert_equals "true" "$download_helper_used" "Installers use shared download helper with optional checksum verification"

if rg -q 'export \$\\(grep|xargs\\)' "$PROJECT_ROOT/scripts/deploy.sh"; then
    unsafe_env_loader="true"
else
    unsafe_env_loader="false"
fi
assert_equals "false" "$unsafe_env_loader" "Deploy env loader does not use export grep xargs"

if [ -x "$PROJECT_ROOT/scripts/smoke_test.sh" ]; then
    smoke_test_executable="true"
else
    smoke_test_executable="false"
fi
assert_equals "true" "$smoke_test_executable" "Real deployment smoke test script is executable"

if [ -x "$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh" ] &&
    rg -q "cert_renew_hook.sh|--reloadcmd.*EDGE_RENEW_HOOK" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh" &&
    rg -q "hysteria-server.service|trojan-go|fix_edge_cert_permissions|grant_cert_access_to_user" "$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"; then
    cert_hook_ready="true"
else
    cert_hook_ready="false"
fi
assert_equals "true" "$cert_hook_ready" "Edge certificate renew hook fixes permissions and restarts dependent services"

if rg -q "maintenance_configure_logs|maintenance_configure_nginx_logrotate" "$PROJECT_ROOT/scripts/deploy.sh" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh" &&
    rg -q "SystemMaxUse|/etc/logrotate.d/easynet-nginx|/var/log/nginx/\\*.log" "$PROJECT_ROOT/scripts/core/maintenance.sh"; then
    log_maintenance_ready="true"
else
    log_maintenance_ready="false"
fi
assert_equals "true" "$log_maintenance_ready" "Long-running log limits are configured for journald and Nginx"

test_end
