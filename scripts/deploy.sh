#!/bin/bash

DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$DEPLOY_SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/firewall.sh"
source "$PROJECT_ROOT/scripts/core/cron.sh"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/core/env_file.sh"
source "$PROJECT_ROOT/scripts/core/maintenance.sh"
source "$PROJECT_ROOT/scripts/core/discovery.sh"
source "$PROJECT_ROOT/scripts/core/profiles.sh"
source "$PROJECT_ROOT/scripts/core/validate.sh"
source "$PROJECT_ROOT/scripts/core/bootstrap.sh"
source "$PROJECT_ROOT/scripts/exposure/edge/routes.sh"

# Error trap for set -eE: provides context on unexpected failures
_easynet_error_handler() {
    local exit_code=$?
    log_error "非预期错误 (退出码: $exit_code) at ${BASH_SOURCE[0]##*/}:${BASH_LINENO[0]}"
    exit "$exit_code"
}

# ALL_MODULES auto-discovered from protocols/*/manifest.sh,
# sorted by MODULE_SECURITY_RANK (lower rank = stronger anti-DPI)
ALL_MODULES=()
while IFS= read -r mod; do
    ALL_MODULES+=("$mod")
done < <(discovery_list_modules_by_security)
DEPLOY_SELECTION_MODULES=()

# Backup file path for auto-rollback
BACKUP_FILE=""

load_env_file_path() {
    load_easynet_env_file "$1"
}

load_env_file() {
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_info "发现 .env 文件，加载 EASYNET_* 环境变量..."
        load_env_file_path "$PROJECT_ROOT/.env"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    if [[ ! "$OS" =~ ^(ubuntu|debian)$ ]]; then
        log_error "此脚本仅支持 Ubuntu 和 Debian 系统"
        exit 1
    fi

    log_info "检测到操作系统: $OS $VERSION"
}

update_system() {
    log_info "更新系统软件包..."
    apt update -y
    apt upgrade -y
}

install_dependencies() {
    log_info "安装基础依赖..."
    apt install -y curl wget git unzip ca-certificates gnupg2 lsb-release qrencode jq gettext-base
}

enable_bbr() {
    log_info "启用 BBR 拥塞控制..."
    
    if ! sysctl net.ipv4.tcp_available_congestion_control | grep -q "bbr"; then
        log_warn "系统不支持 BBR，跳过"
        return
    fi

    cat > /etc/sysctl.d/bbr.conf << 'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    sysctl -p /etc/sysctl.d/bbr.conf
    log_info "BBR 已启用"
}

setup_firewall() {
    log_info "配置防火墙..."
    firewall_apply_rules
    log_info "UFW 防火墙已按基础端口与已启用模块配置"
}

setup_auto_update() {
    log_info "配置自动更新..."
    apt install -y unattended-upgrades
    dpkg-reconfigure -f noninteractive unattended-upgrades
}

setup_cron_jobs() {
    log_info "配置定时任务与系统日志限制..."
    maintenance_configure_logs
    cron_install_restart_job
}

select_from_env() {
    if [ -n "$EASYNET_PROFILE" ]; then
        choice="profile:$EASYNET_PROFILE"
        log_info "从环境变量 EASYNET_PROFILE 读取部署策略: $EASYNET_PROFILE"
        return 0
    fi

    if [ -n "$EASYNET_MODULE" ]; then
        choice="$EASYNET_MODULE"
        log_info "从环境变量 EASYNET_MODULE 读取部署模块: $EASYNET_MODULE"
        return 0
    fi

    if [ -n "$EASYNET_SERVICE_CHOICE" ]; then
        choice="$EASYNET_SERVICE_CHOICE"
        log_info "从环境变量 EASYNET_SERVICE_CHOICE 读取部署选择: $choice"
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
    echo "  EasyNet 代理服务器部署"
    echo "========================================"
    echo "0. 全部部署"
    for module_name in "${ALL_MODULES[@]}"; do
        if discovery_load_manifest "$module_name" 2>/dev/null; then
            printf "%d. 部署 %s\n" "$idx" "$MODULE_DISPLAY_NAME"
        else
            printf "%d. 部署 %s\n" "$idx" "$module_name"
        fi
        ((idx++))
    done
    printf "%d. 退出\n" "$idx"
    echo "========================================"
    echo -e "${YELLOW}提示: 编号 1-${#ALL_MODULES[@]} 按抗 DPI 能力从高到低排序。完成后请选择 ${idx} 退出。${NC}"
    read -r -p "请选择要部署的服务: " choice
}

module_is_known() {
    discovery_module_exists "$1"
}

module_display_name() {
    if discovery_load_manifest "$1" 2>/dev/null; then
        echo "$MODULE_DISPLAY_NAME"
    else
        echo "$1"
    fi
}

module_entrypoint() {
    discovery_module_entrypoint "$1"
}

module_export_script() {
    discovery_module_export_script "$1"
}

deploy_edge_gateway() {
    bash "$DEPLOY_SCRIPT_DIR/exposure/edge/deploy.sh"
}

module_requires_edge() {
    local module="$1"
    if ! discovery_load_manifest "$module" 2>/dev/null; then
        return 1
    fi
    [ "$MODULE_EDGE_MODE" = "backend" ] || [ "$MODULE_EDGE_MODE" = "shared_tls" ]
}

edge_gateway_enabled() {
    local module

    if [ -n "$EASYNET_SUBSCRIPTION_DOMAIN" ] || [ -n "$EASYNET_DOMAIN" ]; then
        return 0
    fi

    for module in "${DEPLOY_SELECTION_MODULES[@]}"; do
        if module_requires_edge "$module"; then
            return 0
        fi
    done

    return 1
}

ensure_edge_domain() {
    if ! edge_gateway_enabled; then
        return 0
    fi

    if [ -n "$EASYNET_DOMAIN" ] || [ -n "$EASYNET_SUBSCRIPTION_DOMAIN" ]; then
        return 0
    fi

    read -r -p "请输入 Edge Gateway 绑定域名: " EASYNET_DOMAIN
    if [ -z "$EASYNET_DOMAIN" ]; then
        log_error "Edge Gateway 域名不能为空"
        return 1
    fi
    # Validate domain format
    if ! [[ "$EASYNET_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "域名格式无效: $EASYNET_DOMAIN"
        return 1
    fi
    export EASYNET_DOMAIN
}

export_route_env_for_module() {
    local module="$1"

    if ! discovery_load_manifest "$module" 2>/dev/null; then
        return 1
    fi

    # Backend-mode protocols need an nginx reverse-proxy route
    if [ "$MODULE_EDGE_MODE" = "backend" ]; then
        ensure_edge_backend_route "$module"
    fi
}

prepare_module_dependencies() {
    export_route_env_for_module "$1"
}

resolve_profile_modules() {
    profile_resolve "$1"
}

resolve_modules() {
    local selection="$1"

    case "$selection" in
        profile:*) resolve_profile_modules "${selection#profile:}" ;;
        0) printf '%s\n' "${ALL_MODULES[@]}" ;;
        [0-9]|[0-9][0-9])
            local index=$((selection - 1))
            if [ "$index" -ge 0 ] && [ "$index" -lt "${#ALL_MODULES[@]}" ]; then
                echo "${ALL_MODULES[$index]}"
            elif [ "$selection" = "$(( ${#ALL_MODULES[@]} + 1 ))" ]; then
                echo "__exit__"
            else
                return 1
            fi
            ;;
        __exit__) echo "__exit__" ;;
        *)
            if module_is_known "$selection"; then
                echo "$selection"
            else
                return 1
            fi
            ;;
    esac
}

create_backup() {
    local state_dir backup_dir
    state_dir="$(easynet_state_dir)"
    if [ -d "$state_dir" ]; then
        backup_dir="/var/lib/easynet/backups"
        mkdir -p "$backup_dir" && chmod 700 "$backup_dir"
        BACKUP_FILE=$(mktemp "$backup_dir/easynet_backup.XXXXXX.tar.gz")
        if tar czf "$BACKUP_FILE" -C "$(dirname "$state_dir")" "$(basename "$state_dir")" 2>/dev/null; then
            chmod 600 "$BACKUP_FILE"
            log_info "已备份当前状态: $BACKUP_FILE"
        else
            log_warn "状态目录备份失败，跳过回滚保护"
            rm -f "$BACKUP_FILE" 2>/dev/null || true
            BACKUP_FILE=""
        fi
    else
        log_info "无已部署状态，跳过备份"
    fi
}

rollback() {
    local exit_code=$?
    if [ "${EASYNET_AUTO_ROLLBACK:-false}" = "true" ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        log_warn "部署失败 (退出码: $exit_code)，正在自动回滚..."
        local state_dir
        state_dir="$(easynet_state_dir)"
        rm -rf "$state_dir" 2>/dev/null || true
        if tar xzf "$BACKUP_FILE" -C "$(dirname "$state_dir")" 2>/dev/null; then
            rm -f "$BACKUP_FILE" 2>/dev/null || true
            log_info "回滚完成，状态已恢复至部署前"
        else
            log_error "回滚失败，请手动恢复: $BACKUP_FILE"
        fi
    fi
}

deploy_module() {
    local module="$1"
    local entrypoint

    entrypoint=$(module_entrypoint "$module") || {
        log_error "未知模块: $module"
        return 1
    }

    log_info "开始部署 $(module_display_name "$module")..."
    prepare_module_dependencies "$module"
    bash "$entrypoint"

    # Export metadata after deployment (orchestrator responsibility)
    local export_script
    export_script=$(module_export_script "$module") || true
    if [ -n "$export_script" ]; then
        bash "$export_script"
    fi
}

deploy_modules() {
    local module
    DEPLOY_SELECTION_MODULES=("$@")

    # Pre-flight validation (non-fatal by default; set EASYNET_STRICT_PRECHECK=true to abort on failure)
    if ! validate_easynet_config "$@"; then
        if [ "${EASYNET_STRICT_PRECHECK:-false}" = "true" ]; then
            log_error "预检失败，部署中止。设置 EASYNET_STRICT_PRECHECK=false 可跳过预检继续部署。"
            exit 1
        fi
        log_warn "预检发现警告项，继续部署..."
    fi

    if [ "${EASYNET_AUTO_ROLLBACK:-false}" = "true" ]; then
        create_backup
    fi

    ensure_edge_domain
    if edge_gateway_enabled; then
        deploy_edge_gateway
    fi
    for module in "$@"; do
        deploy_module "$module"
    done
    if edge_gateway_enabled; then
        systemctl restart nginx >/dev/null 2>&1 || true
    fi
    bash "$DEPLOY_SCRIPT_DIR/generate_subscription.sh"
    setup_firewall
    setup_cron_jobs
}

main() {
    load_env_file
    check_root
    check_os

    bootstrap_system
    bootstrap_security

    while true; do
        show_menu
        mapfile -t selected_modules < <(resolve_modules "$choice") || {
            log_error "无效选择"
            continue
        }

        if [ "${selected_modules[0]}" = "__exit__" ]; then
            log_info "退出安装"
            exit 0
        fi

        if [ "${EASYNET_AUTO_ROLLBACK:-false}" = "true" ]; then
            trap 'rollback' ERR
        fi
        deploy_modules "${selected_modules[@]}"
        if [ "${EASYNET_AUTO_ROLLBACK:-false}" = "true" ]; then
            trap - ERR
            rm -f "$BACKUP_FILE" 2>/dev/null || true
        fi
        
        # 如果使用环境变量进行自动化部署，执行一次后自动退出，避免死循环
        if [ -n "$EASYNET_SERVICE_CHOICE" ] || [ -n "$EASYNET_MODULE" ] || [ -n "$EASYNET_PROFILE" ]; then
            log_info "自动化部署完成，退出脚本。"
            exit 0
        fi
        
        echo ""
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -eE
    trap '_easynet_error_handler' ERR
    main "$@"
fi
