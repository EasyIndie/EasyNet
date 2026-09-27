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
}
