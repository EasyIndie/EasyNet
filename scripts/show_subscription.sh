#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"

main() {
    local sub_url clash_url singbox_url installer_url

    if ! sub_url="$(easynet_subscription_url "sub")"; then
        log_warn "没有找到可公开访问的订阅域名。请先配置 EASYNET_DOMAIN 或 EASYNET_SUBSCRIPTION_DOMAIN 并部署 Edge Gateway。"
        exit 1
    fi
    clash_url="$(easynet_subscription_url "clash")"
    singbox_url="$(easynet_subscription_url "singbox")"
    installer_url="$(easynet_subscription_url "singbox-client.sh")"

    echo ""
    echo "========================================"
    echo "  EasyNet 订阅链接"
    echo "========================================"
    echo "【URI 订阅】适用于 Shadowrocket / v2rayN / v2rayNG："
    echo -e "${GREEN}${sub_url}${NC}"
    if command -v qrencode &>/dev/null; then
        echo ""
        echo "URI 订阅二维码："
        qrencode -t utf8 "$sub_url"
    else
        echo ""
        echo "未安装 qrencode，无法显示 URI 订阅二维码。"
    fi

    echo ""
    echo "【Clash/Mihomo 订阅】适用于 Clash Verge Rev / Mihomo："
    echo -e "${GREEN}${clash_url}${NC}"
    if command -v qrencode &>/dev/null; then
        echo ""
        echo "Clash/Mihomo 订阅二维码："
        qrencode -t utf8 "$clash_url"
    else
        echo ""
        echo "未安装 qrencode，无法显示 Clash/Mihomo 订阅二维码。"
    fi
    echo ""
    echo "【sing-box 配置】适用于 Raspberry Pi / 卡片机 / 无界面 Linux："
    echo -e "${GREEN}${singbox_url}${NC}"
    if command -v qrencode &>/dev/null; then
        echo ""
        echo "sing-box 配置二维码："
        qrencode -t utf8 "$singbox_url"
    else
        echo ""
        echo "未安装 qrencode，无法显示 sing-box 配置二维码。"
    fi
    echo ""
    echo "树莓派快速安装："
    echo "curl -fsSL \"${installer_url}\" -o easynet-singbox-client.sh"
    echo "sudo bash easynet-singbox-client.sh --config-url \"${singbox_url}\""
    echo "========================================"
}

main "$@"
