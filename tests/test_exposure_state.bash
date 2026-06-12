#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Exposure State Isolation"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export EASYNET_STATE_DIR="$TMP_DIR/state"
source "$PROJECT_ROOT/scripts/core/env.sh"

assert_equals "$TMP_DIR/state/exposure/edge" "$(easynet_edge_state_dir)" "Edge exposure state lives under EasyNet state dir"

if [ -d "$PROJECT_ROOT/scripts/exposure/nginx" ] || [ -d "$PROJECT_ROOT/scripts/exposure/subscription" ]; then
    old_exposure_dirs_present="true"
else
    old_exposure_dirs_present="false"
fi
assert_equals "false" "$old_exposure_dirs_present" "Old exposure implementations have been removed"

if rg -q "/usr/local/etc/xray" "$PROJECT_ROOT/scripts/exposure"; then
    exposure_uses_protocol_state="true"
else
    exposure_uses_protocol_state="false"
fi
assert_equals "false" "$exposure_uses_protocol_state" "Exposure layer does not depend on protocol config directories"

if [ -d "$PROJECT_ROOT/scripts/server" ] || [ -d "$PROJECT_ROOT/scripts/legacy" ]; then
    legacy_dirs_present="true"
else
    legacy_dirs_present="false"
fi
assert_equals "false" "$legacy_dirs_present" "Legacy wrapper directories have been removed"

if rg -q "listen \\$\\{EDGE_HTTPS_PORT\\} ssl|EDGE_HTTPS_PORT=\"\\$\\{EASYNET_EDGE_HTTPS_PORT:-443\\}\"|include \\$\\{EDGE_ROUTES_DIR\\}/\\*.conf" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"; then
    edge_owns_tcp443="true"
else
    edge_owns_tcp443="false"
fi
assert_equals "true" "$edge_owns_tcp443" "Edge Gateway owns TCP 443 and includes independent routes"

if rg -q 'location = /sub|location = /clash' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"; then
    edge_exposes_fixed_subscription_paths="true"
else
    edge_exposes_fixed_subscription_paths="false"
fi
assert_equals "false" "$edge_exposes_fixed_subscription_paths" "Edge Gateway does not expose fixed subscription paths"

if rg -q 'subscription_path_prefix.txt|openssl rand -hex 16|write_edge_subscription_routes|EDGE_ROUTES_DIR/subscription.conf' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"; then
    edge_uses_stable_random_subscription_path="true"
else
    edge_uses_stable_random_subscription_path="false"
fi
assert_equals "true" "$edge_uses_stable_random_subscription_path" "Edge Gateway uses stable random subscription path prefix"

if rg -q 'subscription_path_prefix.previous.txt|--grace|EASYNET_SUBSCRIPTION_ROTATION_GRACE|generate_subscription.sh|show_subscription.sh' "$PROJECT_ROOT/scripts/rotate_subscription.sh"; then
    rotation_script_supports_migration="true"
else
    rotation_script_supports_migration="false"
fi
assert_equals "true" "$rotation_script_supports_migration" "Subscription rotation supports stable path replacement and grace migration"

if rg -q "sub_full|clash_full|nginx-exposure|subscription-exposure|easynet_nginx_state_dir|easynet_subscription_state_dir" "$PROJECT_ROOT/scripts"; then
    old_exposure_references_present="true"
else
    old_exposure_references_present="false"
fi
assert_equals "false" "$old_exposure_references_present" "Scripts do not reference old exposure implementations"

test_end
