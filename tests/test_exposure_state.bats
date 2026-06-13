#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export TMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "Edge exposure state lives under EasyNet state dir" {
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    [ "$(easynet_edge_state_dir)" = "$TMP_DIR/state/exposure/edge" ]
}

@test "Old exposure implementations have been removed" {
    [ ! -d "$PROJECT_ROOT/scripts/exposure/nginx" ]
    [ ! -d "$PROJECT_ROOT/scripts/exposure/subscription" ]
}

@test "Exposure layer does not depend on protocol config directories" {
    run rg -q "/usr/local/etc/xray" "$PROJECT_ROOT/scripts/exposure"
    [ "$status" -eq 1 ]
}

@test "Legacy wrapper directories have been removed" {
    [ ! -d "$PROJECT_ROOT/scripts/server" ]
    [ ! -d "$PROJECT_ROOT/scripts/legacy" ]
}

@test "Edge Gateway owns TCP 443 and includes independent routes" {
    run rg -q "listen \\\$\\{EDGE_HTTPS_PORT\\} ssl|EDGE_HTTPS_PORT=\"\\\$\\{EASYNET_EDGE_HTTPS_PORT:-443\\}\"|include \\\$\\{EDGE_ROUTES_DIR\\}/\\*.conf" "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "Edge Gateway does not expose fixed subscription paths" {
    run rg -q 'location = /sub|location = /clash' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Edge Gateway uses stable random subscription path prefix" {
    run rg -q 'subscription_path_prefix.txt|openssl rand -hex 16|write_edge_subscription_routes|EDGE_ROUTES_DIR/subscription.conf' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "Subscription rotation supports stable path replacement and grace migration" {
    run rg -q 'subscription_path_prefix.previous.txt|--grace|EASYNET_SUBSCRIPTION_ROTATION_GRACE|generate_subscription.sh|show_subscription.sh' "$PROJECT_ROOT/scripts/rotate_subscription.sh"
    [ "$status" -eq 0 ]
}

@test "Scripts do not reference old exposure implementations" {
    run rg -q "sub_full|clash_full|nginx-exposure|subscription-exposure|easynet_nginx_state_dir|easynet_subscription_state_dir" "$PROJECT_ROOT/scripts"
    [ "$status" -eq 1 ]
}
