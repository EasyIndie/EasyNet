#!/bin/bash
# 用**真实客户端二进制**校验我们生成的订阅（发布前的最后一道闸门）。
#
# 为什么需要它
# ------------
# 0.0.13 之前，hysteria2 端口跳跃的间隔字段按 sing-box 方言写成 `hop-interval: "30s"`
# 发给 mihomo；mihomo 的该字段是**整数秒**，它把 `30s` 拿去当端口范围解析，报出
# `proxy 1: invalid range: 30s` 并**拒绝整份订阅**。而当时的单元测试恰恰把这个错误
# 格式写成了"预期值"，于是单测全绿、用户导入失败。
# 教训：客户端渲染字段（名称/类型/单位）的正确性**只能由真二进制判定**，
# 字符串断言只能防回归，不能当验证。
#
# 用法
# ----
#   client_check.sh platform                      打印当前平台与 pin 可用性
#   client_check.sh fetch <mihomo|singbox>        按 pin 下载校验并打印二进制路径
#   client_check.sh check-clash <config.yaml>     用真 mihomo 校验 Clash 配置
#   client_check.sh check-singbox <config.json>   用真 sing-box 校验配置
#   client_check.sh require <mihomo|singbox>      工具是否可用（不可用则非零退出）
#
# 环境变量
# --------
#   EASYNET_CLIENT_BIN_DIR        缓存目录（默认 ~/.cache/easynet/client-bin）
#   EASYNET_MIHOMO_BIN            直接指定已有 mihomo 二进制（跳过下载）
#   EASYNET_SINGBOX_BIN           直接指定已有 sing-box 二进制（跳过下载）
#   EASYNET_REQUIRE_CLIENT_CHECK  =1 时"平台未 pin / 无法下载"视为失败（CI 用）

set -uo pipefail

CLIENT_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=core/pins.sh
. "$CLIENT_CHECK_DIR/core/pins.sh"
# shellcheck source=core/logging.sh
. "$CLIENT_CHECK_DIR/core/logging.sh"

# 缓存目录：优先 env，其次 XDG/HOME。注意不能放 /tmp —— 在启用 tmpfs 的机器上
# 那是内存盘，几十 MB 的二进制会白占 RAM（实测踩过一次）。
client_check_bin_dir() {
    if [ -n "${EASYNET_CLIENT_BIN_DIR:-}" ]; then
        printf '%s' "${EASYNET_CLIENT_BIN_DIR:-}"
    else
        printf '%s' "${HOME:-/root}/.cache/easynet/client-bin"
    fi
    return 0
}

# 递归依赖 sha256sum(Linux)->shasum(macOS)，任一可用即可。
client_check_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        return 1
    fi
    return 0
}

# 打印当前平台与两个工具的 pin 情况（诊断用）。
client_check_platform() {
    local platform tool
    platform="$(easynet_client_platform)"
    printf '平台: %s\n' "${platform:-不支持（$(uname -s)/$(uname -m)）}"
    for tool in mihomo singbox; do
        if [ -n "$(easynet_client_pin_sha256 "$tool")" ]; then
            printf '  %-8s pin=%s 资产=%s\n' "$tool" \
                "$(easynet_client_pin_sha256 "$tool" | cut -c1-12)" \
                "$(easynet_client_pin_asset "$tool")"
        else
            printf '  %-8s 当前平台未 pin\n' "$tool"
        fi
    done
    printf '缓存目录: %s\n' "$(client_check_bin_dir)"
    return 0
}

# 已存在的二进制（env 指定 → 缓存目录 → PATH），找不到则无输出。
client_check_resolve() {
    local tool="$1" env_var cached
    case "$tool" in
        mihomo)  env_var="${EASYNET_MIHOMO_BIN:-}" ;;
        singbox) env_var="${EASYNET_SINGBOX_BIN:-}" ;;
        *) return 1 ;;
    esac
    if [ -n "$env_var" ] && [ -x "$env_var" ]; then
        printf '%s' "$env_var"
        return 0
    fi
    cached="$(client_check_bin_dir)/$tool"
    if [ -x "$cached" ]; then
        # 只有缓存里的资产仍与 pin 一致时才信任该二进制（防"缓存被替换/损坏"）
        if client_check_cache_valid "$tool"; then
            printf '%s' "$cached"
            return 0
        fi
        log_warn "缓存中的 $tool 资产与 pin 不一致，忽略缓存并重新下载"
        return 1
    fi
    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool"
        return 0
    fi
    return 1
}

# 缓存里的资产包是否与 pin 一致（每次使用都校验，避免缓存被替换/损坏）。
client_check_cache_valid() {
    local tool="$1" asset expected cached_file
    asset="$(easynet_client_pin_asset "$tool")"
    [ -n "$asset" ] || return 1
    cached_file="$(client_check_bin_dir)/$asset"
    [ -f "$cached_file" ] || return 1
    expected="$(easynet_client_pin_sha256 "$tool")"
    [ -n "$expected" ] || return 1
    [ "$(client_check_sha256 "$cached_file")" = "$expected" ]
}

# 按 pin 下载 → SHA256 校验 → 解包 → 安装到缓存目录，打印二进制路径。
client_check_fetch() {
    local tool="$1" url asset expected dir archive tmp_dir binary
    url="$(easynet_client_pin_url "$tool")"
    asset="$(easynet_client_pin_asset "$tool")"
    expected="$(easynet_client_pin_sha256 "$tool")"

    if [ -z "$url" ] || [ -z "$asset" ] || [ -z "$expected" ]; then
        log_error "当前平台（$(easynet_client_platform || printf '未知')）未 pin $tool 二进制，无法校验。"
        log_error "如需支持该平台：在 scripts/core/pins.sh 补 <版本+平台哈希> 后重试。"
        return 1
    fi

    dir="$(client_check_bin_dir)"
    mkdir -p "$dir" || return 1
    archive="$dir/$asset"

    if client_check_cache_valid "$tool" && [ -x "$dir/$tool" ]; then
        printf '%s' "$dir/$tool"
        return 0
    fi

    log_info "下载 ${tool}（pin ${asset}）..."
    if ! curl -fsSL --max-time 300 "$url" -o "$archive.tmp"; then
        rm -f "$archive.tmp"
        log_error "$tool 下载失败: $url"
        return 1
    fi
    if [ "$(client_check_sha256 "$archive.tmp")" != "$expected" ]; then
        rm -f "$archive.tmp"
        log_error "$tool 的 SHA256 与 pin 不一致，拒绝使用（上游资产可能已变更）。"
        return 1
    fi
    mv -f "$archive.tmp" "$archive"

    tmp_dir="$(mktemp -d)" || return 1
    case "$tool" in
        mihomo)
            # mihomo 发布的是裸 .gz（单个可执行文件）
            if ! gunzip -c "$archive" > "$tmp_dir/$tool" 2>/dev/null; then
                rm -rf "$tmp_dir"
                log_error "$tool 解压失败"
                return 1
            fi
            ;;
        singbox)
            if ! tar -xzf "$archive" -C "$tmp_dir" 2>/dev/null; then
                rm -rf "$tmp_dir"
                log_error "$tool 解压失败"
                return 1
            fi
            binary="$(find "$tmp_dir" -type f -name sing-box -perm -111 -print -quit)"
            if [ -z "$binary" ]; then
                rm -rf "$tmp_dir"
                log_error "$tool 压缩包内未找到可执行文件"
                return 1
            fi
            mv -f "$binary" "$tmp_dir/$tool"
            ;;
    esac
    install -m 0755 "$tmp_dir/$tool" "$dir/$tool" || {
        rm -rf "$tmp_dir"
        log_error "$tool 安装到缓存目录失败: $dir"
        return 1
    }
    rm -rf "$tmp_dir"
    printf '%s' "$dir/$tool"
    return 0
}

# 确保工具有可用二进制：先找现成的，再按 pin 下载。
# 拿不到时：EASYNET_REQUIRE_CLIENT_CHECK=1 → 失败；否则返回 1（调用方跳过）。
client_check_tool() {
    local tool="$1" bin
    bin="$(client_check_resolve "$tool")" && { printf '%s' "$bin"; return 0; }
    bin="$(client_check_fetch "$tool")" && { printf '%s' "$bin"; return 0; }
    if [ "${EASYNET_REQUIRE_CLIENT_CHECK:-}" = "1" ]; then
        log_error "真客户端校验被要求（EASYNET_REQUIRE_CLIENT_CHECK=1），但 $tool 不可用。"
        return 1
    fi
    return 1
}

# 用真 mihomo 校验 Clash 订阅。mihomo 会在 -d 数据目录里放 geodata 缓存。
client_check_clash() {
    local config="$1" bin data_dir
    [ -s "$config" ] || { log_error "配置文件不存在或为空: $config"; return 1; }
    bin="$(client_check_tool mihomo)" || return 1
    data_dir="$(client_check_bin_dir)/mihomo-data"
    mkdir -p "$data_dir"
    if ! "$bin" -t -d "$data_dir" -f "$config" > "$data_dir/last-check.log" 2>&1; then
        log_error "mihomo 拒绝该 Clash 配置："
        grep -iE 'level=error|level=fatal|test failed' "$data_dir/last-check.log" | tail -3 >&2 || true
        return 1
    fi
    log_info "mihomo（$("$bin" -v 2>/dev/null | awk 'NR==1{print $3}')）已接受该 Clash 配置。"
    return 0
}

# 用真 sing-box 校验订阅配置。
client_check_singbox() {
    local config="$1" bin data_dir
    [ -s "$config" ] || { log_error "配置文件不存在或为空: $config"; return 1; }
    bin="$(client_check_tool singbox)" || return 1
    data_dir="$(client_check_bin_dir)/singbox-data"
    mkdir -p "$data_dir"
    if ! "$bin" check -c "$config" -D "$data_dir" > "$data_dir/last-check.log" 2>&1; then
        log_error "sing-box 拒绝该配置："
        tail -3 "$data_dir/last-check.log" >&2 || true
        return 1
    fi
    log_info "sing-box（$("$bin" version 2>/dev/null | awk 'NR==1{print $3}')）已接受该配置。"
    return 0
}

usage() {
    cat <<'EOF'
EasyNet 客户端配置校验（真二进制）

用法: client_check.sh <命令> [参数]
  platform                     打印当前平台与 pin 可用性
  fetch <mihomo|singbox>       按 pin 下载并校验二进制，输出路径
  check-clash <config.yaml>    用真 mihomo 校验 Clash 配置
  check-singbox <config.json>  用真 sing-box 校验配置

环境变量:
  EASYNET_CLIENT_BIN_DIR       二进制缓存目录（默认 ~/.cache/easynet/client-bin）
  EASYNET_MIHOMO_BIN/SINGBOX_BIN  指定已有二进制（跳过下载）
  EASYNET_REQUIRE_CLIENT_CHECK =1 工具不可用时直接失败（CI 用）
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        platform)      client_check_platform ;;
        require)       client_check_tool "${1:-}" >/dev/null ;;
        fetch)         client_check_fetch "${1:-}" ;;
        check-clash)   client_check_clash "${1:-}" ;;
        check-singbox) client_check_singbox "${1:-}" ;;
        -h|--help|help) usage ;;
        *)
            log_error "未知命令: $cmd"
            usage >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
