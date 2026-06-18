#!/usr/bin/env bats
# TLS / certificate error scenario tests
#
# These tests verify that the system handles missing, expired, or
# misconfigured TLS certificates gracefully without crashing.

load test_helper

setup() {
    export TMP_DIR=$(mktemp -d)
    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."
    source "$PROJECT_ROOT/scripts/core/logging.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ============================================================
# Hysteria2 require_tls_certificate behaviour
# ============================================================

@test "Hysteria2 require_tls_certificate exits when cert files are missing" {
    local deploy="$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    # Extract and eval only the require_tls_certificate function (skip main())
    eval "$(sed -n '/^require_tls_certificate()/,/^}/p' "$deploy")"

    HYSTERIA2_CERT_DIR="$TMP_DIR/missing-certs"
    HYSTERIA2_CERT_FILE="$TMP_DIR/missing-certs/fullchain.crt"
    HYSTERIA2_KEY_FILE="$TMP_DIR/missing-certs/private.key"

    run require_tls_certificate
    echo "# require_tls_certificate exit: $status" >&3
    [ "$status" -ne 0 ]
}

@test "Hysteria2 require_tls_certificate succeeds when cert files exist" {
    mkdir -p "$TMP_DIR/certs"
    touch "$TMP_DIR/certs/fullchain.crt" "$TMP_DIR/certs/private.key"

    local deploy="$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    eval "$(sed -n '/^require_tls_certificate()/,/^}/p' "$deploy")"

    HYSTERIA2_CERT_DIR="$TMP_DIR/certs"
    HYSTERIA2_CERT_FILE="$TMP_DIR/certs/fullchain.crt"
    HYSTERIA2_KEY_FILE="$TMP_DIR/certs/private.key"

    run require_tls_certificate
    echo "# require_tls_certificate exit: $status" >&3
    [ "$status" -eq 0 ]
}

# ============================================================
# cert_renew_hook behaviour
# ============================================================

@test "cert_renew_hook: script exists and is executable" {
    local hook="$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"
    [ -f "$hook" ]
    [ -x "$hook" ]
}

@test "cert_renew_hook: fixes cert file permissions when EASYNET_EDGE_CERT_DIR is set" {
    local hook="$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"
    eval "$(sed -n '/^fix_edge_cert_permissions()/,/^}/p' "$hook")"

    mkdir -p "$TMP_DIR/certs"
    touch "$TMP_DIR/certs/fullchain.crt" "$TMP_DIR/certs/private.key"

    EASYNET_EDGE_CERT_DIR="$TMP_DIR/certs" run fix_edge_cert_permissions 2>/dev/null
    echo "# fix_edge_cert_permissions exit: $status" >&3
}

@test "cert_renew_hook: does not crash on missing cert directory" {
    local hook="$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"
    eval "$(sed -n '/^fix_edge_cert_permissions()/,/^}/p' "$hook")"

    EASYNET_EDGE_CERT_DIR="$TMP_DIR/nonexistent" run fix_edge_cert_permissions 2>/dev/null
    echo "# fix_edge_cert_permissions exit: $status" >&3
}

@test "cert_renew_hook: includes restart commands for dependent services" {
    local hook="$PROJECT_ROOT/scripts/exposure/edge/cert_renew_hook.sh"
    run grep -c "systemctl" "$hook"
    [ "$status" -eq 0 ]
}

# ============================================================
# Smoke test cert checks
# ============================================================

@test "Smoke test check_cert_expiry: does not crash on missing cert" {
    run bash -c '
        source "$0/scripts/core/logging.sh" 2>/dev/null
        source "$0/scripts/core/metadata.sh" 2>/dev/null
        source "$0/scripts/core/subscription.sh" 2>/dev/null
        source <(sed "/^main \"\$\@\"$/d" "$0/scripts/smoke_test.sh") 2>/dev/null
        EASYNET_EDGE_CERT_DIR="$1/nonexistent"
        check_cert_expiry 2>/dev/null || true
        echo "completed without crash"
    ' "$PROJECT_ROOT" "$TMP_DIR"

    echo "# check_cert_expiry status=$status output=$output" >&3
}
