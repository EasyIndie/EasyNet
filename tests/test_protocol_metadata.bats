#!/usr/bin/env bats

load test_helper

setup_file() {
    export TMP_DIR=$(mktemp -d)
    export STATE_DIR="$TMP_DIR/state"
    XRAY_FIXTURE_DIR="$TMP_DIR/xray"
    SS_FIXTURE_DIR="$TMP_DIR/shadowsocks"
    WG_FIXTURE_DIR="$TMP_DIR/wireguard"
    HY2_FIXTURE_DIR="$TMP_DIR/hysteria2"
    mkdir -p "$XRAY_FIXTURE_DIR" "$SS_FIXTURE_DIR" "$WG_FIXTURE_DIR/clients" "$HY2_FIXTURE_DIR"

    # Xray fixture
    cat > "$XRAY_FIXTURE_DIR/config.json" <<'JSON'
{"inbounds":[{"listen":"0.0.0.0","port":8443,"protocol":"vless","settings":{"clients":[{"id":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverNames":["www.example.com"],"shortIds":["aabbccddeeff0011"]}}}]}
JSON
    echo "public-key-fixture" > "$XRAY_FIXTURE_DIR/public.key"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_PUBLIC_IP="203.0.113.10" XRAY_DIR="$XRAY_FIXTURE_DIR" \
        bash "$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts/protocols/xray-reality/export.sh"

    # Shadowsocks fixture
    cat > "$SS_FIXTURE_DIR/config.json" <<'JSON'
{"server":["0.0.0.0","::0"],"server_port":8388,"password":"ss-password-fixture","method":"2022-blake3-aes-256-gcm"}
JSON
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_PUBLIC_IP="203.0.113.10" SHADOWSOCKS_CONFIG_DIR="$SS_FIXTURE_DIR" \
        bash "$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts/protocols/shadowsocks/export.sh"

    # WireGuard fixture
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
    EASYNET_STATE_DIR="$STATE_DIR" WG_DIR="$WG_FIXTURE_DIR" CLIENT_CONFIG_DIR="$WG_FIXTURE_DIR/clients" \
        bash "$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts/protocols/wireguard/export.sh"

    # Hysteria2 fixture
    cat > "$HY2_FIXTURE_DIR/easynet.env" <<'ENV'
HYSTERIA2_DOMAIN=proxy.example.com
HYSTERIA2_PORT=443
HYSTERIA2_PASSWORD=hysteria-password-fixture
HYSTERIA2_OBFS_PASSWORD=hysteria-obfs-fixture
HYSTERIA2_SNI=proxy.example.com
ENV
    EASYNET_STATE_DIR="$STATE_DIR" HYSTERIA2_ENV_FILE="$HY2_FIXTURE_DIR/easynet.env" \
        bash "$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts/protocols/hysteria2/export.sh"

    # Subscription generation
    export WEB_ROOT="$TMP_DIR/web"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" EASYNET_PUBLIC_IP="203.0.113.10" \
        bash "$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts/generate_subscription.sh" >/dev/null

    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."
}

setup() {
    load test_helper
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
}

teardown_file() {
    rm -rf "$TMP_DIR"
}

# --- Xray Reality ---

@test "Xray Reality export writes module metadata" {
    [ -f "$STATE_DIR/modules/xray-reality/metadata.json" ]
}

@test "Generated metadata satisfies core contract" {
    metadata_validate_file "$STATE_DIR/modules/xray-reality/metadata.json"
}

@test "Metadata module name is stable" {
    [ "$(jq -r '.module' "$STATE_DIR/modules/xray-reality/metadata.json")" = "xray-reality" ]
}

@test "Metadata exposes Clash-compatible protocol type" {
    [ "$(jq -r '.client.clash.type' "$STATE_DIR/modules/xray-reality/metadata.json")" = "vless" ]
}

@test "Metadata declares required firewall port" {
    [ "$(jq -r '.firewall[0].port' "$STATE_DIR/modules/xray-reality/metadata.json")" = "8443" ]
}

@test "Xray Reality metadata declares service" {
    [ "$(jq -r '.systemd.services[0]' "$STATE_DIR/modules/xray-reality/metadata.json")" = "xray" ]
}

@test "Metadata exports Reality client URI" {
    uri=$(jq -r '.client.uri' "$STATE_DIR/modules/xray-reality/metadata.json")
    [[ "$uri" == vless://* ]] && [[ "$uri" == *203.0.113.10:8443* ]] && [[ "$uri" == *security=reality* ]]
}

@test "Xray Reality module does not depend on legacy state paths" {
    run rg -q "/etc/trojan-go|v2ray_path|trojan_path" "$PROJECT_ROOT/scripts/protocols/xray-reality"
    [ "$status" -eq 1 ]
}

# --- Shadowsocks ---

@test "Shadowsocks export writes module metadata" {
    [ -f "$STATE_DIR/modules/shadowsocks/metadata.json" ]
}

@test "Shadowsocks metadata satisfies core contract" {
    metadata_validate_file "$STATE_DIR/modules/shadowsocks/metadata.json"
}

@test "Shadowsocks metadata exposes Clash type" {
    [ "$(jq -r '.client.clash.type' "$STATE_DIR/modules/shadowsocks/metadata.json")" = "ss" ]
}

@test "Shadowsocks metadata declares firewall port" {
    [ "$(jq -r '.firewall[0].port' "$STATE_DIR/modules/shadowsocks/metadata.json")" = "8388" ]
}

@test "Shadowsocks metadata declares service" {
    [ "$(jq -r '.systemd.services[0]' "$STATE_DIR/modules/shadowsocks/metadata.json")" = "shadowsocks-rust-server" ]
}

# --- WireGuard ---

@test "WireGuard export writes module metadata" {
    [ -f "$STATE_DIR/modules/wireguard/metadata.json" ]
}

@test "WireGuard metadata satisfies core contract" {
    metadata_validate_file "$STATE_DIR/modules/wireguard/metadata.json"
}

@test "WireGuard metadata exposes Clash type" {
    [ "$(jq -r '.client.clash.type' "$STATE_DIR/modules/wireguard/metadata.json")" = "wireguard" ]
}

@test "WireGuard metadata declares firewall port" {
    [ "$(jq -r '.firewall[0].port' "$STATE_DIR/modules/wireguard/metadata.json")" = "51820" ]
}

@test "WireGuard metadata declares service" {
    [ "$(jq -r '.systemd.services[0]' "$STATE_DIR/modules/wireguard/metadata.json")" = "wg-quick@wg0" ]
}

@test "Migrated SS/WG modules do not depend on legacy state paths" {
    run rg -q "/etc/trojan-go|v2ray_path|trojan_path" "$PROJECT_ROOT/scripts/protocols/shadowsocks" "$PROJECT_ROOT/scripts/protocols/wireguard"
    [ "$status" -eq 1 ]
}

# --- Hysteria2 ---

@test "Hysteria2 export writes module metadata" {
    [ -f "$STATE_DIR/modules/hysteria2/metadata.json" ]
}

@test "Hysteria2 metadata satisfies core contract" {
    metadata_validate_file "$STATE_DIR/modules/hysteria2/metadata.json"
}

@test "Hysteria2 metadata exposes Clash type" {
    [ "$(jq -r '.client.clash.type' "$STATE_DIR/modules/hysteria2/metadata.json")" = "hysteria2" ]
}

@test "Hysteria2 metadata declares UDP firewall port" {
    [ "$(jq -r '.firewall[0].port' "$STATE_DIR/modules/hysteria2/metadata.json")" = "443" ]
}

@test "Hysteria2 firewall rule uses UDP" {
    [ "$(jq -r '.firewall[0].proto' "$STATE_DIR/modules/hysteria2/metadata.json")" = "udp" ]
}

@test "Hysteria2 metadata declares service" {
    [ "$(jq -r '.systemd.services[0]' "$STATE_DIR/modules/hysteria2/metadata.json")" = "hysteria-server.service" ]
}

@test "Hysteria2 protocol module is isolated from legacy state paths" {
    run rg -q "/etc/trojan-go|v2ray_path|trojan_path|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/protocols/hysteria2"
    [ "$status" -eq 1 ]
}

@test "Hysteria2 deploy prints QR code for client URI" {
    rg -q "配置二维码" "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    rg -q 'qrencode -t utf8 "\$config_url"' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
}

@test "Hysteria2 reuses Edge TLS certificate without standalone ACME or provider-specific guidance" {
    rg -q "tls:|cert:|key:" "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    run rg -q "acme:|Cloudflare|橙云" "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    [ "$status" -eq 1 ]
}

@test "Hysteria2 deploy grants config and certificate access to the systemd service user" {
    rg -q "systemctl cat.*HYSTERIA2_SERVICE|chown root.*service_user|chmod 640|chmod 750" "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
}

# --- Subscription generation ---

@test "Subscription generator writes Clash file from metadata" {
    [ -f "$WEB_ROOT/clash" ]
}

@test "Subscription generator writes URI subscription from metadata" {
    [ -f "$WEB_ROOT/sub" ]
}

@test "Subscription Clash output includes metadata nodes" {
    clash_file="$WEB_ROOT/clash"
    rg -q "EasyNet-Reality" "$clash_file"
    rg -q "reality-opts" "$clash_file"
    rg -q "EasyNet-SS" "$clash_file"
    rg -q "EasyNet-WG" "$clash_file"
    rg -q "EasyNet-Hysteria2" "$clash_file"
}
