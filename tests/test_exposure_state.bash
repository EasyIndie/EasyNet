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

test_end
