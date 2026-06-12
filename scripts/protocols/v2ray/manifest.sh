#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the V2Ray module.

MODULE_NAME="v2ray"
MODULE_DISPLAY_NAME="V2Ray"
MODULE_PROTOCOL="vmess"
MODULE_CLASH_TYPE="vmess"
MODULE_SINGBOX_TYPE="vmess"
MODULE_SECURITY_RANK=40
MODULE_DEFAULT_PORT=4443
MODULE_DEFAULT_PUBLIC_PORT=443
MODULE_EDGE_MODE="backend"
MODULE_PROFILES="compat"
MODULE_SYSTEMD_SERVICES=("v2ray")

# Nginx route template for the Edge Gateway reverse-proxy.
# Trojan-Go uses HTTPS proxy_pass, V2Ray uses HTTP (no client-side TLS).
MODULE_NGINX_ROUTE_TEMPLATE='location ${ROUTE_PATH} {
    access_log off;
    proxy_redirect off;
    proxy_pass http://127.0.0.1:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}'
