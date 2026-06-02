#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Subscription Generator Isolation"

if rg -q "/etc/trojan-go|/usr/local/etc/v2ray|/etc/shadowsocks-libev|/etc/wireguard|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/generate_subscription.sh"; then
    generator_reads_protocol_state="true"
else
    generator_reads_protocol_state="false"
fi
assert_equals "false" "$generator_reads_protocol_state" "Subscription generator does not read protocol config paths"

if rg -q "curl -s ipinfo.io|ifconfig.me|api.ipify.org" "$PROJECT_ROOT/scripts/generate_subscription.sh"; then
    generator_queries_public_ip="true"
else
    generator_queries_public_ip="false"
fi
assert_equals "false" "$generator_queries_public_ip" "Subscription generator does not query public IP directly"

if rg -q "easynet_nginx_state_dir|easynet_subscription_state_dir|sub_full|clash_full|trojan_metadata_file" "$PROJECT_ROOT/scripts/core/subscription.sh" "$PROJECT_ROOT/scripts/generate_subscription.sh"; then
    subscription_has_old_fallbacks="true"
else
    subscription_has_old_fallbacks="false"
fi
assert_equals "false" "$subscription_has_old_fallbacks" "Subscription logic has no old exposure fallbacks"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_DIR="$TMP_DIR/state"
WEB_ROOT="$TMP_DIR/web"
mkdir -p "$STATE_DIR/modules/example"

cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "example",
  "enabled": true,
  "protocol": "vless",
  "listen": "0.0.0.0",
  "port": 8443,
  "transport": "tcp",
  "security": "reality",
  "client": {
    "uri": "vless://example",
    "clash": {
      "name": "Example",
      "type": "vless",
      "server": "203.0.113.10",
      "port": 8443,
      "uuid": "11111111-1111-4111-8111-111111111111",
      "network": "tcp",
      "flow": "xtls-rprx-vision",
      "servername": "www.example.com",
      "client-fingerprint": "chrome",
      "reality-opts": {
        "public-key": "public-key-fixture",
        "short-id": "aabbccddeeff0011"
      }
    }
  }
}
JSON

output_without_edge=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
    EASYNET_DOMAIN="proxy.example.com" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)

if printf '%s\n' "$output_without_edge" | rg -q "https://proxy.example.com"; then
    printed_without_edge_state="true"
else
    printed_without_edge_state="false"
fi
assert_equals "false" "$printed_without_edge_state" "Subscription links are not printed until Edge state exists"

mkdir -p "$STATE_DIR/exposure/edge"
echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
echo "443" > "$STATE_DIR/exposure/edge/port.txt"
echo "/s/0123456789abcdef0123456789abcdef" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"

output_with_edge_domain=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)
if printf '%s\n' "$output_with_edge_domain" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/sub" \
    && printf '%s\n' "$output_with_edge_domain" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/singbox" \
    && ! printf '%s\n' "$output_with_edge_domain" | rg -q "edge.example.com:443|https://edge.example.com/sub|sub_full|clash_full"; then
    printed_edge_domain="true"
else
    printed_edge_domain="false"
fi
assert_equals "true" "$printed_edge_domain" "Edge domain prints stable random subscription paths without fixed or full links"

if jq -e '.inbounds[] | select(.type == "mixed" and .listen_port == 7890)' "$WEB_ROOT/singbox" >/dev/null \
    && ! jq -e '.inbounds[] | has("sniff")' "$WEB_ROOT/singbox" >/dev/null \
    && jq -e '.route.rules[] | select(.inbound == "mixed-in" and .action == "sniff")' "$WEB_ROOT/singbox" >/dev/null \
    && jq -e '.outbounds[] | select(.type == "vless" and .tag == "Example")' "$WEB_ROOT/singbox" >/dev/null \
    && [ -f "$WEB_ROOT/easynet-singbox-client.sh" ]; then
    singbox_config_generated="true"
else
    singbox_config_generated="false"
fi
assert_equals "true" "$singbox_config_generated" "sing-box config and client installer are generated from metadata without protocol config access"

rm -rf "$STATE_DIR/modules"
mkdir -p \
    "$STATE_DIR/modules/wireguard" \
    "$STATE_DIR/modules/v2ray" \
    "$STATE_DIR/modules/trojan-go" \
    "$STATE_DIR/modules/shadowsocks" \
    "$STATE_DIR/modules/hysteria2" \
    "$STATE_DIR/modules/xray-reality"

for module in wireguard v2ray trojan-go shadowsocks hysteria2 xray-reality; do
    if [ "$module" = "wireguard" ]; then
        cat > "$STATE_DIR/modules/$module/metadata.json" <<JSON
{
  "schemaVersion": 1,
  "module": "$module",
  "enabled": true,
  "protocol": "$module",
  "client": {
    "uri": "$module://node",
    "clash": {
      "name": "$module",
      "type": "wireguard",
      "server": "203.0.113.10",
      "port": 51820,
      "ip": "10.0.0.2",
      "private-key": "private-key",
      "public-key": "public-key",
      "pre-shared-key": "psk",
      "mtu": 1360,
      "dns": ["1.1.1.1"]
    }
  }
}
JSON
    else
        cat > "$STATE_DIR/modules/$module/metadata.json" <<JSON
{
  "schemaVersion": 1,
  "module": "$module",
  "enabled": true,
  "protocol": "$module",
  "client": {
    "uri": "$module://node",
    "clash": {
      "name": "$module",
      "type": "ss",
      "server": "203.0.113.10",
      "port": 8388,
      "cipher": "aes-256-gcm",
      "password": "password"
    }
  }
}
JSON
    fi
done

EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_WEB_ROOT="$WEB_ROOT" \
    bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null

ordered_subscription_links="$(openssl base64 -d -A -in "$WEB_ROOT/sub")"
expected_subscription_links=$'xray-reality://node\nhysteria2://node\ntrojan-go://node\nv2ray://node\nshadowsocks://node\nwireguard://node'
assert_equals "$expected_subscription_links" "$ordered_subscription_links" "URI subscription file orders nodes by security and anti-DPI strength"
ordered_singbox_tags="$(jq -r '.outbounds[] | select(.tag == "Proxy").outbounds[] | select(. != "Auto" and . != "DIRECT")' "$WEB_ROOT/singbox")"
expected_singbox_tags=$'xray-reality\nhysteria2\ntrojan-go\nv2ray\nshadowsocks\nwireguard'
assert_equals "$expected_singbox_tags" "$ordered_singbox_tags" "sing-box config orders nodes by security and anti-DPI strength"
if jq -e '.endpoints[] | select(.type == "wireguard" and .tag == "wireguard")' "$WEB_ROOT/singbox" >/dev/null; then
    singbox_wireguard_endpoint="true"
else
    singbox_wireguard_endpoint="false"
fi
assert_equals "true" "$singbox_wireguard_endpoint" "sing-box config renders WireGuard as endpoint for current sing-box versions"

show_subscription_output=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
        bash "$PROJECT_ROOT/scripts/show_subscription.sh"
)
if printf '%s\n' "$show_subscription_output" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/clash" \
    && printf '%s\n' "$show_subscription_output" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/singbox" \
    && printf '%s\n' "$show_subscription_output" | rg -q "sudo bash easynet-singbox-client.sh --config-url"; then
    show_subscription_uses_edge_path="true"
else
    show_subscription_uses_edge_path="false"
fi
assert_equals "true" "$show_subscription_uses_edge_path" "Show subscription command reprints stable Edge subscription links"

if rg -q "qrencode -t utf8.*sub_url|qrencode -t utf8.*clash_url|qrencode -t utf8.*singbox_url|无法显示 URI 订阅二维码|无法显示 Clash/Mihomo 订阅二维码|无法显示 sing-box 配置二维码" "$PROJECT_ROOT/scripts/show_subscription.sh"; then
    show_subscription_qr_behavior="true"
else
    show_subscription_qr_behavior="false"
fi
assert_equals "true" "$show_subscription_qr_behavior" "Show subscription command prints QR codes or explicit QR fallback messages"

rotation_output=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
    EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh"
)
rotated_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt")"
previous_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.previous.txt")"
assert_equals "/s/0123456789abcdef0123456789abcdef" "$previous_prefix" "Subscription rotation records previous path prefix"
if [[ "$rotated_prefix" =~ ^/s/[0-9a-f]{32}$ ]] && [ "$rotated_prefix" != "$previous_prefix" ]; then
    rotation_prefix_ok="true"
else
    rotation_prefix_ok="false"
fi
assert_equals "true" "$rotation_prefix_ok" "Subscription rotation writes a new stable random path"
if printf '%s\n' "$rotation_output" | rg -q "https://edge.example.com${rotated_prefix}/sub" \
    && printf '%s\n' "$rotation_output" | rg -q "https://edge.example.com${rotated_prefix}/singbox" \
    && rg -q "location = ${rotated_prefix}/clash" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${rotated_prefix}/singbox" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${rotated_prefix}/singbox-client.sh" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && ! rg -q "$previous_prefix" "$STATE_DIR/exposure/edge/routes/subscription.conf"; then
    rotation_updates_routes="true"
else
    rotation_updates_routes="false"
fi
assert_equals "true" "$rotation_updates_routes" "Subscription rotation updates Edge routes and prints new links"

grace_output=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
    EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh" --grace
)
grace_new_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt")"
grace_previous_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.previous.txt")"
if printf '%s\n' "$grace_output" | rg -q "https://edge.example.com${grace_new_prefix}/clash" \
    && printf '%s\n' "$grace_output" | rg -q "https://edge.example.com${grace_new_prefix}/singbox" \
    && rg -q "location = ${grace_new_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${grace_new_prefix}/singbox" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${grace_new_prefix}/singbox-client.sh" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${grace_previous_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${grace_previous_prefix}/singbox" "$STATE_DIR/exposure/edge/routes/subscription.conf" \
    && rg -q "location = ${grace_previous_prefix}/singbox-client.sh" "$STATE_DIR/exposure/edge/routes/subscription.conf"; then
    rotation_grace_keeps_previous="true"
else
    rotation_grace_keeps_previous="false"
fi
assert_equals "true" "$rotation_grace_keeps_previous" "Subscription rotation grace keeps previous links active"

test_end
