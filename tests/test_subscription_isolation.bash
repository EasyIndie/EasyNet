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

output_with_edge_domain=$(
    EASYNET_STATE_DIR="$STATE_DIR" \
    EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
)
if printf '%s\n' "$output_with_edge_domain" | rg -q "https://edge.example.com/sub" && ! printf '%s\n' "$output_with_edge_domain" | rg -q "edge.example.com:443"; then
    printed_edge_domain="true"
else
    printed_edge_domain="false"
fi
assert_equals "true" "$printed_edge_domain" "Edge domain prints standard HTTPS subscription links without explicit port"

test_end
