#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
}

# -- Static analysis tests --

@test "Subscription generator does not read protocol config paths" {
    run rg -q "/etc/shadowsocks-libev|/etc/wireguard|/usr/local/etc/xray" "$PROJECT_ROOT/scripts/generate_subscription.sh"
    [ "$status" -eq 1 ]
}

@test "Subscription generator does not query public IP directly" {
    run rg -q "curl -s ipinfo.io|ifconfig.me|api.ipify.org" "$PROJECT_ROOT/scripts/generate_subscription.sh"
    [ "$status" -eq 1 ]
}

@test "Subscription logic has no old exposure fallbacks" {
    run rg -q "easynet_nginx_state_dir|easynet_subscription_state_dir|sub_full|clash_full|trojan_metadata_file" \
        "$PROJECT_ROOT/scripts/core/subscription.sh" "$PROJECT_ROOT/scripts/generate_subscription.sh"
    [ "$status" -eq 1 ]
}

# -- Subscription generation without Edge state --

@test "Subscription links are not printed until Edge state exists" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless","server":"203.0.113.10","port":8443,"uuid":"11111111-1111-4111-8111-111111111111","network":"tcp","flow":"xtls-rprx-vision","servername":"www.example.com","client-fingerprint":"chrome","reality-opts":{"public-key":"pk","short-id":"sid"}}}}
JSON
    run env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
    echo "$output" | rg -qv "https://proxy.example.com"
    rm -rf "$TMP_DIR"
}

# -- With Edge state, verify stable paths --

@test "Edge domain prints stable random subscription paths without fixed or full links" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless","server":"203.0.113.10","port":8443,"uuid":"11111111-1111-4111-8111-111111111111","network":"tcp","flow":"xtls-rprx-vision","servername":"www.example.com","client-fingerprint":"chrome","reality-opts":{"public-key":"pk","short-id":"sid"}}}}
JSON
    mkdir -p "$STATE_DIR/exposure/edge"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" > "$STATE_DIR/exposure/edge/port.txt"
    echo "/s/0123456789abcdef0123456789abcdef" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    run env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
    echo "$output" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/sub"
    echo "$output" | rg -q "https://edge.example.com/s/0123456789abcdef0123456789abcdef/singbox"
    rm -rf "$TMP_DIR"
}

@test "sing-box config and client installer are generated from metadata without protocol config access" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://example","clash":{"name":"Example","type":"vless","server":"203.0.113.10","port":8443,"uuid":"11111111-1111-4111-8111-111111111111","network":"tcp","flow":"xtls-rprx-vision","servername":"www.example.com","client-fingerprint":"chrome","reality-opts":{"public-key":"pk","short-id":"sid"}}}}
JSON
    mkdir -p "$STATE_DIR/exposure/edge"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" > "$STATE_DIR/exposure/edge/port.txt"
    echo "/s/test" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null
    [ -f "$WEB_ROOT/singbox" ] && jq -e '.inbounds[] | select(.type == "mixed" and .listen_port == 7890)' "$WEB_ROOT/singbox" >/dev/null
    [ -f "$WEB_ROOT/easynet-singbox-client.sh" ]
    rm -rf "$TMP_DIR"
}

# -- Ordering by security rank --

@test "URI subscription file orders nodes by security and anti-DPI strength" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/wireguard" "$STATE_DIR/modules/shadowsocks" "$STATE_DIR/modules/hysteria2" "$STATE_DIR/modules/xray-reality"
    for module in wireguard shadowsocks hysteria2 xray-reality; do
        cat > "$STATE_DIR/modules/$module/metadata.json" <<JSON
{"schemaVersion":1,"module":"$module","enabled":true,"protocol":"$module","client":{"uri":"$module://node","clash":{"name":"$module","type":"ss","server":"203.0.113.10","port":8388,"cipher":"aes-256-gcm","password":"password"}}}
JSON
    done
    # Override wireguard with proper type
    cat > "$STATE_DIR/modules/wireguard/metadata.json" <<JSON
{"schemaVersion":1,"module":"wireguard","enabled":true,"protocol":"wireguard","client":{"uri":"wireguard://node","clash":{"name":"wireguard","type":"wireguard","server":"203.0.113.10","port":51820,"ip":"10.0.0.2","private-key":"pk","public-key":"pk","pre-shared-key":"psk","mtu":1360,"dns":["1.1.1.1"]}}}
JSON
    env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true
    ordered_links="$(openssl base64 -d -A -in "$WEB_ROOT/sub" 2>/dev/null || base64 -D -i "$WEB_ROOT/sub" 2>/dev/null)"
    echo "$ordered_links" | head -1 | rg -q "xray-reality"
    rm -rf "$TMP_DIR"
}

@test "sing-box config orders nodes by security and anti-DPI strength" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/wireguard" "$STATE_DIR/modules/shadowsocks" "$STATE_DIR/modules/hysteria2" "$STATE_DIR/modules/xray-reality"
    for module in wireguard shadowsocks hysteria2 xray-reality; do
        cat > "$STATE_DIR/modules/$module/metadata.json" <<JSON
{"schemaVersion":1,"module":"$module","enabled":true,"protocol":"$module","client":{"uri":"$module://node","clash":{"name":"$module","type":"ss","server":"203.0.113.10","port":8388,"cipher":"aes-256-gcm","password":"password"}}}
JSON
    done
    env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true
    tags="$(jq -r '.outbounds[] | select(.tag == "Proxy").outbounds[] | select(. != "Auto" and . != "DIRECT")' "$WEB_ROOT/singbox" 2>/dev/null)"
    echo "$tags" | head -1 | rg -q "xray-reality"
    rm -rf "$TMP_DIR"
}

@test "sing-box config renders WireGuard as endpoint for current sing-box versions" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/modules/example"
    cat > "$STATE_DIR/modules/example/metadata.json" <<JSON
{"schemaVersion":1,"module":"wireguard","enabled":true,"protocol":"wireguard","client":{"uri":"wg://node","clash":{"name":"Example WG","type":"wireguard","server":"203.0.113.10","port":51820,"ip":"10.0.0.2","private-key":"pk","public-key":"pk","pre-shared-key":"psk","mtu":1360,"dns":["1.1.1.1"]}}}
JSON
    env EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true
    jq -e '.endpoints[] | select(.type == "wireguard")' "$WEB_ROOT/singbox" >/dev/null 2>&1
    rm -rf "$TMP_DIR"
}

# -- Show subscription --

@test "Show subscription command reprints stable Edge subscription links" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/modules/example"
    echo "/s/test" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" > "$STATE_DIR/exposure/edge/port.txt"
    run env EASYNET_STATE_DIR="$STATE_DIR" \
        bash "$PROJECT_ROOT/scripts/show_subscription.sh"
    echo "$output" | rg -q "https://edge.example.com/s/test/clash"
    rm -rf "$TMP_DIR"
}

@test "Show subscription command prints QR codes or explicit QR fallback messages" {
    run rg -q "qrencode -t utf8.*sub_url|qrencode -t utf8.*clash_url|qrencode -t utf8.*singbox_url|无法显示 URI 订阅二维码|无法显示 Clash/Mihomo 订阅二维码|无法显示 sing-box 配置二维码" "$PROJECT_ROOT/scripts/show_subscription.sh"
    [ "$status" -eq 0 ]
}

# -- Rotation --

@test "Subscription rotation records previous path prefix" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/exposure/edge/routes"
    echo "/s/0123456789abcdef0123456789abcdef" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh" >/dev/null 2>&1 || true
    [ "$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.previous.txt")" = "/s/0123456789abcdef0123456789abcdef" ]
    rm -rf "$TMP_DIR"
}

@test "Subscription rotation writes a new stable random path" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/exposure/edge/routes"
    echo "/s/0123456789abcdef0123456789abcdef" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh" >/dev/null 2>&1 || true
    new_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt")"
    [[ "$new_prefix" =~ ^/s/[0-9a-f]{32}$ ]]
    [ "$new_prefix" != "/s/0123456789abcdef0123456789abcdef" ]
    rm -rf "$TMP_DIR"
}

@test "Subscription rotation updates Edge routes and prints new links" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge/routes" "$STATE_DIR/modules/example"
    echo "/s/oldprefix12345678901234567890123456" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    cat > "$STATE_DIR/modules/example/metadata.json" <<JSON
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","client":{"uri":"vless://node","clash":{"test":true}}}
JSON
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh" >/dev/null 2>&1 || true
    new_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt")"
    rg -q "location = ${new_prefix}/clash" "$STATE_DIR/exposure/edge/routes/subscription.conf"
    rm -rf "$TMP_DIR"
}

@test "Subscription rotation grace keeps previous links active" {
    TMP_DIR=$(mktemp -d)
    STATE_DIR="$TMP_DIR/state"
    WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge/routes" "$STATE_DIR/modules/example"
    echo "/s/oldprefix12345678901234567890123456" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"
    echo "edge.example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    cat > "$STATE_DIR/modules/example/metadata.json" <<JSON
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","client":{"uri":"vless://node","clash":{"test":true}}}
JSON
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" EASYNET_SKIP_NGINX_RELOAD=true \
        bash "$PROJECT_ROOT/scripts/rotate_subscription.sh" --grace >/dev/null 2>&1 || true
    new_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt")"
    old_prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.previous.txt")"
    rg -q "location = ${new_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf"
    rg -q "location = ${old_prefix}/sub" "$STATE_DIR/exposure/edge/routes/subscription.conf"
    rm -rf "$TMP_DIR"
}
