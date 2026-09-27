#!/bin/bash
# shellcheck disable=SC2034  # sourced by orchestrators
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the WireGuard module.

MANIFEST_VERSION=1
MODULE_NAME="wireguard"
MODULE_DISPLAY_NAME="AmneziaWG"
MODULE_PROTOCOL="wireguard"
MODULE_CLASH_TYPE="wireguard"
MODULE_SINGBOX_TYPE="wireguard"
MODULE_SECURITY_RANK=50
MODULE_DEFAULT_PORT=51820
MODULE_EDGE_MODE="none"
MODULE_PROFILES="compat"
# Where this protocol keeps its on-disk configuration (indexed by ~/.easynet)
MODULE_CONFIG_DIR="/etc/amnezia/amneziawg"
MODULE_SYSTEMD_SERVICES=("awg-quick@wg0")
