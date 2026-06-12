#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the Hysteria2 module.

MODULE_NAME="hysteria2"
MODULE_DISPLAY_NAME="Hysteria2"
MODULE_PROTOCOL="hysteria2"
MODULE_CLASH_TYPE="hysteria2"
MODULE_SINGBOX_TYPE="hysteria2"
MODULE_SECURITY_RANK=20
MODULE_DEFAULT_PORT=443
MODULE_EDGE_MODE="shared_tls"
MODULE_PROFILES="balanced compat"
MODULE_SYSTEMD_SERVICES=("hysteria-server.service")
