#!/usr/bin/env bats
# 用**真实客户端二进制**校验我们生成的订阅。
#
# 这是 0.0.13 事故（mihomo 报 `invalid range: 30s` 拒绝整份订阅）之后补的闸门：
# 客户端渲染字段的名称/类型/单位只能由真二进制判定，字符串断言只能防回归。
#
# 本地无二进制时会 skip（可用 scripts/client_check.sh fetch 准备）；
# CI 里设 EASYNET_REQUIRE_CLIENT_CHECK=1，工具不可用即失败 —— 不允许静默通过。

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export PROJECT_ROOT
    export TMP_DIR="$(mktemp -d)"
    export STATE_DIR="$TMP_DIR/state"
    export WEB_ROOT="$TMP_DIR/web"
    export EASYNET_CLIENT_BIN_DIR="${EASYNET_CLIENT_BIN_DIR:-$TMP_DIR/client-bin}"

    mkdir -p "$STATE_DIR/exposure/edge" \
        "$STATE_DIR/modules/xray-reality" "$STATE_DIR/modules/shadowsocks" \
        "$STATE_DIR/modules/wireguard" "$STATE_DIR/modules/hysteria2"

    echo "example.com" > "$STATE_DIR/exposure/edge/domain.txt"
    echo "https" > "$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" > "$STATE_DIR/exposure/edge/port.txt"
    echo "/s/aaaa1111bbbb2222cccc3333dddd4444" > "$STATE_DIR/exposure/edge/subscription_path_prefix.txt"

    cat > "$STATE_DIR/modules/xray-reality/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"xray-reality","enabled":true,"protocol":"vless","port":8443,"client":{"uri":"vless://11111111-1111-1111-1111-111111111111@example.com:8443?encryption=none&security=reality&sni=example.com&fp=chrome&pbk=0Eg1f6-qvU2SB1aEZQ925p-UP0g9IoWE-Y4BsiQQ31Y&sid=0123456789abcdef&flow=xtls-rprx-vision#EasyNet-Reality","clash":{"name":"EasyNet-Reality","type":"vless","server":"example.com","port":8443,"uuid":"11111111-1111-1111-1111-111111111111","network":"tcp","flow":"xtls-rprx-vision","servername":"example.com","client-fingerprint":"chrome","reality-opts":{"public-key":"0Eg1f6-qvU2SB1aEZQ925p-UP0g9IoWE-Y4BsiQQ31Y","short-id":"0123456789abcdef"}}}}
JSON
    cat > "$STATE_DIR/modules/shadowsocks/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"shadowsocks","enabled":true,"protocol":"ss","port":8388,"client":{"uri":"ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMTExMTExMTEx@example.com:8388#EasyNet-SS","clash":{"name":"EasyNet-SS","type":"ss","server":"example.com","port":8388,"cipher":"aes-256-gcm","password":"password1111111111"}}}
JSON
    cat > "$STATE_DIR/modules/wireguard/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"wireguard","enabled":true,"protocol":"wireguard","port":51820,"client":{"uri":"wg://spk@example.com:51820#EasyNet-WG","clash":{"name":"EasyNet-WG","type":"wireguard","server":"example.com","port":51820,"ip":"10.0.0.2/32","private-key":"mKOu5BEOCxmEAWoyj8HBVgvDkTpuMgyw25YgEh1aGkY=","public-key":"IrKSvjJmLYhyoYPPiwqnldw8nUMnabv6EXrYHaDdUUg=","pre-shared-key":"wAEk26NALLNm7QbXY82CJ3Y0XrLgly3VIp9e9sQ3BlA=","mtu":1280,"dns":["1.1.1.1"],"amnezia-wg-option":{"jc":4,"jmin":40,"jmax":70,"s1":30,"s2":40,"h1":100,"h2":200,"h3":300,"h4":400}}}}
JSON
    # 端口跳跃：元数据里存的是 sing-box 方言的 "30s"（mihomo 需要整数秒，渲染时换算）
    cat > "$STATE_DIR/modules/hysteria2/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","enabled":true,"protocol":"hysteria2","port":443,"client":{"uri":"hysteria2://password1111111111@example.com:443/?sni=example.com&obfs=salamander&obfs-password=obfspass&porthopping=20000-30000&porthopping-interval=30s#EasyNet-Hysteria2","clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"example.com","port":443,"password":"password1111111111","sni":"example.com","obfs":"salamander","obfs-password":"obfspass","up":"100 Mbps","down":"100 Mbps","hop-range":"20000-30000","hop-interval":"30s"}}}
JSON

    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true
}

teardown() {
    rm -rf "$TMP_DIR"
}

# 工具可用性：CI 用 EASYNET_REQUIRE_CLIENT_CHECK=1 强制；本地缺失则 skip。
skip_unless_client() {
    local tool="$1"
    if bash "$PROJECT_ROOT/scripts/client_check.sh" require "$tool" >/dev/null 2>&1; then
        return 0
    fi
    if [ "${EASYNET_REQUIRE_CLIENT_CHECK:-}" = "1" ]; then
        echo "# EASYNET_REQUIRE_CLIENT_CHECK=1 但 $tool 不可用" >&3
        return 1
    fi
    skip "本机无 $tool 二进制（可运行 scripts/client_check.sh fetch $tool 准备）"
}

@test "订阅文件生成成功（前置条件）" {
    [ -s "$WEB_ROOT/clash" ]
    [ -s "$WEB_ROOT/singbox" ]
}

@test "生成的 Clash 订阅能被真实 mihomo 接受（四协议 + 端口跳跃）" {
    skip_unless_client mihomo
    run bash "$PROJECT_ROOT/scripts/client_check.sh" check-clash "$WEB_ROOT/clash"
    [ "$status" -eq 0 ]
}

@test "生成的 sing-box 订阅能被真实 sing-box 接受" {
    skip_unless_client singbox
    run bash "$PROJECT_ROOT/scripts/client_check.sh" check-singbox "$WEB_ROOT/singbox"
    [ "$status" -eq 0 ]
}

@test "mihomo 的 hop-interval 各种输入形态都被接受" {
    skip_unless_client mihomo
    local interval out
    for interval in "30s" "30" "1m" "1h"; do
        out="$TMP_DIR/clash-$interval.yaml"
        cat > "$TMP_DIR/hy2-$interval.json" <<JSON
{"module":"hysteria2","client":{"clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"example.com","port":443,"password":"pw","sni":"example.com","obfs":"salamander","obfs-password":"op","up":"100 Mbps","down":"100 Mbps","hop-range":"20000-30000","hop-interval":"$interval"}}}
JSON
        {
            printf 'mixed-port: 7890\nmode: rule\nproxies:\n'
            bash "$PROJECT_ROOT/scripts/protocols/hysteria2/render_clash.sh" "$TMP_DIR/hy2-$interval.json"
            printf 'rules:\n  - MATCH,DIRECT\n'
        } > "$out"
        run bash "$PROJECT_ROOT/scripts/client_check.sh" check-clash "$out"
        [ "$status" -eq 0 ]
    done
}

@test "校验器本身有效：hop-interval 写成 \"30s\" 必须被 mihomo 拒绝（0.0.13 事故哨兵）" {
    skip_unless_client mihomo
    # 直接构造 0.0.13 之前的错误输出：把 sing-box 方言原样写给 mihomo
    cat > "$TMP_DIR/broken.yaml" <<'YAML'
mixed-port: 7890
mode: rule
proxies:
  - name: "EasyNet-Hysteria2"
    type: hysteria2
    server: example.com
    port: 443
    password: "pw"
    obfs: "salamander"
    obfs-password: "op"
    ports: "20000-30000"
    hop-interval: "30s"
rules:
  - MATCH,DIRECT
YAML
    run bash "$PROJECT_ROOT/scripts/client_check.sh" check-clash "$TMP_DIR/broken.yaml"
    [ "$status" -ne 0 ]
}

@test "校验器本身有效：非法 sing-box 配置必须被拒绝" {
    skip_unless_client singbox
    jq '.outbounds[0].type = "not-a-real-protocol"' "$WEB_ROOT/singbox" > "$TMP_DIR/broken.json"
    run bash "$PROJECT_ROOT/scripts/client_check.sh" check-singbox "$TMP_DIR/broken.json"
    [ "$status" -ne 0 ]
}

@test "缓存被篡改时不得信任缓存里的二进制（SHA256 防替换）" {
    export EASYNET_CLIENT_BIN_DIR="$TMP_DIR/poisoned"
    mkdir -p "$EASYNET_CLIENT_BIN_DIR"
    local asset
    asset="$(bash -c 'source "'"$PROJECT_ROOT"'/scripts/core/pins.sh"; easynet_client_pin_asset mihomo')"
    [ -n "$asset" ] || skip "当前平台未 pin mihomo"
    # 伪造"已被替换"的资产 + 一个看起来可用的假二进制
    printf 'not-the-real-archive' > "$EASYNET_CLIENT_BIN_DIR/$asset"
    printf '#!/bin/sh\necho fake-mihomo\n' > "$EASYNET_CLIENT_BIN_DIR/mihomo"
    chmod +x "$EASYNET_CLIENT_BIN_DIR/mihomo"

    run bash -c "source '""$PROJECT_ROOT""/scripts/client_check.sh'; client_check_resolve mihomo"
    # 允许解析到别处的真二进制，但**绝不能**把被污染的缓存当成可用工具
    if [ "$status" -eq 0 ]; then
        [ "$output" != "$EASYNET_CLIENT_BIN_DIR/mihomo" ]
    fi
}
