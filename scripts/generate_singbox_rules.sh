#!/bin/bash

# EasyNet sing-box 规则集生成器
#
# 把官方 GeoIP/Geosite 数据库转成 sing-box 二进制规则集（.srs）并发布到 edge 的 web root：
#     ${EASYNET_WEB_ROOT:-/var/www/html}/rules/<tag>.srs
#     ${EASYNET_WEB_ROOT:-/var/www/html}/rules/manifest.json      ← tag/文件/sha256/size
#
# 类别清单来自 scripts/core/singbox-rules.conf（加类别只改那一行）。
# 生成物是"构建产物"，不进版本库；客户端由 install_singbox_client.sh 下载后落成本地文件
# （用 local 而不是 remote —— 远程规则集在启动时拉不到会让 sing-box 直接起不来）。
#
# 用法：
#     ./scripts/generate_singbox_rules.sh                 # 用最新 sing-box + 最新官方数据库
#     ./scripts/generate_singbox_rules.sh --dry-run       # 只打印将要做什么，不写任何文件
#     ./scripts/generate_singbox_rules.sh --tag v1.13.12  # 指定构建用 sing-box 版本
#
# 可覆盖的环境变量：
#     EASYNET_SINGBOX_RULES_BIN      已有 sing-box 可执行文件（跳过下载）
#     EASYNET_SINGBOX_RULES_CACHE    构建缓存目录（默认 <state>/tools）
#     EASYNET_SINGBOX_RULES_CONF     类别清单路径（默认 scripts/core/singbox-rules.conf）
#     EASYNET_SINGBOX_RULES_DETOUR   remote 规则集的下载出站（http_client.detour，默认 DIRECT，仅写入订阅）
#     EASYNET_WEB_ROOT               发布目录（默认 /var/www/html）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/core/download.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"

WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
RULES_DIR="$WEB_ROOT/rules"
CACHE_DIR="${EASYNET_SINGBOX_RULES_CACHE:-$(easynet_state_dir)/tools}"
SINGBOX_REPO="SagerNet/sing-box"
GEOSITE_REPO="SagerNet/sing-geosite"
GEOIP_REPO="SagerNet/sing-geoip"
BUILD_TAG="latest"
DRY_RUN="no"

die() {
    log_error "$1"
    exit 1
}

usage() {
    sed -n '2,25p' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run)
        DRY_RUN="yes"
        shift
        ;;
    --tag)
        BUILD_TAG="${2:-}"
        [ -n "$BUILD_TAG" ] || die "--tag 需要版本号，例如 --tag v1.13.12"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        die "未知参数: $1"
        ;;
    esac
done

# 从 GitHub release 资产里取官方 sha256（github 的 API 现在直接给出 digest 字段）
github_asset_field() {
    local repo="$1" tag="$2" pattern="$3" field="$4"
    local api url
    if [ "$tag" = "latest" ]; then
        url="https://api.github.com/repos/${repo}/releases/latest"
    else
        url="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    fi
    api="$(curl -fsSL --max-time 30 "$url" 2>/dev/null)" || return 1
    printf '%s' "$api" |
        jq -r --arg re "$pattern" --arg f "$field" \
            '.assets[]? | select(.name | test($re)) | .[$f] // empty' |
        head -n 1
}

github_asset_sha256() {
    local repo="$1" tag="$2" pattern="$3" digest
    digest="$(github_asset_field "$repo" "$tag" "$pattern" digest)"
    case "$digest" in
    sha256:*) printf '%s' "${digest#sha256:}" ;;
    *) printf '' ;;
    esac
}

ensure_build_binary() {
    if [ -n "${EASYNET_SINGBOX_RULES_BIN:-}" ]; then
        [ -x "${EASYNET_SINGBOX_RULES_BIN:-}" ] || die "EASYNET_SINGBOX_RULES_BIN 不可执行: ${EASYNET_SINGBOX_RULES_BIN:-}"
        printf '%s' "${EASYNET_SINGBOX_RULES_BIN:-}"
        return 0
    fi

    local arch version pattern url sha target
    case "$(uname -m)" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    armv7l) arch="armv7" ;;
    *) die "不支持的架构: $(uname -m)（可用 EASYNET_SINGBOX_RULES_BIN 指定现成的 sing-box）" ;;
    esac

    pattern="sing-box-.*-linux-${arch}\\.tar\\.gz$"
    version="$(github_asset_field "${SINGBOX_REPO:-}" "$BUILD_TAG" "$pattern" name)" || die "无法获取 sing-box release 信息（网络？）"
    [ -n "$version" ] || die "没有找到匹配的 sing-box 资产（tag=$BUILD_TAG, arch=${arch}）"
    target="$CACHE_DIR/$version"
    if [ -x "$target/sing-box" ]; then
        printf '%s' "$target/sing-box"
        return 0
    fi

    url="$(github_asset_field "${SINGBOX_REPO:-}" "$BUILD_TAG" "$pattern" browser_download_url)"
    sha="$(github_asset_sha256 "${SINGBOX_REPO:-}" "$BUILD_TAG" "$pattern")"
    [ -n "$url" ] || die "无法解析 sing-box 下载地址"

    log_info "下载构建用 sing-box: ${version}（sha256 ${sha:-未知}）" >&2
    mkdir -p "$CACHE_DIR"
    local tarball="$CACHE_DIR/${version}.tar.gz"
    download_file "$url" "$tarball" "$sha" >/dev/null || die "sing-box 下载或校验失败"
    rm -rf "$target"
    mkdir -p "$target"
    tar -xzf "$tarball" -C "$target" --strip-components=1
    [ -x "$target/sing-box" ] || die "解包后没有找到 sing-box 可执行文件"
    printf '%s' "$target/sing-box"
}

ensure_db() {
    local kind="$1" repo="$2" file="${1}.db" url sha out
    out="$CACHE_DIR/db-$kind.db"
    if [ -f "$out" ] && [ "${EASYNET_SINGBOX_RULES_REFRESH_DB:-false}" != "true" ]; then
        printf '%s' "$out"
        return 0
    fi
    url="$(github_asset_field "$repo" latest "^${file}$" browser_download_url)"
    sha="$(github_asset_sha256 "$repo" latest "^${file}$")"
    [ -n "$url" ] || die "无法获取 ${file} 下载地址（repo=${repo}）"
    mkdir -p "$CACHE_DIR"
    log_info "下载官方数据库: ${file}" >&2
    download_file "$url" "$out" "$sha" >/dev/null || die "${file} 下载或校验失败"
    printf '%s' "$out"
}

build_one() {
    local tag="$1" source_type="$2" category="$3" bin="$4" geosite_db="$5" geoip_db="$6"
    local json srs db
    json="$CACHE_DIR/build-${tag}.json"
    srs="$CACHE_DIR/build-${tag}.srs"

    case "$source_type" in
    geosite) db="$geosite_db" ;;
    geoip) db="$geoip_db" ;;
    *) die "未知 source 类型: ${source_type}（清单里只支持 geosite|geoip）" ;;
    esac

    if ! "$bin" "$source_type" export -f "$db" "$category" -o "$json" >/dev/null 2>&1; then
        log_error "导出失败: ${tag}（${source_type} ${category}）"
        return 1
    fi
    if ! "$bin" rule-set compile "$json" -o "$srs" >/dev/null 2>&1; then
        log_error "编译失败: ${tag}"
        return 1
    fi
    # 自校验：编译产物必须能被同版本 sing-box 读回
    if ! "$bin" rule-set decompile "$srs" >/dev/null 2>&1; then
        log_error "产物不可读（版本不匹配？）: ${tag}"
        return 1
    fi

    if [ "$DRY_RUN" = "yes" ]; then
        log_info "[dry-run] 将安装 ${tag}.srs（$(wc -c < "$srs" 2>/dev/null || echo 0) B）"
        return 0
    fi

    mkdir -p "$RULES_DIR"
    install -m 0644 "$srs" "$RULES_DIR/${tag}.srs"
    log_info "已发布 ${RULES_DIR}/${tag}.srs（$(wc -c < "$RULES_DIR/${tag}.srs") B）"
    rm -f "$json" "$srs"
}

write_manifest() {
    local bin="$1" tmp entries
    mkdir -p "$RULES_DIR"
    tmp="$(mktemp)"
    entries="[]"
    while IFS='|' read -r tag source_type category; do
        [ -z "$tag" ] && continue
        [ -f "$RULES_DIR/${tag}.srs" ] || continue
        entries="$(jq -c \
            --argjson acc "$entries" \
            --arg tag "$tag" \
            --arg source "$source_type" \
            --arg category "$category" \
            --arg file "rules/${tag}.srs" \
            --arg sha "$(sha256sum "$RULES_DIR/${tag}.srs" | awk '{print $1}')" \
            --argjson size "$(wc -c < "$RULES_DIR/${tag}.srs")" \
            '$acc + [{tag:$tag, source:$source, category:$category, file:$file, sha256:$sha, size:$size}]' \
            <<<'null')"
    done < <(easynet_singbox_rules_specs | awk -F'|' '{ print $1 "|" $2 "|" $3 }')

    jq -n \
        --argjson files "$entries" \
        --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg singbox "$("$bin" version 2>/dev/null | head -n 1)" \
        '{generated_at: $generated_at, singbox: $singbox, files: $files}' >"$tmp"

    if [ "$DRY_RUN" = "yes" ]; then
        log_info "[dry-run] manifest: $(jq -c . "$tmp")"
        rm -f "$tmp"
        return 0
    fi
    install -m 0644 "$tmp" "$RULES_DIR/manifest.json"
    rm -f "$tmp"
    log_info "已发布 ${RULES_DIR}/manifest.json（$(jq '.files | length' "$RULES_DIR/manifest.json") 个规则集）"
}

main() {
    local conf; conf="$(easynet_singbox_rules_conf)"
    [ -f "$conf" ] || die "找不到类别清单: $conf"
    if [ -z "$(easynet_singbox_rules_specs)" ]; then
        log_warn "类别清单为空，无事可做: $conf"
        exit 0
    fi

    local bin geosite_db geoip_db failed=0
    bin="$(ensure_build_binary | tail -n 1)"
    log_info "构建用 sing-box: $("$bin" version 2>/dev/null | head -n 1)"

    geosite_db="$(ensure_db geosite "$GEOSITE_REPO" | tail -n 1)"
    geoip_db="$(ensure_db geoip "$GEOIP_REPO" | tail -n 1)"

    while IFS='|' read -r tag source_type category; do
        [ -z "$tag" ] && continue
        build_one "$tag" "$source_type" "$category" "$bin" "$geosite_db" "$geoip_db" || failed=1
    done < <(easynet_singbox_rules_specs | awk -F'|' '{ print $1 "|" $2 "|" $3 }')

    write_manifest "$bin"

    if [ "$failed" = "1" ]; then
        log_error "有规则集构建失败（其余已发布，旧文件未被删除）"
        exit 1
    fi
    log_info "完成。订阅端会自动引用这些规则集；客户端在下次每日更新时拉取。"
}

main "$@"
