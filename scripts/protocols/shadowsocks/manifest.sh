#!/bin/bash
# EasyNet protocol manifest - sourced by orchestrators
# Static metadata for the Shadowsocks 2022 Edition module.

MANIFEST_VERSION=1
MODULE_NAME="shadowsocks"
MODULE_DISPLAY_NAME="Shadowsocks 2022"
MODULE_PROTOCOL="ss"
MODULE_CLASH_TYPE="ss"
# Sing-box uses "shadowsocks" as its type identifier (not "ss")
MODULE_SINGBOX_TYPE="shadowsocks"
MODULE_SECURITY_RANK=40
MODULE_DEFAULT_PORT=8388
MODULE_EDGE_MODE="none"
MODULE_PROFILES="compat"
MODULE_SYSTEMD_SERVICES=("shadowsocks-rust-server")
