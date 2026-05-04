#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Exposure State Isolation"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export EASYNET_STATE_DIR="$TMP_DIR/state"
source "$PROJECT_ROOT/scripts/core/env.sh"

assert_equals "$TMP_DIR/state/exposure/nginx" "$(easynet_nginx_state_dir)" "Nginx exposure state lives under EasyNet state dir"

if rg -q "/etc/trojan-go|/usr/local/etc/v2ray|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/exposure"; then
    exposure_uses_protocol_state="true"
else
    exposure_uses_protocol_state="false"
fi
assert_equals "false" "$exposure_uses_protocol_state" "Exposure layer does not depend on protocol config directories"

if [ -d "$PROJECT_ROOT/scripts/server" ]; then
    legacy_server_dir_present="true"
else
    legacy_server_dir_present="false"
fi
assert_equals "false" "$legacy_server_dir_present" "Legacy server wrapper directory has been removed"

if rg -q "EASYNET_TROJAN_WS_PATH" "$PROJECT_ROOT/scripts/protocols/trojan-go/deploy.sh"; then
    trojan_accepts_external_route="true"
else
    trojan_accepts_external_route="false"
fi
assert_equals "true" "$trojan_accepts_external_route" "Trojan-Go protocol accepts route path from exposure layer"

if rg -q "/etc/trojan-go|/usr/local/etc/v2ray|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/exposure/subscription"; then
    subscription_exposure_uses_protocol_state="true"
else
    subscription_exposure_uses_protocol_state="false"
fi
assert_equals "false" "$subscription_exposure_uses_protocol_state" "Subscription exposure does not depend on protocol config directories"

if rg -q "trojan-go|EASYNET_TROJAN_WS_PATH" "$PROJECT_ROOT/scripts/exposure/subscription/deploy.sh"; then
    subscription_exposure_depends_on_trojan="true"
else
    subscription_exposure_depends_on_trojan="false"
fi
assert_equals "false" "$subscription_exposure_depends_on_trojan" "Subscription exposure is decoupled from Trojan-Go"

if rg -q "ssl_certificate|acme.sh|SUBSCRIPTION_HTTPS_PORT" "$PROJECT_ROOT/scripts/exposure/subscription/deploy.sh"; then
    subscription_exposure_supports_tls="true"
else
    subscription_exposure_supports_tls="false"
fi
assert_equals "true" "$subscription_exposure_supports_tls" "Subscription exposure supports direct TLS"

if rg -q "listen \\$\\{EDGE_HTTPS_PORT\\} ssl|EDGE_HTTPS_PORT=\"\\$\\{EASYNET_EDGE_HTTPS_PORT:-443\\}\"|include \\$\\{EDGE_ROUTES_DIR\\}/\\*.conf" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"; then
    edge_owns_tcp443="true"
else
    edge_owns_tcp443="false"
fi
assert_equals "true" "$edge_owns_tcp443" "Edge Gateway owns TCP 443 and includes independent routes"

if rg -q "/etc/trojan-go|/usr/local/etc/v2ray|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/exposure/edge"; then
    edge_uses_protocol_state="true"
else
    edge_uses_protocol_state="false"
fi
assert_equals "false" "$edge_uses_protocol_state" "Edge Gateway does not depend on protocol config directories"

if rg -q "sub_full|clash_full" "$PROJECT_ROOT/scripts/exposure/subscription/deploy.sh" "$PROJECT_ROOT/scripts/exposure/nginx/deploy.sh"; then
    exposure_serves_full_subscriptions="true"
else
    exposure_serves_full_subscriptions="false"
fi
assert_equals "false" "$exposure_serves_full_subscriptions" "Exposure routes only serve current subscription endpoints"

test_end
