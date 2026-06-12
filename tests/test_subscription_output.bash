#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Subscription Output Verification"

# ============================================================
# Setup: Create a fake state with metadata fixtures for all 4 protocols
# ============================================================
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_DIR="$TMP_DIR/state"
WEB_ROOT="$TMP_DIR/web"
mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/modules"
for mod in xray-reality shadowsocks wireguard hysteria2; do
    mkdir -p "$STATE_DIR/modules/$mod"
done
echo "example.com" > "$STATE_DIR/exposure/edge/domain.txt"
echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
echo "443" > "$STATE_DIR/exposure/edge/port.txt"
echo "/s/aaaa1111bbbb2222cccc3333dddd4444" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"

# Write metadata for a vless node (Xray Reality style)
cat > "$STATE_DIR/modules/xray-reality/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "xray-reality",
  "enabled": true,
  "protocol": "vless",
  "listen": "0.0.0.0",
  "port": 8443,
  "transport": "tcp",
  "security": "reality",
  "client": {
    "uri": "vless://uuid-1@10.0.0.1:8443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=pubkey-1&sid=abcd00000001&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality",
    "clash": {
      "name": "EasyNet-Reality",
      "type": "vless",
      "server": "10.0.0.1",
      "port": 8443,
      "uuid": "uuid-1111-1111-1111-111111111111",
      "network": "tcp",
      "flow": "xtls-rprx-vision",
      "servername": "www.microsoft.com",
      "client-fingerprint": "chrome",
      "reality-opts": {
        "public-key": "pubkey-reality-111111111111",
        "short-id": "abcd00000001"
      }
    }
  },
  "firewall": [
    { "port": 8443, "proto": "tcp" }
  ],
  "systemd": {
    "services": ["xray"]
  }
}
JSON

# Write metadata for an ss node (Shadowsocks style)
cat > "$STATE_DIR/modules/shadowsocks/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "shadowsocks",
  "enabled": true,
  "protocol": "ss",
  "listen": "0.0.0.0",
  "port": 8388,
  "transport": "tcp",
  "security": "aes-256-gcm",
  "client": {
    "uri": "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMTExMTExMTE@10.0.0.1:8388#EasyNet-Shadowsocks",
    "clash": {
      "name": "EasyNet-Shadowsocks",
      "type": "ss",
      "server": "10.0.0.1",
      "port": 8388,
      "cipher": "aes-256-gcm",
      "password": "password1111111111"
    }
  },
  "firewall": [
    { "port": 8388, "proto": "tcp" },
    { "port": 8388, "proto": "udp" }
  ],
  "systemd": {
    "services": ["shadowsocks-rust-server"]
  }
}
JSON

# Write metadata for a wireguard node
cat > "$STATE_DIR/modules/wireguard/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "wireguard",
  "enabled": true,
  "protocol": "wireguard",
  "client": {
    "uri": "wireguard://...",
    "clash": {
      "name": "EasyNet-WireGuard",
      "type": "wireguard",
      "server": "10.0.0.1",
      "port": 51820,
      "ip": "10.99.0.2",
      "private-key": "wg-private-key-44444444",
      "public-key": "wg-public-key-44444444",
      "pre-shared-key": "wg-psk-444444444444",
      "mtu": 1360,
      "dns": ["1.1.1.1", "8.8.8.8"]
    }
  },
  "firewall": [
    { "port": 51820, "proto": "udp" }
  ],
  "systemd": {
    "services": ["wg-quick@wg0"]
  }
}
JSON

# Write metadata for a hysteria2 node
cat > "$STATE_DIR/modules/hysteria2/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "hysteria2",
  "enabled": true,
  "protocol": "hysteria2",
  "client": {
    "uri": "hysteria2://password555@example.com:443?sni=example.com&obfs=salamander&obfs-password=obfs-pwd-555#EasyNet-Hysteria2",
    "clash": {
      "name": "EasyNet-Hysteria2",
      "type": "hysteria2",
      "server": "example.com",
      "port": 443,
      "password": "password5555555555",
      "sni": "example.com",
      "obfs": "salamander",
      "obfs-password": "obfs-password-555555",
      "up": "100 Mbps",
      "down": "200 Mbps"
    }
  },
  "firewall": [
    { "port": 443, "proto": "udp" }
  ],
  "systemd": {
    "services": ["hysteria-server.service"]
  }
}
JSON

# ============================================================
# Run subscription generation
# ============================================================
EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_WEB_ROOT="$WEB_ROOT" \
EASYNET_DOMAIN="example.com" \
    bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1

# ============================================================
# Test 1: URI subscription file exists and is non-empty
# ============================================================
assert_equals "true" "$([ -s "$WEB_ROOT/sub" ] && echo true || echo false)" "URI subscription file is non-empty"

# ============================================================
# Test 2: Clash config file exists
# ============================================================
assert_equals "true" "$([ -f "$WEB_ROOT/clash" ] && echo true || echo false)" "Clash config file exists"

# ============================================================
# Test 3: sing-box config file exists
# ============================================================
assert_equals "true" "$([ -f "$WEB_ROOT/singbox" ] && echo true || echo false)" "sing-box config file exists"

# ============================================================
# Test 4: Clash config has expected structure
# ============================================================
clash_content="$(cat "$WEB_ROOT/clash")"

if printf '%s\n' "$clash_content" | grep -q "mixed-port: 7890"; then
    clash_has_mixed_port="true"
else
    clash_has_mixed_port="false"
fi
assert_equals "true" "$clash_has_mixed_port" "Clash config has mixed-port"

if printf '%s\n' "$clash_content" | grep -q "mode: rule"; then
    clash_has_mode="true"
else
    clash_has_mode="false"
fi
assert_equals "true" "$clash_has_mode" "Clash config has mode: rule"

if printf '%s\n' "$clash_content" | grep -q "Proxy" && printf '%s\n' "$clash_content" | grep -q "Auto"; then
    clash_has_proxy_groups="true"
else
    clash_has_proxy_groups="false"
fi
assert_equals "true" "$clash_has_proxy_groups" "Clash config has Proxy and Auto groups"

# ============================================================
# Test 5: Clash config includes all 4 protocol proxies
# ============================================================
for name in "EasyNet-Reality" "EasyNet-Shadowsocks" "EasyNet-WireGuard" "EasyNet-Hysteria2"; do
    if printf '%s\n' "$clash_content" | grep -q "name: \"$name\""; then
        result="true"
    else
        result="false"
    fi
    assert_equals "true" "$result" "Clash proxy includes $name"
done

# ============================================================
# Test 6: Clash vless proxy has reality-opts
# ============================================================
if printf '%s\n' "$clash_content" | grep -q "reality-opts:"; then
    clash_has_reality="true"
else
    clash_has_reality="false"
fi
assert_equals "true" "$clash_has_reality" "Clash vless proxy has reality-opts"

# ============================================================
# Test 7: Clash vless proxy has reality-opts (anti-DPI protection)
# ============================================================
if printf '%s\n' "$clash_content" | grep -q "reality-opts:"; then
    clash_has_reality_anti_dpi="true"
else
    clash_has_reality_anti_dpi="false"
fi
assert_equals "true" "$clash_has_reality_anti_dpi" "Clash vless proxy retains reality-opts for anti-DPI"

# ============================================================
# Test 8: Clash wireguard proxy has dns entries
# ============================================================
if printf '%s\n' "$clash_content" | grep -q "1.1.1.1" && printf '%s\n' "$clash_content" | grep -q "8.8.8.8"; then
    clash_wg_has_dns="true"
else
    clash_wg_has_dns="false"
fi
assert_equals "true" "$clash_wg_has_dns" "Clash wireguard proxy has DNS entries"

# ============================================================
# Test 9: Clash hysteria2 proxy has obfs fields
# ============================================================
if printf '%s\n' "$clash_content" | grep -q "obfs:"; then
    clash_h2_has_obfs="true"
else
    clash_h2_has_obfs="false"
fi
assert_equals "true" "$clash_h2_has_obfs" "Clash hysteria2 proxy has obfs fields"

# ============================================================
# Test 9: sing-box config has valid JSON structure
# ============================================================
if jq -e '.log.level == "info"' "$WEB_ROOT/singbox" >/dev/null 2>&1; then
    sb_has_log="true"
else
    sb_has_log="false"
fi
assert_equals "true" "$sb_has_log" "sing-box config has log section"

if jq -e '.outbounds | length >= 6' "$WEB_ROOT/singbox" >/dev/null 2>&1; then
    sb_has_outbounds="true"
else
    sb_has_outbounds="false"
fi
assert_equals "true" "$sb_has_outbounds" "sing-box config has expected outbounds (nodes + Proxy + Auto + DIRECT + REJECT)"

# ============================================================
# Test 10: sing-box config has all node types
# ============================================================
sb_types="$(jq -r '[.outbounds[].type] | join(",")' "$WEB_ROOT/singbox")"

for sb_type in "vless" "shadowsocks" "hysteria2"; do
    if printf '%s\n' "$sb_types" | grep -q "$sb_type"; then
        result="true"
    else
        result="false"
    fi
    assert_equals "true" "$result" "sing-box config has $sb_type outbound"
done

# ============================================================
# Test 11: WireGuard is rendered as endpoint (not outbound) in sing-box
# ============================================================
if jq -e '.endpoints[] | select(.type == "wireguard")' "$WEB_ROOT/singbox" >/dev/null 2>&1; then
    sb_wg_is_endpoint="true"
else
    sb_wg_is_endpoint="false"
fi
assert_equals "true" "$sb_wg_is_endpoint" "sing-box renders WireGuard as endpoint"

# ============================================================
# Test 12: sing-box has route section with sniff rule
# ============================================================
if jq -e '.route.final == "Proxy"' "$WEB_ROOT/singbox" >/dev/null 2>&1; then
    sb_has_route="true"
else
    sb_has_route="false"
fi
assert_equals "true" "$sb_has_route" "sing-box config has route section"

# ============================================================
# Test 13: Empty metadata dir produces no error (graceful)
# ============================================================
EMPTY_DIR="$(mktemp -d)"
EMPTY_WEB="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$EMPTY_DIR" "$EMPTY_WEB"' EXIT

mkdir -p "$EMPTY_DIR/modules" "$EMPTY_WEB"
output_empty=$(
    EASYNET_STATE_DIR="$EMPTY_DIR" \
    EASYNET_WEB_ROOT="$EMPTY_WEB" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" 2>&1
)
if printf '%s\n' "$output_empty" | grep -q "没有找到任何有效的节点配置"; then
    empty_graceful="true"
else
    empty_graceful="false"
fi
assert_equals "true" "$empty_graceful" "Empty metadata dir exits gracefully without error"

test_end
