#!/usr/bin/env bats
# Deployment error handling tests
#
# Verify that deploy.sh functions handle errors gracefully when
# modules are misconfigured, unknown, or incomplete.

load test_helper

setup() {
    export TMP_DIR=$(mktemp -d)
    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    source "$PROJECT_ROOT/scripts/core/logging.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ============================================================
# Module resolution error handling
# ============================================================

@test "module_is_known returns false for unknown module" {
    source "$PROJECT_ROOT/scripts/core/discovery.sh"

    run discovery_module_exists "definitely-not-a-real-module-12345"
    [ "$status" -eq 1 ]
}

@test "discovery_load_manifest returns 1 for unknown module" {
    source "$PROJECT_ROOT/scripts/core/discovery.sh"

    run discovery_load_manifest "definitely-not-a-real-module-12345"
    [ "$status" -eq 1 ]
}

@test "discovery_list_modules discovers all 4 protocol modules" {
    source "$PROJECT_ROOT/scripts/core/discovery.sh"

    run discovery_list_modules
    local count
    count=$(echo "$output" | grep -c '^')
    [ "$count" -eq 4 ] || {
        echo "# discovery_list_modules found $count modules:" >&3
        echo "$output" >&3
        return 1
    }
}

@test "resolve_modules returns 1 for invalid menu choice" {
    source "$PROJECT_ROOT/scripts/core/discovery.sh"
    source "$PROJECT_ROOT/scripts/deploy.sh"

    run resolve_modules "9999"
    [ "$status" -eq 1 ]
}

# ============================================================
# Validation error handling
# ============================================================

@test "validate_port_conflicts detects port conflict" {
    source "$PROJECT_ROOT/scripts/core/discovery.sh"
    source "$PROJECT_ROOT/scripts/core/validate.sh"

    # Hysteria2 and another shared_tls module both default to 443
    run validate_port_conflicts "hysteria2" "hysteria2"
    [ "$status" -ne 0 ]
}

@test "validate_required_tools returns 1 when jq is missing" {
    local real_path="$PATH"
    source "$PROJECT_ROOT/scripts/core/discovery.sh"
    source "$PROJECT_ROOT/scripts/core/validate.sh"

    # Temporarily remove jq from PATH
    PATH="/nonexistent" run validate_required_tools
    PATH="$real_path"
    [ "$status" -ne 0 ]
}

# ============================================================
# Deploy error trap
# ============================================================

@test "deploy.sh has _easynet_error_handler trap for set -eE" {
    local deploy="$PROJECT_ROOT/scripts/deploy.sh"

    # The error handler must be registered with trap ... ERR
    grep -q "trap.*_easynet_error_handler.*ERR" "$deploy"
    grep -q "set -eE" "$deploy"
}

@test "deploy.sh error handler logs exit code and location" {
    local deploy="$PROJECT_ROOT/scripts/deploy.sh"

    grep -q 'log_error.*退出码.*BASH_SOURCE.*BASH_LINENO' "$deploy"
}
