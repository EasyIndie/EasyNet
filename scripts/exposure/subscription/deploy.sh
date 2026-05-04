#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"

SUBSCRIPTION_STATE_DIR="${EASYNET_SUBSCRIPTION_STATE_DIR:-$(easynet_subscription_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
SUBSCRIPTION_DOMAIN="${EASYNET_SUBSCRIPTION_DOMAIN:-${EASYNET_DOMAIN:-}}"
SUBSCRIPTION_SCHEME="${EASYNET_SUBSCRIPTION_SCHEME:-http}"
SUBSCRIPTION_PORT="${EASYNET_SUBSCRIPTION_PORT:-80}"

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
    echo "$SUBSCRIPTION_SCHEME" > "$SUBSCRIPTION_STATE_DIR/scheme.txt"
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

    cat > /etc/nginx/sites-available/easynet-subscription << EOF
server {
    listen ${SUBSCRIPTION_PORT};
    server_name ${SUBSCRIPTION_DOMAIN};

    root $WEB_ROOT;
    index index.html;

    location = /sub {
        try_files \$uri =404;
        default_type text/plain;
    }

    location = /sub_full {
        try_files \$uri =404;
        default_type text/plain;
    }

    location = /clash {
        try_files \$uri =404;
        default_type application/x-yaml;
    }

    location = /clash_full {
        try_files \$uri =404;
        default_type application/x-yaml;
    }

    location / {
        access_log off;
        try_files \$uri \$uri/ =404;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/easynet-subscription /etc/nginx/sites-enabled/
    systemctl enable nginx
    systemctl restart nginx
}

main() {
    require_subscription_domain
    write_subscription_state
    setup_subscription_nginx
    log_info "独立订阅承载已配置: ${SUBSCRIPTION_SCHEME}://${SUBSCRIPTION_DOMAIN}"
}

main "$@"
