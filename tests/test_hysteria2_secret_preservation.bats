#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export H2="$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    return 0
}

# -- Static analysis --

@test "Hysteria2 deploy has an entrypoint guard so functions can be sourced" {
    run rg -q 'BASH_SOURCE\[0\].*==.*\$0' "$H2"
    [ "$status" -eq 0 ]
}

@test "Hysteria2 deploy defines secret resolution helpers" {
    run rg -q "load_previous_secret" "$H2"
    [ "$status" -eq 0 ]
    run rg -q "resolve_hysteria2_secret" "$H2"
    [ "$status" -eq 0 ]
}

# -- Functional: secret preservation across re-deploys --

@test "resolve_hysteria2_secret prefers an explicit env value" {
    TMP_DIR="$(mktemp -d)"
    printf "HYSTERIA2_PASSWORD='fromfile'\n" > "$TMP_DIR/easynet.env"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/easynet.env'; source \"$H2\"; resolve_hysteria2_secret fromenv HYSTERIA2_PASSWORD"
    [ "$status" -eq 0 ]
    [ "$output" = "fromenv" ]
}

@test "resolve_hysteria2_secret reuses the previously persisted password" {
    TMP_DIR="$(mktemp -d)"
    printf "HYSTERIA2_PASSWORD='persisted-secret'\n" > "$TMP_DIR/easynet.env"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/easynet.env'; source \"$H2\"; resolve_hysteria2_secret '' HYSTERIA2_PASSWORD"
    [ "$status" -eq 0 ]
    [ "$output" = "persisted-secret" ]
}

@test "resolve_hysteria2_secret reuses the previously persisted obfs password" {
    TMP_DIR="$(mktemp -d)"
    printf "HYSTERIA2_OBFS_PASSWORD='persisted-obfs'\n" > "$TMP_DIR/easynet.env"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/easynet.env'; source \"$H2\"; resolve_hysteria2_secret '' HYSTERIA2_OBFS_PASSWORD"
    [ "$status" -eq 0 ]
    [ "$output" = "persisted-obfs" ]
}

@test "resolve_hysteria2_secret generates a fresh non-empty value when nothing is available" {
    TMP_DIR="$(mktemp -d)"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/missing.env'; source \"$H2\"; resolve_hysteria2_secret '' HYSTERIA2_PASSWORD"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "$output" =~ ^[0-9a-f]{32,}$ ]]
}

@test "Explicit env value overrides the persisted value" {
    TMP_DIR="$(mktemp -d)"
    printf "HYSTERIA2_PASSWORD='persisted-secret'\n" > "$TMP_DIR/easynet.env"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/easynet.env'; source \"$H2\"; resolve_hysteria2_secret 'explicit' HYSTERIA2_PASSWORD"
    [ "$status" -eq 0 ]
    [ "$output" = "explicit" ]
}

@test "load_previous_secret returns empty for a missing variable or file" {
    TMP_DIR="$(mktemp -d)"
    printf "HYSTERIA2_PASSWORD='x'\n" > "$TMP_DIR/easynet.env"
    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/easynet.env'; source \"$H2\"; load_previous_secret NO_SUCH_VAR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run bash -c "export HYSTERIA2_ENV_FILE='$TMP_DIR/missing.env'; source \"$H2\"; load_previous_secret HYSTERIA2_PASSWORD"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
