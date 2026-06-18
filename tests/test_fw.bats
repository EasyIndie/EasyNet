#!/usr/bin/env bats
load test_helper
setup() {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    export EASYNET_STATE_DIR="$STATE_DIR"
    source "$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/core/firewall.sh"
    mkdir -p "$STATE_DIR/modules/example" "$STATE_DIR/modules/example-b"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'J'
{"schemaVersion":1,"module":"example","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
J
    cat > "$STATE_DIR/modules/example-b/metadata.json" <<'J'
{"schemaVersion":1,"module":"example-b","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"ExampleB","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
J
}
teardown() { rm -rf "$TMP_DIR"; }

@test "firewall_all_rules dedup" {
    run firewall_all_rules
    echo "# OUTPUT: $output" >&3
    echo "# MATCHES 8443/tcp: $(echo "$output" | grep -c "8443/tcp")" >&3
    [ "$(echo "$output" | grep -c "8443/tcp")" = "1" ]
}
