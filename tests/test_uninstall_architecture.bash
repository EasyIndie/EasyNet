#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/uninstall.sh"

test_start "Uninstall Architecture"

assert_equals "hysteria2" "$(resolve_uninstall_modules 1)" "Uninstall menu 1 resolves to Hysteria2 (alphabetically first)"
assert_equals "shadowsocks" "$(resolve_uninstall_modules 2)" "Uninstall menu 2 resolves to Shadowsocks"
assert_equals "wireguard" "$(resolve_uninstall_modules 3)" "Uninstall menu 3 resolves to WireGuard"
assert_equals "xray-reality" "$(resolve_uninstall_modules 4)" "Uninstall menu 4 resolves to Xray+Reality (alphabetically last)"
assert_equals "edge-exposure" "$(resolve_uninstall_modules 5)" "Uninstall menu 5 resolves to Edge Gateway"
assert_equals "__exit__" "$(resolve_uninstall_modules 6)" "Uninstall menu 6 resolves to exit sentinel"

all_modules="$(resolve_uninstall_modules 0 | xargs)"
assert_equals "hysteria2 shadowsocks wireguard xray-reality edge-exposure" "$all_modules" "Uninstall menu 0 removes all protocol modules and Edge Gateway (alphabetical order)"

assert_equals "$PROJECT_ROOT/scripts/protocols/xray-reality/uninstall.sh" "$(uninstall_entrypoint xray-reality)" "Xray Reality has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/hysteria2/uninstall.sh" "$(uninstall_entrypoint hysteria2)" "Hysteria2 has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/shadowsocks/uninstall.sh" "$(uninstall_entrypoint shadowsocks)" "Shadowsocks has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/protocols/wireguard/uninstall.sh" "$(uninstall_entrypoint wireguard)" "WireGuard has isolated uninstall entrypoint"
assert_equals "$PROJECT_ROOT/scripts/exposure/edge/uninstall.sh" "$(uninstall_entrypoint edge-exposure)" "Edge Gateway has isolated uninstall entrypoint"

if resolve_uninstall_modules unknown-module >/dev/null; then
    invalid_ok="false"
else
    invalid_ok="true"
fi
assert_equals "true" "$invalid_ok" "Unknown uninstall module fails resolution"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STATE_DIR="$TMP_DIR/state"
export EASYNET_STATE_DIR="$STATE_DIR"
source "$PROJECT_ROOT/scripts/core/firewall.sh"
mkdir -p "$STATE_DIR/modules/example"

cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example",
  "enabled": true,
  "protocol": "vless",
  "client": {
    "uri": "vless://example",
    "clash": { "name": "Example", "type": "vless" }
  },
  "firewall": [
    { "port": 8443, "proto": "tcp" }
  ]
}
JSON

if printf '%s\n' "$(firewall_metadata_rules)" | rg -q "8443/tcp"; then
    unique_rule_found="true"
else
    unique_rule_found="false"
fi
assert_equals "true" "$unique_rule_found" "Unique module firewall rule is removable"

if printf '%s\n' "$(firewall_all_rules)" | rg -q "22/tcp"; then
    base_rules_preserved="true"
else
    base_rules_preserved="false"
fi
assert_equals "true" "$base_rules_preserved" "Base firewall rule is preserved during module uninstall"

mkdir -p "$STATE_DIR/modules/example-b"
cat > "$STATE_DIR/modules/example-b/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example-b",
  "enabled": true,
  "protocol": "vless",
  "client": {
    "uri": "vless://example",
    "clash": { "name": "ExampleB", "type": "vless" }
  },
  "firewall": [
    { "port": 8443, "proto": "tcp" }
  ]
}
JSON
all_rules="$(firewall_all_rules)"
duplicate_count=$(printf '%s\n' "$all_rules" | grep -c "8443/tcp")
if [ "$duplicate_count" -eq 1 ]; then
    duplicate_rule_deduped="true"
else
    duplicate_rule_deduped="false"
fi
assert_equals "true" "$duplicate_rule_deduped" "Firewall rule shared by another module is preserved"

if rg -q "scripts/server|/server/|nginx-exposure|subscription-exposure" "$PROJECT_ROOT/scripts/uninstall.sh"; then
    uninstall_references_legacy="true"
else
    uninstall_references_legacy="false"
fi
assert_equals "false" "$uninstall_references_legacy" "Uninstall flow does not reference legacy server wrappers"

if rg -q "sub_full|clash_full|easynet_nginx_state_dir|easynet_subscription_state_dir" "$PROJECT_ROOT/scripts/uninstall.sh"; then
    uninstall_references_old_exposure="true"
else
    uninstall_references_old_exposure="false"
fi
assert_equals "false" "$uninstall_references_old_exposure" "Uninstall flow does not reference old exposure implementations"

test_end
