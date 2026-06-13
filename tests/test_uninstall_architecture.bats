#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
}

@test "Uninstall menu 1 resolves to Edge Gateway (alphabetically first)" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 1
    [ "$output" = "edge" ]
}

@test "Uninstall menu 2 resolves to Hysteria2" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 2
    [ "$output" = "hysteria2" ]
}

@test "Uninstall menu 3 resolves to Shadowsocks" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 3
    [ "$output" = "shadowsocks" ]
}

@test "Uninstall menu 4 resolves to WireGuard" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 4
    [ "$output" = "wireguard" ]
}

@test "Uninstall menu 5 resolves to Xray+Reality (alphabetically last)" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 5
    [ "$output" = "xray-reality" ]
}

@test "Uninstall menu 6 resolves to exit sentinel" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 6
    [ "$output" = "__exit__" ]
}

@test "Uninstall menu 0 removes all modules (alphabetical order, includes Edge Gateway)" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules 0
    [ "$(echo "$output" | xargs)" = "edge hysteria2 shadowsocks wireguard xray-reality" ]
}

@test "Xray Reality has isolated uninstall entrypoint" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    result="$(uninstall_entrypoint xray-reality)"
    [[ "$result" == */protocols/xray-reality/uninstall.sh ]]
}

@test "Hysteria2 has isolated uninstall entrypoint" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    result="$(uninstall_entrypoint hysteria2)"
    [[ "$result" == */protocols/hysteria2/uninstall.sh ]]
}

@test "Shadowsocks has isolated uninstall entrypoint" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    result="$(uninstall_entrypoint shadowsocks)"
    [[ "$result" == */protocols/shadowsocks/uninstall.sh ]]
}

@test "WireGuard has isolated uninstall entrypoint" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    result="$(uninstall_entrypoint wireguard)"
    [[ "$result" == */protocols/wireguard/uninstall.sh ]]
}

@test "Edge Gateway has isolated uninstall entrypoint" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    result="$(uninstall_entrypoint edge)"
    [[ "$result" == */exposure/edge/uninstall.sh ]]
}

@test "Unknown uninstall module fails resolution" {
    source "$PROJECT_ROOT/scripts/uninstall.sh"
    run resolve_uninstall_modules unknown-module
    [ "$status" -eq 1 ]
}

@test "Unique module firewall rule is removable" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    export EASYNET_STATE_DIR="$STATE_DIR"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
JSON
    run firewall_metadata_rules
    echo "$output" | grep -q "8443/tcp"
    rm -rf "$TMP_DIR"
}

@test "Base firewall rule is preserved during module uninstall" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    export EASYNET_STATE_DIR="$STATE_DIR"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
JSON
    run firewall_all_rules
    echo "$output" | grep -q "22/tcp"
    rm -rf "$TMP_DIR"
}

@test "Firewall rule shared by another module is preserved" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    export EASYNET_STATE_DIR="$STATE_DIR"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"
    mkdir -p "$STATE_DIR/modules/example" "$STATE_DIR/modules/example-b"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
JSON
    cat > "$STATE_DIR/modules/example-b/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"example-b","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"ExampleB","type":"vless"}},"firewall":[{"port":8443,"proto":"tcp"}]}
JSON
    run firewall_all_rules
    [ "$(echo "$output" | grep -c "8443/tcp")" = "1" ]
    rm -rf "$TMP_DIR"
}

@test "Uninstall flow does not reference legacy server wrappers" {
    run rg -q "scripts/server|/server/|nginx-exposure|subscription-exposure" "$PROJECT_ROOT/scripts/uninstall.sh"
    [ "$status" -eq 1 ]
}

@test "Uninstall flow does not reference old exposure implementations" {
    run rg -q "sub_full|clash_full|easynet_nginx_state_dir|easynet_subscription_state_dir" "$PROJECT_ROOT/scripts/uninstall.sh"
    [ "$status" -eq 1 ]
}
