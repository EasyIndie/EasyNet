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
source "$PROJECT_ROOT/scripts/core/env_file.sh"
source "$PROJECT_ROOT/scripts/core/cron.sh"
source "$PROJECT_ROOT/scripts/core/discovery.sh"

# ALL_MODULES is auto-discovered from protocols/*/manifest.sh
ALL_MODULES=()
while IFS= read -r mod; do
    ALL_MODULES+=("$mod")
done < <(discovery_list_modules)

load_env_file() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_info "发现 .env 文件，加载 EASYNET_* 环境变量..."
        load_easynet_env_file "$PROJECT_ROOT/.env"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行卸载脚本"
        exit 1
    fi
}

module_is_known() {
    discovery_module_exists "$1"
}

module_display_name() {
    if [ "$1" = "edge-exposure" ]; then
        echo "Edge Gateway"
    elif discovery_load_manifest "$1" 2>/dev/null; then
        echo "$MODULE_DISPLAY_NAME"
    else
        echo "$1"
    fi
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

    local idx=1
    echo "========================================"
    echo "  EasyNet 代理服务器卸载"
    echo "========================================"
    echo "0. 卸载全部协议与 Edge Gateway"
    for module_name in "${ALL_MODULES[@]}"; do
        if discovery_load_manifest "$module_name" 2>/dev/null; then
            printf "%d. 卸载 %s\n" "$idx" "$MODULE_DISPLAY_NAME"
        else
            printf "%d. 卸载 %s\n" "$idx" "$module_name"
        fi
        ((idx++))
    done
    printf "%d. 仅清理 Edge Gateway 与订阅文件\n" "$idx"
    printf "%d. 退出\n" "$((idx + 1))"
    echo "========================================"
    echo -e "${YELLOW}提示: 默认会删除 EasyNet 生成的配置、服务文件、metadata 与订阅文件；包卸载需显式设置 EASYNET_UNINSTALL_PURGE_PACKAGES=true。${NC}"
    read -p "请选择要卸载的服务: " choice
}

resolve_uninstall_modules() {
    local selection="$1"
    local edge_index=$(( ${#ALL_MODULES[@]} + 1 ))
    local exit_index=$(( ${#ALL_MODULES[@]} + 2 ))

    case "$selection" in
        0) printf '%s\n' "${ALL_MODULES[@]}"; echo "edge-exposure" ;;
        [0-9]|[0-9][0-9])
            local index=$((selection - 1))
            if [ "$index" -ge 0 ] && [ "$index" -lt "${#ALL_MODULES[@]}" ]; then
                echo "${ALL_MODULES[$index]}"
            elif [ "$selection" = "$edge_index" ]; then
                echo "edge-exposure"
            elif [ "$selection" = "$exit_index" ]; then
                echo "__exit__"
            else
                return 1
            fi
            ;;
        edge-exposure) echo "edge-exposure" ;;
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

    if [ "$module" = "edge-exposure" ]; then
        local entrypoint="$UNINSTALL_SCRIPT_DIR/exposure/edge/uninstall.sh"
        if [ -x "$entrypoint" ]; then
            echo "$entrypoint"
            return 0
        fi
        return 1
    fi

    discovery_uninstall_entrypoint "$module"
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
