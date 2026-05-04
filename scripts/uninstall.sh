#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

UNINSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$UNINSTALL_SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/core/cron.sh"

ALL_MODULES=(xray-reality hysteria2 trojan-go v2ray shadowsocks wireguard)

load_env_file() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_info "发现 .env 文件，加载环境变量..."
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行卸载脚本"
        exit 1
    fi
}

module_is_known() {
    local module="$1"
    local known
    for known in "${ALL_MODULES[@]}"; do
        [ "$module" = "$known" ] && return 0
    done
    return 1
}

module_display_name() {
    case "$1" in
        trojan-go) echo "Trojan-Go" ;;
        v2ray) echo "V2Ray" ;;
        shadowsocks) echo "Shadowsocks" ;;
        wireguard) echo "WireGuard" ;;
        xray-reality) echo "Xray+Reality" ;;
        hysteria2) echo "Hysteria2" ;;
        nginx-exposure) echo "Nginx 暴露层" ;;
        edge-exposure) echo "Edge Gateway" ;;
        subscription-exposure) echo "独立订阅承载" ;;
        *) echo "$1" ;;
    esac
}

select_from_env() {
    if [ -n "$EASYNET_UNINSTALL_MODULE" ]; then
        choice="$EASYNET_UNINSTALL_MODULE"
        log_info "从环境变量 EASYNET_UNINSTALL_MODULE 读取卸载模块: $choice"
        return 0
    fi

    if [ -n "$EASYNET_UNINSTALL_CHOICE" ]; then
        choice="$EASYNET_UNINSTALL_CHOICE"
        log_info "从环境变量 EASYNET_UNINSTALL_CHOICE 读取卸载选择: $choice"
        return 0
    fi

    return 1
}

show_menu() {
    if select_from_env; then
        return
    fi

    echo "========================================"
    echo "  EasyNet 代理服务器卸载"
    echo "========================================"
    echo "0. 卸载全部协议与 EasyNet Nginx 暴露层"
    echo "1. 卸载 Xray+Reality"
    echo "2. 卸载 Hysteria2"
    echo "3. 卸载 Trojan-Go"
    echo "4. 卸载 V2Ray"
    echo "5. 卸载 Shadowsocks-libev"
    echo "6. 卸载 WireGuard"
    echo "7. 仅清理 EasyNet Nginx 暴露层与订阅文件"
    echo "8. 仅清理 Edge Gateway 与订阅文件"
    echo "9. 仅清理旧版独立订阅承载与订阅文件"
    echo "10. 退出"
    echo "========================================"
    echo -e "${YELLOW}提示: 默认会删除 EasyNet 生成的配置、服务文件、metadata 与订阅文件；包卸载需显式设置 EASYNET_UNINSTALL_PURGE_PACKAGES=true。${NC}"
    read -p "请选择要卸载的服务: " choice
}

resolve_uninstall_modules() {
    local selection="$1"

    case "$selection" in
        0) printf '%s\n' "${ALL_MODULES[@]}"; echo "nginx-exposure"; echo "edge-exposure"; echo "subscription-exposure" ;;
        1) echo "xray-reality" ;;
        2) echo "hysteria2" ;;
        3) echo "trojan-go" ;;
        4) echo "v2ray" ;;
        5) echo "shadowsocks" ;;
        6) echo "wireguard" ;;
        7) echo "nginx-exposure" ;;
        8) echo "edge-exposure" ;;
        9) echo "subscription-exposure" ;;
        10) echo "__exit__" ;;
        nginx-exposure) echo "nginx-exposure" ;;
        edge-exposure) echo "edge-exposure" ;;
        subscription-exposure) echo "subscription-exposure" ;;
        *)
            if module_is_known "$selection"; then
                echo "$selection"
            else
                return 1
            fi
            ;;
    esac
}

uninstall_entrypoint() {
    local module="$1"
    local entrypoint

    case "$module" in
        nginx-exposure) entrypoint="$UNINSTALL_SCRIPT_DIR/exposure/nginx/uninstall.sh" ;;
        edge-exposure) entrypoint="$UNINSTALL_SCRIPT_DIR/exposure/edge/uninstall.sh" ;;
        subscription-exposure) entrypoint="$UNINSTALL_SCRIPT_DIR/exposure/subscription/uninstall.sh" ;;
        *) entrypoint="$UNINSTALL_SCRIPT_DIR/protocols/$module/uninstall.sh" ;;
    esac

    if [ -x "$entrypoint" ]; then
        echo "$entrypoint"
    else
        return 1
    fi
}

uninstall_module() {
    local module="$1"
    local entrypoint

    entrypoint=$(uninstall_entrypoint "$module") || {
        log_error "未知或不可卸载模块: $module"
        return 1
    }

    log_info "开始卸载 $(module_display_name "$module")..."
    bash "$entrypoint"
}

refresh_after_uninstall() {
    if [ -x "$UNINSTALL_SCRIPT_DIR/generate_subscription.sh" ]; then
        bash "$UNINSTALL_SCRIPT_DIR/generate_subscription.sh" >/dev/null 2>&1 || true
    fi
    cron_install_restart_job
}

main() {
    load_env_file
    check_root

    show_menu
    mapfile -t selected_modules < <(resolve_uninstall_modules "$choice") || {
        log_error "无效选择"
        exit 1
    }

    if [ "${selected_modules[0]}" = "__exit__" ]; then
        log_info "退出卸载"
        exit 0
    fi

    local module
    for module in "${selected_modules[@]}"; do
        uninstall_module "$module"
    done

    refresh_after_uninstall
    log_info "卸载流程完成"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e
    main "$@"
fi
