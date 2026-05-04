#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/uninstall.sh"

test_start "Uninstall Architecture"

assert_equals "xray-reality" "$(resolve_uninstall_modules 1)" "Uninstall menu 1 resolves to Xray Reality"
assert_equals "hysteria2" "$(resolve_uninstall_modules 2)" "Uninstall menu 2 resolves to Hysteria2"
assert_equals "trojan-go" "$(resolve_uninstall_modules 3)" "Uninstall menu 3 resolves to Trojan-Go"
assert_equals "v2ray" "$(resolve_uninstall_modules 4)" "Uninstall menu 4 resolves to V2Ray"
assert_equals "shadowsocks" "$(resolve_uninstall_modules 5)" "Uninstall menu 5 resolves to Shadowsocks"
assert_equals "wireguard" "$(resolve_uninstall_modules 6)" "Uninstall menu 6 resolves to WireGuard"
assert_equals "nginx-exposure" "$(resolve_uninstall_modules 7)" "Uninstall menu 7 resolves to Nginx exposure"
assert_equals "__exit__" "$(resolve_uninstall_modules 8)" "Uninstall menu 8 resolves to exit sentinel"

all_uninstall_modules="$(resolve_uninstall_modules 0 | xargs)"
assert_equals "xray-reality hysteria2 trojan-go v2ray shadowsocks wireguard nginx-exposure" "$all_uninstall_modules" "Uninstall menu 0 removes all protocol modules and exposure layer"

assert_equals "$PROJECT_ROOT/scripts/protocols/xray-reality/uninstall.sh" "$(uninstall_entrypoint xray-reality)" "Xray Reality has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/hysteria2/uninstall.sh" "$(uninstall_entrypoint hysteria2)" "Hysteria2 has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/trojan-go/uninstall.sh" "$(uninstall_entrypoint trojan-go)" "Trojan-Go has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/v2ray/uninstall.sh" "$(uninstall_entrypoint v2ray)" "V2Ray has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/shadowsocks/uninstall.sh" "$(uninstall_entrypoint shadowsocks)" "Shadowsocks has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/wireguard/uninstall.sh" "$(uninstall_entrypoint wireguard)" "WireGuard has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/exposure/nginx/uninstall.sh" "$(uninstall_entrypoint nginx-exposure)" "Nginx exposure has isolated uninstall entrypoint"

if resolve_uninstall_modules unknown-module >/dev/null; then
    invalid_module_ok="false"
else
    invalid_module_ok="true"
fi
assert_equals "true" "$invalid_module_ok" "Unknown uninstall module fails resolution"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export EASYNET_STATE_DIR="$TMP_DIR/state"
mkdir -p "$EASYNET_STATE_DIR/modules/xray-reality" "$EASYNET_STATE_DIR/modules/trojan-go" "$EASYNET_STATE_DIR/modules/wireguard" "$EASYNET_STATE_DIR/modules/example-shared"

cat > "$EASYNET_STATE_DIR/modules/xray-reality/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "xray-reality",
  "enabled": true,
  "protocol": "vless",
  "client": {
    "uri": "vless://example",
    "clash": {"name": "xray", "type": "vless"}
  },
  "firewall": [
    {"port": 8443, "proto": "tcp"}
  ],
  "systemd": {"services": ["xray"]}
}
JSON

cat > "$EASYNET_STATE_DIR/modules/trojan-go/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "trojan-go",
  "enabled": true,
  "protocol": "trojan",
  "client": {
    "uri": "trojan://example",
    "clash": {"name": "trojan", "type": "trojan"}
  },
  "firewall": [
    {"port": 443, "proto": "tcp"}
  ],
  "systemd": {"services": ["trojan-go"]}
}
JSON

cat > "$EASYNET_STATE_DIR/modules/wireguard/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "wireguard",
  "enabled": true,
  "protocol": "wireguard",
  "client": {
    "uri": "wg://example",
    "clash": {"name": "wg", "type": "wireguard"}
  },
  "firewall": [
    {"port": 51820, "proto": "udp"}
  ],
  "systemd": {"services": ["wg-quick@wg0"]}
}
JSON

cat > "$EASYNET_STATE_DIR/modules/example-shared/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example-shared",
  "enabled": true,
  "protocol": "example",
  "client": {
    "uri": "example://node",
    "clash": {"name": "example", "type": "ss"}
  },
  "firewall": [
    {"port": 51820, "proto": "udp"}
  ],
  "systemd": {"services": ["example"]}
}
JSON

source "$PROJECT_ROOT/scripts/core/uninstall.sh"

assert_equals "8443/tcp" "$(uninstall_firewall_rules_to_delete xray-reality)" "Unique module firewall rule is removable"
assert_equals "" "$(uninstall_firewall_rules_to_delete trojan-go)" "Base firewall rule is preserved during module uninstall"
assert_equals "" "$(uninstall_firewall_rules_to_delete wireguard)" "Firewall rule shared by another module is preserved"

if rg -q "scripts/server|/server/" "$PROJECT_ROOT/scripts/uninstall.sh" "$PROJECT_ROOT/scripts/protocols"/*/uninstall.sh; then
    uninstall_references_legacy_server="true"
else
    uninstall_references_legacy_server="false"
fi
assert_equals "false" "$uninstall_references_legacy_server" "Uninstall flow does not reference legacy server wrappers"

test_end
