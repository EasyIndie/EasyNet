#!/bin/bash

set -euo pipefail

CONFIG_URL=""
SINGBOX_URL="${EASYNET_SINGBOX_DOWNLOAD_URL:-}"
INSTALL_DIR="${EASYNET_SINGBOX_INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${EASYNET_SINGBOX_CONFIG_DIR:-/etc/sing-box}"
STATE_DIR="${EASYNET_SINGBOX_STATE_DIR:-/etc/easynet}"
SERVICE_NAME="${EASYNET_SINGBOX_SERVICE_NAME:-easynet-singbox}"
UPDATE_NAME="${EASYNET_SINGBOX_UPDATE_NAME:-easynet-singbox-update}"
GITHUB_API="${EASYNET_SINGBOX_RELEASE_API:-https://api.github.com/repos/SagerNet/sing-box/releases/latest}"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo bash $0 --config-url <EasyNet /singbox URL> [--sing-box-url <tar.gz URL>]

Options:
  --config-url      EasyNet sing-box config URL, usually https://domain/s/<random>/singbox
  --sing-box-url    Optional sing-box release tarball URL. Auto-detected when omitted.
  -h, --help        Show this help.
EOF
}

require_root() {
    [ "$(id -u)" = "0" ] || die "请使用 root 运行，例如: sudo bash $0 --config-url <URL>"
}

parse_args() {
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
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "未知参数: $1"
                ;;
        esac
    done

    [ -n "$CONFIG_URL" ] || die "缺少 --config-url"
    case "$CONFIG_URL" in
        http://*|https://*) ;;
        *) die "--config-url 必须是 http 或 https URL" ;;
    esac
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
        apt-get install -y ca-certificates curl tar
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl tar
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl tar
    else
        warn "未识别包管理器，请确认 ca-certificates、curl、tar 已安装。"
    fi
}

resolve_singbox_url() {
    local asset_arch
    [ -n "$SINGBOX_URL" ] && return 0

    asset_arch="$(detect_asset_arch)"
    SINGBOX_URL="$(
        curl -fsSL "$GITHUB_API" \
            | sed -n "s/.*\"browser_download_url\": \"\\([^\"]*sing-box-[^\"]*-${asset_arch}\\.tar\\.gz\\)\".*/\\1/p" \
            | head -n 1
    )"
    [ -n "$SINGBOX_URL" ] || die "无法自动找到 sing-box ${asset_arch} 下载地址，请使用 --sing-box-url 指定。"
}

install_singbox_binary() {
    local tmp_dir tarball binary_path existing_binary

    if command -v sing-box >/dev/null 2>&1; then
        existing_binary="$(command -v sing-box)"
        log "检测到已安装 sing-box: $existing_binary"
        if [ "$existing_binary" != "$INSTALL_DIR/sing-box" ]; then
            install -m 0755 "$existing_binary" "$INSTALL_DIR/sing-box"
        fi
        return 0
    fi

    resolve_singbox_url
    tmp_dir="$(mktemp -d /tmp/easynet-singbox.XXXXXX)"
    trap 'rm -rf "$tmp_dir"' EXIT
    tarball="$tmp_dir/sing-box.tar.gz"

    log "下载 sing-box: $SINGBOX_URL"
    curl -fL "$SINGBOX_URL" -o "$tarball"
    tar -xzf "$tarball" -C "$tmp_dir"
    binary_path="$(find "$tmp_dir" -type f -name sing-box -perm -111 | head -n 1)"
    [ -n "$binary_path" ] || die "下载包中未找到 sing-box 可执行文件"

    install -m 0755 "$binary_path" "$INSTALL_DIR/sing-box"
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
EOF
    chmod 600 "$STATE_DIR/singbox-client.env"
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
cleanup() { rm -f "$tmp_file"; }
trap cleanup EXIT

curl -fL "$SINGBOX_CONFIG_URL" -o "$tmp_file"
"$SINGBOX_BIN" check -c "$tmp_file"
install -m 0644 "$tmp_file" "$SINGBOX_CONFIG_FILE"
EOF
    chmod 0755 "$INSTALL_DIR/easynet-singbox-update"
}

write_systemd_units() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyNet sing-box Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/systemd/system/${UPDATE_NAME}.service" <<EOF
[Unit]
Description=Update EasyNet sing-box config

[Service]
Type=oneshot
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

main() {
    require_root
    parse_args "$@"
    install_packages
    install_singbox_binary
    write_state
    write_update_script

    log "下载并校验 sing-box 配置..."
    "$INSTALL_DIR/easynet-singbox-update"

    write_systemd_units
    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service"
    systemctl enable --now "${UPDATE_NAME}.timer"

    log "sing-box 客户端已启动。"
    if lan_ip="$(local_lan_ip)" && [ -n "$lan_ip" ]; then
        log "局域网代理地址: http://${lan_ip}:7890 或 socks5://${lan_ip}:7890"
    fi
}

main "$@"
