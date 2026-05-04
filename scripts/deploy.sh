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

DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$DEPLOY_SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/firewall.sh"
source "$PROJECT_ROOT/scripts/core/cron.sh"
source "$PROJECT_ROOT/scripts/core/env.sh"

ALL_MODULES=(xray-reality hysteria2 trojan-go v2ray shadowsocks wireguard)
BALANCED_MODULES=(xray-reality hysteria2)
DEPLOY_SELECTION_MODULES=()

load_env_file() {
    # Load environment variables from .env if it exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_info "发现 .env 文件，加载环境变量..."
        # 使用 export 确保子脚本也能继承这些变量，并忽略以 # 开头的注释行
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
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
    apt install -y curl wget git unzip ca-certificates gnupg2 lsb-release qrencode jq
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
    
    # 限制 systemd journald 日志大小，防止磁盘爆满
    if [ -f /etc/systemd/journald.conf ]; then
        sed -i 's/.*SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
        # 如果原来没有这一行，则追加
        if ! grep -q "SystemMaxUse=500M" /etc/systemd/journald.conf; then
            echo "SystemMaxUse=500M" >> /etc/systemd/journald.conf
        fi
        systemctl restart systemd-journald
    fi

    # 每日凌晨4点按已启用模块重启服务以释放内存
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

    echo "========================================"
    echo "  EasyNet 代理服务器部署"
    echo "========================================"
    echo "0. 全部部署"
    echo "1. 部署 Xray+Reality (最高安全/抗 DPI)"
    echo "2. 部署 Hysteria2"
    echo "3. 部署 Trojan-Go"
    echo "4. 部署 V2Ray"
    echo "5. 部署 Shadowsocks-libev"
    echo "6. 部署 WireGuard"
    echo "7. 退出"
    echo "========================================"
    echo -e "${YELLOW}提示: 编号 1-6 按安全性和抗 DPI 能力从高到低排序。完成后请选择 7 退出。${NC}"
    read -p "请选择要部署的服务: " choice
}

module_is_known() {
    local module="$1"
    local known
    for known in "${ALL_MODULES[@]}"; do
        if [ "$module" = "$known" ]; then
            return 0
        fi
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
        *) echo "$1" ;;
    esac
}

module_entrypoint() {
    local protocol_entrypoint="$DEPLOY_SCRIPT_DIR/protocols/$1/deploy.sh"
    if [ -x "$protocol_entrypoint" ]; then
        echo "$protocol_entrypoint"
    else
        return 1
    fi
}

deployment_includes_module() {
    local target="$1"
    local module
    for module in "${DEPLOY_SELECTION_MODULES[@]}"; do
        if [ "$module" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

deploy_edge_gateway() {
    bash "$DEPLOY_SCRIPT_DIR/exposure/edge/deploy.sh"
}

module_uses_edge_backend() {
    case "$1" in
        trojan-go|v2ray) return 0 ;;
        *) return 1 ;;
    esac
}

module_requires_edge() {
    case "$1" in
        hysteria2|trojan-go|v2ray) return 0 ;;
        *) return 1 ;;
    esac
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

    read -p "请输入 Edge Gateway 绑定域名: " EASYNET_DOMAIN
    if [ -z "$EASYNET_DOMAIN" ]; then
        log_error "Edge Gateway 域名不能为空"
        return 1
    fi
    export EASYNET_DOMAIN
}

edge_public_domain() {
    echo "${EASYNET_SUBSCRIPTION_DOMAIN:-${EASYNET_DOMAIN:-}}"
}

protocol_public_domain() {
    echo "${EASYNET_DOMAIN:-${EASYNET_SUBSCRIPTION_DOMAIN:-}}"
}

ensure_edge_trojan_route() {
    local edge_state_dir edge_routes_dir route_path route_domain

    edge_state_dir="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
    edge_routes_dir="$edge_state_dir/routes"
    mkdir -p "$edge_routes_dir"

    if [ -n "$EASYNET_TROJAN_WS_PATH" ]; then
        route_path="$EASYNET_TROJAN_WS_PATH"
    elif [ -f "$edge_state_dir/trojan_path.txt" ]; then
        route_path=$(cat "$edge_state_dir/trojan_path.txt")
    else
        route_path="/$(openssl rand -hex 16)"
        echo "$route_path" > "$edge_state_dir/trojan_path.txt"
    fi

    route_domain="$(protocol_public_domain)"

    export EASYNET_TROJAN_PORT="${EASYNET_TROJAN_PORT:-4444}"
    export EASYNET_TROJAN_LISTEN="${EASYNET_TROJAN_LISTEN:-127.0.0.1}"
    export EASYNET_TROJAN_PUBLIC_PORT="${EASYNET_TROJAN_PUBLIC_PORT:-443}"
    export EASYNET_TROJAN_WS_PATH="$route_path"
    export EASYNET_TROJAN_CERT_DIR="${EASYNET_TROJAN_CERT_DIR:-${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}}"

    cat > "$edge_routes_dir/trojan-go.conf" <<EOF
location ${route_path} {
    access_log off;
    proxy_redirect off;
    proxy_pass https://127.0.0.1:${EASYNET_TROJAN_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_ssl_server_name on;
    proxy_ssl_name ${route_domain};
    proxy_ssl_verify off;
}
EOF
}

ensure_edge_v2ray_route() {
    local edge_state_dir edge_routes_dir route_path

    edge_state_dir="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
    edge_routes_dir="$edge_state_dir/routes"
    mkdir -p "$edge_routes_dir"

    if [ -n "$EASYNET_V2RAY_WS_PATH" ]; then
        route_path="$EASYNET_V2RAY_WS_PATH"
    elif [ -f "$edge_state_dir/v2ray_path.txt" ]; then
        route_path=$(cat "$edge_state_dir/v2ray_path.txt")
    else
        route_path="/$(openssl rand -hex 16)"
        echo "$route_path" > "$edge_state_dir/v2ray_path.txt"
    fi

    export EASYNET_V2RAY_PORT="${EASYNET_V2RAY_PORT:-4443}"
    export EASYNET_V2RAY_LISTEN="${EASYNET_V2RAY_LISTEN:-127.0.0.1}"
    export EASYNET_V2RAY_PUBLIC_PORT="${EASYNET_V2RAY_PUBLIC_PORT:-443}"
    export EASYNET_V2RAY_WS_PATH="$route_path"

    cat > "$edge_routes_dir/v2ray.conf" <<EOF
location ${route_path} {
    access_log off;
    proxy_redirect off;
    proxy_pass http://127.0.0.1:${EASYNET_V2RAY_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}
EOF
}

export_route_env_for_module() {
    local module="$1"

    case "$module" in
        trojan-go)
            ensure_edge_trojan_route
            ;;
        v2ray)
            ensure_edge_v2ray_route
            ;;
    esac
}

prepare_module_dependencies() {
    export_route_env_for_module "$1"
}

resolve_profile_modules() {
    case "$1" in
        strict) echo "xray-reality" ;;
        balanced) printf '%s\n' "${BALANCED_MODULES[@]}" ;;
        compat) printf '%s\n' "${ALL_MODULES[@]}" ;;
        *) return 1 ;;
    esac
}

resolve_modules() {
    local selection="$1"

    case "$selection" in
        profile:*) resolve_profile_modules "${selection#profile:}" ;;
        0) printf '%s\n' "${ALL_MODULES[@]}" ;;
        1) echo "xray-reality" ;;
        2) echo "hysteria2" ;;
        3) echo "trojan-go" ;;
        4) echo "v2ray" ;;
        5) echo "shadowsocks" ;;
        6) echo "wireguard" ;;
        7) echo "__exit__" ;;
        *)
            if module_is_known "$selection"; then
                echo "$selection"
            else
                return 1
            fi
            ;;
    esac
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
}

deploy_modules() {
    local module
    DEPLOY_SELECTION_MODULES=("$@")
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

    update_system
    install_dependencies
    enable_bbr
    setup_firewall
    setup_auto_update
    setup_cron_jobs

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

        deploy_modules "${selected_modules[@]}"
        
        # 如果使用环境变量进行自动化部署，执行一次后自动退出，避免死循环
        if [ -n "$EASYNET_SERVICE_CHOICE" ] || [ -n "$EASYNET_MODULE" ] || [ -n "$EASYNET_PROFILE" ]; then
            log_info "自动化部署完成，退出脚本。"
            exit 0
        fi
        
        echo ""
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e
    main "$@"
fi
