#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    source "$PROJECT_ROOT/scripts/deploy.sh"
}

@test "Menu 1 resolves to Xray-Reality module (strongest anti-DPI first)" {
    run resolve_modules 1
    [ "$output" = "xray-reality" ]
}

@test "Menu 2 resolves to Hysteria2 module" {
    run resolve_modules 2
    [ "$output" = "hysteria2" ]
}

@test "Menu 3 resolves to Shadowsocks module" {
    run resolve_modules 3
    [ "$output" = "shadowsocks" ]
}

@test "Menu 4 resolves to WireGuard module (weakest anti-DPI last)" {
    run resolve_modules 4
    [ "$output" = "wireguard" ]
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

@test "Menu 0 resolves to all modules (anti-DPI security order)" {
    run resolve_modules 0
    [ "$(echo "$output" | xargs)" = "xray-reality hysteria2 shadowsocks wireguard" ]
}

@test "Compat profile resolves to all modules (anti-DPI security order)" {
    run resolve_modules profile:compat
    [ "$(echo "$output" | xargs)" = "xray-reality hysteria2 shadowsocks wireguard" ]
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

# -- Manifest validation (fail-fast) --

@test "All discovered protocol manifests pass validation" {
    local module
    for module in $(discovery_list_modules); do
        discovery_load_manifest "$module"
        if ! discovery_validate_manifest; then
            echo "manifest validation failed: $module"
            return 1
        fi
    done
}

@test "discovery_validate_manifest rejects a manifest missing a required field" {
    discovery_load_manifest xray-reality
    MODULE_DEFAULT_PORT=""
    run discovery_validate_manifest
    [ "$status" -eq 1 ]
}

@test "discovery_validate_manifest rejects a non-numeric default port" {
    discovery_load_manifest xray-reality
    MODULE_DEFAULT_PORT="not-a-port"
    run discovery_validate_manifest
    [ "$status" -eq 1 ]
}

@test "discovery_validate_manifest rejects an out-of-range default port" {
    discovery_load_manifest xray-reality
    MODULE_DEFAULT_PORT="70000"
    run discovery_validate_manifest
    [ "$status" -eq 1 ]
}

@test "validate_module_manifest accepts a well-formed module" {
    run validate_module_manifest xray-reality
    [ "$status" -eq 0 ]
}

@test "validate_module_manifest rejects an unknown module" {
    run validate_module_manifest no-such-module
    [ "$status" -eq 1 ]
}

@test "firewall_normalize_rule converts metadata hyphen ranges to UFW colon form" {
    source "$PROJECT_ROOT/scripts/core/firewall.sh"
    [ "$(firewall_normalize_rule '20000-30000/udp')" = "20000:30000/udp" ]
}

@test "firewall_normalize_rule leaves plain ports untouched" {
    source "$PROJECT_ROOT/scripts/core/firewall.sh"
    [ "$(firewall_normalize_rule '443/udp')" = "443/udp" ]
    [ "$(firewall_normalize_rule '8388/tcp')" = "8388/tcp" ]
}

@test "uninstall normalises port ranges before calling ufw delete" {
    # Regression: uninstall used to pass "20000-30000/udp" straight to
    # `ufw delete`, which fails with "Bad port" and silently leaves the
    # Hysteria2 port-hopping range open after the service is gone.
    run grep -q 'rule="$(firewall_normalize_rule "$rule")"' "$PROJECT_ROOT/scripts/core/uninstall.sh"
    [ "$status" -eq 0 ]
}

@test "every module uninstall removes the hardening drop-in it created" {
    for f in "$PROJECT_ROOT"/scripts/protocols/*/uninstall.sh; do
        run grep -q 'uninstall_remove_hardening_dropin' "$f"
        [ "$status" -eq 0 ]
    done
}

@test "uninstall prunes empty state directories but keeps the state root" {
    source "$PROJECT_ROOT/scripts/core/uninstall.sh"
    local state="$BATS_TEST_TMPDIR/state"
    mkdir -p "$state/modules/xray-reality" "$state/edge" "$state/keepme"
    printf 'x\n' > "$state/keepme/country_code"

    EASYNET_STATE_DIR="$state" uninstall_prune_empty_state_dirs

    [ -d "$state" ]            # root survives
    [ -d "$state/keepme" ]     # non-empty dir survives
    [ ! -d "$state/modules/xray-reality" ]
    [ ! -d "$state/edge" ]
    [ ! -d "$state/modules" ]
}

@test "uninstall flow prunes empty state dirs at the end (covers modules like edge)" {
    # The Edge Gateway uninstall does not call uninstall_refresh_runtime_state, so
    # the final flow must prune: /var/lib/easynet/exposure stayed behind otherwise.
    run grep -q 'uninstall_prune_empty_state_dirs' "$PROJECT_ROOT/scripts/uninstall.sh"
    [ "$status" -eq 0 ]
}

@test "uninstall orchestrator sources the core helpers it calls" {
    # Regression: refresh_after_uninstall() called uninstall_prune_empty_state_dirs
    # without sourcing core/uninstall.sh. Under `set -e` that exits 127 and aborts
    # the whole teardown (cron not refreshed, ~/.easynet index left stale).
    run grep -q 'source "$PROJECT_ROOT/scripts/core/uninstall.sh"' "$PROJECT_ROOT/scripts/uninstall.sh"
    [ "$status" -eq 0 ]
}

@test "every uninstall_* helper called by the orchestrator is actually defined" {
    local fn
    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        grep -qE "^${fn}\(\)" "$PROJECT_ROOT/scripts/uninstall.sh" ||
            grep -qE "^${fn}\(\)" "$PROJECT_ROOT/scripts/core/uninstall.sh" || {
            echo "调用但未定义: $fn" >&2
            return 1
        }
    done < <(grep -oE '\buninstall_[a-z_]+' "$PROJECT_ROOT/scripts/uninstall.sh" | sort -u)
}
