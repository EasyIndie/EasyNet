#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"

test_start "Protocol Module Metadata Contract"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

XRAY_FIXTURE_DIR="$TMP_DIR/xray"
SS_FIXTURE_DIR="$TMP_DIR/shadowsocks"
WG_FIXTURE_DIR="$TMP_DIR/wireguard"
TROJAN_FIXTURE_DIR="$TMP_DIR/trojan-go"
V2RAY_FIXTURE_DIR="$TMP_DIR/v2ray"
HYSTERIA2_FIXTURE_DIR="$TMP_DIR/hysteria2"
STATE_DIR="$TMP_DIR/state"
mkdir -p "$XRAY_FIXTURE_DIR" "$SS_FIXTURE_DIR" "$WG_FIXTURE_DIR/clients" "$TROJAN_FIXTURE_DIR" "$V2RAY_FIXTURE_DIR" "$HYSTERIA2_FIXTURE_DIR"

cat > "$XRAY_FIXTURE_DIR/config.json" <<'JSON'
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "11111111-1111-4111-8111-111111111111",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverNames": ["www.example.com"],
          "shortIds": ["aabbccddeeff0011"]
        }
      }
    }
  ]
}
JSON

echo "public-key-fixture" > "$XRAY_FIXTURE_DIR/public.key"

EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_PUBLIC_IP="203.0.113.10" \
XRAY_DIR="$XRAY_FIXTURE_DIR" \
    bash "$PROJECT_ROOT/scripts/protocols/xray-reality/export.sh"

METADATA_FILE="$STATE_DIR/modules/xray-reality/metadata.json"

assert_equals "true" "$([ -f "$METADATA_FILE" ] && echo true || echo false)" "Xray Reality export writes module metadata"

source "$PROJECT_ROOT/scripts/core/metadata.sh"
EASYNET_STATE_DIR="$STATE_DIR"
if metadata_validate_file "$METADATA_FILE"; then
    metadata_valid="true"
else
    metadata_valid="false"
fi
assert_equals "true" "$metadata_valid" "Generated metadata satisfies core contract"

module_name=$(jq -r '.module' "$METADATA_FILE")
client_uri=$(jq -r '.client.uri' "$METADATA_FILE")
clash_type=$(jq -r '.client.clash.type' "$METADATA_FILE")
firewall_port=$(jq -r '.firewall[0].port' "$METADATA_FILE")

assert_equals "xray-reality" "$module_name" "Metadata module name is stable"
assert_equals "vless" "$clash_type" "Metadata exposes Clash-compatible protocol type"
assert_equals "8443" "$firewall_port" "Metadata declares required firewall port"
assert_equals "xray" "$(jq -r '.systemd.services[0]' "$METADATA_FILE")" "Xray Reality metadata declares service"

case "$client_uri" in
    vless://*203.0.113.10:8443*security=reality*)
        uri_ok="true"
        ;;
    *)
        uri_ok="false"
        ;;
esac
assert_equals "true" "$uri_ok" "Metadata exports Reality client URI"

if rg -q "/etc/trojan-go|v2ray_path|trojan_path" "$PROJECT_ROOT/scripts/protocols/xray-reality"; then
    isolated="false"
else
    isolated="true"
fi
assert_equals "true" "$isolated" "Xray Reality module does not depend on Trojan state paths"

cat > "$SS_FIXTURE_DIR/config.json" <<'JSON'
{
  "server": ["0.0.0.0", "::0"],
  "server_port": 8388,
  "password": "ss-password-fixture",
  "timeout": 60,
  "method": "chacha20-ietf-poly1305"
}
JSON

EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_PUBLIC_IP="203.0.113.10" \
SHADOWSOCKS_CONFIG_DIR="$SS_FIXTURE_DIR" \
    bash "$PROJECT_ROOT/scripts/protocols/shadowsocks/export.sh"

SS_METADATA_FILE="$STATE_DIR/modules/shadowsocks/metadata.json"
assert_equals "true" "$([ -f "$SS_METADATA_FILE" ] && echo true || echo false)" "Shadowsocks export writes module metadata"

if metadata_validate_file "$SS_METADATA_FILE"; then
    ss_metadata_valid="true"
else
    ss_metadata_valid="false"
fi
assert_equals "true" "$ss_metadata_valid" "Shadowsocks metadata satisfies core contract"
assert_equals "ss" "$(jq -r '.client.clash.type' "$SS_METADATA_FILE")" "Shadowsocks metadata exposes Clash type"
assert_equals "8388" "$(jq -r '.firewall[0].port' "$SS_METADATA_FILE")" "Shadowsocks metadata declares firewall port"
assert_equals "shadowsocks-libev-server" "$(jq -r '.systemd.services[0]' "$SS_METADATA_FILE")" "Shadowsocks metadata declares service"

cat > "$WG_FIXTURE_DIR/clients/client1.conf" <<'CONF'
[Interface]
PrivateKey = client-private+key=
Address = 10.0.0.2/32
DNS = 1.1.1.1, 8.8.8.8
MTU = 1360

[Peer]
PublicKey = server-public+key=
PresharedKey = pre-shared+key=
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CONF

EASYNET_STATE_DIR="$STATE_DIR" \
WG_DIR="$WG_FIXTURE_DIR" \
CLIENT_CONFIG_DIR="$WG_FIXTURE_DIR/clients" \
    bash "$PROJECT_ROOT/scripts/protocols/wireguard/export.sh"

WG_METADATA_FILE="$STATE_DIR/modules/wireguard/metadata.json"
assert_equals "true" "$([ -f "$WG_METADATA_FILE" ] && echo true || echo false)" "WireGuard export writes module metadata"

if metadata_validate_file "$WG_METADATA_FILE"; then
    wg_metadata_valid="true"
else
    wg_metadata_valid="false"
fi
assert_equals "true" "$wg_metadata_valid" "WireGuard metadata satisfies core contract"
assert_equals "wireguard" "$(jq -r '.client.clash.type' "$WG_METADATA_FILE")" "WireGuard metadata exposes Clash type"
assert_equals "51820" "$(jq -r '.firewall[0].port' "$WG_METADATA_FILE")" "WireGuard metadata declares firewall port"
assert_equals "wg-quick@wg0" "$(jq -r '.systemd.services[0]' "$WG_METADATA_FILE")" "WireGuard metadata declares service"

if rg -q "/etc/trojan-go|v2ray_path|trojan_path" "$PROJECT_ROOT/scripts/protocols/shadowsocks" "$PROJECT_ROOT/scripts/protocols/wireguard"; then
    migrated_modules_isolated="false"
else
    migrated_modules_isolated="true"
fi
assert_equals "true" "$migrated_modules_isolated" "Migrated SS/WG modules do not depend on Trojan state paths"

cat > "$TROJAN_FIXTURE_DIR/config.json" <<'JSON'
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["trojan-password-fixture"],
  "ssl": {
    "cert": "/etc/ssl/trojan-go/fullchain.crt",
    "key": "/etc/ssl/trojan-go/private.key",
    "sni": "proxy.example.com",
    "fallback_port": 80
  },
  "websocket": {
    "enabled": true,
    "path": "/abcdef12",
    "host": "proxy.example.com"
  }
}
JSON

EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_PUBLIC_IP="203.0.113.10" \
TROJAN_CONFIG_DIR="$TROJAN_FIXTURE_DIR" \
    bash "$PROJECT_ROOT/scripts/protocols/trojan-go/export.sh"

TROJAN_METADATA_FILE="$STATE_DIR/modules/trojan-go/metadata.json"
assert_equals "true" "$([ -f "$TROJAN_METADATA_FILE" ] && echo true || echo false)" "Trojan-Go export writes module metadata"

if metadata_validate_file "$TROJAN_METADATA_FILE"; then
    trojan_metadata_valid="true"
else
    trojan_metadata_valid="false"
fi
assert_equals "true" "$trojan_metadata_valid" "Trojan-Go metadata satisfies core contract"
assert_equals "trojan" "$(jq -r '.client.clash.type' "$TROJAN_METADATA_FILE")" "Trojan-Go metadata exposes Clash type"
assert_equals "443" "$(jq -r '.firewall[0].port' "$TROJAN_METADATA_FILE")" "Trojan-Go metadata declares firewall port"
assert_equals "trojan-go" "$(jq -r '.systemd.services[0]' "$TROJAN_METADATA_FILE")" "Trojan-Go metadata declares service"

cat > "$TROJAN_FIXTURE_DIR/config.json" <<'JSON'
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": 4444,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["trojan-password-fixture"],
  "ssl": {
    "cert": "/etc/ssl/easynet-edge/fullchain.crt",
    "key": "/etc/ssl/easynet-edge/private.key",
    "sni": "proxy.example.com",
    "fallback_port": 80
  },
  "websocket": {
    "enabled": true,
    "path": "/edgepath",
    "host": "proxy.example.com"
  }
}
JSON

EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_PUBLIC_IP="203.0.113.10" \
EASYNET_TROJAN_PUBLIC_PORT="443" \
TROJAN_CONFIG_DIR="$TROJAN_FIXTURE_DIR" \
    bash "$PROJECT_ROOT/scripts/protocols/trojan-go/export.sh"

assert_equals "4444" "$(jq -r '.port' "$TROJAN_METADATA_FILE")" "Trojan-Go backend metadata records private listener port"
assert_equals "443" "$(jq -r '.publicPort' "$TROJAN_METADATA_FILE")" "Trojan-Go backend metadata records public Edge port"
assert_equals "443" "$(jq -r '.client.clash.port' "$TROJAN_METADATA_FILE")" "Trojan-Go backend Clash metadata uses public Edge port"
assert_equals "0" "$(jq -r '.firewall | length' "$TROJAN_METADATA_FILE")" "Trojan-Go backend does not expose private port through firewall metadata"

if rg -q "v2ray_path|/usr/local/etc/v2ray|/usr/local/bin/v2ray" "$PROJECT_ROOT/scripts/protocols/trojan-go"; then
    trojan_protocol_isolated="false"
else
    trojan_protocol_isolated="true"
fi
assert_equals "true" "$trojan_protocol_isolated" "Trojan-Go protocol module does not depend on V2Ray state"

cat > "$V2RAY_FIXTURE_DIR/config.json" <<'JSON'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 4443,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "22222222-2222-4222-8222-222222222222",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/v2fixture"
        }
      }
    }
  ]
}
JSON
echo "proxy.example.com" > "$V2RAY_FIXTURE_DIR/domain.txt"

EASYNET_STATE_DIR="$STATE_DIR" \
V2RAY_CONFIG_DIR="$V2RAY_FIXTURE_DIR" \
EASYNET_V2RAY_PUBLIC_PORT="443" \
    bash "$PROJECT_ROOT/scripts/protocols/v2ray/export.sh"

V2RAY_METADATA_FILE="$STATE_DIR/modules/v2ray/metadata.json"
assert_equals "true" "$([ -f "$V2RAY_METADATA_FILE" ] && echo true || echo false)" "V2Ray export writes module metadata"

if metadata_validate_file "$V2RAY_METADATA_FILE"; then
    v2ray_metadata_valid="true"
else
    v2ray_metadata_valid="false"
fi
assert_equals "true" "$v2ray_metadata_valid" "V2Ray metadata satisfies core contract"
assert_equals "vmess" "$(jq -r '.client.clash.type' "$V2RAY_METADATA_FILE")" "V2Ray metadata exposes Clash type"
assert_equals "4443" "$(jq -r '.firewall[0].port' "$V2RAY_METADATA_FILE")" "V2Ray metadata declares backend firewall port"
assert_equals "v2ray" "$(jq -r '.systemd.services[0]' "$V2RAY_METADATA_FILE")" "V2Ray metadata declares service"

if rg -q "/etc/trojan-go|trojan_path|v2ray_path" "$PROJECT_ROOT/scripts/protocols/v2ray"; then
    v2ray_protocol_isolated="false"
else
    v2ray_protocol_isolated="true"
fi
assert_equals "true" "$v2ray_protocol_isolated" "V2Ray protocol module does not depend on Trojan state"

cat > "$HYSTERIA2_FIXTURE_DIR/easynet.env" <<'ENV'
HYSTERIA2_DOMAIN=proxy.example.com
HYSTERIA2_PORT=443
HYSTERIA2_PASSWORD=hysteria-password-fixture
HYSTERIA2_OBFS_PASSWORD=hysteria-obfs-fixture
HYSTERIA2_SNI=proxy.example.com
ENV

EASYNET_STATE_DIR="$STATE_DIR" \
HYSTERIA2_ENV_FILE="$HYSTERIA2_FIXTURE_DIR/easynet.env" \
    bash "$PROJECT_ROOT/scripts/protocols/hysteria2/export.sh"

HYSTERIA2_METADATA_FILE="$STATE_DIR/modules/hysteria2/metadata.json"
assert_equals "true" "$([ -f "$HYSTERIA2_METADATA_FILE" ] && echo true || echo false)" "Hysteria2 export writes module metadata"

if metadata_validate_file "$HYSTERIA2_METADATA_FILE"; then
    hysteria2_metadata_valid="true"
else
    hysteria2_metadata_valid="false"
fi
assert_equals "true" "$hysteria2_metadata_valid" "Hysteria2 metadata satisfies core contract"
assert_equals "hysteria2" "$(jq -r '.client.clash.type' "$HYSTERIA2_METADATA_FILE")" "Hysteria2 metadata exposes Clash type"
assert_equals "443" "$(jq -r '.firewall[0].port' "$HYSTERIA2_METADATA_FILE")" "Hysteria2 metadata declares UDP firewall port"
assert_equals "udp" "$(jq -r '.firewall[0].proto' "$HYSTERIA2_METADATA_FILE")" "Hysteria2 firewall rule uses UDP"
assert_equals "hysteria-server.service" "$(jq -r '.systemd.services[0]' "$HYSTERIA2_METADATA_FILE")" "Hysteria2 metadata declares service"

if rg -q "/etc/trojan-go|v2ray_path|trojan_path|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/protocols/hysteria2"; then
    hysteria2_protocol_isolated="false"
else
    hysteria2_protocol_isolated="true"
fi
assert_equals "true" "$hysteria2_protocol_isolated" "Hysteria2 protocol module is isolated from legacy state paths"

if rg -q "配置二维码" "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh" && rg -q 'qrencode -t utf8 "\$config_url"' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"; then
    hysteria2_qr_output="true"
else
    hysteria2_qr_output="false"
fi
assert_equals "true" "$hysteria2_qr_output" "Hysteria2 deploy prints QR code for client URI"

WEB_ROOT="$TMP_DIR/web"
EASYNET_STATE_DIR="$STATE_DIR" \
EASYNET_WEB_ROOT="$WEB_ROOT" \
EASYNET_PUBLIC_IP="203.0.113.10" \
    bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null

clash_file="$WEB_ROOT/clash"
sub_file="$WEB_ROOT/sub"

assert_equals "true" "$([ -f "$clash_file" ] && echo true || echo false)" "Subscription generator writes Clash file from metadata"
assert_equals "true" "$([ -f "$sub_file" ] && echo true || echo false)" "Subscription generator writes URI subscription from metadata"

if rg -q "EasyNet-Reality" "$clash_file" && rg -q "reality-opts" "$clash_file" && rg -q "EasyNet-SS" "$clash_file" && rg -q "EasyNet-WG" "$clash_file" && rg -q "EasyNet-Trojan" "$clash_file" && rg -q "EasyNet-V2Ray" "$clash_file" && rg -q "EasyNet-Hysteria2" "$clash_file"; then
    clash_ok="true"
else
    clash_ok="false"
fi
assert_equals "true" "$clash_ok" "Subscription Clash output includes metadata nodes"

test_end
