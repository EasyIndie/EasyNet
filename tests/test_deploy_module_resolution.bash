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

if awk '/subscription_carrier_enabled|deploy_subscription_exposure/ { print }' "$PROJECT_ROOT/scripts/deploy.sh" | rg -q "trojan-go"; then
    subscription_carrier_adds_trojan="true"
else
    subscription_carrier_adds_trojan="false"
fi
assert_equals "false" "$subscription_carrier_adds_trojan" "Subscription carrier is decoupled from Trojan-Go protocol selection"

if rg -q "exposure/subscription/deploy.sh" "$PROJECT_ROOT/scripts/deploy.sh"; then
    deploy_has_subscription_exposure="true"
else
    deploy_has_subscription_exposure="false"
fi
assert_equals "true" "$deploy_has_subscription_exposure" "Deploy can invoke independent subscription exposure"

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
export_route_env_for_module v2ray
assert_equals "" "${EASYNET_V2RAY_MODE:-}" "Standalone V2Ray does not inherit exposure backend state"

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
