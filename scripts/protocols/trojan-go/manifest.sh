#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the Trojan-Go module.

MANIFEST_VERSION=1
MODULE_NAME="trojan-go"
MODULE_DISPLAY_NAME="Trojan-Go"
MODULE_PROTOCOL="trojan"
MODULE_CLASH_TYPE="trojan"
MODULE_SINGBOX_TYPE="trojan"
MODULE_SECURITY_RANK=30
MODULE_DEFAULT_PORT=4444
MODULE_DEFAULT_PUBLIC_PORT=443
MODULE_EDGE_MODE="backend"
MODULE_PROFILES="compat"
MODULE_SYSTEMD_SERVICES=("trojan-go")
# Env var prefix for backward compatibility (used in EASYNET_TROJAN_PORT etc.)
MODULE_ENV_PREFIX="TROJAN"

# Nginx route template for the Edge Gateway reverse-proxy.
# Variables: ${BACKEND_PORT}, ${BACKEND_LISTEN}, ${ROUTE_PATH}, ${ROUTE_DOMAIN}
MODULE_NGINX_ROUTE_TEMPLATE='location ${ROUTE_PATH} {
    access_log off;
    proxy_redirect off;
    proxy_pass https://127.0.0.1:${BACKEND_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_ssl_server_name on;
    proxy_ssl_name ${ROUTE_DOMAIN};
    proxy_ssl_verify off;
}'
