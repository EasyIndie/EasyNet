#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Firewall Rules From Metadata"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export EASYNET_STATE_DIR="$TMP_DIR/state"
source "$PROJECT_ROOT/scripts/core/firewall.sh"

mkdir -p "$EASYNET_STATE_DIR/modules/example-a" "$EASYNET_STATE_DIR/modules/example-b"

cat > "$EASYNET_STATE_DIR/modules/example-a/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example-a",
  "enabled": true,
  "protocol": "vless",
  "listen": "0.0.0.0",
  "port": 8443,
  "transport": "tcp",
  "security": "reality",
  "client": {
    "uri": "vless://example",
    "clash": {}
  },
  "firewall": [
    { "port": 8443, "proto": "tcp" },
    { "port": 443, "proto": "tcp" }
  ]
}
JSON

cat > "$EASYNET_STATE_DIR/modules/example-b/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example-b",
  "enabled": true,
  "protocol": "wireguard",
  "listen": "0.0.0.0",
  "port": 51820,
  "transport": "udp",
  "security": "wireguard",
  "client": {
    "uri": "wg://example",
    "clash": {}
  },
  "firewall": [
    { "port": 51820, "proto": "udp" }
  ]
}
JSON

rules="$(firewall_all_rules)"

for expected_rule in "22/tcp" "80/tcp" "443/tcp" "8443/tcp" "51820/udp"; do
    if printf '%s\n' "$rules" | grep -qx "$expected_rule"; then
        found="true"
    else
        found="false"
    fi
    assert_equals "true" "$found" "Firewall plan includes $expected_rule"
done

duplicate_count=$(printf '%s\n' "$rules" | grep -xc "443/tcp")
assert_equals "1" "$duplicate_count" "Firewall plan de-duplicates repeated rules"

if printf '%s\n' "$rules" | grep -q "8388/tcp"; then
    unexpected_rule="true"
else
    unexpected_rule="false"
fi
assert_equals "false" "$unexpected_rule" "Firewall plan does not include undeclared protocol ports"

if rg -q "ufw allow" "$PROJECT_ROOT/scripts/protocols"; then
    protocol_ufw_write="true"
else
    protocol_ufw_write="false"
fi
assert_equals "false" "$protocol_ufw_write" "Protocol modules do not write firewall rules directly"

test_end
