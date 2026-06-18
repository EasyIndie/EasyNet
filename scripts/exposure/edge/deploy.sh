#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"
source "$CORE_DIR/download.sh"
source "$CORE_DIR/maintenance.sh"
source "$CORE_DIR/subscription.sh"

EDGE_STATE_DIR="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
EDGE_ROUTES_DIR="$EDGE_STATE_DIR/routes"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
EDGE_DOMAIN="${EASYNET_SUBSCRIPTION_DOMAIN:-${EASYNET_DOMAIN:-}}"
EDGE_HTTP_PORT="${EASYNET_EDGE_HTTP_PORT:-80}"
EDGE_HTTPS_PORT="${EASYNET_EDGE_HTTPS_PORT:-443}"
EDGE_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
EDGE_RENEW_HOOK="${EASYNET_EDGE_RENEW_HOOK:-$SCRIPT_DIR/cert_renew_hook.sh}"
EDGE_MASQUERADE_URL="${EASYNET_EDGE_MASQUERADE_URL:-https://www.bing.com}"
EDGE_SUBSCRIPTION_PATH_PREFIX=""
EDGE_SERVER_NAMES="$EDGE_DOMAIN"
if [ -n "${EASYNET_DOMAIN:-}" ] && [ "${EASYNET_DOMAIN:-}" != "$EDGE_DOMAIN" ]; then
    EDGE_SERVER_NAMES="$EDGE_SERVER_NAMES ${EASYNET_DOMAIN:-}"
fi

edge_acme_domain_args() {
    printf '%s\n' "-d" "$EDGE_DOMAIN"
    if [ -n "$EASYNET_DOMAIN" ] && [ "$EASYNET_DOMAIN" != "$EDGE_DOMAIN" ]; then
        printf '%s\n' "-d" "$EASYNET_DOMAIN"
    fi
}

ensure_edge_subscription_path_prefix() {
    local path_file path_prefix

    path_file="$EDGE_STATE_DIR/subscription_path_prefix.txt"
    if [ -n "${EASYNET_SUBSCRIPTION_PATH_PREFIX:-}" ]; then
        path_prefix="/${EASYNET_SUBSCRIPTION_PATH_PREFIX#/}"
        path_prefix="${path_prefix%/}"
    elif [ -f "$path_file" ]; then
        path_prefix=$(cat "$path_file")
    else
        path_prefix="/s/$(openssl rand -hex 16)"
    fi

    path_prefix="/${path_prefix#/}"
    path_prefix="${path_prefix%/}"
    echo "$path_prefix" > "$path_file"
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
}

write_edge_http_site() {
    cat > /etc/nginx/sites-available/easynet-edge << EOF
server {
    listen ${EDGE_HTTP_PORT};
    server_name ${EDGE_SERVER_NAMES};

    root $WEB_ROOT;

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

    location / {
        access_log off;
        proxy_pass ${EDGE_MASQUERADE_URL};
        proxy_set_header Host \$proxy_host;
        proxy_ssl_server_name on;
        proxy_redirect off;
    }
}
EOF
}

write_edge_https_site() {
    cat > /etc/nginx/sites-available/easynet-edge << EOF
server {
    listen ${EDGE_HTTP_PORT};
    server_name ${EDGE_SERVER_NAMES};

    root $WEB_ROOT;

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

    location / {
        access_log off;
        proxy_pass ${EDGE_MASQUERADE_URL};
        proxy_set_header Host \$proxy_host;
        proxy_ssl_server_name on;
        proxy_redirect off;
    }
}

server {
    listen ${EDGE_HTTPS_PORT} ssl;
    server_name ${EDGE_SERVER_NAMES};

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

    include ${EDGE_ROUTES_DIR}/*.conf;

    location / {
        access_log off;
        proxy_pass ${EDGE_MASQUERADE_URL};
        proxy_set_header Host \$proxy_host;
        proxy_ssl_server_name on;
        proxy_redirect off;
    }
}
EOF
}

install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        log_info "安装 acme.sh 用于 Edge TLS 证书..."
        run_downloaded_script "https://get.acme.sh" "${EASYNET_ACME_INSTALL_SHA256:-}"
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

    write_edge_http_site
    ln -sf /etc/nginx/sites-available/easynet-edge /etc/nginx/sites-enabled/
    systemctl enable nginx
    if ! nginx -t; then
        log_error "Nginx HTTP 配置测试失败，请检查语法错误。"
        return 1
    fi
    systemctl restart nginx

    issue_edge_certificate
    maintenance_configure_nginx_logrotate
    write_edge_subscription_routes
    write_edge_https_site
    if ! nginx -t; then
        log_error "Nginx HTTPS 配置测试失败，请检查语法错误。"
        return 1
    fi
    systemctl restart nginx

    if command -v ufw &>/dev/null; then
        ufw allow "${EDGE_HTTP_PORT}/tcp" >/dev/null 2>&1 || true
        ufw allow "${EDGE_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
    fi
}

main() {
    require_edge_domain
    write_edge_state
    setup_edge_nginx
    log_info "Edge Gateway 已配置: https://${EDGE_DOMAIN}"
}

main "$@"
