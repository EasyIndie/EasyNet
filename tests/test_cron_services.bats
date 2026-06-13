#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    TMP_DIR=$(mktemp -d)
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    source "$PROJECT_ROOT/scripts/core/cron.sh"

    mkdir -p "$EASYNET_STATE_DIR/modules/example-a" "$EASYNET_STATE_DIR/modules/example-b"
    cat > "$EASYNET_STATE_DIR/modules/example-a/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example-a","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{}},"systemd":{"services":["xray","xray"]}}
JSON
    cat > "$EASYNET_STATE_DIR/modules/example-b/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example-b","enabled":true,"protocol":"wireguard","port":51820,"client":{"uri":"wg://example","clash":{}},"systemd":{"services":["wg-quick@wg0"]}}
JSON
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "Cron service list includes xray" {
    run cron_restart_services
    echo "$output" | grep -qx "xray"
}

@test "Cron service list includes wg-quick@wg0" {
    run cron_restart_services
    echo "$output" | grep -qx "wg-quick@wg0"
}

@test "Cron service list de-duplicates repeated services" {
    run cron_restart_services
    [ "$(echo "$output" | grep -xc "xray")" = "1" ]
}

@test "Cron restart command is generated from metadata" {
    run cron_restart_command
    [ "$output" = "/usr/bin/systemctl restart xray wg-quick@wg0 2>/dev/null" ]
}

@test "Cron restart command excludes undeclared services" {
    run cron_restart_command
    echo "$output" | grep -qv "trojan-go"
}
