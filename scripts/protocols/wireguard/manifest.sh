#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the WireGuard module.

MODULE_NAME="wireguard"
MODULE_DISPLAY_NAME="WireGuard"
MODULE_PROTOCOL="wireguard"
MODULE_CLASH_TYPE="wireguard"
MODULE_SINGBOX_TYPE="wireguard"
MODULE_SECURITY_RANK=60
MODULE_DEFAULT_PORT=51820
MODULE_EDGE_MODE="none"
MODULE_PROFILES="compat"
MODULE_SYSTEMD_SERVICES=("wg-quick@wg0")
