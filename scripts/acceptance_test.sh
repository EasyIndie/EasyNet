#!/bin/bash
# EasyNet VPS 验收脚本（初步验收：本地 tarball + file:// 模式）
#
# 覆盖：
#   1. 校验失败中止（防篡改 / fail-closed）
#   2. 一键安装（安装机制）
#   3. .env 保留与升级
#   4. balanced 真实部署（Edge + Xray+Reality + Hysteria2）
#   5. 订阅生成
#   6. uninstall 全卸载
#
# 用法（在测试 VPS 上以 root 运行，源码目录即脚本上级）：
#   EASYNET_DOMAIN=test-world.jokerhub.cn bash scripts/acceptance_test.sh
#
# 环境变量：
#   EASYNET_DOMAIN                测试域名（真实部署必需；缺省则跳过第 4/5 步）
#   EASYNET_ACCEPT_WORK           工作目录（默认 /tmp/easynet-accept）
#   EASYNET_ACCEPT_INSTALL_DIR    安装目录（默认 /opt/easynet）
#   EASYNET_ACCEPT_SKIP_DEPLOY    设为 1 只做第 1-3 步
#   EASYNET_ACCEPT_SKIP_UNINSTALL 设为 1 跳过第 6 步

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
WORK="${EASYNET_ACCEPT_WORK:-/tmp/easynet-accept}"
INSTALL_DIR="${EASYNET_ACCEPT_INSTALL_DIR:-/opt/easynet}"
DOMAIN="${EASYNET_DOMAIN:-}"
SKIP_DEPLOY="${EASYNET_ACCEPT_SKIP_DEPLOY:-0}"
SKIP_UNINSTALL="${EASYNET_ACCEPT_SKIP_UNINSTALL:-0}"

RELEASE_ROOT="$WORK/release"
RELEASE_DIR="$RELEASE_ROOT/download/test"
TARBALL="easynet.tar.gz"
CHECKSUM="$TARBALL.sha256"

PASS=0
FAIL=0
SKIP=0

log() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
pass() {
    PASS=$((PASS + 1))
    printf '   \033[1;32mPASS\033[0m %s\n' "$*"
}
fail() {
    FAIL=$((FAIL + 1))
    printf '   \033[1;31mFAIL\033[0m %s\n' "$*"
}
skip() {
    SKIP=$((SKIP + 1))
    printf '   \033[1;33mSKIP\033[0m %s\n' "$*"
}

require_root() {
    [ "$(id -u)" = "0" ] || {
        echo "请以 root 运行验收脚本" >&2
        exit 2
    }
}

check_os() {
    # shellcheck source=/dev/null  # 系统文件，路径固定
    . /etc/os-release
    case "${ID:-}" in
        ubuntu | debian) info "操作系统: ${PRETTY_NAME:-$ID}" ;;
        *)
            echo "仅支持 Ubuntu/Debian（检测到 ${ID:-unknown}）" >&2
            exit 2
            ;;
    esac
}

build_package() {
    rm -rf "$RELEASE_ROOT"
    mkdir -p "$RELEASE_DIR"
    tar czf "$RELEASE_DIR/$TARBALL" -C "$SRC_DIR" --exclude-vcs .
    (cd "$RELEASE_DIR" && sha256sum "$TARBALL" > "$CHECKSUM")
    info "已构建本地 release 包: $RELEASE_DIR/$TARBALL"
}

run_install() {
    # $1 = install dir; install-only mode so we can isolate the install mechanism
    local install_dir="$1"
    EASYNET_RELEASE_BASE_URL="file://$RELEASE_ROOT" \
        EASYNET_VERSION="test" \
        EASYNET_INSTALL_DIR="$install_dir" \
        EASYNET_INSTALL_ONLY="true" \
        bash "$SRC_DIR/scripts/install.sh"
}

phase_prepare() {
    log "P0 准备"
    require_root
    check_os
    info "源码目录: $SRC_DIR"
    info "工作目录: $WORK"
    info "安装目录: $INSTALL_DIR"

    if [ -x "$INSTALL_DIR/scripts/uninstall.sh" ]; then
        info "检测到已有安装，先执行卸载清理..."
        EASYNET_UNINSTALL_CHOICE=0 bash "$INSTALL_DIR/scripts/uninstall.sh" >/dev/null 2>&1 || true
    fi
    rm -rf "$INSTALL_DIR"
    build_package
}

phase_checksum() {
    log "P1 校验失败中止（防篡改）"
    local bad_dir="$WORK/opt-fail"

    cp "$RELEASE_DIR/$CHECKSUM" "$WORK/checksum.bak"
    printf 'deadbeef  %s\n' "$TARBALL" > "$RELEASE_DIR/$CHECKSUM"

    if run_install "$bad_dir" >/dev/null 2>&1; then
        fail "篡改校验后安装仍然成功（应中止）"
    else
        pass "篡改校验后安装被中止"
    fi
    if [ -e "$bad_dir/scripts/deploy.sh" ]; then
        fail "校验失败后仍留下安装文件: $bad_dir"
    else
        pass "校验失败后未留下安装目录"
    fi

    cp "$WORK/checksum.bak" "$RELEASE_DIR/$CHECKSUM"
}

phase_install() {
    log "P2 一键安装（安装机制）"
    if run_install "$INSTALL_DIR" >/dev/null 2>&1; then
        pass "安装器返回成功"
    else
        fail "安装器返回失败"
    fi
    if [ -x "$INSTALL_DIR/scripts/deploy.sh" ]; then
        pass "deploy.sh 已落地且可执行"
    else
        fail "deploy.sh 缺失或不可执行"
    fi
    if [ -f "$INSTALL_DIR/scripts/install.sh" ]; then
        pass "安装目录包含完整脚本"
    else
        fail "安装目录缺少 install.sh"
    fi
}

phase_env_upgrade() {
    log "P3 .env 保留与升级"
    local sentinel
    sentinel="# acceptance-upgrade-sentinel-$(date +%s)"

    printf 'EASYNET_PROFILE=balanced\nEASYNET_DOMAIN=%s\n' "$DOMAIN" > "$INSTALL_DIR/.env"

    # 给源码注入 sentinel，重建包后重装，验证脚本确实被刷新
    cp "$SRC_DIR/scripts/deploy.sh" "$WORK/deploy.sh.bak"
    printf '\n%s\n' "$sentinel" >> "$SRC_DIR/scripts/deploy.sh"
    build_package

    if run_install "$INSTALL_DIR" >/dev/null 2>&1; then
        pass "重复安装（升级）返回成功"
    else
        fail "重复安装（升级）失败"
    fi
    if grep -qF "$sentinel" "$INSTALL_DIR/scripts/deploy.sh"; then
        pass "升级后脚本已刷新"
    else
        fail "升级后脚本未刷新"
    fi

    cp "$WORK/deploy.sh.bak" "$SRC_DIR/scripts/deploy.sh"
    build_package

    if grep -q '^EASYNET_PROFILE=balanced$' "$INSTALL_DIR/.env" &&
        grep -qF "EASYNET_DOMAIN=$DOMAIN" "$INSTALL_DIR/.env"; then
        pass ".env 在升级后保留"
    else
        fail ".env 未保留"
    fi
}

phase_deploy() {
    log "P4 balanced 真实部署"
    if [ -z "$DOMAIN" ]; then
        skip "未提供 EASYNET_DOMAIN，跳过真实部署"
        return 0
    fi
    if [ "$SKIP_DEPLOY" = "1" ]; then
        skip "EASYNET_ACCEPT_SKIP_DEPLOY=1"
        return 0
    fi

    info "运行 deploy.sh（balanced, 域名 $DOMAIN）... 可能需要数分钟"
    if bash "$INSTALL_DIR/scripts/deploy.sh"; then
        pass "deploy.sh 退出码 0"
    else
        fail "deploy.sh 非零退出"
    fi

    local svc
    for svc in nginx xray hysteria-server.service; do
        if systemctl is-active --quiet "$svc"; then
            pass "服务运行中: $svc"
        else
            fail "服务未运行: $svc"
        fi
    done
    if [ -f /var/lib/easynet/modules/xray-reality/metadata.json ]; then
        pass "xray-reality metadata 存在"
    else
        fail "xray-reality metadata 缺失"
    fi
    if [ -f /var/lib/easynet/modules/hysteria2/metadata.json ]; then
        pass "hysteria2 metadata 存在"
    else
        fail "hysteria2 metadata 缺失"
    fi
    if [ -f /etc/ssl/easynet-edge/fullchain.crt ]; then
        pass "Edge 证书已签发"
    else
        fail "Edge 证书缺失"
    fi
}

phase_subscription() {
    log "P5 订阅生成"
    if [ -z "$DOMAIN" ] || [ "$SKIP_DEPLOY" = "1" ]; then
        skip "未部署，跳过订阅生成校验"
        return 0
    fi

    if bash "$INSTALL_DIR/scripts/generate_subscription.sh" >/dev/null 2>&1; then
        pass "generate_subscription.sh 退出码 0"
    else
        fail "generate_subscription.sh 非零退出"
    fi

    local f
    for f in sub clash singbox easynet-singbox-client.sh; do
        if [ -s "/var/www/html/$f" ]; then
            pass "订阅文件存在: $f"
        else
            fail "订阅文件缺失: $f"
        fi
    done

    if curl -fsS --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/clash" >/dev/null 2>&1; then
        pass "Edge HTTPS 订阅端点可访问: /clash"
    else
        fail "Edge HTTPS 订阅端点不可访问: /clash"
    fi
}

phase_uninstall() {
    log "P6 uninstall 全卸载"
    if [ "$SKIP_UNINSTALL" = "1" ]; then
        skip "EASYNET_ACCEPT_SKIP_UNINSTALL=1"
        return 0
    fi
    if [ ! -x "$INSTALL_DIR/scripts/uninstall.sh" ]; then
        skip "无安装目录，跳过卸载"
        return 0
    fi

    if EASYNET_UNINSTALL_CHOICE=0 bash "$INSTALL_DIR/scripts/uninstall.sh"; then
        pass "uninstall.sh 退出码 0"
    else
        fail "uninstall.sh 非零退出"
    fi

    local svc
    for svc in xray hysteria-server.service; do
        if systemctl is-active --quiet "$svc"; then
            fail "服务未停止: $svc"
        else
            pass "服务已停止: $svc"
        fi
    done
    if [ ! -f /var/lib/easynet/modules/xray-reality/metadata.json ]; then
        pass "metadata 已清理"
    else
        fail "metadata 未清理"
    fi
}

summary() {
    log "验收汇总"
    printf '   PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
    if [ "$FAIL" -eq 0 ]; then
        printf '   \033[1;32m结果: 通过\033[0m\n'
        return 0
    fi
    printf '   \033[1;31m结果: 失败\033[0m\n'
    return 1
}

main() {
    phase_prepare
    phase_checksum
    phase_install
    phase_env_upgrade
    phase_deploy
    phase_subscription
    phase_uninstall
    summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
