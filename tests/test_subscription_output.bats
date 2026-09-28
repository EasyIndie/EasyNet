#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export TMP_DIR=$(mktemp -d)
    export STATE_DIR="$TMP_DIR/state"
    export WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/modules/xray-reality" "$STATE_DIR/modules/shadowsocks" "$STATE_DIR/modules/wireguard" "$STATE_DIR/modules/hysteria2"

    echo "example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" > "$STATE_DIR/exposure/edge/port.txt"
    echo "/s/aaaa1111bbbb2222cccc3333dddd4444" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"

    cat > "$STATE_DIR/modules/xray-reality/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://uuid-1@10.0.0.1:8443#EasyNet-Reality","clash":{"name":"EasyNet-Reality","type":"vless","server":"10.0.0.1","port":8443,"uuid":"uuid-1111-1111-1111-111111111111","network":"tcp","flow":"xtls-rprx-vision","servername":"www.microsoft.com","client-fingerprint":"chrome","reality-opts":{"public-key":"pk","short-id":"sid"}}}}
JSON
    cat > "$STATE_DIR/modules/shadowsocks/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"shadowsocks","enabled":true,"protocol":"ss","port":8388,"client":{"uri":"ss://cipher:pass@10.0.0.1:8388#EasyNet-SS","clash":{"name":"EasyNet-SS","type":"ss","server":"10.0.0.1","port":8388,"cipher":"aes-256-gcm","password":"ss-password"}}}
JSON
    cat > "$STATE_DIR/modules/wireguard/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"wireguard","enabled":true,"protocol":"wireguard","port":51820,"client":{"uri":"wg://pk@10.0.0.1:51820#EasyNet-WG","clash":{"name":"EasyNet-WG","type":"wireguard","server":"10.0.0.1","port":51820,"ip":"10.0.0.2/32","private-key":"cpk","public-key":"spk","pre-shared-key":"psk","mtu":1360,"dns":["1.1.1.1"]}}}
JSON
    cat > "$STATE_DIR/modules/hysteria2/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","enabled":true,"protocol":"hysteria2","port":443,"client":{"uri":"hysteria2://pass@example.com:443#EasyNet-Hysteria2","clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"example.com","port":443,"password":"hp","sni":"example.com","skip-cert-verify":false,"obfs":"salamander","obfs-password":"op","up":"100 Mbps","down":"100 Mbps"}}}
JSON

    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true
}

teardown() {
    rm -rf "$TMP_DIR"
}

# -- File existence --

@test "URI subscription file is non-empty" {
    [ -s "$WEB_ROOT/sub" ]
}

@test "Clash config file exists" {
    [ -s "$WEB_ROOT/clash" ]
}

@test "sing-box config file exists" {
    [ -s "$WEB_ROOT/singbox" ]
}

# -- Clash config structure --

@test "Clash config has mixed-port" {
    grep -q "mixed-port: 7890" "$WEB_ROOT/clash"
}

@test "Clash config has mode: rule" {
    grep -q "mode: rule" "$WEB_ROOT/clash"
}

@test "Clash config has Proxy and Auto groups" {
    grep -q "Proxy" "$WEB_ROOT/clash"
    grep -q "Auto" "$WEB_ROOT/clash"
}

@test "Clash proxy includes EasyNet-Reality" {
    grep -q "EasyNet-Reality" "$WEB_ROOT/clash"
}

@test "Clash proxy includes EasyNet-Shadowsocks" {
    grep -q "EasyNet-SS" "$WEB_ROOT/clash"
}

@test "Clash proxy includes EasyNet-WireGuard" {
    grep -q "EasyNet-WG" "$WEB_ROOT/clash"
}

@test "Clash proxy includes EasyNet-Hysteria2" {
    grep -q "EasyNet-Hysteria2" "$WEB_ROOT/clash"
}

@test "Clash vless proxy has reality-opts" {
    grep -q "reality-opts" "$WEB_ROOT/clash"
}

@test "Clash vless proxy retains reality-opts for anti-DPI" {
    grep -q "public-key:" "$WEB_ROOT/clash"
    grep -q "short-id:" "$WEB_ROOT/clash"
}

@test "Clash wireguard proxy has DNS entries" {
    grep -q "dns:" "$WEB_ROOT/clash"
}

@test "Clash hysteria2 proxy has obfs fields" {
    grep -q "salamander" "$WEB_ROOT/clash"
}

# -- Sing-box config structure --

@test "sing-box config has log section" {
    jq -e '.log.level == "info"' "$WEB_ROOT/singbox" >/dev/null
}

@test "sing-box config has expected outbounds (nodes + Proxy + Auto + DIRECT + REJECT)" {
    [ "$(jq '.outbounds | length' "$WEB_ROOT/singbox")" -ge 6 ]
}

@test "sing-box config has vless outbound" {
    jq -e '.outbounds[] | select(.type == "vless")' "$WEB_ROOT/singbox" >/dev/null
}

@test "sing-box config has shadowsocks outbound" {
    jq -e '.outbounds[] | select(.type == "shadowsocks")' "$WEB_ROOT/singbox" >/dev/null
}

@test "sing-box config has hysteria2 outbound" {
    jq -e '.outbounds[] | select(.type == "hysteria2")' "$WEB_ROOT/singbox" >/dev/null
}

@test "sing-box config omits AmneziaWG (unsupported by sing-box)" {
    ! jq -e '.endpoints[]? | select(.type == "wireguard")' "$WEB_ROOT/singbox" >/dev/null 2>&1
    ! jq -e '.outbounds[] | select(.tag == "EasyNet-WG")' "$WEB_ROOT/singbox" >/dev/null 2>&1
    ! jq -e '.route.final as $f | .outbounds[] | select(.tag == "Proxy").outbounds | index("EasyNet-WG")' "$WEB_ROOT/singbox" >/dev/null 2>&1
}

@test "sing-box config has route section" {
    jq -e '.route.final == "Proxy"' "$WEB_ROOT/singbox" >/dev/null
}

@test "Empty metadata dir exits gracefully without error" {
    TMP2=$(mktemp -d)
    run bash "$PROJECT_ROOT/scripts/generate_subscription.sh" \
        EASYNET_STATE_DIR="$TMP2/state" EASYNET_WEB_ROOT="$TMP2/web"
    [ "$status" -eq 0 ]
    rm -rf "$TMP2"
}

@test "Hysteria2 subscription exposes hopping to every client dialect" {
    # sing-box wants server_ports ["start:end"], mihomo wants ports "start-end",
    # and the URI carries the (non-standard but widely understood) porthopping
    # params. All three must agree on the same range.
    local meta="$BATS_TEST_TMPDIR/hy2.json"
    cat > "$meta" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","protocol":"hysteria2","port":443,
 "client":{"uri":"hysteria2://pw@d.example.com:443/?sni=d.example.com&obfs=salamander&obfs-password=o&porthopping=20000-30000&porthopping-interval=30s#EasyNet-Hysteria2",
 "clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"d.example.com","port":443,"password":"pw","sni":"d.example.com","obfs":"salamander","obfs-password":"o","up":"100 Mbps","down":"100 Mbps","hop-range":"20000-30000","hop-interval":"30s","hop-interval-max":"60s"}}}
JSON

    run jq -c -f "$PROJECT_ROOT/scripts/protocols/hysteria2/render_singbox.jq" "$meta"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -c '.server_ports')" = '["20000:30000"]' ]
    [ "$(printf '%s' "$output" | jq -r '.hop_interval')" = "30s" ]
    # Randomised upper bound (sing-box >=1.14 hop_interval_max).
    [ "$(printf '%s' "$output" | jq -r '.hop_interval_max')" = "60s" ]

    run bash "$PROJECT_ROOT/scripts/protocols/hysteria2/render_clash.sh" "$meta"
    [ "$status" -eq 0 ]
    [[ "$output" == *'ports: "20000-30000"'* ]]
    # mihomo 的 hop-interval 是**整数秒**：发 "30s" 会被它当端口范围解析，
    # 报 `invalid range: 30s` 并拒绝整份订阅（真实客户端实测）。
    [[ "$output" == *'hop-interval: 30'* ]]
    [[ "$output" != *'hop-interval: "30s"'* ]]
    # 随机化只加在 sing-box：mihomo 保持单整数（范围方言会打挂 1.19 前的老客户端）。
    [[ "$output" != *'hop-interval: "30-60"'* ]]

    run jq -r '.client.uri' "$meta"
    [[ "$output" == *"porthopping=20000-30000"* ]]
}

@test "Hysteria2 renderers omit hopping fields when hopping is disabled" {
    local meta="$BATS_TEST_TMPDIR/hy2off.json"
    cat > "$meta" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","protocol":"hysteria2","port":443,
 "client":{"uri":"hysteria2://pw@d.example.com:443/","clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"d.example.com","port":443,"password":"pw","sni":"d.example.com","obfs":"salamander","obfs-password":"o","up":"100 Mbps","down":"100 Mbps"}}}
JSON
    run jq -c -f "$PROJECT_ROOT/scripts/protocols/hysteria2/render_singbox.jq" "$meta"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -c 'has("server_ports")')" = "false" ]
    [ "$(printf '%s' "$output" | jq -c 'has("hop_interval")')" = "false" ]
    [ "$(printf '%s' "$output" | jq -c 'has("hop_interval_max")')" = "false" ]

    run bash "$PROJECT_ROOT/scripts/protocols/hysteria2/render_clash.sh" "$meta"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ports:"* ]]
}

@test "Hysteria2 sing-box omits hop_interval_max when equal to hop_interval" {
    # 想回到固定间隔：把 max 设成与基础间隔相同即可（等价于不随机）。
    local meta="$BATS_TEST_TMPDIR/hy2_fixed.json"
    cat > "$meta" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","protocol":"hysteria2","port":443,
 "client":{"clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"d.example.com","port":443,"password":"pw","hop-range":"20000-30000","hop-interval":"30s","hop-interval-max":"30s"}}}
JSON
    run jq -c -f "$PROJECT_ROOT/scripts/protocols/hysteria2/render_singbox.jq" "$meta"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.hop_interval')" = "30s" ]
    [ "$(printf '%s' "$output" | jq -c 'has("hop_interval_max")')" = "false" ]
}

@test "Hysteria2 mihomo hop-interval is always integer seconds (regression)" {
    # 回归：mihomo 只接受整数秒（Clash Verge 曾报 "proxy 1: invalid range: 30s"）。
    # 元数据里存的是 sing-box 方言 "30s"，渲染 mihomo 时必须换算。
    render_with_interval() {
        local meta="$BATS_TEST_TMPDIR/hy2_$1.json"
        cat > "$meta" <<JSON
{"schemaVersion":1,"module":"hysteria2","protocol":"hysteria2","port":443,
 "client":{"clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"d.example.com","port":443,"password":"pw","hop-range":"20000-30000","hop-interval":"$1"}}}
JSON
        bash "$PROJECT_ROOT/scripts/protocols/hysteria2/render_clash.sh" "$meta"
    }

    [ "$(render_with_interval 30s | awk '/hop-interval/{print $2}')" = "30" ]
    [ "$(render_with_interval 30 | awk '/hop-interval/{print $2}')" = "30" ]
    [ "$(render_with_interval 1m | awk '/hop-interval/{print $2}')" = "60" ]
    # 无法识别的值：省略字段（mihomo 用自己的默认值），绝不把非法值写进去
    run render_with_interval bogus
    [ "$status" -eq 0 ]
    [[ "$output" == *'ports: "20000-30000"'* ]]
    [[ "$output" != *"hop-interval"* ]]
    # 任何情况下写出去的 hop-interval 值都必须是不带单位的纯整数
    for v in 30s 1m 1h bogus 30; do
        local rendered value
        rendered="$(render_with_interval "$v")"
        value="$(printf '%s\n' "$rendered" | awk '/hop-interval/{print $2}')"
        if [ -n "$value" ] && [[ ! "$value" =~ ^[0-9]+$ ]]; then
            echo "# hop-interval 值非法（应为纯整数秒）: $value" >&3
            return 1
        fi
    done
    return 0
}
