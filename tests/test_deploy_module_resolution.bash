#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/deploy.sh"

test_start "Deploy Module Resolution"

assert_equals "xray-reality" "$(resolve_modules 1)" "Menu 1 resolves to Xray Reality module"
assert_equals "hysteria2" "$(resolve_modules 2)" "Menu 2 resolves to Hysteria2 module"
assert_equals "trojan-go" "$(resolve_modules 3)" "Menu 3 resolves to Trojan-Go module"
assert_equals "v2ray" "$(resolve_modules 4)" "Menu 4 resolves to V2Ray module"
assert_equals "shadowsocks" "$(resolve_modules 5)" "Menu 5 resolves to Shadowsocks module"
assert_equals "wireguard" "$(resolve_modules 6)" "Menu 6 resolves to WireGuard module"
assert_equals "xray-reality" "$(resolve_modules xray-reality)" "Module name resolves directly"
assert_equals "xray-reality" "$(resolve_modules profile:strict)" "Strict profile resolves to Xray Reality"
assert_equals "xray-reality hysteria2" "$(resolve_modules profile:balanced | xargs)" "Balanced profile resolves to Reality and Hysteria2"
assert_equals "__exit__" "$(resolve_modules 7)" "Menu 7 resolves to exit sentinel"

unset EASYNET_DOMAIN
unset EASYNET_SUBSCRIPTION_DOMAIN
if subscription_carrier_enabled; then
    carrier_without_domain="true"
else
    carrier_without_domain="false"
fi
assert_equals "false" "$carrier_without_domain" "Subscription carrier is disabled when no domain is configured"

EASYNET_DOMAIN="proxy.example.com"
if subscription_carrier_enabled; then
    carrier_with_domain="true"
else
    carrier_with_domain="false"
fi
assert_equals "true" "$carrier_with_domain" "Subscription carrier auto-enables when EASYNET_DOMAIN is configured"
EASYNET_EDGE_ENABLED="false"
if subscription_carrier_enabled; then
    carrier_with_edge_disabled="true"
else
    carrier_with_edge_disabled="false"
fi
assert_equals "false" "$carrier_with_edge_disabled" "Subscription carrier can be explicitly disabled for direct TCP 443 protocols"
unset EASYNET_EDGE_ENABLED
unset EASYNET_DOMAIN

EASYNET_SUBSCRIPTION_DOMAIN="sub.example.com"
if subscription_carrier_enabled; then
    carrier_with_subscription_domain="true"
else
    carrier_with_subscription_domain="false"
fi
assert_equals "true" "$carrier_with_subscription_domain" "Subscription carrier auto-enables when EASYNET_SUBSCRIPTION_DOMAIN is configured"
unset EASYNET_SUBSCRIPTION_DOMAIN

all_modules="$(resolve_modules 0 | xargs)"
assert_equals "xray-reality hysteria2 trojan-go v2ray shadowsocks wireguard" "$all_modules" "Menu 0 resolves to all modules in security order"

compat_modules="$(resolve_modules profile:compat | xargs)"
assert_equals "xray-reality hysteria2 trojan-go v2ray shadowsocks wireguard" "$compat_modules" "Compat profile resolves to all modules in security order"

assert_equals "$PROJECT_ROOT/scripts/protocols/trojan-go/deploy.sh" "$(module_entrypoint trojan-go)" "Trojan-Go deploys through protocol module"
assert_equals "$PROJECT_ROOT/scripts/protocols/v2ray/deploy.sh" "$(module_entrypoint v2ray)" "V2Ray deploys through protocol module"

carrier_code="$(sed -n '/subscription_carrier_enabled()/,/^}/p; /deploy_subscription_exposure()/,/^}/p' "$PROJECT_ROOT/scripts/deploy.sh")"
if printf '%s\n' "$carrier_code" | rg -q "trojan-go"; then
    subscription_carrier_adds_trojan="true"
else
    subscription_carrier_adds_trojan="false"
fi
assert_equals "false" "$subscription_carrier_adds_trojan" "Subscription carrier is decoupled from Trojan-Go protocol selection"

if rg -q "exposure/subscription/deploy.sh" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_uses_legacy_subscription_exposure="true"
else
    deploy_uses_legacy_subscription_exposure="false"
fi
assert_equals "false" "$deploy_uses_legacy_subscription_exposure" "Deploy does not invoke legacy subscription exposure"

if rg -q "exposure/edge/deploy.sh" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_has_edge_exposure="true"
else
    deploy_has_edge_exposure="false"
fi
assert_equals "true" "$deploy_has_edge_exposure" "Deploy can invoke Edge Gateway"

if rg -q "scripts/server|/server/" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_references_legacy_server="true"
else
    deploy_references_legacy_server="false"
fi
assert_equals "false" "$deploy_references_legacy_server" "Deploy entrypoint does not reference legacy server wrappers"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export EASYNET_STATE_DIR="$TMP_DIR/state"
mkdir -p "$EASYNET_STATE_DIR/exposure/nginx"
echo "/v2route" > "$EASYNET_STATE_DIR/exposure/nginx/v2ray_path.txt"
echo "proxy.example.com" > "$EASYNET_STATE_DIR/exposure/nginx/domain.txt"

DEPLOY_SELECTION_MODULES=(v2ray)
unset EASYNET_V2RAY_MODE
unset EASYNET_V2RAY_WS_PATH
unset EASYNET_DOMAIN
unset EASYNET_SUBSCRIPTION_DOMAIN
export_route_env_for_module v2ray
assert_equals "" "${EASYNET_V2RAY_MODE:-}" "Standalone V2Ray does not inherit exposure backend state"

DEPLOY_SELECTION_MODULES=(v2ray)
EASYNET_DOMAIN="proxy.example.com"
export_route_env_for_module v2ray
assert_equals "backend" "$EASYNET_V2RAY_MODE" "V2Ray uses Edge backend when subscription domain is configured"
assert_equals "127.0.0.1" "$EASYNET_V2RAY_LISTEN" "V2Ray Edge backend listens on loopback"
assert_equals "443" "$EASYNET_V2RAY_PUBLIC_PORT" "V2Ray Edge backend keeps public port 443"
assert_not_empty "$EASYNET_V2RAY_WS_PATH" "V2Ray Edge backend receives route path"
if rg -q "deny all" "$EASYNET_STATE_DIR/exposure/edge/routes/v2ray.conf"; then
    edge_v2ray_route_blocks_public_clients="true"
else
    edge_v2ray_route_blocks_public_clients="false"
fi
assert_equals "false" "$edge_v2ray_route_blocks_public_clients" "V2Ray Edge route accepts public clients and proxies to loopback backend"
unset EASYNET_DOMAIN

EASYNET_DOMAIN="proxy.example.com"
if validate_edge_compatibility xray-reality hysteria2 >/dev/null 2>&1; then
    edge_safe_modules_ok="true"
else
    edge_safe_modules_ok="false"
fi
assert_equals "true" "$edge_safe_modules_ok" "Edge Gateway allows modules that do not directly bind TCP 443"

if validate_edge_compatibility trojan-go >/dev/null 2>&1; then
    edge_trojan_backend_ok="true"
else
    edge_trojan_backend_ok="false"
fi
assert_equals "true" "$edge_trojan_backend_ok" "Edge Gateway allows Trojan-Go after backend routing"

DEPLOY_SELECTION_MODULES=(trojan-go)
export_route_env_for_module trojan-go
assert_equals "backend" "$EASYNET_TROJAN_MODE" "Trojan-Go uses Edge backend when subscription domain is configured"
assert_equals "127.0.0.1" "$EASYNET_TROJAN_LISTEN" "Trojan-Go Edge backend listens on loopback"
assert_equals "4444" "$EASYNET_TROJAN_PORT" "Trojan-Go Edge backend uses private backend port"
assert_equals "443" "$EASYNET_TROJAN_PUBLIC_PORT" "Trojan-Go Edge backend keeps public port 443"
assert_not_empty "$EASYNET_TROJAN_WS_PATH" "Trojan-Go Edge backend receives route path"
if rg -q "proxy_pass https://127.0.0.1:4444" "$EASYNET_STATE_DIR/exposure/edge/routes/trojan-go.conf"; then
    edge_trojan_route_proxies_tls_backend="true"
else
    edge_trojan_route_proxies_tls_backend="false"
fi
assert_equals "true" "$edge_trojan_route_proxies_tls_backend" "Trojan-Go Edge route proxies to TLS loopback backend"
unset EASYNET_DOMAIN
unset EASYNET_TROJAN_MODE
unset EASYNET_TROJAN_LISTEN
unset EASYNET_TROJAN_PORT
unset EASYNET_TROJAN_PUBLIC_PORT
unset EASYNET_TROJAN_WS_PATH

DEPLOY_SELECTION_MODULES=(trojan-go v2ray)
unset EASYNET_V2RAY_MODE
unset EASYNET_V2RAY_WS_PATH
unset EASYNET_DOMAIN
export_route_env_for_module v2ray
assert_equals "backend" "$EASYNET_V2RAY_MODE" "Combined Trojan-Go and V2Ray deployment uses exposure backend"
assert_equals "/v2route" "$EASYNET_V2RAY_WS_PATH" "Combined deployment passes V2Ray exposure path"

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
