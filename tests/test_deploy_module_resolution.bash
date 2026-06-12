#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/deploy.sh"

test_start "Deploy Module Resolution"

assert_equals "hysteria2" "$(resolve_modules 1)" "Menu 1 resolves to Hysteria2 module (alphabetically first)"
assert_equals "shadowsocks" "$(resolve_modules 2)" "Menu 2 resolves to Shadowsocks module"
assert_equals "trojan-go" "$(resolve_modules 3)" "Menu 3 resolves to Trojan-Go module"
assert_equals "v2ray" "$(resolve_modules 4)" "Menu 4 resolves to V2Ray module"
assert_equals "wireguard" "$(resolve_modules 5)" "Menu 5 resolves to WireGuard module"
assert_equals "xray-reality" "$(resolve_modules 6)" "Menu 6 resolves to Xray-Reality module (alphabetically last)"
assert_equals "xray-reality" "$(resolve_modules xray-reality)" "Module name resolves directly"
assert_equals "xray-reality" "$(resolve_modules profile:strict)" "Strict profile resolves to Xray Reality"
assert_equals "xray-reality hysteria2" "$(resolve_modules profile:balanced | xargs)" "Balanced profile resolves to Reality and Hysteria2"
assert_equals "__exit__" "$(resolve_modules 7)" "Menu 7 resolves to exit sentinel"

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

DEPLOY_SELECTION_MODULES=(trojan-go)
if edge_gateway_enabled; then
    edge_with_backend_module="true"
else
    edge_with_backend_module="false"
fi
assert_equals "true" "$edge_with_backend_module" "Edge Gateway is required for Trojan-Go backend deployment"

all_modules="$(resolve_modules 0 | xargs)"
assert_equals "hysteria2 shadowsocks trojan-go v2ray wireguard xray-reality" "$all_modules" "Menu 0 resolves to all modules (alphabetical order)"

compat_modules="$(resolve_modules profile:compat | xargs)"
assert_equals "hysteria2 shadowsocks trojan-go v2ray wireguard xray-reality" "$compat_modules" "Compat profile resolves to all modules (alphabetical order)"

assert_equals "$PROJECT_ROOT/scripts/protocols/trojan-go/deploy.sh" "$(module_entrypoint trojan-go)" "Trojan-Go deploys through protocol module"
assert_equals "$PROJECT_ROOT/scripts/protocols/v2ray/deploy.sh" "$(module_entrypoint v2ray)" "V2Ray deploys through protocol module"

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

if rg -q "ensure_edge_trojan_route|ensure_edge_v2ray_route" "$PROJECT_ROOT/scripts/exposure/edge/routes.sh"; then
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

DEPLOY_SELECTION_MODULES=(v2ray)
EASYNET_DOMAIN="proxy.example.com"
unset EASYNET_V2RAY_WS_PATH
export_route_env_for_module v2ray
assert_equals "127.0.0.1" "$EASYNET_V2RAY_LISTEN" "V2Ray Edge backend listens on loopback"
assert_equals "4443" "$EASYNET_V2RAY_PORT" "V2Ray Edge backend uses private backend port"
assert_equals "443" "$EASYNET_V2RAY_PUBLIC_PORT" "V2Ray Edge backend keeps public port 443"
assert_not_empty "$EASYNET_V2RAY_WS_PATH" "V2Ray Edge backend receives route path"
if [[ "$EASYNET_V2RAY_WS_PATH" =~ ^/[0-9a-f]{32}$ ]]; then
    edge_v2ray_path_entropy_ok="true"
else
    edge_v2ray_path_entropy_ok="false"
fi
assert_equals "true" "$edge_v2ray_path_entropy_ok" "V2Ray Edge route path uses 128-bit random value"
if rg -q "deny all" "$EASYNET_STATE_DIR/exposure/edge/routes/v2ray.conf"; then
    edge_v2ray_route_blocks_public_clients="true"
else
    edge_v2ray_route_blocks_public_clients="false"
fi
assert_equals "false" "$edge_v2ray_route_blocks_public_clients" "V2Ray Edge route accepts public clients and proxies to loopback backend"

DEPLOY_SELECTION_MODULES=(trojan-go)
unset EASYNET_TROJAN_WS_PATH
export_route_env_for_module trojan-go
assert_equals "127.0.0.1" "$EASYNET_TROJAN_LISTEN" "Trojan-Go Edge backend listens on loopback"
assert_equals "4444" "$EASYNET_TROJAN_PORT" "Trojan-Go Edge backend uses private backend port"
assert_equals "443" "$EASYNET_TROJAN_PUBLIC_PORT" "Trojan-Go Edge backend keeps public port 443"
assert_not_empty "$EASYNET_TROJAN_WS_PATH" "Trojan-Go Edge backend receives route path"
if [[ "$EASYNET_TROJAN_WS_PATH" =~ ^/[0-9a-f]{32}$ ]]; then
    edge_trojan_path_entropy_ok="true"
else
    edge_trojan_path_entropy_ok="false"
fi
assert_equals "true" "$edge_trojan_path_entropy_ok" "Trojan-Go Edge route path uses 128-bit random value"
if rg -q "proxy_pass https://127.0.0.1:4444" "$EASYNET_STATE_DIR/exposure/edge/routes/trojan-go.conf"; then
    edge_trojan_route_proxies_tls_backend="true"
else
    edge_trojan_route_proxies_tls_backend="false"
fi
assert_equals "true" "$edge_trojan_route_proxies_tls_backend" "Trojan-Go Edge route proxies to TLS loopback backend"
unset EASYNET_DOMAIN

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
