#!/bin/bash

set -euo pipefail

CONFIG_URL=""
ACTION="install"
MODE="${EASYNET_SINGBOX_MODE:-mixed}"
SINGBOX_URL="${EASYNET_SINGBOX_DOWNLOAD_URL:-}"
INSTALL_DIR="${EASYNET_SINGBOX_INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${EASYNET_SINGBOX_CONFIG_DIR:-/etc/sing-box}"
STATE_DIR="${EASYNET_SINGBOX_STATE_DIR:-/etc/easynet}"
SERVICE_NAME="${EASYNET_SINGBOX_SERVICE_NAME:-easynet-singbox}"
UPDATE_NAME="${EASYNET_SINGBOX_UPDATE_NAME:-easynet-singbox-update}"
GITHUB_API="${EASYNET_SINGBOX_RELEASE_API:-https://api.github.com/repos/SagerNet/sing-box/releases/latest}"
ENV_FILE="$STATE_DIR/singbox-client.env"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage:
  sudo bash $0 --config-url <EasyNet /singbox URL> [--mode mixed|tun] [--sing-box-url <tar.gz URL>]
  sudo bash $0 start|stop|restart|status|update|doctor
  sudo bash $0 switch-mode mixed|tun

Options:
  --config-url      EasyNet sing-box config URL, usually https://domain/s/<random>/singbox
  --mode            Client mode. mixed opens HTTP/SOCKS port only. tun enables local full-device proxy.
  --sing-box-url    Optional sing-box release tarball URL. Auto-detected when omitted.
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
    local tmp_dir="" tarball binary_path existing_binary

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
    trap 'rm -rf "${tmp_dir:-}"' RETURN
    tarball="$tmp_dir/sing-box.tar.gz"

    log "下载 sing-box: $SINGBOX_URL"
    curl -fL "$SINGBOX_URL" -o "$tarball"
    tar -xzf "$tarball" -C "$tmp_dir"
    binary_path="$(find "$tmp_dir" -type f -name sing-box -perm -111 | head -n 1)"
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
EOF
    chmod 600 "$STATE_DIR/singbox-client.env"
}

set_saved_mode() {
    local mode="$1"
    local tmp_file

    [ -f "$ENV_FILE" ] || die "未找到 $ENV_FILE，请先完成客户端安装。"

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

curl -fL "$SINGBOX_CONFIG_URL" -o "$tmp_file"

case "${SINGBOX_MODE:-mixed}" in
    mixed)
        jq '
            .inbounds = [
                {
                    type: "mixed",
                    tag: "mixed-in",
                    listen: "0.0.0.0",
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
        echo "Unsupported SINGBOX_MODE: ${SINGBOX_MODE}" >&2
        exit 1
        ;;
esac

"$SINGBOX_BIN" check -c "$mode_file"
install -m 0644 "$mode_file" "$SINGBOX_CONFIG_FILE"
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
        warn "未找到 $ENV_FILE，请先完成客户端安装。"
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
        warn "未找到 $ENV_FILE，无法读取保存模式。"
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

    [ -f "$ENV_FILE" ] || die "未找到 $ENV_FILE，请先完成客户端安装。"
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

    write_systemd_units
    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service"
    systemctl enable --now "${UPDATE_NAME}.timer"

    log "sing-box 客户端已启动，当前模式: $MODE"
    if lan_ip="$(local_lan_ip)" && [ -n "$lan_ip" ]; then
        if [ "$MODE" = "mixed" ]; then
            log "局域网代理地址: http://${lan_ip}:7890 或 socks5://${lan_ip}:7890"
        else
            log "TUN 模式已启用，树莓派本机流量会由 sing-box 接管。"
        fi
    fi
}

main "$@"
