#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the Xray + Reality module.

MANIFEST_VERSION=1
MODULE_NAME="xray-reality"
MODULE_DISPLAY_NAME="Xray+Reality"
MODULE_PROTOCOL="vless"
MODULE_CLASH_TYPE="vless"
MODULE_SINGBOX_TYPE="vless"
MODULE_SECURITY_RANK=10
MODULE_DEFAULT_PORT=8443
MODULE_EDGE_MODE="none"
MODULE_PROFILES="strict balanced compat"
MODULE_SYSTEMD_SERVICES=("xray")
