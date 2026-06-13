#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    source "$PROJECT_ROOT/scripts/deploy.sh"
}

@test "Without EASYNET_SERVICE_CHOICE, it should fall back to interactive prompt" {
    unset EASYNET_SERVICE_CHOICE EASYNET_MODULE EASYNET_PROFILE
    run select_from_env
    [ "$status" -eq 1 ]
}

@test "With EASYNET_SERVICE_CHOICE=0, it should automatically select all modules" {
    export EASYNET_SERVICE_CHOICE="0"
    unset EASYNET_MODULE EASYNET_PROFILE
    choice=""
    select_from_env >/dev/null
    [ "$choice" = "0" ]
}

@test "With EASYNET_MODULE=xray-reality, it should select Xray Reality" {
    unset EASYNET_SERVICE_CHOICE EASYNET_PROFILE
    export EASYNET_MODULE="xray-reality"
    choice=""
    select_from_env >/dev/null
    [ "$choice" = "xray-reality" ]
}

@test "With EASYNET_MODULE=wireguard, it should select WireGuard" {
    unset EASYNET_SERVICE_CHOICE EASYNET_PROFILE
    export EASYNET_MODULE="wireguard"
    choice=""
    select_from_env >/dev/null
    [ "$choice" = "wireguard" ]
}

@test "With EASYNET_MODULE=hysteria2, it should select Hysteria2" {
    unset EASYNET_SERVICE_CHOICE EASYNET_PROFILE
    export EASYNET_MODULE="hysteria2"
    choice=""
    select_from_env >/dev/null
    [ "$choice" = "hysteria2" ]
}

@test "With EASYNET_PROFILE=strict, it should select strict profile" {
    unset EASYNET_SERVICE_CHOICE EASYNET_MODULE
    export EASYNET_PROFILE="strict"
    choice=""
    select_from_env >/dev/null
    [ "$choice" = "profile:strict" ]
}

@test "Without EASYNET_DOMAIN, edge requirement prompts or passes" {
    unset EASYNET_DOMAIN EASYNET_SUBSCRIPTION_DOMAIN
    DEPLOY_SELECTION_MODULES=()
    run ensure_edge_domain
    # When Edge is not enabled and no domain is set, returns 0 (skipped)
    [ "$status" -eq 0 ]
}

@test "With EASYNET_DOMAIN set, it should automatically use the domain" {
    export EASYNET_DOMAIN="proxy.example.com"
    run ensure_edge_domain
    [ "$status" -eq 0 ]
}

@test "Env parser preserves quoted EASYNET value with spaces" {
    TMP_DIR=$(mktemp -d)
    ENV_FILE="$TMP_DIR/.env"
    cat > "$ENV_FILE" <<'ENV'
EASYNET_DOMAIN="proxy env.example.com"
ENV
    unset EASYNET_DOMAIN
    load_env_file_path "$ENV_FILE"
    [ "$EASYNET_DOMAIN" = "proxy env.example.com" ]
    rm -rf "$TMP_DIR"
}

@test "Env parser loads plain EASYNET value" {
    TMP_DIR=$(mktemp -d)
    ENV_FILE="$TMP_DIR/.env"
    cat > "$ENV_FILE" <<'ENV'
EASYNET_PROFILE=balanced
ENV
    unset EASYNET_PROFILE
    load_env_file_path "$ENV_FILE"
    [ "$EASYNET_PROFILE" = "balanced" ]
    rm -rf "$TMP_DIR"
}

@test "Env parser supports export prefix and single quotes" {
    TMP_DIR=$(mktemp -d)
    ENV_FILE="$TMP_DIR/.env"
    cat > "$ENV_FILE" <<'ENV'
export EASYNET_SUBSCRIPTION_DOMAIN='sub.example.com'
ENV
    unset EASYNET_SUBSCRIPTION_DOMAIN
    load_env_file_path "$ENV_FILE"
    [ "$EASYNET_SUBSCRIPTION_DOMAIN" = "sub.example.com" ]
    rm -rf "$TMP_DIR"
}

@test "Env parser ignores non-EASYNET variables" {
    TMP_DIR=$(mktemp -d)
    ENV_FILE="$TMP_DIR/.env"
    cat > "$ENV_FILE" <<'ENV'
UNSUPPORTED_VAR=hello
ENV
    unset UNSUPPORTED_VAR
    load_env_file_path "$ENV_FILE"
    [ -z "${UNSUPPORTED_VAR:-}" ]
    rm -rf "$TMP_DIR"
}

@test "Env parser does not execute command substitutions" {
    TMP_DIR=$(mktemp -d)
    ENV_FILE="$TMP_DIR/.env"
    cat > "$ENV_FILE" <<'ENV'
UNSAFE_COMMAND=$(touch /tmp/easynet-should-not-exist)
ENV
    load_env_file_path "$ENV_FILE"
    [ ! -e /tmp/easynet-should-not-exist ]
    rm -rf "$TMP_DIR"
}
