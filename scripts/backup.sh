#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BACKUP_DIR="/root/easynet_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_ARCHIVE="${BACKUP_DIR}.tar.gz"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

backup_configs() {
    log_info "开始备份 EasyNet 配置..."
    mkdir -p "$BACKUP_DIR"

    # 1. 备份 Trojan-Go
    if [ -d "/etc/trojan-go" ]; then
        log_info "备份 Trojan-Go 配置..."
        cp -r /etc/trojan-go "$BACKUP_DIR/"
    fi
    if [ -d "/etc/ssl/trojan-go" ]; then
        log_info "备份 Trojan-Go 证书..."
        mkdir -p "$BACKUP_DIR/ssl"
        cp -r /etc/ssl/trojan-go "$BACKUP_DIR/ssl/"
    fi

    # 2. 备份 V2Ray
    if [ -d "/usr/local/etc/v2ray"    if [ -d "/usr/local/etc/v2ray"    if [ -d "/usr/local/etc/v2ray "    if [ -R/v    i
                 r/                  "                 r"
           if            if            if            if      "�           if            if            if       _D           if            if            if      IR/           if            if            if            if/e           if            if           log_info "备份           if            i                if            if            if            if             ifireGuard
    if [ -d "/etc/wire    if [ -d "/etc/wire    if [ -d "/etc/wireGu    if [ -d "/etc/wire    -r    if [ -d "/etc/wire  _D    if [ -d "/etc/wire    if [ -d "      if [ -d "/etc/wire    if [ -d "/etc/wire      if [ -d "/etc/wire    if [ -d "/etc/w cp    ius    if [ -d "/etc/wire    if [ -d "/etc
                                             f "/etc/nginx/sites-available/easynet                                             f "/e�     ��.                     "                                             f "/etc/nginx/sites-available/easynet                                      .s                                             f "/etc/ngithen
        log_info "备份 ACME.sh 数据..."
        cp -r /root/.acme.sh "$BACKUP_DIR/"
    fi

    # 打包压缩
    log_info "打包备份文件..."
    tar -czf "$BACKUP_ARCHIVE" -C /root "$(basename "$BACKUP_DIR")"
    rm -rf "$BACKUP_DIR"

    echo ""
    echo "========================================"
    echo -e "${GREEN}备份完成！${NC}"
    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备份文件路径    echo "备�ot
    backup_configs
}

main "$@"
