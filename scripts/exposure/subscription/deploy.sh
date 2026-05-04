#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"

SUBSCRIPTION_STATE_DIR="${EASYNET_SUBSCRIPTION_STATE_DIR:-$(easynet_subscription_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
SUBSCRIPTION_DOMAIN="${EASYNET_SUBSCRIPTION_DOMAIN:-${EASYNET_DOMAIN:-}}"
SUBSCRIPTION_TLS="${EASYNET_SUBSCRIPTION_TLS:-true}"
SUBSCRIPTION_HTTP_PORT="${EASYNET_SUBSCRIPTION_HTTP_PORT:-80}"
SUBSCRIPTION_HTTPS_PORT="${EASYNET_SUBSCRIPTION_HTTPS_PORT:-9443}"
SUBSCRIPTION_CERT_DIR="${EASYNET_SUBSCRIPTION_CERT_DIR:-/etc/ssl/easynet-subscription}"

require_subscription_domain() {
    if [ -n "$SUBSCRIPTION_DOMAIN" ]; then
        return 0
    fi

    read -p "请输入订阅承载域名: " SUBSCRIPTION_DOMAIN
    if [ -z "$SUBSCRIPTION_DOMAIN" ]; then
        log_error "订阅承载需要域名。"
        exit 1
    fi
}

write_subscription_state() {
    mkdir -p "$SUBSCRIPTION_STATE_DIR"
    echo "$SUBSCRIPTION_DOMAIN" > "$SUBSCRIPTION_STATE_DIR/domain.txt"
    if [ "$SUBSCRIPTION_TLS" = "true" ]; then
        echo "https" > "$SUBSCRIPTION_STATE_DIR/scheme.txt"
        echo "$SUBSCRIPTION_HTTPS_PORT" > "$SUBSCRIPTION_STATE_DIR/port.txt"
    else
        echo "http" > "$SUBSCRIPTION_STATE_DIR/scheme.txt"
        echo "$SUBSCRIPTION_HTTP_PORT" > "$SUBSCRIPTION_STATE_DIR/port.txt"
    fi
}

write_http_nginx_site() {
    cat > /etc/nginx/sites-available/easynet-subscription << EOF
server {
    listen ${SUBSCRIPTION_HTTP_PORT};
    server_name ${SUBSCRIPTION_DOMAIN};

    root $WEB_ROOT;
    index index.html;

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

    location = /sub {
        try_files \$uri =404;
        default_type text/plain;
    }

    location = /clash {
        try_files \$uri =404;
        default_type application/x-yaml;
    }

    location / {
        access_log off;
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

write_https_nginx_site() {
    cat > /etc/nginx/sites-available/easynet-subscription << EOF
server {
    listen ${SUBSCRIPTION_HTTP_PORT};
    server_name ${SUBSCRIPTION_DOMAIN};

    root $WEB_ROOT;

    location /.well-known/acme-challenge/ {
        root $WEB_ROOT;
    }

    location / {
        return 301 https://\$host:${SUBSCRIPTION_HTTPS_PORT}\$request_uri;
    }
}

server {
    listen ${SUBSCRIPTION_HTTPS_PORT} ssl;
    server_name ${SUBSCRIPTION_DOMAIN};

    ssl_certificate ${SUBSCRIPTION_CERT_DIR}/fullchain.crt;
    ssl_certificate_key ${SUBSCRIPTION_CERT_DIR}/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root $WEB_ROOT;
    index index.html;

    location = /sub {
        try_files \$uri =404;
        default_type text/plain;
    }

    location = /clash {
        try_files \$uri =404;
        default_type application/x-yaml;
    }

    location / {
        access_log off;
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        log_info "安装 acme.sh 用于订阅承载 TLS 证书..."
        curl https://get.acme.sh | sh
    fi
    export PATH="$HOME/.acme.sh:$PATH"
}

issue_subscription_certificate() {
    log_info "申请订阅承载 TLS 证书..."
    install_acme
    mkdir -p "$SUBSCRIPTION_CERT_DIR" "$WEB_ROOT/.well-known/acme-challenge"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    set +e
    ~/.acme.sh/acme.sh --issue -d "$SUBSCRIPTION_DOMAIN" --webroot "$WEB_ROOT" -k ec-256
    local acme_status=$?
    set -e

    if [ $acme_status -ne 0 ] && [ $acme_status -ne 2 ]; then
        log_error "订阅承载 TLS 证书申请失败，请检查域名解析和 TCP/${SUBSCRIPTION_HTTP_PORT} 入站访问。"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$SUBSCRIPTION_DOMAIN" --ecc \
        --key-file "$SUBSCRIPTION_CERT_DIR/private.key" \
        --fullchain-file "$SUBSCRIPTION_CERT_DIR/fullchain.crt" \
        --reloadcmd "systemctl restart nginx"
}

setup_subscription_nginx() {
    log_info "配置独立订阅承载 Nginx..."
    apt install -y nginx
    mkdir -p "$WEB_ROOT"

    cat > "$WEB_ROOT/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Welcome</h1>
</body>
</html>
HTML

    write_http_nginx_site
    ln -sf /etc/nginx/sites-available/easynet-subscription /etc/nginx/sites-enabled/
    systemctl enable nginx
    systemctl restart nginx

    if [ "$SUBSCRIPTION_TLS" = "true" ]; then
        issue_subscription_certificate
        write_https_nginx_site
        systemctl restart nginx
    fi

    if command -v ufw &>/dev/null; then
        ufw allow "${SUBSCRIPTION_HTTP_PORT}/tcp" >/dev/null 2>&1 || true
        if [ "$SUBSCRIPTION_TLS" = "true" ]; then
            ufw allow "${SUBSCRIPTION_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
        fi
    fi
}

main() {
    require_subscription_domain
    write_subscription_state
    setup_subscription_nginx
    if [ "$SUBSCRIPTION_TLS" = "true" ]; then
        log_info "独立订阅承载已配置: https://${SUBSCRIPTION_DOMAIN}:${SUBSCRIPTION_HTTPS_PORT}"
    else
        log_info "独立订阅承载已配置: http://${SUBSCRIPTION_DOMAIN}:${SUBSCRIPTION_HTTP_PORT}"
    fi
}

main "$@"
