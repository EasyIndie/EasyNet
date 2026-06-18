#!/bin/bash
# EasyNet Display Module
# Terminal output helpers: QR code display, formatted messages.
# Source this file, then call:
#   show_qrcode <data> [label]

show_qrcode() {
    local data="$1"
    local label="${2:-二维码}"
    if command -v qrencode &>/dev/null; then
        echo ""
        echo "${label}:"
        qrencode -t utf8 "$data"
    else
        echo ""
        echo "未安装 qrencode，无法显示 ${label}。"
    fi
}
