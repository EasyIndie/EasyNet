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

HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_CONFIG_FILE="${HYSTERIA2_CONFIG_FILE:-$HYSTERIA2_CONFIG_DIR/config.yaml}"
HYSTERIA2_ENV_FILE="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"
HYSTERIA2_SERVICE="${HYSTERIA2_SERVICE:-hysteria-server.service}"
HYSTERIA2_CERT_DIR="${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
HYSTERIA2_CERT_FILE="${EASYNET_HYSTERIA2_CERT_FILE:-$HYSTERIA2_CERT_DIR/fullchain.crt}"
HYSTERIA2_KEY_FILE="${EASYNET_HYSTERIA2_KEY_FILE:-$HYSTERIA2_CERT_DIR/private.key"

install_hysteria2() {
    if command -v hysteria &>/dev/null; then
        log_info "检测到 Hysteria2 已安装，跳过安装。"
        return
    fi

    log_info "安装 Hysteria2..."
    run_downloaded_script "https://get.hy2.sh/" "${EASYNET_HYSTERIA2_INSTALL_SHA256:-}"
}

require_domain() {
    if [ -n "$EASYNET_DOMAIN" ]; then
        echo "$EASYNET_DOMAIN"
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
    if [ -f "$HYSTERIA2_CERT_FILE" ] && [ -f "$HYSTERIA2_KEY_FILE" ]; then
        return 0
    fi

    log_error "未找到 Hysteria2 TLS 证书：$HYSTERIA2_CERT_FILE / $HYSTERIA2_KEY_FILE"
    log_error "请先部署 Edge Gateway 生成统一证书，或设置 EASYNET_HYSTERIA2_CERT_FILE 与 EASYNET_HYSTERIA2_KEY_FILE。"
    exit 1
}

write_env_var() {
    printf '%s=%q\n' "$1" "$2" >> "$HYSTERIA2_ENV_FILE"
}

hysteria2_service_user() {
    systemctl cat "$HYSTERIA2_SERVICE" 2>/dev/null |
        awk -F= '/^[[:space:]]*User=/{ gsub(/[[:space:]]/, "", $2); print $2; exit }'
}

set_hysteria2_file_permissions() {
    local service_user

    service_user="$(hysteria2_service_user)"
    service_user="${service_user:-root}"

    if [ "$service_user" = "root" ]; then
        chmod 600 "$HYSTERIA2_CONFIG_FILE" "$HYSTERIA2_ENV_FILE"
        chmod 644 "$HYSTERIA2_CERT_FILE"
        chmod 600 "$HYSTERIA2_KEY_FILE"
        return
    fi

    if ! id "$service_user" >/dev/null 2>&1; then
        log_warn "未找到 Hysteria2 systemd 用户 $service_user，暂时仅设置 root 可读权限。"
        chmod 600 "$HYSTERIA2_CONFIG_FILE" "$HYSTERIA2_ENV_FILE" "$HYSTERIA2_KEY_FILE"
        chmod 644 "$HYSTERIA2_CERT_FILE"
        return
    fi

    chown root:"$service_user" \
        "$HYSTERIA2_CONFIG_FILE" \
        "$HYSTERIA2_ENV_FILE" \
        "$HYSTERIA2_CERT_FILE" \
        "$HYSTERIA2_KEY_FILE"
    chmod 750 "$HYSTERIA2_CERT_DIR"
    chown root:"$service_user" "$HYSTERIA2_CERT_DIR"
    chmod 640 \
        "$HYSTERIA2_CONFIG_FILE" \
        "$HYSTERIA2_ENV_FILE" \
        "$HYSTERIA2_CERT_FILE" \
        "$HYSTERIA2_KEY_FILE"
}

configure_hysteria2() {
    local domain port password obfs_password masquerade_url port_hopping hop_interval

    domain="$(require_domain)"
    port="${EASYNET_HYSTERIA2_PORT:-443}"
    password="${EASYNET_HYSTERIA2_PASSWORD:-$(random_secret)}"
    obfs_password="${EASYNET_HYSTERIA2_OBFS_PASSWORD:-$(random_secret)}"
    masquerade_url="${EASYNET_HYSTERIA2_MASQUERADE_URL:-https://www.bing.com/}"
    port_hopping="${EASYNET_HYSTERIA2_PORT_HOPPING:-}"
    hop_interval="${EASYNET_HYSTERIA2_PORT_HOP_INTERVAL:-30s}"

    log_info "配置 Hysteria2..."
    mkdir -p "$HYSTERIA2_CONFIG_DIR"
    require_tls_certificate

    cat > "$HYSTERIA2_CONFIG_FILE" <<EOF
listen: :$port

tls:
  cert: $HYSTERIA2_CERT_FILE
  key: $HYSTERIA2_KEY_FILE

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: $masquerade_url
    rewriteHost: true

obfs:
  type: salamander
  salamander:
    password: $obfs_password
EOF

    # Append port hopping config if enabled
    if [ -n "$port_hopping" ]; then
        cat >> "$HYSTERIA2_CONFIG_FILE" <<EOF

portHopping:
  interval: $hop_interval
  ports:
    - $port_hopping
EOF
        log_info "Port Hopping 已启用: $port_hopping (间隔 $hop_interval)"
    fi

    : > "$HYSTERIA2_ENV_FILE"
    write_env_var HYSTERIA2_DOMAIN "$domain"
    write_env_var HYSTERIA2_PORT "$port"
    write_env_var HYSTERIA2_PASSWORD "$password"
    write_env_var HYSTERIA2_OBFS_PASSWORD "$obfs_password"
    write_env_var HYSTERIA2_SNI "$domain"
    if [ -n "$port_hopping" ]; then
        write_env_var HYSTERIA2_PORT_HOPPING "$port_hopping"
        write_env_var HYSTERIA2_PORT_HOP_INTERVAL "$hop_interval"
    fi

    set_hysteria2_file_permissions
}

restart_hysteria2() {
    log_info "启动 Hysteria2 服务..."
    systemctl enable "$HYSTERIA2_SERVICE"
    systemctl restart "$HYSTERIA2_SERVICE"
}

show_config() {
    local domain port config_url

    # shellcheck disable=SC1090
    source "$HYSTERIA2_ENV_FILE"
    domain="$HYSTERIA2_DOMAIN"
    port="$HYSTERIA2_PORT"

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
    echo "- Hysteria2 使用 UDP/$port，请确认云厂商安全组和服务器防火墙均已放行 UDP/$port"
    echo "========================================"
}

main() {
    install_hysteria2
    configure_hysteria2
    restart_hysteria2
    show_config
}

main "$@"
