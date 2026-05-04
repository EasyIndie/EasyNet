#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Cron Services From Metadata"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export EASYNET_STATE_DIR="$TMP_DIR/state"
source "$PROJECT_ROOT/scripts/core/cron.sh"

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
  "systemd": {
    "services": ["xray", "xray"]
  }
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
  "systemd": {
    "services": ["wg-quick@wg0"]
  }
}
JSON

services="$(cron_restart_services)"

for expected_service in "xray" "wg-quick@wg0"; do
    if printf '%s\n' "$services" | grep -qx "$expected_service"; then
        found="true"
    else
        found="false"
    fi
    assert_equals "true" "$found" "Cron service list includes $expected_service"
done

duplicate_count=$(printf '%s\n' "$services" | grep -xc "xray")
assert_equals "1" "$duplicate_count" "Cron service list de-duplicates repeated services"

restart_command="$(cron_restart_command)"
assert_equals "/usr/bin/systemctl restart xray wg-quick@wg0 2>/dev/null" "$restart_command" "Cron restart command is generated from metadata"

if printf '%s\n' "$restart_command" | grep -q "trojan-go"; then
    undeclared_service="true"
else
    undeclared_service="false"
fi
assert_equals "false" "$undeclared_service" "Cron restart command excludes undeclared services"

test_end
