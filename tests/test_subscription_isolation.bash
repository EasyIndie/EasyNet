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

if [ -d "$PROJECT_ROOT/scripts/legacy" ]; then
    legacy_dir_present="true"
else
    legacy_dir_present="false"
fi
assert_equals "false" "$legacy_dir_present" "Legacy importer directory has been removed"

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

output_without_exposure=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
    EASYNET_DOMAIN="proxy.example.com" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)

if printf '%s\n' "$output_without_exposure" | rg -q "https://proxy.example.com/sub"; then
    printed_generic_domain="true"
else
    printed_generic_domain="false"
fi
assert_equals "false" "$printed_generic_domain" "Subscription links are not printed from generic EASYNET_DOMAIN"

output_with_subscription_domain=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
    EASYNET_SUBSCRIPTION_DOMAIN="sub.example.com" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)

if printf '%s\n' "$output_with_subscription_domain" | rg -q "https://sub.example.com/sub"; then
    printed_explicit_domain="true"
else
    printed_explicit_domain="false"
fi
assert_equals "true" "$printed_explicit_domain" "Explicit subscription domain prints subscription links"

mkdir -p "$STATE_DIR/exposure/subscription"
echo "subcarrier.example.com" > "$STATE_DIR/exposure/subscription/domain.txt"
echo "https" > "$STATE_DIR/exposure/subscription/scheme.txt"
echo "9443" > "$STATE_DIR/exposure/subscription/port.txt"

output_with_subscription_exposure=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)

if printf '%s\n' "$output_with_subscription_exposure" | rg -q "https://subcarrier.example.com:9443/sub"; then
    printed_subscription_exposure_domain="true"
else
    printed_subscription_exposure_domain="false"
fi
assert_equals "true" "$printed_subscription_exposure_domain" "Independent subscription exposure domain prints subscription links"

if printf '%s\n' "$output_with_subscription_exposure" | rg -q "sub_full|clash_full|完整订阅二维码"; then
    printed_full_subscription_links="true"
else
    printed_full_subscription_links="false"
fi
assert_equals "false" "$printed_full_subscription_links" "Subscription output omits full subscription links and QR codes"

rm -rf "$STATE_DIR/exposure/subscription"
mkdir -p "$STATE_DIR/exposure/nginx"
echo "nginx.example.com" > "$STATE_DIR/exposure/nginx/domain.txt"

output_with_exposure_domain=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)

if printf '%s\n' "$output_with_exposure_domain" | rg -q "https://nginx.example.com/sub"; then
    printed_exposure_domain="true"
else
    printed_exposure_domain="false"
fi
assert_equals "true" "$printed_exposure_domain" "Nginx exposure domain prints subscription links"

mkdir -p "$STATE_DIR/modules/trojan-go"
cat > "$STATE_DIR/modules/trojan-go/metadata.json" <<'JSON'
{
  "schemaVersion": 1,
  "module": "trojan-go",
  "enabled": true,
  "protocol": "trojan",
  "client": {
    "uri": "trojan://secret@trojan.example.com:443?security=tls&type=ws&path=/safe#EasyNet-Trojan",
    "clash": {
      "name": "EasyNet-Trojan",
      "type": "trojan",
      "server": "trojan.example.com",
      "port": 443,
      "password": "secret"
    }
  },
  "firewall": [
    {"port": 443, "proto": "tcp"}
  ],
  "systemd": {
    "services": ["trojan-go"]
  }
}
JSON

rm -f "$STATE_DIR/exposure/nginx/domain.txt"
output_with_trojan_metadata=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)
if printf '%s\n' "$output_with_trojan_metadata" | rg -q "https://trojan.example.com/sub"; then
    printed_trojan_domain="true"
else
    printed_trojan_domain="false"
fi
assert_equals "true" "$printed_trojan_domain" "Trojan-Go metadata domain prints subscription links"

if [ -f "$WEB_ROOT/sub_full" ] || [ -f "$WEB_ROOT/clash_full" ]; then
    full_subscription_files_present="true"
else
    full_subscription_files_present="false"
fi
assert_equals "false" "$full_subscription_files_present" "Subscription generator removes legacy full subscription files"

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
if printf '%s\n' "$output_with_edge_domain" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/sub" && ! printf '%s\n' "$output_with_edge_domain" | rg -q "edge.example.com:443|https://edge.example.com/sub"; then
    printed_edge_domain="true"
else
    printed_edge_domain="false"
fi
assert_equals "true" "$printed_edge_domain" "Edge domain prints stable random subscription path without explicit port"

show_subscription_output=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
        bash "$PROJECT_ROOT/scripts/show_subscription.sh"
)
if printf '%s\n' "$show_subscription_output" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/clash"; then
    show_subscription_uses_edge_path="true"
else
    show_subscription_uses_edge_path="false"
fi
assert_equals "true" "$show_subscription_uses_edge_path" "Show subscription command reprints stable Edge subscription links"

if rg -q "qrencode -t utf8.*sub_url|qrencode -t utf8.*clash_url|无法显示 URI 订阅二维码|无法显示 Clash/Mihomo 订阅二维码" "$PROJECT_ROOT/scripts/show_subscription.sh"; then
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
if printf '%s\n' "$rotation_output" | rg -q "https://edge.example.com${rotated_prefix}/sub" && rg -q "location = ${rotated_prefix}/clash" "$STATE_DIR/exposure/edge/routes/subscription.conf" && ! rg -q "$previous_prefix" "$STATE_DIR/exposure/edge/routes/subscription.conf"; then
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
if printf '%s\n' "$grace_output" | rg -q "https://edge.example.com${grace_new_prefix}/clash" && rg -q "location = ${grace_new_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf" && rg -q "location = ${grace_previous_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf"; then
    rotation_grace_keeps_previous="true"
else
    rotation_grace_keeps_previous="false"
fi
assert_equals "true" "$rotation_grace_keeps_previous" "Subscription rotation grace keeps previous links active"

test_end
