#!/bin/bash
# Upstream dependency pins: exact version + SHA256 of the artifact EasyNet installs.
#
# Why this exists
# ---------------
# Every installer downloads a binary or a script from a third party and then runs
# it as root. Without a pin, a compromised or silently-changed upstream artifact
# is executed with full privileges. The pins below live in the repository (so a
# change is visible in a PR/review) and are verified by default.
#
# Where each hash comes from (always the vendor's own release metadata):
#   Xray     -> <asset>.zip.dgst   `SHA2-256=` line of the official release asset
#   Hysteria -> hashes.txt         shipped in the release
#   SS-rust  -> <asset>.tar.xz.sha256
#   acme.sh  -> sha256 of get.acme.sh at the pinned version
#
# Policy
# ------
#   * No override        -> pinned version + pinned SHA256, always verified.
#   * Version override   -> must also supply the checksum, otherwise the install
#                           aborts (set EASYNET_ALLOW_UNPINNED=1 to downgrade to a
#                           warning when you really need to).
#
# Refresh procedure (see scripts/check_upstream_pins.sh for the "is it stale?" check):
#   1. bump the version + hash constants below
#   2. run the test suite and deploy to a throwaway VPS
#   3. commit with the upstream release notes linked

# shellcheck disable=SC2034  # constants are read by accessors below / sourced by callers
EASYNET_PIN_XRAY_VERSION="26.3.27"
EASYNET_PIN_XRAY_SHA256_X86_64="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
EASYNET_PIN_XRAY_SHA256_AARCH64="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c"

EASYNET_PIN_HYSTERIA2_VERSION="2.12.3"
EASYNET_PIN_HYSTERIA2_SHA256_X86_64="8c7a68a906998b747a0db87586e364f995fbfddb95693ae6e2fdb68a6e920d3e"
EASYNET_PIN_HYSTERIA2_SHA256_AARCH64="c8dc653c3ba0a28d29a26b8fa52d2086f27c0927afddce95c09965e7174e78b0"

EASYNET_PIN_SHADOWSOCKS_VERSION="1.25.0"
EASYNET_PIN_SHADOWSOCKS_SHA256_X86_64="874f817fcf3e6d7681ec715a1c13c686c6eaae936524d102639b38364f3966ae"
EASYNET_PIN_SHADOWSOCKS_SHA256_AARCH64="9c3b7fd2df1b7fd12cd80bb3b57d9de98a0fb526921669c3ac40587b88be3009"

EASYNET_PIN_ACME_VERSION="3.1.6"
EASYNET_PIN_ACME_SHA256="8681df828f7765a351a4fc708a46fc3f7f383c0155fe4b19002d20e5c4ee5431"

# ---------------------------------------------------------------------------
# 客户端校验工具（**不参与部署**：服务端不装它们）
# ---------------------------------------------------------------------------
# 用途：发布前用**真实客户端二进制**校验我们生成的订阅能不能被接受。
# 为什么必须 pin：不 pin 就不可复现——"用最新版验过了"无法回答"验的是哪个版本"，
# 而客户端方言变化恰恰会打穿我们生成的配置（0.0.13 的 mihomo `hop-interval` 事故）。
# 哈希来自官方 release 资产本身（两项目都不发布校验文件，故为本仓库实测并记录）。
#
# 刷新步骤：改版本 + 三个平台的哈希 → 同步
# scripts/clients/install_singbox_client.sh 里内联的 sing-box 常量
# （tests/test_singbox_client_installer.bats 有防漂移断言）→ 跑一遍真二进制校验。
# shellcheck disable=SC2034  # 常量由下面的访问器读取
EASYNET_PIN_MIHOMO_VERSION="1.19.31"
EASYNET_PIN_MIHOMO_SHA256_LINUX_AMD64="d5e74bbddbdfff49a1aef7775bf5911da59f0d7196ed509a0ac914b3653dd5f1"
EASYNET_PIN_MIHOMO_SHA256_LINUX_ARM64="9e0f11afbf38426b8bd88fdc594678f8161c57eccb4e1b77acb12b493904f1d4"
EASYNET_PIN_MIHOMO_SHA256_DARWIN_AMD64="3546681ebef3415e5dcbe7210a61aa80748136e95e6552768fd883df345508ed"

# shellcheck disable=SC2034  # 同上，参见 install_singbox_client.sh 的防漂移测试
EASYNET_PIN_SINGBOX_VERSION="1.14.2"
EASYNET_PIN_SINGBOX_SHA256_LINUX_AMD64="a684484d7477d1437282ee411f4d131d0340aaad60a7868841ebd5d87dd8a0c6"
EASYNET_PIN_SINGBOX_SHA256_LINUX_ARM64="b43a1fb1bda131c6653576741ce527eb2bdeab7c9308ca90ee8b972abb7e4a7f"
EASYNET_PIN_SINGBOX_SHA256_DARWIN_AMD64="b0bfb0dc70a5fc708710b9f5ea98b9ee76d40fa4169928d25d73edc4331df2fe"

# 当前平台标识：linux_amd64 / linux_arm64 / darwin_amd64（不支持则无输出）
easynet_client_platform() {
    local os arch
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="darwin" ;;
        *)      return 0 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             return 0 ;;
    esac
    printf '%s_%s' "$os" "$arch"
}

# 当前平台上某个客户端工具的 pin 哈希（未 pin 该平台则无输出）
easynet_client_pin_sha256() {
    local platform
    platform="$(easynet_client_platform)"
    case "${1:-}:${platform}" in
        mihomo:linux_amd64)   printf '%s' "$EASYNET_PIN_MIHOMO_SHA256_LINUX_AMD64" ;;
        mihomo:linux_arm64)   printf '%s' "$EASYNET_PIN_MIHOMO_SHA256_LINUX_ARM64" ;;
        mihomo:darwin_amd64)  printf '%s' "$EASYNET_PIN_MIHOMO_SHA256_DARWIN_AMD64" ;;
        singbox:linux_amd64)  printf '%s' "$EASYNET_PIN_SINGBOX_SHA256_LINUX_AMD64" ;;
        singbox:linux_arm64)  printf '%s' "$EASYNET_PIN_SINGBOX_SHA256_LINUX_ARM64" ;;
        singbox:darwin_amd64) printf '%s' "$EASYNET_PIN_SINGBOX_SHA256_DARWIN_AMD64" ;;
        *)                    return 0 ;;
    esac
}

# 官方 release 资产名（mihomo 是 .gz，sing-box 是 .tar.gz）
easynet_client_pin_asset() {
    local platform
    platform="$(easynet_client_platform)"
    case "${1:-}" in
        mihomo)
            case "$platform" in
                linux_amd64)  printf 'mihomo-linux-amd64-v%s.gz' "$EASYNET_PIN_MIHOMO_VERSION" ;;
                linux_arm64)  printf 'mihomo-linux-arm64-v%s.gz' "$EASYNET_PIN_MIHOMO_VERSION" ;;
                darwin_amd64) printf 'mihomo-darwin-amd64-v%s.gz' "$EASYNET_PIN_MIHOMO_VERSION" ;;
            esac
            ;;
        singbox)
            case "$platform" in
                linux_amd64)  printf 'sing-box-%s-linux-amd64.tar.gz' "$EASYNET_PIN_SINGBOX_VERSION" ;;
                linux_arm64)  printf 'sing-box-%s-linux-arm64.tar.gz' "$EASYNET_PIN_SINGBOX_VERSION" ;;
                darwin_amd64) printf 'sing-box-%s-darwin-amd64.tar.gz' "$EASYNET_PIN_SINGBOX_VERSION" ;;
            esac
            ;;
    esac
}

# 官方 release 下载 URL（未 pin 当前平台则无输出）
easynet_client_pin_url() {
    local asset
    asset="$(easynet_client_pin_asset "${1:-}")"
    [ -n "$asset" ] || return 0
    case "${1:-}" in
        mihomo)  printf 'https://github.com/MetaCubeX/mihomo/releases/download/v%s/%s' "$EASYNET_PIN_MIHOMO_VERSION" "$asset" ;;
        singbox) printf 'https://github.com/SagerNet/sing-box/releases/download/v%s/%s' "$EASYNET_PIN_SINGBOX_VERSION" "$asset" ;;
    esac
}

# Pinned SHA256 for a component on the current architecture.
# Prints nothing when the architecture is unsupported (caller decides).
easynet_pin_sha256() {
    local component="$1"
    local arch
    arch="$(detect_arch)"

    case "${component}:${arch}" in
        xray:x86_64)           printf '%s' "$EASYNET_PIN_XRAY_SHA256_X86_64" ;;
        xray:aarch64)          printf '%s' "$EASYNET_PIN_XRAY_SHA256_AARCH64" ;;
        hysteria2:x86_64)      printf '%s' "$EASYNET_PIN_HYSTERIA2_SHA256_X86_64" ;;
        hysteria2:aarch64)     printf '%s' "$EASYNET_PIN_HYSTERIA2_SHA256_AARCH64" ;;
        shadowsocks:x86_64)    printf '%s' "$EASYNET_PIN_SHADOWSOCKS_SHA256_X86_64" ;;
        shadowsocks:aarch64)   printf '%s' "$EASYNET_PIN_SHADOWSOCKS_SHA256_AARCH64" ;;
        acme:*)                printf '%s' "$EASYNET_PIN_ACME_SHA256" ;;
        *)                     return 0 ;;
    esac
}

# Pinned release asset name for a component on the current architecture.
easynet_pin_asset() {
    local component="$1"
    local arch
    arch="$(detect_arch)"

    case "$component" in
        xray)
            case "$arch" in
                x86_64)  printf 'Xray-linux-64.zip' ;;
                aarch64) printf 'Xray-linux-arm64-v8a.zip' ;;
            esac
            ;;
        hysteria2)
            case "$arch" in
                x86_64)  printf 'hysteria-linux-amd64' ;;
                aarch64) printf 'hysteria-linux-arm64' ;;
            esac
            ;;
        shadowsocks)
            case "$arch" in
                x86_64)  printf 'shadowsocks-v%s.x86_64-unknown-linux-gnu.tar.xz' "$EASYNET_PIN_SHADOWSOCKS_VERSION" ;;
                aarch64) printf 'shadowsocks-v%s.aarch64-unknown-linux-gnu.tar.xz' "$EASYNET_PIN_SHADOWSOCKS_VERSION" ;;
            esac
            ;;
    esac
}

# easynet_resolve_pin <xray|hysteria2|shadowsocks|acme>
# Resolves the effective "<version>|<sha256>" for a component, honouring user
# overrides, and refuses to continue when a version was overridden without a
# checksum (unless EASYNET_ALLOW_UNPINNED=1).
easynet_resolve_pin() {
    local component="$1"
    local version="" sha256=""

    case "$component" in
        xray)
            version="${EASYNET_XRAY_VERSION:-$EASYNET_PIN_XRAY_VERSION}"
            if [ "$version" = "$EASYNET_PIN_XRAY_VERSION" ]; then
                sha256="$(easynet_pin_sha256 xray)"
            else
                sha256="${EASYNET_XRAY_SHA256:-}"
            fi
            ;;
        hysteria2)
            version="${EASYNET_HYSTERIA2_VERSION:-$EASYNET_PIN_HYSTERIA2_VERSION}"
            if [ "$version" = "$EASYNET_PIN_HYSTERIA2_VERSION" ]; then
                sha256="$(easynet_pin_sha256 hysteria2)"
            else
                sha256="${EASYNET_HYSTERIA2_SHA256:-}"
            fi
            ;;
        shadowsocks)
            version="${EASYNET_SHADOWSOCKS_VERSION:-$EASYNET_PIN_SHADOWSOCKS_VERSION}"
            if [ "$version" = "$EASYNET_PIN_SHADOWSOCKS_VERSION" ]; then
                sha256="$(easynet_pin_sha256 shadowsocks)"
            else
                sha256="${EASYNET_SHADOWSOCKS_SHA256:-}"
            fi
            ;;
        acme)
            version="${EASYNET_ACME_VERSION:-$EASYNET_PIN_ACME_VERSION}"
            if [ "$version" = "$EASYNET_PIN_ACME_VERSION" ]; then
                sha256="$(easynet_pin_sha256 acme)"
            else
                sha256="${EASYNET_ACME_SHA256:-}"
            fi
            ;;
        *)
            if command -v log_error >/dev/null 2>&1; then
                log_error "未知的依赖组件: $component"
            fi
            return 1
            ;;
    esac

    if [ -z "$sha256" ]; then
        local hint="设置 EASYNET_ALLOW_UNPINNED=1 可跳过校验（不建议）"
        case "$component" in
            xray)        hint="请同时设置 EASYNET_XRAY_SHA256=<sha256>；$hint" ;;
            hysteria2)   hint="请同时设置 EASYNET_HYSTERIA2_SHA256=<sha256>；$hint" ;;
            shadowsocks) hint="请同时设置 EASYNET_SHADOWSOCKS_SHA256=<sha256>；$hint" ;;
            acme)        hint="请同时设置 EASYNET_ACME_SHA256=<sha256>；$hint" ;;
        esac
        local message="无法校验 ${component} ${version} 的完整性（未提供 SHA256）。${hint}"
        if [ "${EASYNET_ALLOW_UNPINNED:-}" = "1" ]; then
            if command -v log_warn >/dev/null 2>&1; then
                log_warn "$message"
            fi
        else
            if command -v log_error >/dev/null 2>&1; then
                log_error "$message"
            fi
            return 1
        fi
    fi

    printf '%s|%s' "$version" "$sha256"
}

# Print the human-readable pin table (used by scripts/check_upstream_pins.sh and docs).
easynet_pin_table() {
    printf 'xray|%s|%s\n'        "$EASYNET_PIN_XRAY_VERSION" "${EASYNET_PIN_XRAY_SHA256_X86_64:0:12}"
    printf 'hysteria2|%s|%s\n'   "$EASYNET_PIN_HYSTERIA2_VERSION" "${EASYNET_PIN_HYSTERIA2_SHA256_X86_64:0:12}"
    printf 'shadowsocks|%s|%s\n' "$EASYNET_PIN_SHADOWSOCKS_VERSION" "${EASYNET_PIN_SHADOWSOCKS_SHA256_X86_64:0:12}"
    printf 'acme|%s|%s\n'        "$EASYNET_PIN_ACME_VERSION" "${EASYNET_PIN_ACME_SHA256:0:12}"
    printf 'mihomo|%s|%s\n'      "$EASYNET_PIN_MIHOMO_VERSION" "${EASYNET_PIN_MIHOMO_SHA256_LINUX_AMD64:0:12}"
    printf 'sing-box|%s|%s\n'    "$EASYNET_PIN_SINGBOX_VERSION" "${EASYNET_PIN_SINGBOX_SHA256_LINUX_AMD64:0:12}"
}
