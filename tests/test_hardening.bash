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

test_end
