#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the Shadowsocks module.

MODULE_NAME="shadowsocks"
MODULE_DISPLAY_NAME="Shadowsocks"
MODULE_PROTOCOL="ss"
MODULE_CLASH_TYPE="ss"
# Sing-box uses "shadowsocks" as its type identifier (not "ss")
MODULE_SINGBOX_TYPE="shadowsocks"
MODULE_SECURITY_RANK=50
MODULE_DEFAULT_PORT=8388
MODULE_EDGE_MODE="none"
MODULE_PROFILES="compat"
MODULE_SYSTEMD_SERVICES=("shadowsocks-libev-server")
