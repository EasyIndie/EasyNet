#!/bin/bash
# 客户端二进制镜像：把 pin 住的 sing-box 发布到 Edge web root，供**设备端**下载。
#
# 为什么需要
# ----------
# 设备（树莓派、软路由、旧手机…）一旦代理失效，就失去了从 GitHub 下载 sing-box
# 自救的通道——实测在国内直连 GitHub release 会卡死（90 秒 0 字节后 curl(18)），
# 而订阅站（自己的域名）通常是通的。因此服务端顺手托管一份 pinned 二进制，
# 安装器优先从订阅站取、GitHub 兜底，形成"只要能访问域名就能自愈"的闭环。
#
# 发布内容（$WEB_ROOT/bin/）
#   sing-box-<版本>-<平台>.tar.gz          官方 release 原包（逐字节）
#   sing-box-<版本>-<平台>.tar.gz.sha256   供 sha256sum -c 校验
#   manifest.json                          版本 + 各平台资产与 SHA256
#
# 策略
#   * best-effort：下载/校验失败只 WARN，绝不中断部署（与规则集同样的思路）；
#   * 已发布且 SHA256 与 pin 一致 → 跳过（不重复下载；版本升级时自动替换）；
#   * 取源优先级：client_check 缓存（已校验过的原包）→ 官方 release URL；
#   * EASYNET_PUBLISH_CLIENT_BINARIES=false 可整体关闭（设备将无法从订阅站自愈）。
#
# 手动刷新：easynet clients

# 与 client_check.sh 共用缓存目录，避免同一份原包重复下载。
easynet_client_binaries_cache_dir() {
    if [ -n "${EASYNET_CLIENT_BIN_DIR:-}" ]; then
        printf '%s' "${EASYNET_CLIENT_BIN_DIR:-}"
    else
        printf '%s' "${HOME:-/root}/.cache/easynet/client-bin"
    fi
    return 0
}

# 递归依赖 sha256sum(Linux)->shasum(macOS)
easynet_client_binaries_sha256() {
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

# 发布单个平台。返回 0=已就绪（含原本就存在），1=失败。
easynet_client_binaries_publish_one() {
    local web_root="$1" platform="$2"
    local bin_dir="$web_root/bin"
    local asset sha target cache source_url tmp
    asset="$(easynet_client_pin_asset_for singbox "$platform")"
    sha="$(easynet_client_pin_sha256_for singbox "$platform")"
    [ -n "$asset" ] && [ -n "$sha" ] || return 1

    target="$bin_dir/$asset"

    # 已发布且内容与 pin 一致 → 跳过
    if [ -f "$target" ] && [ "$(easynet_client_binaries_sha256 "$target")" = "$sha" ]; then
        printf '%s  %s\n' "$sha" "$asset" > "$bin_dir/$asset.sha256"
        return 0
    fi

    # 取源 1：client_check 缓存里的原包（同一资产名，已按 pin 校验过）
    cache="$(easynet_client_binaries_cache_dir)/$asset"
    tmp="$(mktemp "$bin_dir/.incoming.XXXXXX")" || return 1
    if [ -f "$cache" ] && [ "$(easynet_client_binaries_sha256 "$cache")" = "$sha" ]; then
        cp -f "$cache" "$tmp" || { rm -f "$tmp"; return 1; }
    else
        # 取源 2：官方 release（pin 版本 + 固定 URL）
        source_url="$(easynet_client_pin_url_for singbox "$platform")"
        if ! curl -fsSL --max-time 300 "$source_url" -o "$tmp"; then
            rm -f "$tmp"
            return 1
        fi
        if [ "$(easynet_client_binaries_sha256 "$tmp")" != "$sha" ]; then
            rm -f "$tmp"
            return 1
        fi
    fi

    install -m 0644 "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    printf '%s  %s\n' "$sha" "$asset" > "$bin_dir/$asset.sha256"
    return 0
}

# 发布全部 pin 平台，并写 manifest.json。始终返回 0（best-effort）。
easynet_client_binaries_publish() {
    local web_root="${1:-${EASYNET_WEB_ROOT:-/var/www/html}}"
    local bin_dir="$web_root/bin"
    local version="$EASYNET_PIN_SINGBOX_VERSION"
    local platform asset sha size ok=0 failed=0 tmp_manifest entries_file

    if [ "${EASYNET_PUBLISH_CLIENT_BINARIES:-true}" = "false" ]; then
        log_warn "已跳过客户端二进制发布（EASYNET_PUBLISH_CLIENT_BINARIES=false）"
        log_warn "  → 设备代理失效后将无法从订阅站下载 sing-box 自愈（只能依赖 GitHub）。"
        return 0
    fi

    mkdir -p "$bin_dir"
    chmod 0755 "$bin_dir" 2>/dev/null || true

    entries_file="$(mktemp)"
    while IFS= read -r platform; do
        [ -n "$platform" ] || continue
        asset="$(easynet_client_pin_asset_for singbox "$platform")"
        [ -n "$asset" ] || continue
        if easynet_client_binaries_publish_one "$web_root" "$platform"; then
            sha="$(easynet_client_pin_sha256_for singbox "$platform")"
            size="$(wc -c < "$bin_dir/$asset" | tr -d ' ')"
            printf '    {"platform": "%s", "asset": "%s", "sha256": "%s", "size": %s}\n' \
                "$platform" "$asset" "$sha" "$size" >> "$entries_file"
            ok=$((ok + 1))
        else
            failed=$((failed + 1))
            log_warn "客户端二进制发布失败: ${asset}（可稍后运行 easynet clients 重试）"
        fi
    done < <(easynet_client_binary_platforms)

    if [ "$ok" -gt 0 ]; then
        tmp_manifest="$(mktemp "$bin_dir/.manifest.XXXXXX")"
        {
            printf '{\n'
            printf '  "schemaVersion": 1,\n'
            printf '  "tool": "sing-box",\n'
            printf '  "version": "%s",\n' "$version"
            printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            printf '  "files": [\n'
            # 用 awk 在条目之间插入逗号，避免手写拼接产生非法 JSON 的尾逗号
            awk 'NR>1 { print prev "," } { prev = $0 } END { if (NR) print prev }' "$entries_file"
            printf '  ]\n}\n'
        } > "$tmp_manifest"
        install -m 0644 "$tmp_manifest" "$bin_dir/manifest.json"
        rm -f "$tmp_manifest"
    fi

    rm -f "$entries_file"

    if [ "$failed" -gt 0 ]; then
        log_warn "客户端二进制: ${ok} 个已就绪、${failed} 个失败（设备端仍可回落到 GitHub 下载）"
    else
        log_info "客户端二进制已发布: ${bin_dir}（sing-box ${version} × ${ok} 平台，供设备自愈下载）"
    fi
    return 0
}

# 打印当前发布状态（easynet clients 用）
easynet_client_binaries_status() {
    local web_root="${1:-${EASYNET_WEB_ROOT:-/var/www/html}}"
    local bin_dir="$web_root/bin" platform asset sha state
    printf '目录: %s\n' "$bin_dir"
    while IFS= read -r platform; do
        [ -n "$platform" ] || continue
        asset="$(easynet_client_pin_asset_for singbox "$platform")"
        [ -n "$asset" ] || continue
        sha="$(easynet_client_pin_sha256_for singbox "$platform")"
        if [ -f "$bin_dir/$asset" ] && [ "$(easynet_client_binaries_sha256 "$bin_dir/$asset")" = "$sha" ]; then
            state="✅ 已发布（$(wc -c < "$bin_dir/$asset" | tr -d ' ') B）"
        elif [ -f "$bin_dir/$asset" ]; then
            state="⚠️  存在但 SHA256 与 pin 不一致（运行 easynet clients 重新发布）"
        else
            state="❌ 未发布（运行 easynet clients）"
        fi
        printf '  %-14s %s\n' "$platform" "$state"
    done < <(easynet_client_binary_platforms)
    [ -f "$bin_dir/manifest.json" ] && printf '  manifest.json: 存在\n' || printf '  manifest.json: 缺失\n'
    return 0
}
