#!/bin/bash

set -e

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables from .env if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    log_info "发现 .env 文件，加载环境变量..."
    # 使用 export 确保子脚本也能继承这些变量，并忽略以 # 开头的注释行
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

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
    
    if command -v ufw &>/dev/null; then
        # 移除 ufw --force reset 以防止清空之前添加的其他服务端口规则
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8443/tcp
        ufw allow 8388/tcp
        ufw allow 51820/udp
        
        # 如果 ufw 尚未启用，则启用它
        if ! ufw status | grep -q "Status: active"; then
            ufw --force enable
        fi
        
        # 恢复安全的默认 DROP 策略（如果之前被修改过）
        if [[ -f /etc/default/ufw ]]; then
            sed -i 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/g' /etc/default/ufw
            ufw reload &>/dev/null || true
        fi
        
        log_info "UFW 防火墙已配置"
    fi
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

    # 每日凌晨4点重启核心服务以释放内存
    (crontab -l 2>/dev/null | grep -v "systemctl restart"; echo "0 4 * * * /usr/bin/systemctl restart trojan-go v2ray xray shadowsocks-libev-server 2>/dev/null") | crontab -
}

show_menu() {
    if [ -n "$EASYNET_SERVICE_CHOICE" ]; then
        choice="$EASYNET_SERVICE_CHOICE"
        log_info "从环境变量 EASYNET_SERVICE_CHOICE 读取部署选择: $choice"
        return
    fi
    echo "========================================"
    echo "  EasyNet 代理服务器部署"
    echo "========================================"
    echo "1. 部署 Trojan-Go (推荐)"
    echo "2. 部署 V2Ray"
    echo "3. 部署 Shadowsocks-libev"
    echo "4. 部署 WireGuard"
    echo "5. 部署 Xray+Reality"
    echo "6. 全部部署"
    echo "7. 退出"
    echo "========================================"
    echo -e "${YELLOW}提示: 如果您已完成所需服务的部署，请选择 7 退出。${NC}"
    read -p "请选择要部署的服务: " choice
}

deploy_trojan() {
    log_info "开始部署 Trojan-Go..."
    bash "$SCRIPT_DIR/server/trojan-go.sh"
}

deploy_v2ray() {
    log_info "开始部署 V2Ray..."
    bash "$SCRIPT_DIR/server/v2ray.sh"
}

deploy_shadowsocks() {
    log_info "开始部署 Shadowsocks..."
    bash "$SCRIPT_DIR/server/shadowsocks.sh"
}

deploy_wireguard() {
    log_info "开始部署 WireGuard..."
    bash "$SCRIPT_DIR/server/wireguard.sh"
}

deploy_xray() {
    log_info "开始部署 Xray+Reality..."
    bash "$SCRIPT_DIR/server/xray-reality.sh"
}

main() {
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
        case $choice in
            1)
                deploy_trojan
                bash "$SCRIPT_DIR/generate_subscription.sh"
                ;;
            2)
                deploy_v2ray
                bash "$SCRIPT_DIR/generate_subscription.sh"
                ;;
            3)
                deploy_shadowsocks
                bash "$SCRIPT_DIR/generate_subscription.sh"
                ;;
            4)
                deploy_wireguard
                ;;
            5)
                deploy_xray
                bash "$SCRIPT_DIR/generate_subscription.sh"
                ;;
            6)
                deploy_trojan
                deploy_v2ray
                deploy_shadowsocks
                deploy_wireguard
                deploy_xray
                bash "$SCRIPT_DIR/generate_subscription.sh"
                ;;
            7)
                log_info "退出安装"
                exit 0
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
        
        # 如果使用环境变量进行自动化部署，执行一次后自动退出，避免死循环
        if [ -n "$EASYNET_SERVICE_CHOICE" ]; then
            log_info "自动化部署完成，退出脚本。"
            exit 0
        fi
        
        echo ""
    done
}

main "$@"
