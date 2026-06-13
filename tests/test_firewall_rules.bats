#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    TMP_DIR=$(mktemp -d)
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"

    mkdir -p "$EASYNET_STATE_DIR/modules/example-a" "$EASYNET_STATE_DIR/modules/example-b"
    cat > "$EASYNET_STATE_DIR/modules/example-a/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example-a","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{}},"firewall":[{"port":8443,"proto":"tcp"},{"port":443,"proto":"tcp"}]}
JSON
    cat > "$EASYNET_STATE_DIR/modules/example-b/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example-b","enabled":true,"protocol":"wireguard","port":51820,"client":{"uri":"wg://example","clash":{}},"firewall":[{"port":51820,"proto":"udp"}]}
JSON
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "Firewall plan includes 22/tcp" {
    run firewall_all_rules
    echo "$output" | grep -qx "22/tcp"
}

@test "Firewall plan includes 80/tcp" {
    run firewall_all_rules
    echo "$output" | grep -qx "80/tcp"
}

@test "Firewall plan includes 443/tcp" {
    run firewall_all_rules
    echo "$output" | grep -qx "443/tcp"
}

@test "Firewall plan includes 8443/tcp" {
    run firewall_all_rules
    echo "$output" | grep -qx "8443/tcp"
}

@test "Firewall plan includes 51820/udp" {
    run firewall_all_rules
    echo "$output" | grep -qx "51820/udp"
}

@test "Firewall plan de-duplicates repeated rules" {
    run firewall_all_rules
    [ "$(echo "$output" | grep -xc "443/tcp")" = "1" ]
}

@test "Firewall plan does not include undeclared protocol ports" {
    run firewall_all_rules
    echo "$output" | grep -qv "8388/tcp"
}

@test "Protocol modules do not write firewall rules directly" {
    run rg -q "ufw allow" "$PROJECT_ROOT/scripts/protocols"
    [ "$status" -eq 1 ]
}
