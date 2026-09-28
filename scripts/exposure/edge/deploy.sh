#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"
source "$CORE_DIR/download.sh"
source "$CORE_DIR/pins.sh"
source "$CORE_DIR/maintenance.sh"
source "$CORE_DIR/subscription.sh"
source "$SCRIPT_DIR/render_site.sh"

EDGE_STATE_DIR="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
EDGE_ROUTES_DIR="$EDGE_STATE_DIR/routes"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
EDGE_DOMAIN="${EASYNET_SUBSCRIPTION_DOMAIN:-${EASYNET_DOMAIN:-}}"
EDGE_HTTP_PORT="${EASYNET_EDGE_HTTP_PORT:-80}"
EDGE_HTTPS_PORT="${EASYNET_EDGE_HTTPS_PORT:-443}"
EDGE_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
# nginx 站点目录可覆盖（测试可直接 source 本文件并断言真实生成的配置，
# 不再内联复刻模板 —— 之前正是内联复刻漏掉了「默认反代 bing」的行为）。
EDGE_SITES_AVAILABLE_DIR="${EASYNET_EDGE_SITES_AVAILABLE_DIR:-/etc/nginx/sites-available}"
EDGE_SITES_ENABLED_DIR="${EASYNET_EDGE_SITES_ENABLED_DIR:-/etc/nginx/sites-enabled}"
EDGE_SITE_FILE="${EDGE_SITES_AVAILABLE_DIR}/easynet-edge"
EDGE_RENEW_HOOK="${EASYNET_EDGE_RENEW_HOOK:-$SCRIPT_DIR/cert_renew_hook.sh}"
# 伪装站模式：默认**自托管静态站**（域名/证书/内容自洽）。
# 只有显式设置 EASYNET_EDGE_MASQUERADE_URL 时才反代，且只能指向「自己拥有的」站点：
# 反代第三方大站会把「我在镜像别人」写进响应与页面（canonical 指向第三方、
# Set-Cookie 带 domain=.第三方、origin 字段点名第三方、任意 Host 都返回对方首页），
# 属于比 TLS 指纹更容易被自动化识别的内容层镜像特征。详见 render_site.sh 顶部说明。
EDGE_MASQUERADE_URL="${EASYNET_EDGE_MASQUERADE_URL:-}"
EDGE_SITE_DIR="${EASYNET_EDGE_SITE_DIR:-}"
EDGE_ROOT_LOCATION=""
EDGE_ERROR_PAGE=""
EDGE_HTTPS_LISTEN=""
EDGE_HTTP2_DIRECTIVE=""
EDGE_SUBSCRIPTION_PATH_PREFIX=""
EDGE_SERVER_NAMES="$EDGE_DOMAIN"
if [ -n "${EASYNET_DOMAIN:-}" ] && [ "${EASYNET_DOMAIN:-}" != "$EDGE_DOMAIN" ]; then
    EDGE_SERVER_NAMES="$EDGE_SERVER_NAMES ${EASYNET_DOMAIN:-}"
fi

edge_acme_domain_args() {
    printf '%s\n' "-d" "$EDGE_DOMAIN"
    if [ -n "${EASYNET_DOMAIN:-}" ] && [ "${EASYNET_DOMAIN:-}" != "$EDGE_DOMAIN" ]; then
        printf '%s\n' "-d" "${EASYNET_DOMAIN:-}"
    fi
}

ensure_edge_subscription_path_prefix() {
    local path_file path_prefix requested

    path_file="$EDGE_STATE_DIR/subscription_path_prefix.txt"
    requested="${EASYNET_SUBSCRIPTION_PATH_PREFIX:-}"
    if [ -n "$requested" ]; then
        # A pinned prefix keeps subscription URLs stable across re-installs,
        # but it is also the only secret protecting the subscription: reject
        # values that would break URLs or that are too short to resist guessing.
        if [[ "$requested" == *[[:space:]\?\#\&]* ]]; then
            log_error "EASYNET_SUBSCRIPTION_PATH_PREFIX 不能包含空白、?、# 或 &"
            exit 1
        fi
        if [ "${#requested}" -lt 16 ]; then
            log_warn "EASYNET_SUBSCRIPTION_PATH_PREFIX 少于 16 字符，过于容易被猜中；建议使用 \`openssl rand -hex 16\`"
        fi
        path_prefix="/${requested#/}"
        path_prefix="${path_prefix%/}"
    elif [ -f "$path_file" ]; then
        path_prefix=$(cat "$path_file")
    else
        path_prefix="/s/$(openssl rand -hex 16)"
    fi

    path_prefix="/${path_prefix#/}"
    path_prefix="${path_prefix%/}"
    echo "$path_prefix" > "$path_file"
    # The prefix is the only secret gating all credentials: root-only.
    chmod 600 "$path_file" 2>/dev/null || true
    EDGE_SUBSCRIPTION_PATH_PREFIX="$path_prefix"
}

require_edge_domain() {
    if [ -n "$EDGE_DOMAIN" ]; then
        return 0
    fi

    log_error "Edge 需要 EASYNET_DOMAIN 或 EASYNET_SUBSCRIPTION_DOMAIN。"
    exit 1
}

write_edge_state() {
    mkdir -p "$EDGE_STATE_DIR" "$EDGE_ROUTES_DIR"
    echo "$EDGE_DOMAIN" > "$EDGE_STATE_DIR/domain.txt"
    echo "https" > "$EDGE_STATE_DIR/scheme.txt"
    echo "$EDGE_HTTPS_PORT" > "$EDGE_STATE_DIR/port.txt"
    ensure_edge_subscription_path_prefix
    echo "# EasyNet Edge route placeholder" > "$EDGE_ROUTES_DIR/00-placeholder.conf"
}

write_edge_subscription_routes() {
    easynet_write_subscription_routes "$EDGE_ROUTES_DIR/subscription.conf" "$WEB_ROOT" "$EDGE_SUBSCRIPTION_PATH_PREFIX"

    # Also write direct-path routes (e.g. /sub, /clash, /singbox) for convenience.
    # Off by default: the random path is unguessable, a fixed path is not.
    # Enabled via EASYNET_SUBSCRIPTION_DIRECT_PATHS=true
    if [ "${EASYNET_SUBSCRIPTION_DIRECT_PATHS:-false}" = "true" ]; then
        while IFS='|' read -r endpoint file_name content_type; do
            [ -z "$endpoint" ] && continue
            cat >> "$EDGE_ROUTES_DIR/subscription.conf" <<EOF
location = /${endpoint} {
    alias ${WEB_ROOT}/${file_name};
    default_type ${content_type};
}

EOF
        done < <(easynet_subscription_endpoint_specs)
    else
        # 订阅文件就放在 web root 根目录（$WEB_ROOT/sub 等），随机前缀是唯一保护。
        # 但 location / 现在是**静态文件服务**（try_files）：不显式拒绝的话，
        # /sub、/clash、/singbox 这些可猜到的路径会被直接当成静态文件返回，
        # 等于把全部节点凭据公开（旧版走反代时看不见，换成静态站后就会暴露）。
        # 拒绝清单与直连路径走同一份端点定义，新增端点时自动生效。
        while IFS='|' read -r endpoint file_name content_type; do
            [ -z "$file_name" ] && continue
            cat >> "$EDGE_ROUTES_DIR/subscription.conf" <<EOF
location = /${file_name} {
    return 404;
}

EOF
        done < <(easynet_subscription_endpoint_specs)
    fi
}

# nginx 1.25.1+ 推荐 `http2 on;`；旧版本（如 Ubuntu 24.04 的 1.24）必须用
# `listen ... ssl http2`，否则配置直接加载失败。
edge_nginx_uses_modern_http2() {
    local ver major minor
    ver="$(nginx -v 2>&1 | sed -n 's|.*nginx/\([0-9][0-9]*\)\.\([0-9][0-9]*\).*|\1 \2|p')"
    [ -n "$ver" ] || return 1
    major="${ver%% *}"
    minor="${ver##* }"
    [ "$major" -gt 1 ] || [ "$minor" -ge 25 ]
}

# Edge 的 location / 与 404 处理：默认自托管静态站；仅显式配置时才反代。
setup_edge_root_location() {
    if [ -n "$EDGE_MASQUERADE_URL" ]; then
        log_info "伪装站: 反向代理 ${EDGE_MASQUERADE_URL}（必须是你自己拥有的站点）"
        EDGE_ROOT_LOCATION="    location / {
        access_log off;
        proxy_pass ${EDGE_MASQUERADE_URL};
        proxy_set_header Host \$proxy_host;
        proxy_ssl_server_name on;
        proxy_redirect off;
        # 上游自带安全头；不透传才不会出现两个互相冲突的 HSTS（RFC 6797）
        proxy_hide_header Strict-Transport-Security;
        proxy_hide_header X-Frame-Options;
        proxy_hide_header X-Content-Type-Options;
    }"
    else
        # shellcheck disable=SC2016  # $uri 是 nginx 变量，必须原样写进配置
        EDGE_ROOT_LOCATION='    location / {
        access_log off;
        try_files $uri $uri/ =404;
    }'
    fi
    # 有自带 404 页时才引用它：否则内部重定向找不到文件会变成 500
    if [ -f "$WEB_ROOT/404.html" ]; then
        EDGE_ERROR_PAGE="    error_page 404 /404.html;"
    else
        EDGE_ERROR_PAGE=""
    fi
}

write_edge_http_site() {
    cat > "$EDGE_SITE_FILE" << EOF
server {
    listen ${EDGE_HTTP_PORT};
    server_name ${EDGE_SERVER_NAMES};
    server_tokens off;

    root $WEB_ROOT;
${EDGE_ERROR_PAGE}

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

${EDGE_ROOT_LOCATION}
}
EOF
}

write_edge_https_site() {
    cat > "$EDGE_SITE_FILE" << EOF
server {
    listen ${EDGE_HTTP_PORT};
    server_name ${EDGE_SERVER_NAMES};
    server_tokens off;

    root $WEB_ROOT;
${EDGE_ERROR_PAGE}

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

${EDGE_ROOT_LOCATION}
}

server {
    ${EDGE_HTTPS_LISTEN}
${EDGE_HTTP2_DIRECTIVE}
    server_name ${EDGE_SERVER_NAMES};
    server_tokens off;

    ssl_certificate ${EDGE_CERT_DIR}/fullchain.crt;
    ssl_certificate_key ${EDGE_CERT_DIR}/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate ${EDGE_CERT_DIR}/fullchain.crt;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    root $WEB_ROOT;
${EDGE_ERROR_PAGE}

    include ${EDGE_ROUTES_DIR}/*.conf;

${EDGE_ROOT_LOCATION}
}
EOF
}

install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        local pin
        # Pinned + verified by default (core/pins.sh). Note: acme.sh itself may
        # self-upgrade later via its own cron entry - that is upstream behaviour
        # and is out of scope for the install-time pin.
        pin="$(easynet_resolve_pin acme)" || exit 1
        log_info "安装 acme.sh v${pin%%|*} 用于 Edge TLS 证书..."
        run_downloaded_script "https://get.acme.sh" "${pin#*|}"
    fi
    export PATH="$HOME/.acme.sh:$PATH"
}

issue_edge_certificate() {
    log_info "申请 Edge TLS 证书..."
    install_acme
    mkdir -p "$EDGE_CERT_DIR" "$WEB_ROOT/.well-known/acme-challenge"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    mapfile -t edge_domain_args < <(edge_acme_domain_args)

    set +e
    ~/.acme.sh/acme.sh --issue "${edge_domain_args[@]}" --webroot "$WEB_ROOT" -k ec-256
    local acme_status=$?
    set -e

    if [ $acme_status -ne 0 ] && [ $acme_status -ne 2 ]; then
        log_error "Edge TLS 证书申请失败，请检查域名解析和 TCP/${EDGE_HTTP_PORT} 入站访问。"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$EDGE_DOMAIN" --ecc \
        --key-file "$EDGE_CERT_DIR/private.key" \
        --fullchain-file "$EDGE_CERT_DIR/fullchain.crt" \
        --reloadcmd "$EDGE_RENEW_HOOK"
}

setup_edge_nginx() {
    log_info "配置 Edge Gateway..."
    apt install -y nginx
    mkdir -p "$WEB_ROOT" "$EDGE_ROUTES_DIR"

    if edge_nginx_uses_modern_http2; then
        EDGE_HTTPS_LISTEN="listen ${EDGE_HTTPS_PORT} ssl;"
        EDGE_HTTP2_DIRECTIVE="    http2 on;"
    else
        EDGE_HTTPS_LISTEN="listen ${EDGE_HTTPS_PORT} ssl http2;"
        EDGE_HTTP2_DIRECTIVE=""
    fi

    # 伪装站：默认渲染「属于本域名」的自洽静态站（见 render_site.sh）；
    # EASYNET_EDGE_SITE_DIR 可指向自带站点目录。
    easynet_edge_site_install "$WEB_ROOT" "$EDGE_DOMAIN" "$EDGE_STATE_DIR" "$EDGE_SITE_DIR"
    setup_edge_root_location

    # Ubuntu/Debian 自带的默认站点占着 80/443 的 default_server 并返回
    # "Welcome to nginx!" 欢迎页 —— 这是「刚装完 nginx」的指纹，且让未知 Host
    # 看到与本站无关的内容。禁用它，让 Edge 站点成为唯一的默认 server。
    if [ -L "$EDGE_SITES_ENABLED_DIR/default" ]; then
        rm -f "$EDGE_SITES_ENABLED_DIR/default"
        log_info "已禁用 nginx 默认站点（其欢迎页是全新安装的指纹）"
    fi

    write_edge_http_site
    mkdir -p "$EDGE_SITES_ENABLED_DIR"
    ln -sf "$EDGE_SITE_FILE" "$EDGE_SITES_ENABLED_DIR/easynet-edge"
    systemctl enable nginx
    if ! nginx -t; then
        log_error "Nginx HTTP 配置测试失败，请检查语法错误。"
        return 1
    fi
    # Reload instead of restart: a reload keeps existing TLS connections and
    # in-flight subscriber downloads alive, a restart drops them.
    if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi

    issue_edge_certificate
    maintenance_configure_nginx_logrotate
    write_edge_subscription_routes
    write_edge_https_site
    if ! nginx -t; then
        log_error "Nginx HTTPS 配置测试失败，请检查语法错误。"
        return 1
    fi
    if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi

    if command -v ufw &>/dev/null; then
        ufw allow "${EDGE_HTTP_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${EDGE_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
    fi

    # nginx 同时承担伪装站、订阅分发与 Reality 回落目标：崩溃后必须自愈
    # （发行版默认 Restart=no，而 xray/hysteria 都已有 on-failure）。
    maintenance_apply_restart_policy nginx
}

main() {
    require_edge_domain
    write_edge_state
    setup_edge_nginx
    log_info "Edge Gateway 已配置: https://${EDGE_DOMAIN}"
}

# 允许被测试脚本 source：只加载函数，不执行部署。
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
