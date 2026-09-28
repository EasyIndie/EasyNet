#!/usr/bin/env bats
# Edge Gateway nginx 配置验证
#
# 本文件**直接 source 真实的 scripts/exposure/edge/deploy.sh** 并断言它生成的配置。
# 早先的版本把模板内联复刻到测试里，结果测试与真实配置各自漂移 —— 真实配置默认
# 反代第三方大站（bing）这件事，正是在内联复刻下被漏掉的。现在只保留一条真实来源。

load test_helper

setup() {
    export TMP_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."
    export NGINX_CONF="$TMP_DIR/sites-available/easynet-edge"
    export EASYNET_WEB_ROOT="$TMP_DIR/www"
    export EASYNET_EDGE_SITES_AVAILABLE_DIR="$TMP_DIR/sites-available"
    export EASYNET_EDGE_SITES_ENABLED_DIR="$TMP_DIR/sites-enabled"
    export EASYNET_EDGE_ROUTES_DIR="$TMP_DIR/routes"
    mkdir -p "$EASYNET_WEB_ROOT" "$EASYNET_EDGE_SITES_AVAILABLE_DIR" \
        "$EASYNET_EDGE_SITES_ENABLED_DIR" "$EASYNET_EDGE_ROUTES_DIR"

    source "$PROJECT_ROOT/scripts/core/logging.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    # 只加载函数（deploy.sh 末尾有 BASH_SOURCE 守卫）
    source "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"

    EDGE_HTTP_PORT=80
    EDGE_HTTPS_PORT=443
    EDGE_SERVER_NAMES="test.example.com"
    EDGE_CERT_DIR="/etc/ssl/easynet-edge"
    EDGE_ROUTES_DIR="$EASYNET_EDGE_ROUTES_DIR"
    WEB_ROOT="$EASYNET_WEB_ROOT"
    EDGE_HTTPS_LISTEN="listen 443 ssl;"
    EDGE_HTTP2_DIRECTIVE="    http2 on;"
    EDGE_ERROR_PAGE=""
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ============================================================
# 伪装站：默认静态自洽，只有显式配置才反代
# ============================================================

@test "默认伪装站是自托管静态站（不反代任何第三方）" {
    EDGE_MASQUERADE_URL=""
    mkdir -p "$WEB_ROOT"
    printf '<html></html>\n' > "$WEB_ROOT/404.html"
    setup_edge_root_location

    [[ "$EDGE_ROOT_LOCATION" == *'try_files $uri $uri/ =404'* ]]
    [[ "$EDGE_ROOT_LOCATION" != *"proxy_pass"* ]]
    [[ "$EDGE_ERROR_PAGE" == *"error_page 404 /404.html"* ]]
}

@test "未提供 404 页时不引用 error_page（避免内部重定向变成 500）" {
    rm -f "$WEB_ROOT/404.html"
    mkdir -p "$WEB_ROOT"
    EDGE_MASQUERADE_URL=""
    setup_edge_root_location
    [ -z "$EDGE_ERROR_PAGE" ]
}

@test "显式设置 EASYNET_EDGE_MASQUERADE_URL 时才反代，且隐藏上游冲突安全头" {
    EDGE_MASQUERADE_URL="https://my-own-site.example.net"
    setup_edge_root_location
    [[ "$EDGE_ROOT_LOCATION" == *"proxy_pass https://my-own-site.example.net"* ]]
    [[ "$EDGE_ROOT_LOCATION" == *"proxy_hide_header Strict-Transport-Security"* ]]
    [[ "$EDGE_ROOT_LOCATION" == *"proxy_hide_header X-Frame-Options"* ]]
}

# ============================================================
# HTTP 站点
# ============================================================

@test "write_edge_http_site: 生成合法配置且包含 acme-challenge" {
    mkdir -p "$WEB_ROOT"
    EDGE_ROOT_LOCATION='    location / {
        access_log off;
        try_files $uri $uri/ =404;
    }'
    write_edge_http_site

    assert_file_contains "$NGINX_CONF" "listen 80" "HTTP 监听 80"
    assert_file_contains "$NGINX_CONF" "server_name .*test\\.example\\.com" "有 server_name"
    assert_file_contains "$NGINX_CONF" "\\.well-known/acme-challenge" "有 acme-challenge"
    assert_file_contains "$NGINX_CONF" "server_tokens off" "隐藏 nginx 版本"
}

# ============================================================
# HTTPS 站点
# ============================================================

@test "write_edge_https_site: TLS 指令与证书路径正确" {
    EDGE_ROOT_LOCATION='    location / { try_files $uri $uri/ =404; }'
    write_edge_https_site

    assert_file_contains "$NGINX_CONF" "ssl_certificate .*/fullchain\\.crt" "有 ssl_certificate"
    assert_file_contains "$NGINX_CONF" "ssl_certificate_key .*/private\\.key" "有 ssl_certificate_key"
    assert_file_contains "$NGINX_CONF" "listen 443 ssl" "HTTPS 监听 443 ssl"
    assert_file_contains "$NGINX_CONF" "include .*/\\*\\.conf" "包含订阅路由"
}

@test "write_edge_https_site: 安全头与 OCSP 装订" {
    EDGE_ROOT_LOCATION='    location / { try_files $uri $uri/ =404; }'
    write_edge_https_site

    assert_file_contains "$NGINX_CONF" "Strict-Transport-Security" "有 HSTS"
    assert_file_contains "$NGINX_CONF" "X-Content-Type-Options" "有 nosniff"
    assert_file_contains "$NGINX_CONF" "X-Frame-Options" "有 DENY"
    assert_file_contains "$NGINX_CONF" "ssl_stapling on" "OCSP 装订"
    assert_file_contains "$NGINX_CONF" "ssl_trusted_certificate" "受信任证书链"
}

@test "write_edge_https_site: 只允许 TLS 1.2/1.3" {
    EDGE_ROOT_LOCATION='    location / { try_files $uri $uri/ =404; }'
    write_edge_https_site

    assert_file_contains "$NGINX_CONF" "TLSv1\\.2.*TLSv1\\.3" "仅 TLS 1.2/1.3"
    assert_file_not_contains "$NGINX_CONF" "SSLv3" "不含 SSLv3"
}

@test "write_edge_https_site: 启用 HTTP/2" {
    EDGE_ROOT_LOCATION='    location / { try_files $uri $uri/ =404; }'
    write_edge_https_site
    assert_file_contains "$NGINX_CONF" "http2 on;" "新语法 http2 on;"
}

@test "write_edge_https_site: 旧版 nginx 退回 listen ... http2" {
    EDGE_HTTPS_LISTEN="listen 443 ssl http2;"
    EDGE_HTTP2_DIRECTIVE=""
    EDGE_ROOT_LOCATION='    location / { try_files $uri $uri/ =404; }'
    write_edge_https_site

    assert_file_contains "$NGINX_CONF" "listen 443 ssl http2;" "旧语法兼容"
    assert_file_not_contains "$NGINX_CONF" "^    http2 on;$" "不混用两种写法"
}

@test "nginx HTTP/2 语法探测：无 nginx 时安全退化" {
    run edge_nginx_uses_modern_http2
    # 本地（macOS）通常没有 nginx：必须返回非 0 而不是崩溃
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ============================================================
# 订阅路径前缀
# ============================================================

@test "ensure_edge_subscription_path_prefix: 无前缀时生成 hex 路径" {
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    EDGE_STATE_DIR="$EASYNET_STATE_DIR/exposure/edge"
    EDGE_SUBSCRIPTION_PATH_PREFIX=""
    rm -f "$EDGE_STATE_DIR/subscription_path_prefix.txt"
    mkdir -p "$EDGE_STATE_DIR"

    ensure_edge_subscription_path_prefix
    [[ "$EDGE_SUBSCRIPTION_PATH_PREFIX" =~ ^/s/[0-9a-f]{32}$ ]]
}

@test "ensure_edge_subscription_path_prefix: 复用已有前缀" {
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    EDGE_STATE_DIR="$EASYNET_STATE_DIR/exposure/edge"
    mkdir -p "$EDGE_STATE_DIR"
    echo "/s/aaaa1111bbbb2222cccc3333dddd4444" > "$EDGE_STATE_DIR/subscription_path_prefix.txt"
    EDGE_SUBSCRIPTION_PATH_PREFIX=""

    ensure_edge_subscription_path_prefix
    [ "$EDGE_SUBSCRIPTION_PATH_PREFIX" = "/s/aaaa1111bbbb2222cccc3333dddd4444" ]
}

@test "ensure_edge_subscription_path_prefix: 使用 EASYNET_SUBSCRIPTION_PATH_PREFIX" {
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    EDGE_STATE_DIR="$EASYNET_STATE_DIR/exposure/edge"
    mkdir -p "$EDGE_STATE_DIR"
    EASYNET_SUBSCRIPTION_PATH_PREFIX="/s/1234567890abcdef1234567890abcdef"
    EDGE_SUBSCRIPTION_PATH_PREFIX=""

    ensure_edge_subscription_path_prefix
    [ "$EDGE_SUBSCRIPTION_PATH_PREFIX" = "/s/1234567890abcdef1234567890abcdef" ]
}

@test "ensure_edge_subscription_path_prefix: 拒绝危险字符" {
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    EDGE_STATE_DIR="$EASYNET_STATE_DIR/exposure/edge"
    mkdir -p "$EDGE_STATE_DIR"
    EASYNET_SUBSCRIPTION_PATH_PREFIX="/s/bad path"
    EDGE_SUBSCRIPTION_PATH_PREFIX=""

    run ensure_edge_subscription_path_prefix
    [ "$status" -ne 0 ]
}
