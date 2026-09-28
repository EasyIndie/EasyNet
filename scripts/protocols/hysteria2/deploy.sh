#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/metadata.sh"
source "$CORE_DIR/env.sh"
source "$CORE_DIR/download.sh"
source "$CORE_DIR/display.sh"
source "$CORE_DIR/crypto.sh"
source "$CORE_DIR/maintenance.sh"
source "$CORE_DIR/pins.sh"

HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_CONFIG_FILE="${HYSTERIA2_CONFIG_FILE:-${HYSTERIA2_CONFIG_DIR:-}/config.yaml}"
HYSTERIA2_ENV_FILE="${HYSTERIA2_ENV_FILE:-${HYSTERIA2_CONFIG_DIR:-}/easynet.env}"
HYSTERIA2_SERVICE="${HYSTERIA2_SERVICE:-hysteria-server.service}"
HYSTERIA2_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
HYSTERIA2_CERT_FILE="${EASYNET_HYSTERIA2_CERT_FILE:-${HYSTERIA2_CERT_DIR:-}/fullchain.crt}"
HYSTERIA2_KEY_FILE="${EASYNET_HYSTERIA2_KEY_FILE:-${HYSTERIA2_CERT_DIR:-}/private.key}"

install_hysteria2() {
    local pin version want_sha256 installed=""
    HYSTERIA2_BINARY_CHANGED=false

    # Pinned version + SHA256 (see core/pins.sh). The upstream one-liner
    # (get.hy2.sh) always installs "latest" as root, so we fetch the exact
    # release asset instead and verify it against a hash stored in this repo.
    pin="$(easynet_resolve_pin hysteria2)" || exit 1
    version="${pin%%|*}"
    want_sha256="${pin#*|}"

    if command -v hysteria >/dev/null 2>&1; then
        # `hysteria version` prints an ASCII banner first, so match the tag itself.
        installed="$(hysteria version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | awk 'NR==1')"
    fi
    if [ "$installed" = "v${version}" ]; then
        log_info "Hysteria2 v${version} 已是最新，跳过安装。"
    else
        log_info "安装 Hysteria2 v${version}..."
        install_hysteria2_binary "$version" "$want_sha256"
    fi

    # Always ensure the runtime prerequisites (service account, state dir, unit):
    # they must exist even when the binary itself is already current.
    ensure_hysteria2_runtime
    write_hysteria2_systemd_unit
}

# Download + verify + install the pinned release asset.
install_hysteria2_binary() {
    local version="$1" want_sha256="$2" asset url tmp_dir
    asset="$(easynet_pin_asset hysteria2)"
    if [ -z "$asset" ]; then
        log_error "Hysteria2 不支持当前架构: $(detect_arch)"
        exit 1
    fi
    url="https://github.com/apernet/hysteria/releases/download/app/v${version}/${asset}"

    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand tmp_dir now
    trap "rm -rf '$tmp_dir'" RETURN

    if ! download_file "$url" "$tmp_dir/hysteria" "$want_sha256"; then
        log_error "Hysteria2 下载或完整性校验失败。"
        log_error "  期望 SHA256: ${want_sha256}"
        log_error "  如确认上游已更换发布物，请更新 scripts/core/pins.sh 并提交评审。"
        exit 1
    fi

    install -m 0755 "$tmp_dir/hysteria" /usr/local/bin/hysteria
    # A new binary only takes effect after a restart, so force one.
    HYSTERIA2_BINARY_CHANGED=true
    log_info "Hysteria2 v${version} 已安装（SHA256 校验通过）。"
}

# Service account + state dir. The upstream installer used to create these; now
# that we install the binary ourselves we own them too.
ensure_hysteria2_runtime() {
    if ! id -u hysteria >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin hysteria
    fi
    mkdir -p "${HYSTERIA2_CONFIG_DIR:-}" /var/lib/hysteria
    chown hysteria:hysteria /var/lib/hysteria 2>/dev/null || true
    chmod 700 /var/lib/hysteria 2>/dev/null || true
}

write_hysteria2_systemd_unit() {
    local unit_dir="${EASYNET_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
    local unit_file="$unit_dir/${HYSTERIA2_SERVICE:-hysteria-server.service}"
    local new_unit
    new_unit="$(mktemp)"
    cat > "$new_unit" << 'EOF'
[Unit]
Description=Hysteria2 Server Service
After=network.target

[Service]
Type=simple
User=hysteria
Group=hysteria
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
WorkingDirectory=/var/lib/hysteria
Environment=HYSTERIA_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$new_unit"

    HYSTERIA2_UNIT_CHANGED=false
    if ! cmp -s "$new_unit" "$unit_file"; then
        install -m 644 "$new_unit" "$unit_file"
        HYSTERIA2_UNIT_CHANGED=true
    fi
    rm -f "$new_unit"
}

require_domain() {
    if [ -n "${EASYNET_DOMAIN:-}" ]; then
        echo "${EASYNET_DOMAIN:-}"
        return
    fi

    read -r -p "请输入 Hysteria2 绑定域名: " domain
    if [ -z "$domain" ]; then
        log_error "Hysteria2 需要可解析到本机的域名。"
        exit 1
    fi
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "域名格式无效: $domain"
        exit 1
    fi
    echo "$domain"
}

require_tls_certificate() {
    if [ -f "${HYSTERIA2_CERT_FILE:-}" ] && [ -f "${HYSTERIA2_KEY_FILE:-}" ]; then
        return 0
    fi

    log_error "未找到 Hysteria2 TLS 证书：${HYSTERIA2_CERT_FILE:-} / ${HYSTERIA2_KEY_FILE:-}"
    log_error "请先部署 Edge Gateway 生成统一证书，或设置 EASYNET_HYSTERIA2_CERT_FILE 与 EASYNET_HYSTERIA2_KEY_FILE。"
    exit 1
}

write_env_var() {
    local file="$1" name="$2" value="$3"
    printf '%s=%q\n' "$name" "$value" >> "$file"
}

# Read a secret persisted by an earlier deploy from HYSTERIA2_ENV_FILE.
# Returns an empty string when the file or variable is unavailable.
load_previous_secret() {
    local var_name="$1"
    local value=""
    if [ -f "${HYSTERIA2_ENV_FILE:-}" ]; then
        # shellcheck disable=SC1090  # 复用上次部署写入的 env 文件
        value="$(set +u; source "${HYSTERIA2_ENV_FILE:-}" 2>/dev/null; printf '%s' "${!var_name:-}")"
    fi
    printf '%s' "$value"
}

# Resolve a Hysteria2 secret with priority: explicit env > previously deployed
# value > newly generated random. This keeps re-deploys/upgrades from rotating
# the password and invalidating existing clients.
resolve_hysteria2_secret() {
    local env_value="$1"
    local var_name="$2"
    local previous=""

    if [ -n "$env_value" ]; then
        printf '%s' "$env_value"
        return 0
    fi
    previous="$(load_previous_secret "$var_name")"
    if [ -n "$previous" ]; then
        printf '%s' "$previous"
        return 0
    fi
    random_secret
}

hysteria2_service_user() {
    local user
    user="$(systemctl cat "${HYSTERIA2_SERVICE:-}" 2>/dev/null |
        awk -F= '/^[[:space:]]*User=/{ gsub(/[[:space:]]/, "", $2); print $2; exit }' || true)"
    printf '%s' "${user:-hysteria}"
}

set_hysteria2_file_permissions() {
    local service_user

    service_user="$(hysteria2_service_user)"
    service_user="${service_user:-root}"

    if [ "$service_user" = "root" ]; then
        chmod 600 "${HYSTERIA2_CONFIG_FILE:-}" "${HYSTERIA2_ENV_FILE:-}"
        chmod 644 "${HYSTERIA2_CERT_FILE:-}"
        chmod 600 "${HYSTERIA2_KEY_FILE:-}"
        return
    fi

    if ! id "$service_user" >/dev/null 2>&1; then
        log_warn "未找到 Hysteria2 systemd 用户 ${service_user}，暂时仅设置 root 可读权限。"
        chmod 600 "${HYSTERIA2_CONFIG_FILE:-}" "${HYSTERIA2_ENV_FILE:-}" "${HYSTERIA2_KEY_FILE:-}"
        chmod 644 "${HYSTERIA2_CERT_FILE:-}"
        return
    fi

    chown root:"$service_user" \
        "${HYSTERIA2_CONFIG_FILE:-}" \
        "${HYSTERIA2_ENV_FILE:-}" \
        "${HYSTERIA2_CERT_FILE:-}" \
        "${HYSTERIA2_KEY_FILE:-}"
    chmod 750 "${HYSTERIA2_CERT_DIR:-}"
    chown root:"$service_user" "${HYSTERIA2_CERT_DIR:-}"
    chmod 640 \
        "${HYSTERIA2_CONFIG_FILE:-}" \
        "${HYSTERIA2_ENV_FILE:-}" \
        "${HYSTERIA2_CERT_FILE:-}" \
        "${HYSTERIA2_KEY_FILE:-}"
}

# 把值写成 YAML 单引号标量（内嵌单引号按 YAML 规则双写）。
# 操作者可能用 EASYNET_HYSTERIA2_PASSWORD/OBFS_PASSWORD/MASQUERADE_URL 覆盖默认值，
# 值里若含 ':'、'#'、'&' 或前导 '!' 等 YAML 特殊字符，裸写会生成非法配置或被
# 静默截断（'#' 之后被当注释）。引号包裹后任意值都安全。
yaml_squote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

configure_hysteria2() {
    local domain port password obfs_password masquerade_url masquerade_block port_hopping hop_interval

    domain="$(require_domain)"
    port="${EASYNET_HYSTERIA2_PORT:-443}"
    password="$(resolve_hysteria2_secret "${EASYNET_HYSTERIA2_PASSWORD:-}" HYSTERIA2_PASSWORD)"
    obfs_password="$(resolve_hysteria2_secret "${EASYNET_HYSTERIA2_OBFS_PASSWORD:-}" HYSTERIA2_OBFS_PASSWORD)"
    masquerade_url="${EASYNET_HYSTERIA2_MASQUERADE_URL:-}"
    port_hopping="${EASYNET_HYSTERIA2_PORT_HOPPING:-}"
    hop_interval="${EASYNET_HYSTERIA2_PORT_HOP_INTERVAL:-30s}"

    # masquerade：未授权 QUIC 请求看到的内容。
    # 默认用与 Edge 相同的**自托管静态站**（域名/证书/内容自洽）；反代第三方大站
    # 会把「我在镜像别人」写进响应（canonical/Cookie/origin），是可被自动化识别的
    # 内容层特征。仍可用 EASYNET_HYSTERIA2_MASQUERADE_URL 显式反代自有站点。
    if [ -n "$masquerade_url" ]; then
        masquerade_block="masquerade:
  type: proxy
  proxy:
    url: $(yaml_squote "$masquerade_url")
    rewriteHost: true"
    else
        local masquerade_dir
        masquerade_dir="${EASYNET_HYSTERIA2_MASQUERADE_DIR:-${EASYNET_WEB_ROOT:-/var/www/html}}"
        if [ ! -f "$masquerade_dir/index.html" ]; then
            # 没有 Edge 伪装站时（例如单独重跑 hysteria2 模块）补一个，避免
            # 未授权探针什么都看不到。生成器与 Edge 共用。
            source "${SCRIPT_DIR}/../../exposure/edge/render_site.sh"
            easynet_edge_site_install "$masquerade_dir" "$domain" \
                "${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}" "${EASYNET_EDGE_SITE_DIR:-}"
        fi
        masquerade_block="masquerade:
  type: file
  file:
    dir: $(yaml_squote "$masquerade_dir")
    index: index.html"
    fi

    # Port hopping is enforced by the *server*: hysteria binds the base port and
    # installs nftables redirects (start..end -> base) for the rest of the range.
    # The `portHopping:` YAML block is a client-side option -- writing it into the
    # server config (as we used to) silently did nothing, so clients that hopped
    # were sent to ports nothing was listening on.
    local listen_spec="$port"
    if [ -n "$port_hopping" ]; then
        if [[ "$port_hopping" =~ ^([0-9]{2,5})-([0-9]{2,5})$ ]] \
            && [ "${BASH_REMATCH[1]}" -ge 1 ] && [ "${BASH_REMATCH[2]}" -le 65535 ] \
            && [ "${BASH_REMATCH[1]}" -lt "${BASH_REMATCH[2]}" ]; then
            listen_spec="$port,$port_hopping"
            log_info "Port Hopping 已启用: $port_hopping (基础端口 ${port}，间隔 $hop_interval)"
            log_info "  服务器将把 $port_hopping/udp 全部重定向到 $port/udp，并自动管理 nftables 规则"
        else
            log_warn "EASYNET_HYSTERIA2_PORT_HOPPING 格式无效（应为 起始-结束，如 20000-30000）: ${port_hopping}，已忽略"
            port_hopping=""
        fi
    fi

    log_info "配置 Hysteria2..."
    mkdir -p "${HYSTERIA2_CONFIG_DIR:-}"
    require_tls_certificate

    local new_config new_env
    new_config="$(mktemp)"
    new_env="$(mktemp)"

    cat > "$new_config" <<EOF
listen: :$listen_spec

tls:
  cert: ${HYSTERIA2_CERT_FILE:-}
  key: ${HYSTERIA2_KEY_FILE:-}

auth:
  type: password
  password: $(yaml_squote "$password")

$masquerade_block

obfs:
  type: salamander
  salamander:
    password: $(yaml_squote "$obfs_password")
EOF


    write_env_var "$new_env" HYSTERIA2_DOMAIN "$domain"
    write_env_var "$new_env" HYSTERIA2_PORT "$port"
    write_env_var "$new_env" HYSTERIA2_PASSWORD "$password"
    write_env_var "$new_env" HYSTERIA2_OBFS_PASSWORD "$obfs_password"
    write_env_var "$new_env" HYSTERIA2_SNI "$domain"
    if [ -n "$port_hopping" ]; then
        write_env_var "$new_env" HYSTERIA2_PORT_HOPPING "$port_hopping"
        write_env_var "$new_env" HYSTERIA2_PORT_HOP_INTERVAL "$hop_interval"
    fi

    # Idempotent apply: replace only when something changed, so a re-deploy does
    # not drop live Hysteria2 sessions.
    HYSTERIA2_CHANGED=false
    if ! cmp -s "$new_config" "${HYSTERIA2_CONFIG_FILE:-}" || ! cmp -s "$new_env" "${HYSTERIA2_ENV_FILE:-}"; then
        install -m 600 "$new_config" "${HYSTERIA2_CONFIG_FILE:-}"
        install -m 600 "$new_env" "${HYSTERIA2_ENV_FILE:-}"
        HYSTERIA2_CHANGED=true
    fi
    rm -f "$new_config" "$new_env"

    set_hysteria2_file_permissions
}

restart_hysteria2() {
    log_info "启动 Hysteria2 服务..."
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${HYSTERIA2_SERVICE:-}" >/dev/null 2>&1 || true
    # Sandbox the upstream unit via drop-in; keep /var/lib/hysteria (its home and
    # WorkingDirectory) writable under ProtectSystem=strict.
    # AF_NETLINK is required: port hopping makes hysteria shell out to nft(8) to
    # install the redirect rules, and without it the service dies at startup with
    # "Unable to initialize Netlink socket: Address family not supported by protocol".
    maintenance_apply_systemd_hardening "${HYSTERIA2_SERVICE:-}" \
        "ReadWritePaths=/var/lib/hysteria
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK"
    if [ "${HYSTERIA2_CHANGED:-true}" != "true" ] && [ "${HYSTERIA2_UNIT_CHANGED:-false}" != "true" ] &&
        [ "${HYSTERIA2_BINARY_CHANGED:-false}" != "true" ] &&
        [ "${SYSTEMD_HARDENING_CHANGED:-false}" != "true" ] &&
        systemctl is-active --quiet "${HYSTERIA2_SERVICE:-}"; then
        log_info "Hysteria2 配置未变化，跳过重启。"
        return 0
    fi
    systemctl restart "${HYSTERIA2_SERVICE:-}"
}

show_config() {
    local domain port config_url hop_range

    # shellcheck disable=SC1090
    source "${HYSTERIA2_ENV_FILE:-}"
    domain="${HYSTERIA2_DOMAIN:-}"
    port="${HYSTERIA2_PORT:-}"
    hop_range="${HYSTERIA2_PORT_HOPPING:-}"

    echo ""
    echo "========================================"
    echo "  Hysteria2 部署成功"
    echo "========================================"
    echo "域名: $domain"
    echo "端口: $port/udp"
    echo "混淆: salamander"
    echo "客户端配置:"
    "$SCRIPT_DIR/export.sh"
    config_url=$(jq -r '.client.uri' "$(easynet_module_metadata_path hysteria2)")
    echo "$config_url"
    echo ""
    echo "配置二维码:"
    show_qrcode "$config_url" "配置二维码"
    echo ""
    echo "连通性提示:"
    echo "- Hysteria2 使用 UDP/${port}，请确认云厂商安全组和服务器防火墙均已放行 UDP/${port}"
    # Port hopping is only useful if the whole range reaches the VM: we install the
    # nftables redirects locally, but the cloud security group is outside our reach.
    if [ -n "$hop_range" ]; then
        echo "- 端口跳跃已启用：云厂商安全组必须放行 UDP/${hop_range}（否则客户端跳变时会断流）"
        echo "  本机防火墙已自动放行；若你用的是云厂商侧防火墙，请手动添加该 UDP 范围"
    fi
    echo "========================================"
}

main() {
    install_hysteria2
    configure_hysteria2
    restart_hysteria2
    show_config
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
