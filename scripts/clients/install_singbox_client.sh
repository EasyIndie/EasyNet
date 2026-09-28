#!/bin/bash

set -euo pipefail

CONFIG_URL=""
ACTION="install"
MODE="${EASYNET_SINGBOX_MODE:-mixed}"
# mixed 模式监听地址。默认 0.0.0.0 便于局域网共享（安装器会提示局域网地址）；
# 公网设备上这会成为开放代理，可用 --listen-address 127.0.0.1 收紧。
LISTEN_ADDRESS="${EASYNET_SINGBOX_LISTEN:-0.0.0.0}"
INSTALL_DIR="${EASYNET_SINGBOX_INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${EASYNET_SINGBOX_CONFIG_DIR:-/etc/sing-box}"
STATE_DIR="${EASYNET_SINGBOX_STATE_DIR:-/etc/easynet}"
SERVICE_NAME="${EASYNET_SINGBOX_SERVICE_NAME:-easynet-singbox}"
UPDATE_NAME="${EASYNET_SINGBOX_UPDATE_NAME:-easynet-singbox-update}"

# ---------------------------------------------------------------------------
# sing-box 版本固定（pin）
# ---------------------------------------------------------------------------
# 服务端四个组件都有 pin + SHA256，客户端不能例外：这个脚本最终以 root 运行在
# 用户设备上，裸拉 latest 等于把“上游随时换一个字节”直接引入设备。
#
# 与 scripts/core/pins.sh 的 EASYNET_PIN_SINGBOX_* 保持一致
# （tests/test_singbox_client_installer.bats 有防漂移断言）。
# 覆盖版本时必须同时给校验和：--sing-box-url 配合 EASYNET_SINGBOX_INSTALL_SHA256，
# 或显式 EASYNET_SINGBOX_SKIP_SHA256=true 承担风险。
PINNED_SINGBOX_VERSION="1.14.2"
PINNED_SINGBOX_SHA256_LINUX_AMD64="a684484d7477d1437282ee411f4d131d0340aaad60a7868841ebd5d87dd8a0c6"
PINNED_SINGBOX_SHA256_LINUX_ARM64="b43a1fb1bda131c6653576741ce527eb2bdeab7c9308ca90ee8b972abb7e4a7f"

SB_VERSION="${EASYNET_SINGBOX_VERSION:-$PINNED_SINGBOX_VERSION}"
SINGBOX_URL="${EASYNET_SINGBOX_DOWNLOAD_URL:-}"
SB_SHA256="${EASYNET_SINGBOX_INSTALL_SHA256:-}"
SB_SKIP_SHA256="${EASYNET_SINGBOX_SKIP_SHA256:-false}"
SINGBOX_MIRROR_URL="${EASYNET_SINGBOX_MIRROR_URL:-}"
SINGBOX_SOURCE_URLS=()
ENV_FILE="$STATE_DIR/singbox-client.env"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage:
  sudo bash $0 --config-url <EasyNet /singbox URL> [--mode mixed|tun] [--sing-box-url <tar.gz URL>]
              [--listen-address <addr>]
  sudo bash $0 start|stop|restart|status|update|doctor
  sudo bash $0 switch-mode mixed|tun

Options:
  --config-url      EasyNet sing-box config URL, usually https://domain/s/<random>/singbox
  --mode            Client mode. mixed opens HTTP/SOCKS port only. tun enables local full-device proxy.
  --sing-box-url    Override the download URL (requires EASYNET_SINGBOX_INSTALL_SHA256).
                    Default: pinned sing-box release asset (see PINNED_SINGBOX_VERSION).
  --listen-address  Address the mixed proxy binds to (default 0.0.0.0 for LAN sharing).
                    Use 127.0.0.1 to keep it local-only on public / untrusted hosts.
  -h, --help        Show this help.
EOF
}

require_root() {
    [ "$(id -u)" = "0" ] || die "请使用 root 运行，例如: sudo bash $0 --config-url <URL>"
}

parse_args() {
    case "${1:-}" in
        start|stop|restart|status|update|doctor)
            ACTION="$1"
            shift
            ;;
        switch-mode)
            ACTION="$1"
            [ $# -ge 2 ] || die "switch-mode 需要 mixed 或 tun"
            MODE="$2"
            shift 2
            ;;
    esac

    while [ $# -gt 0 ]; do
        case "$1" in
            --config-url)
                [ $# -ge 2 ] || die "--config-url 需要一个 URL"
                CONFIG_URL="$2"
                shift 2
                ;;
            --sing-box-url)
                [ $# -ge 2 ] || die "--sing-box-url 需要一个 URL"
                SINGBOX_URL="$2"
                shift 2
                ;;
            --mode)
                [ $# -ge 2 ] || die "--mode 需要 mixed 或 tun"
                MODE="$2"
                shift 2
                ;;
            --listen-address)
                [ $# -ge 2 ] || die "--listen-address 需要一个地址"
                LISTEN_ADDRESS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "未知参数: $1"
                ;;
        esac
    done

    case "$MODE" in
        mixed|tun) ;;
        *) die "--mode 只支持 mixed 或 tun" ;;
    esac

    case "$LISTEN_ADDRESS" in
        *[!A-Za-z0-9:.]*) die "--listen-address 只能是 IP 地址" ;;
    esac
    if [ "$MODE" = "mixed" ] && [ "$LISTEN_ADDRESS" != "127.0.0.1" ] && [ "$LISTEN_ADDRESS" != "::1" ]; then
        warn "mixed 代理将监听 ${LISTEN_ADDRESS}:7890 —— 同网段（公网 IP 则等于全网）均可直接使用，"
        warn "  即一个无认证的开放代理。若不需要局域网共享，请改用 --listen-address 127.0.0.1，"
        warn "  或用防火墙只放行可信用途来源。"
    fi

    if [ "$ACTION" = "install" ]; then
        [ -n "$CONFIG_URL" ] || die "缺少 --config-url"
        case "$CONFIG_URL" in
            http://*|https://*) ;;
            *) die "--config-url 必须是 http 或 https URL" ;;
        esac
    fi
}

detect_asset_arch() {
    case "$(uname -m)" in
        aarch64|arm64) echo "linux-arm64" ;;
        armv7l|armv7*) echo "linux-armv7" ;;
        armv6l|armv6*) echo "linux-armv6" ;;
        x86_64|amd64) echo "linux-amd64" ;;
        *) die "暂不支持的架构: $(uname -m)" ;;
    esac
}

install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y ca-certificates curl jq tar
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl jq tar
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl jq tar
    else
        warn "未识别包管理器，请确认 ca-certificates、curl、jq、tar 已安装。"
    fi

    command -v jq >/dev/null 2>&1 || die "缺少 jq，无法生成 mixed/tun 客户端配置。"
}

# 已 pin 的架构 → SHA256；未 pin 的架构（armv7/armv6）由调用方决定是否接受
pinned_singbox_sha256() {
    case "$(detect_asset_arch)" in
        linux-amd64) printf '%s' "$PINNED_SINGBOX_SHA256_LINUX_AMD64" ;;
        linux-arm64) printf '%s' "$PINNED_SINGBOX_SHA256_LINUX_ARM64" ;;
        *)           return 0 ;;
    esac
}

# 解析下载地址与校验和。
#   默认（pin 版本）→ 官方 release 资产地址 + 仓库内置 SHA256
#   覆盖版本/自定义 URL → 必须显式提供 EASYNET_SINGBOX_INSTALL_SHA256，
#                          否则拒绝继续（除非显式 EASYNET_SINGBOX_SKIP_SHA256=true）
resolve_singbox_download() {
    local asset_arch base cfg
    asset_arch="$(detect_asset_arch)"
    # 安装器自身用 CONFIG_URL；SINGBOX_CONFIG_URL 是写进设备 env、供每日更新脚本使用的
    # 同名变量（两种都认，便于"source 安装器 + 复用 env 文件"的场景）。
    cfg="${CONFIG_URL:-${SINGBOX_CONFIG_URL:-}}"
    base=""
    [ -n "$cfg" ] && base="${cfg%/*}"

    if [ -z "${SINGBOX_URL:-}" ]; then
        SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-${asset_arch}.tar.gz"
        # 未显式指定 URL 时，优先用订阅站托管的同版本原包（easynet clients 发布）
        if [ -n "$base" ] && [ "${EASYNET_SINGBOX_MIRROR:-true}" != "false" ]; then
            SINGBOX_MIRROR_URL="${base}/bin/sing-box-${SB_VERSION}-${asset_arch}.tar.gz"
        fi
    fi
    # 来源列表：镜像在前、GitHub 在后（显式 --sing-box-url 时只用显式来源）
    SINGBOX_SOURCE_URLS=()
    [ -n "${SINGBOX_MIRROR_URL:-}" ] && SINGBOX_SOURCE_URLS+=("${SINGBOX_MIRROR_URL}")
    [ -n "${SINGBOX_URL:-}" ] && SINGBOX_SOURCE_URLS+=("${SINGBOX_URL}")

    if [ -z "${SB_SHA256:-}" ] && [ "$SB_VERSION" = "$PINNED_SINGBOX_VERSION" ]; then
        SB_SHA256="$(pinned_singbox_sha256)"
    fi

    if [ -z "${SB_SHA256:-}" ] && [ "$SB_SKIP_SHA256" != "true" ]; then
        die "无法校验 sing-box ${SB_VERSION}（${asset_arch}）的完整性：未提供 SHA256。
  请设置 EASYNET_SINGBOX_INSTALL_SHA256=<sha256>（可对照 releases 页面自行计算），
  或显式设置 EASYNET_SINGBOX_SKIP_SHA256=true 自行承担风险。"
    fi
}

install_singbox_binary() {
    local tmp_dir="" tarball binary_path installed_version

    # 固定版本安装（不跟随 latest）：apt 仓库里的 sing-box 太旧，而裸拉 latest 会在
    # 上游发布一个字节的差异时静默进入设备 —— 两者都不可接受。
    # 已装且与 pin 一致则跳过（幂等、可重复执行）。
    if [ -f "$INSTALL_DIR/sing-box" ]; then
        installed_version="$("$INSTALL_DIR/sing-box" version 2>/dev/null | awk 'NR==1{print $3}')"
        if [ "$installed_version" = "$SB_VERSION" ]; then
            log "已安装 sing-box ${installed_version}（与固定版本一致），跳过下载"
            return 0
        fi
        log "检测到 sing-box ${installed_version:-未知}，将更新到固定版本 ${SB_VERSION}..."
    fi

    resolve_singbox_download
    tmp_dir="$(mktemp -d /tmp/easynet-singbox.XXXXXX)"
    trap 'rm -rf "${tmp_dir:-}"' RETURN
    tarball="$tmp_dir/sing-box.tar.gz"

    # 取源顺序：订阅站镜像 → GitHub。设备（树莓派等）在国内常无法直连 GitHub
    # release，而订阅站通常是通的；两个来源都必须通过同一个 pin 哈希，
    # 所以镜像即使不可信也不影响完整性。
    local downloaded="no" url
    for url in "${SINGBOX_SOURCE_URLS[@]}"; do
        log "下载 sing-box ${SB_VERSION}: $url"
        if ! curl -fsSL --max-time 300 "$url" -o "$tarball"; then
            warn "下载失败，尝试下一个来源: $url"
            continue
        fi
        if [ -n "${SB_SHA256:-}" ]; then
            if printf '%s  %s\n' "${SB_SHA256}" "$tarball" | sha256sum -c - >/dev/null 2>&1; then
                log "SHA256 校验通过（来源: ${url}）"
                downloaded="yes"
                break
            fi
            warn "SHA256 校验失败（可能下载不完整或资产已变更），尝试下一个来源: $url"
            continue
        fi
        downloaded="yes"
        break
    done
    [ "$downloaded" = "yes" ] || die "无法取得可校验的 sing-box 原包（镜像与 GitHub 均不可用）"
    if [ -z "${SB_SHA256:-}" ]; then
        warn "已跳过 sing-box SHA256 校验（EASYNET_SINGBOX_SKIP_SHA256=true）"
    fi

    tar -xzf "$tarball" -C "$tmp_dir"
    binary_path="$(find "$tmp_dir" -type f -name sing-box -perm -111 -print -quit)"
    [ -n "$binary_path" ] || die "下载包中未找到 sing-box 可执行文件"

    install -m 0755 "$binary_path" "$INSTALL_DIR/sing-box"
    rm -rf "$tmp_dir"
    tmp_dir=""
    trap - RETURN
}

quote_single() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

write_state() {
    mkdir -p "$STATE_DIR" "$CONFIG_DIR"
    cat > "$STATE_DIR/singbox-client.env" <<EOF
SINGBOX_CONFIG_URL='$(quote_single "$CONFIG_URL")'
SINGBOX_CONFIG_FILE='$CONFIG_DIR/config.json'
SINGBOX_BIN='$INSTALL_DIR/sing-box'
SINGBOX_MODE='$MODE'
SINGBOX_LISTEN='$LISTEN_ADDRESS'
SINGBOX_SERVICE='$SERVICE_NAME'
PINNED_SINGBOX_VERSION='$PINNED_SINGBOX_VERSION'
PINNED_SINGBOX_SHA256_LINUX_AMD64='$PINNED_SINGBOX_SHA256_LINUX_AMD64'
PINNED_SINGBOX_SHA256_LINUX_ARM64='$PINNED_SINGBOX_SHA256_LINUX_ARM64'
EOF
    chmod 600 "$STATE_DIR/singbox-client.env"
}

set_saved_mode() {
    local mode="$1"
    local tmp_file

    [ -f "$ENV_FILE" ] || die "未找到 ${ENV_FILE}，请先完成客户端安装。"

    tmp_file="$(mktemp /tmp/easynet-singbox-env.XXXXXX)"
    if grep -q '^SINGBOX_MODE=' "$ENV_FILE"; then
        sed "s/^SINGBOX_MODE=.*/SINGBOX_MODE='$mode'/" "$ENV_FILE" > "$tmp_file"
    else
        cp "$ENV_FILE" "$tmp_file"
        printf "\nSINGBOX_MODE='%s'\n" "$mode" >> "$tmp_file"
    fi
    install -m 0600 "$tmp_file" "$ENV_FILE"
    rm -f "$tmp_file"
}

update_saved_mode() {
    set_saved_mode "$MODE"
}

write_update_script() {
    cat > "$INSTALL_DIR/easynet-singbox-update" <<'EOF'
#!/bin/bash
set -euo pipefail

ENV_FILE="/etc/easynet/singbox-client.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

tmp_file="$(mktemp /tmp/easynet-singbox-config.XXXXXX)"
mode_file="$(mktemp /tmp/easynet-singbox-mode.XXXXXX)"
cleanup() { rm -f "$tmp_file" "$mode_file"; }
trap cleanup EXIT

# ── 二进制版本对齐 ─────────────────────────────────────────────────────────
# 每日更新原本只刷新配置/规则集，sing-box 本体永远停在安装那天的版本。
# 这里按安装器写入的 pin 对齐版本：优先订阅站镜像（设备在国内常无法直连
# GitHub release），GitHub 兜底；两个来源都必须通过 pin 的 SHA256。
# 失败只告警，不影响配置更新（代理照旧可用）。
bin_changed="no"
align_singbox_binary() {
    local want arch asset sha base url tmp_dir bin_path
    want="${PINNED_SINGBOX_VERSION:-}"
    [ -n "$want" ] || return 0
    if [ "$("${SINGBOX_BIN:-sing-box}" version 2>/dev/null | awk 'NR==1{print $3}')" = "$want" ]; then
        return 0
    fi
    case "$(uname -m)" in
        aarch64|arm64) arch="linux-arm64"; sha="${PINNED_SINGBOX_SHA256_LINUX_ARM64:-}" ;;
        x86_64|amd64)  arch="linux-amd64"; sha="${PINNED_SINGBOX_SHA256_LINUX_AMD64:-}" ;;
        *) echo "未知架构，跳过 sing-box 版本对齐" >&2; return 0 ;;
    esac
    if [ -z "$sha" ]; then
        echo "缺少 ${arch} 的 pin 哈希，跳过 sing-box 版本对齐" >&2
        return 0
    fi

    asset="sing-box-${want}-${arch}.tar.gz"
    base="${SINGBOX_CONFIG_URL:-}"
    base="${base%/*}"
    tmp_dir="$(mktemp -d)"
    for url in "${base:+${base}/bin/${asset}}" "https://github.com/SagerNet/sing-box/releases/download/v${want}/${asset}"; do
        [ -n "$url" ] || continue
        if ! curl -fsSL --max-time 300 "$url" -o "$tmp_dir/$asset" 2>/dev/null; then
            continue
        fi
        if [ "$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')" != "$sha" ]; then
            echo "SHA256 不匹配，跳过该来源: $url" >&2
            continue
        fi
        tar -xzf "$tmp_dir/$asset" -C "$tmp_dir" || continue
        bin_path="$(find "$tmp_dir" -type f -name sing-box -perm -111 -print -quit)"
        if [ -z "$bin_path" ]; then
            continue
        fi
        install -m 0755 "$bin_path" "${SINGBOX_BIN:-/usr/local/bin/sing-box}"
        echo "sing-box 已对齐到 ${want}（来源: ${url}）"
        bin_changed="yes"
        rm -rf "$tmp_dir"
        return 0
    done
    rm -rf "$tmp_dir"
    echo "WARN: sing-box ${want} 获取/校验失败（订阅站与 GitHub 均不可用），沿用当前版本" >&2
    return 0
}
align_singbox_binary

curl -fL "${SINGBOX_CONFIG_URL:-}" -o "$tmp_file"

case "${SINGBOX_MODE:-mixed}" in
    mixed)
        jq --arg listen "${SINGBOX_LISTEN:-0.0.0.0}" '
            .inbounds = [
                {
                    type: "mixed",
                    tag: "mixed-in",
                    listen: $listen,
                    listen_port: 7890
                }
            ]
            | .route.rules = ([{ inbound: "mixed-in", action: "sniff" }] + ((.route.rules // []) | map(select(.action != "sniff"))))
        ' "$tmp_file" > "$mode_file"
        ;;
    tun)
        jq '
            def server_domains:
                ([.outbounds[]?.server?, .endpoints[]?.server?]
                    | map(select(type == "string" and test("[A-Za-z]")))
                    | unique);

            server_domains as $server_domains
            | .dns = {
                servers: [
                    {
                        type: "local",
                        tag: "local-dns"
                    },
                    {
                        type: "tcp",
                        tag: "remote-dns",
                        server: "8.8.8.8",
                        server_port: 53,
                        detour: "Proxy"
                    }
                ],
                rules: (
                    if ($server_domains | length) > 0 then
                        [
                            {
                                domain: $server_domains,
                                action: "route",
                                server: "local-dns"
                            }
                        ]
                    else
                        []
                    end
                ),
                final: "remote-dns",
                strategy: "ipv4_only"
            }
            |
            .inbounds = [
                {
                    type: "tun",
                    tag: "tun-in",
                    interface_name: "easynet0",
                    address: ["172.19.0.1/30"],
                    auto_route: true,
                    strict_route: true,
                    stack: "system",
                    mtu: 1500
                }
            ]
            | .route.rules = (
                [
                    { inbound: "tun-in", port: 53, action: "hijack-dns" },
                    { inbound: "tun-in", action: "sniff" }
                ]
                + ((.route.rules // []) | map(select(.action != "sniff" and .action != "hijack-dns")))
            )
            | .route.default_domain_resolver = {
                server: "local-dns",
                strategy: "ipv4_only"
            }
        ' "$tmp_file" > "$mode_file"
        ;;
    *)
        echo "Unsupported SINGBOX_MODE: ${SINGBOX_MODE:-}" >&2
        exit 1
        ;;
esac

# ---- 规则集：下载到本地并把 remote 改写成 local ----
# 远程规则集在启动时拉不到会让 sing-box 直接起不来，所以这里一律落地成本地文件；
# 任何一类拉不到就把它（连同引用它的规则）摘掉，保证配置永远能启动。
config_path="${SINGBOX_CONFIG_FILE:-/etc/sing-box/config.json}"
config_dir="$(dirname "$config_path")"
rules_dir="$config_dir/rules"
rules_base=""
if [ -n "${SINGBOX_CONFIG_URL:-}" ]; then
    rules_base="${SINGBOX_CONFIG_URL%/*}"
fi
manifest_tmp="$(mktemp /tmp/easynet-rules-manifest.XXXXXX)"
mkdir -p "$rules_dir"
manifest_ok="no"
if [ -n "$rules_base" ] &&
    curl -fsSL --max-time 30 "${rules_base}/rules/manifest.json" -o "$manifest_tmp" 2>/dev/null &&
    jq -e '.files | type == "array"' "$manifest_tmp" >/dev/null 2>&1; then
    manifest_ok="yes"
    missing_tags=""
    while IFS=$'\t' read -r rule_tag rule_file rule_sha; do
        [ -n "$rule_tag" ] || continue
        rule_target="$rules_dir/${rule_tag}.srs"
        need_fetch="yes"
        if [ -f "$rule_target" ] && [ -n "$rule_sha" ] &&
            [ "$(sha256sum "$rule_target" | awk '{print $1}')" = "$rule_sha" ]; then
            need_fetch="no"
        fi
        if [ "$need_fetch" = "yes" ]; then
            rule_tmp="$(mktemp /tmp/easynet-rules.XXXXXX)"
            if curl -fsSL --max-time 60 "${rules_base}/${rule_file}" -o "$rule_tmp" 2>/dev/null &&
                { [ -z "$rule_sha" ] || [ "$(sha256sum "$rule_tmp" | awk '{print $1}')" = "$rule_sha" ]; } &&
                "${SINGBOX_BIN:-}" rule-set decompile "$rule_tmp" >/dev/null 2>&1; then
                install -m 0644 "$rule_tmp" "$rule_target"
                echo "规则集已更新: ${rule_tag}.srs"
            else
                echo "规则集获取失败（沿用本地已有文件）: ${rule_tag}.srs" >&2
            fi
            rm -f "$rule_tmp"
        fi
        [ -f "$rule_target" ] || missing_tags="$missing_tags $rule_tag"
    done < <(jq -r '.files[] | [.tag, .file, (.sha256 // "")] | @tsv' "$manifest_tmp")
    install -m 0644 "$manifest_tmp" "$rules_dir/.manifest.json" 2>/dev/null || true
fi
rm -f "$manifest_tmp"

if [ "$manifest_ok" = "yes" ]; then
    jq --arg dir "$rules_dir" --arg missing "$missing_tags" '
        ($missing | split(" ") | map(select(length > 0))) as $missing_tags
        | .route.rule_set = ((.route.rule_set // []) | map(
              select(type == "object")
              | if (.tag as $t | ($missing_tags | index($t)) != null) then empty
                elif .type == "remote"
                then { type: "local", tag: .tag, format: "binary", path: ($dir + "/" + .tag + ".srs") }
                else . end))
        | .route.rules = ((.route.rules // []) | map(
              if (((.rule_set // []) | map(. as $t | ($missing_tags | index($t)) != null) | any))
              then empty else . end))
    ' "$mode_file" > "${mode_file}.localized"
    mv "${mode_file}.localized" "$mode_file"
else
    echo "未能获取规则集清单，本次配置不启用分流规则（服务仍可正常启动）" >&2
    jq '
        .route.rule_set = []
        | .route.rules = ((.route.rules // []) | map(select((.rule_set // []) | length == 0)))
    ' "$mode_file" > "${mode_file}.norules"
    mv "${mode_file}.norules" "$mode_file"
fi

# 形状守卫：确认拿到的确实是 sing-box 配置（防接错端点/被注入页面）
if ! jq -e '.outbounds | type == "array"' "$mode_file" >/dev/null 2>&1; then
    echo "配置形状异常（缺少 outbounds），放弃安装以免影响现役服务" >&2
    exit 1
fi

"${SINGBOX_BIN:-}" check -c "$mode_file"

config_changed="no"
if ! cmp -s "$mode_file" "$config_path"; then
    config_changed="yes"
fi
install -m 0644 "$mode_file" "$config_path"

# 服务在跑就重启让新配置生效；停着的调用方（switch-mode / update 子命令）自己会起
if { [ "$config_changed" = "yes" ] || [ "${bin_changed:-no}" = "yes" ]; } &&
    systemctl is-active --quiet "${SINGBOX_SERVICE:-easynet-singbox}.service" 2>/dev/null; then
    systemctl restart "${SINGBOX_SERVICE:-easynet-singbox}.service"
    echo "配置/二进制已更新并重启服务"
else
    echo "配置已更新（内容无变化或服务未运行，未重启）"
fi
EOF
    chmod 0755 "$INSTALL_DIR/easynet-singbox-update"
}

write_systemd_units() {
    local dynamic_user_caps=""
    # TUN mode requires CAP_NET_ADMIN; mixed mode needs no special privileges
    if [ "${MODE:-mixed}" = "tun" ]; then
        dynamic_user_caps="AmbientCapabilities=CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN"
    fi

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyNet sing-box Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
DynamicUser=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
${dynamic_user_caps:+${dynamic_user_caps}
}ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # The updater rewrites ${CONFIG_DIR}/config.json + rules and restarts the
    # client service, and it reads the 600-root env file. It therefore must run
    # as root: with DynamicUser=yes + ProtectSystem=full it fails with
    # "/etc/easynet/singbox-client.env: Permission denied" and cannot write /etc.
    cat > "/etc/systemd/system/${UPDATE_NAME}.service" <<EOF
[Unit]
Description=Update EasyNet sing-box config

[Service]
Type=oneshot
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=${STATE_DIR} ${CONFIG_DIR}
ExecStart=${INSTALL_DIR}/easynet-singbox-update
EOF

    cat > "/etc/systemd/system/${UPDATE_NAME}.timer" <<EOF
[Unit]
Description=Daily EasyNet sing-box config update

[Timer]
OnBootSec=3min
OnUnitActiveSec=1d
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

local_lan_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

doctor() {
    local mode="${SINGBOX_MODE:-mixed}"
    local config_file="${SINGBOX_CONFIG_FILE:-$CONFIG_DIR/config.json}"
    local service_ok="false"
    local listener_ok="skip"
    local proxy_ok="false"
    local probe_url="${EASYNET_SINGBOX_PROBE_URL:-https://www.gstatic.com/generate_204}"

    log "sing-box 客户端排查信息"

    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        mode="${SINGBOX_MODE:-mixed}"
        config_file="${SINGBOX_CONFIG_FILE:-$CONFIG_DIR/config.json}"
        log "保存模式: $mode"
        log "配置链接: ${SINGBOX_CONFIG_URL:-unknown}"
        log "配置文件: $config_file"
    else
        warn "未找到 ${ENV_FILE}，请先完成客户端安装。"
    fi

    if [ -f "$config_file" ]; then
        log "当前入站配置:"
        jq '.inbounds' "$config_file" || true
    else
        warn "未找到 sing-box 配置文件。"
    fi

    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        service_ok="true"
    fi

    if [ "$mode" = "mixed" ]; then
        log "7890 监听状态:"
        if command -v ss >/dev/null 2>&1; then
            ss -lntup 2>/dev/null | awk 'NR == 1 || /:7890[[:space:]]/'
            if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:|\])7890$'; then
                listener_ok="true"
            else
                listener_ok="false"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            netstat -lntup 2>/dev/null | awk 'NR == 1 || /:7890[[:space:]]/'
            if netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:|\])7890$'; then
                listener_ok="true"
            else
                listener_ok="false"
            fi
        else
            listener_ok="unknown"
            warn "缺少 ss/netstat，无法检查端口监听。"
        fi
    fi

    log "代理连通性测试:"
    if [ "$service_ok" != "true" ]; then
        warn "跳过连通性测试：服务未运行。"
    elif [ "$mode" = "mixed" ]; then
        if curl -fsSIL --max-time 12 -x socks5h://127.0.0.1:7890 "$probe_url" >/dev/null; then
            proxy_ok="true"
            log "mixed 代理测试通过: $probe_url"
        else
            warn "mixed 代理测试失败: curl -x socks5h://127.0.0.1:7890 $probe_url"
        fi
    elif [ "$mode" = "tun" ]; then
        if curl -fsSIL --max-time 12 "$probe_url" >/dev/null; then
            proxy_ok="true"
            log "tun 全局代理测试通过: $probe_url"
        else
            warn "tun 全局代理测试失败: curl $probe_url"
        fi
    else
        warn "未知模式，无法执行代理连通性测试: $mode"
    fi

    log "服务状态:"
    systemctl status "${SERVICE_NAME}.service" --no-pager || true

    log "最近日志:"
    journalctl -u "${SERVICE_NAME}.service" -n 80 --no-pager || true

    log "诊断结论:"
    if [ "$service_ok" != "true" ]; then
        warn "代理异常：${SERVICE_NAME}.service 未运行。"
        return 1
    fi
    if [ "$mode" = "mixed" ] && [ "$listener_ok" = "false" ]; then
        warn "代理异常：mixed 模式未监听 127.0.0.1:7890。"
        return 1
    fi
    if [ "$proxy_ok" != "true" ]; then
        warn "代理异常：连通性测试未通过。"
        return 1
    fi
    log "代理正常：当前 $mode 模式连通性测试通过。"
}

print_status() {
    local mode="${SINGBOX_MODE:-mixed}"

    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        mode="${SINGBOX_MODE:-mixed}"
    else
        warn "未找到 ${ENV_FILE}，无法读取保存模式。"
    fi

    log "当前模式: $mode"
    systemctl status "${SERVICE_NAME}.service" --no-pager
}

service_stop_wait() {
    systemctl stop "${SERVICE_NAME}.service" || true

    for _ in 1 2 3 4 5; do
        if ! systemctl is-active --quiet "${SERVICE_NAME}.service"; then
            return 0
        fi
        sleep 1
    done

    die "停止 ${SERVICE_NAME}.service 超时，请运行 doctor 查看服务状态。"
}

service_start_checked() {
    systemctl start "${SERVICE_NAME}.service"
    systemctl is-active --quiet "${SERVICE_NAME}.service" ||
        die "${SERVICE_NAME}.service 启动失败，请运行 doctor 查看日志。"
}

update_and_restart() {
    service_stop_wait
    "$INSTALL_DIR/easynet-singbox-update"
    service_start_checked
}

switch_mode() {
    local previous_mode

    [ -f "$ENV_FILE" ] || die "未找到 ${ENV_FILE}，请先完成客户端安装。"
    previous_mode="$(
        grep -E '^SINGBOX_MODE=' "$ENV_FILE" 2>/dev/null |
            tail -n 1 |
            sed "s/^SINGBOX_MODE=//; s/^'//; s/'$//"
    )"
    previous_mode="${previous_mode:-mixed}"

    log "停止 sing-box 客户端服务..."
    service_stop_wait

    log "切换模式: ${previous_mode} -> ${MODE}"
    set_saved_mode "$MODE"

    if ! "$INSTALL_DIR/easynet-singbox-update"; then
        warn "新模式配置生成失败，恢复原模式: $previous_mode"
        set_saved_mode "$previous_mode"
        "$INSTALL_DIR/easynet-singbox-update" || true
        service_start_checked
        return 1
    fi

    if ! systemctl start "${SERVICE_NAME}.service"; then
        warn "新模式启动失败，恢复原模式: $previous_mode"
        set_saved_mode "$previous_mode"
        "$INSTALL_DIR/easynet-singbox-update" || true
        service_start_checked
        return 1
    fi

    systemctl is-active --quiet "${SERVICE_NAME}.service" ||
        die "${SERVICE_NAME}.service 启动后未保持运行，请运行 doctor 查看日志。"

    log "sing-box 客户端模式已切换为: $MODE"
}

run_action() {
    case "$ACTION" in
        start)
            systemctl start "${SERVICE_NAME}.service"
            ;;
        stop)
            systemctl stop "${SERVICE_NAME}.service"
            ;;
        restart)
            systemctl restart "${SERVICE_NAME}.service"
            ;;
        status)
            print_status
            ;;
        doctor)
            doctor
            ;;
        update)
            update_and_restart
            ;;
        switch-mode)
            switch_mode
            ;;
    esac
}

main() {
    require_root
    parse_args "$@"

    if [ "$ACTION" != "install" ]; then
        run_action
        exit 0
    fi

    install_packages
    install_singbox_binary
    write_state
    write_update_script

    log "下载并校验 sing-box 配置..."
    "$INSTALL_DIR/easynet-singbox-update"

    # Stop existing service so new config takes effect on re-install
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true

    write_systemd_units
    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service"
    systemctl enable --now "${UPDATE_NAME}.timer"

    log "sing-box 客户端已启动，当前模式: $MODE"
    if [ "$MODE" = "mixed" ]; then
        # Only advertise a LAN address when the proxy actually accepts non-local
        # connections, otherwise we point users at a port that is not listening.
        case "$LISTEN_ADDRESS" in
            127.0.0.1 | ::1)
                log "代理仅监听本机: http://127.0.0.1:7890 或 socks5://127.0.0.1:7890"
                ;;
            *)
                if lan_ip="$(local_lan_ip)" && [ -n "$lan_ip" ]; then
                    log "代理监听 ${LISTEN_ADDRESS}:7890，本机可访问 http://${lan_ip}:7890 或 socks5://${lan_ip}:7890"
                fi
                ;;
        esac
    else
        log "TUN 模式已启用，本机流量会由 sing-box 接管。"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
