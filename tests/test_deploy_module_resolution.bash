#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/deploy.sh"

test_start "Deploy Module Resolution"

assert_equals "hysteria2" "$(resolve_modules 1)" "Menu 1 resolves to Hysteria2 module (alphabetically first)"
assert_equals "shadowsocks" "$(resolve_modules 2)" "Menu 2 resolves to Shadowsocks module"
assert_equals "wireguard" "$(resolve_modules 3)" "Menu 3 resolves to WireGuard module"
assert_equals "xray-reality" "$(resolve_modules 4)" "Menu 4 resolves to Xray-Reality module (alphabetically last)"
assert_equals "xray-reality" "$(resolve_modules xray-reality)" "Module name resolves directly"
assert_equals "xray-reality" "$(resolve_modules profile:strict)" "Strict profile resolves to Xray Reality"
assert_equals "xray-reality hysteria2" "$(resolve_modules profile:balanced | xargs)" "Balanced profile resolves to Reality and Hysteria2"
assert_equals "__exit__" "$(resolve_modules 5)" "Menu 5 resolves to exit sentinel"

unset EASYNET_DOMAIN
unset EASYNET_SUBSCRIPTION_DOMAIN
DEPLOY_SELECTION_MODULES=()
if edge_gateway_enabled; then
    edge_without_domain_or_backend="true"
else
    edge_without_domain_or_backend="false"
fi
assert_equals "false" "$edge_without_domain_or_backend" "Edge Gateway is disabled when no domain and no backend module is selected"

EASYNET_DOMAIN="proxy.example.com"
if edge_gateway_enabled; then
    edge_with_domain="true"
else
    edge_with_domain="false"
fi
assert_equals "true" "$edge_with_domain" "Edge Gateway auto-enables when EASYNET_DOMAIN is configured"
unset EASYNET_DOMAIN

EASYNET_SUBSCRIPTION_DOMAIN="sub.example.com"
if edge_gateway_enabled; then
    edge_with_subscription_domain="true"
else
    edge_with_subscription_domain="false"
fi
assert_equals "true" "$edge_with_subscription_domain" "Edge Gateway auto-enables when EASYNET_SUBSCRIPTION_DOMAIN is configured"
unset EASYNET_SUBSCRIPTION_DOMAIN

all_modules="$(resolve_modules 0 | xargs)"
assert_equals "hysteria2 shadowsocks wireguard xray-reality" "$all_modules" "Menu 0 resolves to all modules (alphabetical order)"

compat_modules="$(resolve_modules profile:compat | xargs)"
assert_equals "hysteria2 shadowsocks wireguard xray-reality" "$compat_modules" "Compat profile resolves to all modules (alphabetical order)"

if rg -q "exposure/(nginx|subscription)|nginx-exposure|subscription-exposure|EASYNET_EDGE_ENABLED|EASYNET_V2RAY_MODE|EASYNET_TROJAN_MODE|validate_edge_compatibility|subscription_carrier_enabled" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_has_old_exposure_logic="true"
else
    deploy_has_old_exposure_logic="false"
fi
assert_equals "false" "$deploy_has_old_exposure_logic" "Deploy entrypoint has no old exposure compatibility logic"

if rg -q "cat > .*trojan-go.conf|cat > .*v2ray.conf|proxy_pass https://127.0.0.1|proxy_pass http://127.0.0.1" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_writes_edge_routes="true"
else
    deploy_writes_edge_routes="false"
fi
assert_equals "false" "$deploy_writes_edge_routes" "Deploy entrypoint delegates Edge route rendering"

if rg -q "exposure/edge/deploy.sh" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_has_edge_exposure="true"
else
    deploy_has_edge_exposure="false"
fi
assert_equals "true" "$deploy_has_edge_exposure" "Deploy invokes Edge Gateway"

if rg -q "ensure_edge_backend_route" "$PROJECT_ROOT/scripts/exposure/edge/routes.sh"; then
    edge_routes_own_backend_routes="true"
else
    edge_routes_own_backend_routes="false"
fi
assert_equals "true" "$edge_routes_own_backend_routes" "Edge exposure layer owns backend route rendering"

if rg -q "scripts/server|/server/" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_references_legacy_server="true"
else
    deploy_references_legacy_server="false"
fi
assert_equals "false" "$deploy_references_legacy_server" "Deploy entrypoint does not reference legacy server wrappers"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export EASYNET_STATE_DIR="$TMP_DIR/state"
mkdir -p "$EASYNET_STATE_DIR"

# Edge backend routes are owned by the generic ensure_edge_backend_route function
# No current protocol uses EDGE_MODE=backend, but the capability is preserved
DEPLOY_SELECTION_MODULES=(xray-reality)
EASYNET_DOMAIN="proxy.example.com"
export_route_env_for_module xray-reality
# Xray-Reality uses EDGE_MODE=none, so no route env vars should be set
assert_equals "" "${EASYNET_XRAY_REALITY_LISTEN:-}" "Non-backend module does not receive Edge route env vars"

if resolve_modules unknown-module >/dev/null; then
    invalid_ok="false"
else
    invalid_ok="true"
fi
assert_equals "true" "$invalid_ok" "Unknown module fails resolution"

if resolve_modules profile:unknown >/dev/null; then
    invalid_profile_ok="false"
else
    invalid_profile_ok="true"
fi
assert_equals "true" "$invalid_profile_ok" "Unknown profile fails resolution"

SCRIPT_DIR="protocol-dir-sentinel"
source "$PROJECT_ROOT/scripts/core/metadata.sh"
assert_equals "protocol-dir-sentinel" "$SCRIPT_DIR" "Core metadata source does not clobber caller SCRIPT_DIR"

test_end
