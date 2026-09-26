#!/bin/bash
# EasyNet 自举安装器 (bootstrap installer)
#
# 目标：无需 git clone 即可在新 VPS 上部署 EasyNet。
# 流程：下载 release 包 -> 校验 SHA256 -> 解压到持久目录 -> 执行 scripts/deploy.sh
#
# 用法：
#   curl -fsSL https://github.com/EasyIndie/EasyNet/releases/latest/download/easynet-install.sh -o install.sh
#   sudo bash install.sh
#
# 自动化部署（其余 EASYNET_* 变量原样透传给 deploy.sh）：
#   sudo EASYNET_PROFILE=balanced EASYNET_DOMAIN=proxy.example.com bash install.sh

set -euo pipefail

# ---------------------------------------------------------
# 可配置项（均可用环境变量覆盖）
# ---------------------------------------------------------
EASYNET_REPO="${EASYNET_REPO:-EasyIndie/EasyNet}"
EASYNET_VERSION="${EASYNET_VERSION:-latest}"
EASYNET_INSTALL_DIR="${EASYNET_INSTALL_DIR:-/opt/easynet}"
EASYNET_SKIP_SHA256="${EASYNET_SKIP_SHA256:-false}"
EASYNET_INSTALL_ONLY="${EASYNET_INSTALL_ONLY:-false}"
EASYNET_RELEASE_BASE_URL="${EASYNET_RELEASE_BASE_URL:-https://github.com/${EASYNET_REPO}/releases}"

TARBALL_NAME="easynet.tar.gz"
CHECKSUM_NAME="${TARBALL_NAME}.sha256"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
EasyNet 自举安装器 — 无需 git clone 的一键部署

用法:
  curl -fsSL https://github.com/${EASYNET_REPO}/releases/latest/download/easynet-install.sh -o install.sh
  sudo bash install.sh

环境变量:
  EASYNET_VERSION          指定版本 tag（默认 latest）
  EASYNET_INSTALL_DIR      安装目录（默认 /opt/easynet）
  EASYNET_SKIP_SHA256      设为 true 跳过校验（仅开发，不推荐）
  EASYNET_INSTALL_ONLY     设为 true 只安装不部署（便于先配置 .env）
  EASYNET_REPO             仓库名（默认 ${EASYNET_REPO}）
  EASYNET_RELEASE_BASE_URL Releases 基础 URL（默认 GitHub）

其余 EASYNET_* 变量会原样传给 deploy.sh，例如:
  sudo EASYNET_PROFILE=balanced EASYNET_DOMAIN=proxy.example.com bash install.sh

参数:
  -h, --help    显示本帮助
EOF
}

require_root() {
    [ "$(id -u)" = "0" ] || die "请使用 root 运行，例如: sudo bash install.sh"
}

check_os() {
    local os=""
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null  # 系统文件，路径固定
        . /etc/os-release
        os="${ID:-}"
    fi
    case "$os" in
        ubuntu | debian) log "检测到操作系统: ${PRETTY_NAME:-$os}" ;;
        *) die "此脚本仅支持 Ubuntu 和 Debian 系统（检测到: ${os:-unknown}）" ;;
    esac
}

install_dependencies() {
    local missing=()
    command -v tar >/dev/null 2>&1 || missing+=(tar)
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing+=(curl)
    fi
    [ "${#missing[@]}" -eq 0 ] && return 0

    log "安装缺失依赖: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" ca-certificates
    else
        die "缺少依赖且无 apt-get: ${missing[*]}"
    fi
}

download() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    else
        wget -q -O "$output" "$url"
    fi
}

release_url() {
    local asset="$1"

    if [ "$EASYNET_VERSION" = "latest" ]; then
        printf '%s/latest/download/%s' "$EASYNET_RELEASE_BASE_URL" "$asset"
    else
        printf '%s/download/%s/%s' "$EASYNET_RELEASE_BASE_URL" "$EASYNET_VERSION" "$asset"
    fi
}

verify_checksum() {
    local work_dir="$1"
    local checksum_file="$work_dir/$CHECKSUM_NAME"

    [ -s "$checksum_file" ] ||
        die "校验文件缺失或为空，拒绝安装。确认无误后可设置 EASYNET_SKIP_SHA256=true 跳过（不推荐）"

    log "校验安装包 SHA256..."
    (cd "$work_dir" && sha256sum -c "$CHECKSUM_NAME") ||
        die "SHA256 校验失败，拒绝安装。请检查网络/镜像来源后重试"
}

install_package() {
    local work_dir="$1"
    local staging=""

    log "下载 EasyNet (${EASYNET_VERSION}): $(release_url "$TARBALL_NAME")"
    download "$(release_url "$TARBALL_NAME")" "$work_dir/$TARBALL_NAME" ||
        die "下载安装包失败: $(release_url "$TARBALL_NAME")"

    if [ "$EASYNET_SKIP_SHA256" = "true" ]; then
        warn "已跳过 SHA256 校验 (EASYNET_SKIP_SHA256=true)，仅建议开发环境使用"
    else
        download "$(release_url "$CHECKSUM_NAME")" "$work_dir/$CHECKSUM_NAME" ||
            die "下载校验文件失败: $(release_url "$CHECKSUM_NAME")"
        verify_checksum "$work_dir"
    fi

    log "解压安装包..."
    mkdir -p "$work_dir/extract"
    tar -xzf "$work_dir/$TARBALL_NAME" -C "$work_dir/extract"
    [ -f "$work_dir/extract/scripts/deploy.sh" ] ||
        die "安装包结构异常：缺少 scripts/deploy.sh"

    # 校验通过后再落到持久目录；staging 与目标同盘，保证 mv 为原子替换
    staging="${EASYNET_INSTALL_DIR}.staging.$$"
    rm -rf "$staging"
    mkdir -p "$(dirname "$EASYNET_INSTALL_DIR")"
    mv "$work_dir/extract" "$staging"

    # 保留已存在的 .env，避免升级时丢失用户配置
    if [ -f "$EASYNET_INSTALL_DIR/.env" ]; then
        cp "$EASYNET_INSTALL_DIR/.env" "$staging/.env"
        log "已保留现有配置: $EASYNET_INSTALL_DIR/.env"
    fi

    rm -rf "$EASYNET_INSTALL_DIR"
    mv "$staging" "$EASYNET_INSTALL_DIR"
    chmod 0755 "$EASYNET_INSTALL_DIR/scripts/deploy.sh" 2>/dev/null || true
    log "已安装到: $EASYNET_INSTALL_DIR"
}

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h | --help)
                usage
                exit 0
                ;;
        esac
    done

    require_root
    check_os
    install_dependencies

    local tmp_dir=""
    tmp_dir="$(mktemp -d /tmp/easynet-install.XXXXXX)"
    # shellcheck disable=SC2317  # 由 EXIT trap 触发，静态分析无法感知
    cleanup() { rm -rf "${tmp_dir:-}"; }
    trap cleanup EXIT

    install_package "$tmp_dir"

    cleanup
    tmp_dir=""
    trap - EXIT

    if [ "$EASYNET_INSTALL_ONLY" = "true" ]; then
        log "已安装到 $EASYNET_INSTALL_DIR（EASYNET_INSTALL_ONLY=true，跳过部署）"
        exit 0
    fi

    log "启动 EasyNet 部署..."
    exec bash "$EASYNET_INSTALL_DIR/scripts/deploy.sh" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
