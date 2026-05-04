#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/env.sh"

NGINX_STATE_DIR="${EASYNET_NGINX_STATE_DIR:-$(easynet_nginx_state_dir)}"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"

ensure_route_path() {
    local path_file="$1"
    local default_path="$2"
    local path_value

    if [ -f "$path_file" ]; then
        path_value=$(cat "$path_file")
    else
        path_value="/$(openssl rand -hex 4)"
        mkdir -p "$(dirname "$path_file")"
        echo "$path_value" > "$path_file"
    fi

    if [ -z "$path_value" ] || [ "$path_value" = "$default_path" ]; then
        path_value="/$(openssl rand -hex 4)"
        echo "$path_value" > "$path_file"
    fi

    echo "$path_value"
}

setup_nginx_fallback() {
    log_info "配置 Nginx 作为伪装站点与流量分发..."
    apt install -y nginx

    local v2ray_path trojan_path
    v2ray_path=$(ensure_route_path "$NGINX_STATE_DIR/v2ray_path.txt" "/v2ray")
    trojan_path=$(ensure_route_path "$NGINX_STATE_DIR/trojan_path.txt" "/trojan")
    if [ -n "$EASYNET_DOMAIN" ]; then
        mkdir -p "$NGINX_STATE_DIR"
        echo "$EASYNET_DOMAIN" > "$NGINX_STATE_DIR/domain.txt"
    fi

    mkdir -p "$WEB_ROOT"
    cat > "$WEB_ROOT/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Welcome to nginx!</h1>
</body>
</html>
HTML

    cat > /etc/nginx/sites-available/easynet-proxy << EOF
server {
    listen 127.0.0.1:80;
    server_name _;

    root $WEB_ROOT;
    index index.html index.htm index.nginx-debian.html;

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

    location $v2ray_path {
        access_log off;
        allow 127.0.0.1;
        deny all;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:4443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location $trojan_path {
        access_log off;
        return 404;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/easynet-proxy /etc/nginx/sites-enabled/

    systemctl enable nginx
    systemctl restart nginx
}

main() {
    setup_nginx_fallback
}

main "$@"
