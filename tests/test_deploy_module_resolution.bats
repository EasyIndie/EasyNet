#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    source "$PROJECT_ROOT/scripts/deploy.sh"
}

@test "Menu 1 resolves to Hysteria2 module (alphabetically first)" {
    run resolve_modules 1
    [ "$output" = "hysteria2" ]
}

@test "Menu 2 resolves to Shadowsocks module" {
    run resolve_modules 2
    [ "$output" = "shadowsocks" ]
}

@test "Menu 3 resolves to WireGuard module" {
    run resolve_modules 3
    [ "$output" = "wireguard" ]
}

@test "Menu 4 resolves to Xray-Reality module (alphabetically last)" {
    run resolve_modules 4
    [ "$output" = "xray-reality" ]
}

@test "Module name resolves directly" {
    run resolve_modules xray-reality
    [ "$output" = "xray-reality" ]
}

@test "Strict profile resolves to Xray Reality" {
    run resolve_modules profile:strict
    [ "$output" = "xray-reality" ]
}

@test "Balanced profile resolves to Reality and Hysteria2" {
    run resolve_modules profile:balanced
    [ "$(echo "$output" | xargs)" = "xray-reality hysteria2" ]
}

@test "Menu 5 resolves to exit sentinel" {
    run resolve_modules 5
    [ "$output" = "__exit__" ]
}

@test "Edge Gateway is disabled when no domain and no backend module is selected" {
    unset EASYNET_DOMAIN EASYNET_SUBSCRIPTION_DOMAIN
    DEPLOY_SELECTION_MODULES=()
    run edge_gateway_enabled
    [ "$status" -eq 1 ]
}

@test "Edge Gateway auto-enables when EASYNET_DOMAIN is configured" {
    export EASYNET_DOMAIN="proxy.example.com"
    DEPLOY_SELECTION_MODULES=("xray-reality")
    run edge_gateway_enabled
    [ "$status" -eq 0 ]
}

@test "Edge Gateway auto-enables when EASYNET_SUBSCRIPTION_DOMAIN is configured" {
    export EASYNET_SUBSCRIPTION_DOMAIN="sub.example.com"
    DEPLOY_SELECTION_MODULES=("xray-reality")
    run edge_gateway_enabled
    [ "$status" -eq 0 ]
}

@test "Menu 0 resolves to all modules (alphabetical order)" {
    run resolve_modules 0
    [ "$(echo "$output" | xargs)" = "hysteria2 shadowsocks wireguard xray-reality" ]
}

@test "Compat profile resolves to all modules (alphabetical order)" {
    run resolve_modules profile:compat
    [ "$(echo "$output" | xargs)" = "hysteria2 shadowsocks wireguard xray-reality" ]
}

@test "Deploy entrypoint has no old exposure compatibility logic" {
    run rg -q "exposure/(nginx|subscription)|nginx-exposure|subscription-exposure|EASYNET_EDGE_ENABLED|EASYNET_V2RAY_MODE|EASYNET_TROJAN_MODE|validate_edge_compatibility|subscription_carrier_enabled" "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Deploy entrypoint delegates Edge route rendering" {
    run rg -q "cat > .*trojan-go.conf|cat > .*v2ray.conf|proxy_pass https://127.0.0.1|proxy_pass http://127.0.0.1" "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Deploy invokes Edge Gateway" {
    run rg -q "exposure/edge/deploy.sh" "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "Edge exposure layer owns backend route rendering" {
    run rg -q "ensure_edge_backend_route" "$PROJECT_ROOT/scripts/exposure/edge/routes.sh"
    [ "$status" -eq 0 ]
}

@test "Deploy entrypoint does not reference legacy server wrappers" {
    run rg -q "scripts/server|/server/" "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Non-backend module does not receive Edge route env vars" {
    TMP_DIR=$(mktemp -d)
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    mkdir -p "$TMP_DIR/state"
    DEPLOY_SELECTION_MODULES=(xray-reality)
    export EASYNET_DOMAIN="proxy.example.com"
    export_route_env_for_module xray-reality
    [ -z "${EASYNET_XRAY_REALITY_LISTEN:-}" ]
    rm -rf "$TMP_DIR"
}

@test "Unknown module fails resolution" {
    run resolve_modules unknown-module
    [ "$status" -eq 1 ]
}

@test "Unknown profile fails resolution" {
    run resolve_modules profile:unknown
    [ "$status" -eq 1 ]
}

@test "Core metadata source does not clobber caller SCRIPT_DIR" {
    SCRIPT_DIR="protocol-dir-sentinel"
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    [ "$SCRIPT_DIR" = "protocol-dir-sentinel" ]
}
