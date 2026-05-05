#!/bin/bash

EASYNET_EDGE_ROUTES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_EDGE_ROUTES_DIR/../../core/env.sh"

edge_protocol_public_domain() {
    echo "${EASYNET_DOMAIN:-${EASYNET_SUBSCRIPTION_DOMAIN:-}}"
}

edge_route_state_dir() {
    echo "${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
}

edge_routes_dir() {
    echo "$(edge_route_state_dir)/routes"
}

ensure_edge_trojan_route() {
    local edge_state_dir edge_routes_dir route_path route_domain

    edge_state_dir="$(edge_route_state_dir)"
    edge_routes_dir="$(edge_routes_dir)"
    mkdir -p "$edge_routes_dir"

    if [ -n "$EASYNET_TROJAN_WS_PATH" ]; then
        route_path="$EASYNET_TROJAN_WS_PATH"
    elif [ -f "$edge_state_dir/trojan_path.txt" ]; then
        route_path=$(cat "$edge_state_dir/trojan_path.txt")
    else
        route_path="/$(openssl rand -hex 16)"
        echo "$route_path" > "$edge_state_dir/trojan_path.txt"
    fi

    route_domain="$(edge_protocol_public_domain)"

    export EASYNET_TROJAN_PORT="${EASYNET_TROJAN_PORT:-4444}"
    export EASYNET_TROJAN_LISTEN="${EASYNET_TROJAN_LISTEN:-127.0.0.1}"
    export EASYNET_TROJAN_PUBLIC_PORT="${EASYNET_TROJAN_PUBLIC_PORT:-443}"
    export EASYNET_TROJAN_WS_PATH="$route_path"
    export EASYNET_TROJAN_CERT_DIR="${EASYNET_TROJAN_CERT_DIR:-${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}}"

    cat > "$edge_routes_dir/trojan-go.conf" <<EOF
location ${route_path} {
    access_log off;
    proxy_redirect off;
    proxy_pass https://127.0.0.1:${EASYNET_TROJAN_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_ssl_server_name on;
    proxy_ssl_name ${route_domain};
    proxy_ssl_verify off;
}
EOF
}

ensure_edge_v2ray_route() {
    local edge_state_dir edge_routes_dir route_path

    edge_state_dir="$(edge_route_state_dir)"
    edge_routes_dir="$(edge_routes_dir)"
    mkdir -p "$edge_routes_dir"

    if [ -n "$EASYNET_V2RAY_WS_PATH" ]; then
        route_path="$EASYNET_V2RAY_WS_PATH"
    elif [ -f "$edge_state_dir/v2ray_path.txt" ]; then
        route_path=$(cat "$edge_state_dir/v2ray_path.txt")
    else
        route_path="/$(openssl rand -hex 16)"
        echo "$route_path" > "$edge_state_dir/v2ray_path.txt"
    fi

    export EASYNET_V2RAY_PORT="${EASYNET_V2RAY_PORT:-4443}"
    export EASYNET_V2RAY_LISTEN="${EASYNET_V2RAY_LISTEN:-127.0.0.1}"
    export EASYNET_V2RAY_PUBLIC_PORT="${EASYNET_V2RAY_PUBLIC_PORT:-443}"
    export EASYNET_V2RAY_WS_PATH="$route_path"

    cat > "$edge_routes_dir/v2ray.conf" <<EOF
location ${route_path} {
    access_log off;
    proxy_redirect off;
    proxy_pass http://127.0.0.1:${EASYNET_V2RAY_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}
EOF
}
