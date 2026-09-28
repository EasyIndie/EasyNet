#!/bin/bash
# Report whether the pins in scripts/core/pins.sh are behind the upstream stable releases.
#
# Used by .github/workflows/pins.yml (weekly) so a stale pin shows up as a red run
# instead of being noticed months later. Exits non-zero when something is outdated.
#
# Usage:
#   bash scripts/check_upstream_pins.sh          # human-readable table
#   bash scripts/check_upstream_pins.sh --quiet  # only print when outdated
#
# Requires: gh (GitHub CLI, authenticated) or GITHUB_TOKEN.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=core/pins.sh
source "$SCRIPT_DIR/core/pins.sh"

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

# latest_stable_tag <repo> [tag_prefix]
latest_stable_tag() {
    local repo="$1" prefix="${2:-}"
    if command -v gh >/dev/null 2>&1; then
        gh api "repos/${repo}/releases?per_page=40" \
            --jq "[.[] | select(.prerelease==false) | select(.tag_name|startswith(\"${prefix}\"))][0].tag_name" \
            2>/dev/null
    else
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
            "https://api.github.com/repos/${repo}/releases?per_page=40" |
            jq -r "[.[] | select(.prerelease==false) | select(.tag_name|startswith(\"${prefix}\"))][0].tag_name"
    fi
}

strip_prefix() {
    local value="$1"
    value="${value#app/v}"
    value="${value#v}"
    printf '%s' "$value"
}

outdated=0
if [ "$QUIET" != true ]; then
    printf '%-14s %-12s %-12s %s\n' COMPONENT PINNED UPSTREAM STATUS
    printf '%-14s %-12s %-12s %s\n' ---------------- ------------ ------------ ------
fi

check() {
    local name="$1" pinned="$2" repo="$3" prefix="${4:-}"
    local upstream status
    upstream="$(strip_prefix "$(latest_stable_tag "$repo" "$prefix")")"
    if [ -z "$upstream" ]; then
        status="无法查询（网络或 API 限制）"
    elif [ "$upstream" = "$pinned" ]; then
        status="✅ 最新"
    else
        status="⚠️  有新版本 (${pinned} -> ${upstream})"
        outdated=$((outdated + 1))
    fi
    if [ "$QUIET" != true ] || [ "$status" != "✅ 最新" ]; then
        printf '%-14s %-12s %-12s %s\n' "$name" "$pinned" "${upstream:--}" "$status"
    fi
}

check "xray"        "$EASYNET_PIN_XRAY_VERSION"        "XTLS/Xray-core"             "v" # ok: pins.sh 常量
check "hysteria2"   "$EASYNET_PIN_HYSTERIA2_VERSION"   "apernet/hysteria"           "app/v" # ok: pins.sh 常量
check "shadowsocks" "$EASYNET_PIN_SHADOWSOCKS_VERSION" "shadowsocks/shadowsocks-rust" "v" # ok: pins.sh 常量
check "acme.sh"     "$EASYNET_PIN_ACME_VERSION"        "acmesh-official/acme.sh"    "" # ok: pins.sh 常量
# 客户端校验工具：不参与部署，但它们的方言决定我们生成的订阅是否可用，需要跟着上游更新
check "mihomo"      "$EASYNET_PIN_MIHOMO_VERSION"      "MetaCubeX/mihomo"           "v" # ok: pins.sh 常量
check "sing-box"    "$EASYNET_PIN_SINGBOX_VERSION"     "SagerNet/sing-box"          "v" # ok: pins.sh 常量

if [ "$outdated" -gt 0 ]; then
    printf '\n有 %d 个依赖落后于上游稳定版。升级步骤见 scripts/core/pins.sh 文件头注释。\n' "$outdated"
    exit 1
fi
[ "$QUIET" != true ] && printf '\n全部 pin 均为上游最新稳定版。\n'
exit 0
