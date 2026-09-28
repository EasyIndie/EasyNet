#!/usr/bin/env bats
# 伪装站（Edge location / 返回的内容）的自洽性测试
#
# 背景：旧默认是透明反代 https://www.bing.com，探针能直接看出「这是反代」——
#   canonical 指向第三方、Set-Cookie 带 domain=.bing.com、base64 里含第三方 origin、
#   镜像第三方 robots.txt、任意 Host 都返回同一个第三方首页。
# 现在的默认是**自托管静态站**：域名/证书/内容自洽，且按域名确定性随机化。

load test_helper

setup() {
    export DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    export PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export TMP_DIR="$(mktemp -d)"
    export WEB_ROOT="$TMP_DIR/www"
    export STATE_DIR="$TMP_DIR/state"
    source "$PROJECT_ROOT/scripts/core/logging.sh"
    source "$PROJECT_ROOT/scripts/exposure/edge/render_site.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

render() {
    easynet_edge_site_install "$WEB_ROOT" "$1" "$STATE_DIR" "${2:-}"
}

# 允许出现的唯一外部 URL 是内联 SVG 的命名空间（不是网络请求）
assert_no_third_party_urls() {
    local file="$1" offenders
    offenders="$(grep -oE 'https?://[^"'"'"' )]+' "$file" |
        grep -vE '^https?://www\.w3\.org/2000/svg$' |
        grep -vE "^https://[^/]+/?$" || true)"
    if [ -n "$offenders" ]; then
        echo "# 发现第三方 URL: $offenders" >&3
        return 1
    fi
}

@test "默认伪装站不引用任何第三方（无镜像特征）" {
    render "world.example.com"
    assert_no_third_party_urls "$WEB_ROOT/index.html"
    assert_no_third_party_urls "$WEB_ROOT/404.html"
    # canonical 必须指向自己
    grep -q 'rel="canonical" href="https://world.example.com/"' "$WEB_ROOT/index.html"
}

@test "默认伪装站不含任何工具名（不是 EasyNet 指纹）" {
    render "world.example.com"
    ! grep -qiE 'easynet|xray|hysteria|sing-?box|shadowsocks|amnezia|wireguard|vpn|proxy' \
        "$WEB_ROOT/index.html" "$WEB_ROOT/404.html"
}

@test "默认伪装站不出现第三方域名或镜像痕迹" {
    render "world.example.com"
    ! grep -qiE 'bing|cloudflare|microsoft|google' "$WEB_ROOT/index.html" "$WEB_ROOT/404.html"
    # 没有任何 Set-Cookie 能力（纯静态），也没有跨域引用
    ! grep -qE 'domain=\.[a-z]' "$WEB_ROOT/index.html"
}

@test "同一域名重部署内容稳定（幂等）" {
    render "world.example.com"
    local first
    first="$(easynet_edge_site_file_hash "$WEB_ROOT/index.html")"
    render "world.example.com"
    [ "$first" = "$(easynet_edge_site_file_hash "$WEB_ROOT/index.html")" ]
}

@test "不同域名内容不同（避免所有实例长得一样）" {
    render "world.example.com"
    local a b
    a="$(easynet_edge_site_file_hash "$WEB_ROOT/index.html")"
    rm -rf "$WEB_ROOT" "$STATE_DIR"
    render "other-service.example.net"
    b="$(easynet_edge_site_file_hash "$WEB_ROOT/index.html")"
    [ "$a" != "$b" ]
}

@test "手工替换的页面不会被重部署覆盖" {
    render "world.example.com"
    printf '<h1>my own page</h1>\n' > "$WEB_ROOT/index.html"
    render "world.example.com"
    grep -q 'my own page' "$WEB_ROOT/index.html"
}

@test "删除手工页面后恢复默认生成" {
    render "world.example.com"
    printf '<h1>my own page</h1>\n' > "$WEB_ROOT/index.html"
    render "world.example.com"
    rm -f "$WEB_ROOT/index.html"
    render "world.example.com"
    grep -q 'rel="canonical" href="https://world.example.com/"' "$WEB_ROOT/index.html"
}

@test "EASYNET_EDGE_SITE_DIR 自带站点优先且内容一字不改" {
    local mine="$TMP_DIR/mine"
    mkdir -p "$mine"
    printf '<h1>bring your own</h1>\n' > "$mine/index.html"
    render "world.example.com" "$mine"

    [ -f "$WEB_ROOT/index.html" ]
    grep -q 'bring your own' "$WEB_ROOT/index.html"
    grep -q '^external:' "$STATE_DIR/camouflage_site.state"
}

@test "EASYNET_EDGE_SITE_DIR 指向不存在的目录时报错" {
    run render "world.example.com" "$TMP_DIR/nope"
    [ "$status" -ne 0 ]
}

@test "默认伪装站包含 404 页，robots.txt 为真实站点的常见写法之一（或不存在）" {
    render "world.example.com"
    [ -s "$WEB_ROOT/404.html" ]
    # robots.txt 按域名种子选变体；"none" 表示不生成 —— 很多真实站点也没有它，
    # 关键是**不能所有部署都逐字节相同**（那本身就是同源模板指纹）。
    if [ -f "$WEB_ROOT/robots.txt" ]; then
        grep -q '^User-agent: \*' "$WEB_ROOT/robots.txt"
        [ "$(wc -l < "$WEB_ROOT/robots.txt")" -le 6 ]
    fi
}
@test "404 页同样自洽（canonical 缺失也无第三方引用）" {
    render "world.example.com"
    assert_no_third_party_urls "$WEB_ROOT/404.html"
    grep -q '404' "$WEB_ROOT/404.html"
}

# ---------------------------------------------------------------- 防回归

@test "默认值里不得再出现第三方大站的伪装目标" {
    run grep -rnE ':-[^}]*\b(bing|cloudflare)\.[a-z]+' \
        "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/.env.example"
    [ "$status" -ne 0 ]
}

@test "Edge 默认不再反代任何外部站点" {
    run grep -nE '^EDGE_MASQUERADE_URL=' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'EASYNET_EDGE_MASQUERADE_URL:-}'
    ! echo "$output" | grep -qE 'https?://'
}

@test "hysteria2 masquerade 默认使用本地静态站" {
    grep -q 'masquerade_block="masquerade:' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    grep -q 'type: file' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    run grep -nE 'EASYNET_HYSTERIA2_MASQUERADE_URL:-https' \
        "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    [ "$status" -ne 0 ]
}
