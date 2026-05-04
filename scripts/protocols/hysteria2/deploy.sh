#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/metadata.sh"

HYSTERIA2_CONFIG_DIR="${HYSTERIA2_CONFIG_DIR:-/etc/hysteria}"
HYSTERIA2_CONFIG_FILE="${HYSTERIA2_CONFIG_FILE:-$HYSTERIA2_CONFIG_DIR/config.yaml}"
HYSTERIA2_ENV_FILE="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"
HYSTERIA2_SERVICE="${HYSTERIA2_SERVICE:-hysteria-server.service}"

random_secret() {
    openssl rand -hex 16
}

install_hysteria2() {
    if command -v hysteria &>/dev/null; then
        log_info "检测到 Hysteria2 已安装，跳过安装。"
        return
    fi

    log_info "安装 Hysteria2..."
    bash -c "$(curl -fsSL https://get.hy2.sh/)"
}

require_domain() {
    if [ -n "$EASYNET_DOMAIN" ]; then
        echo "$EASYNET_DOMAIN"
        return
    fi

    read -p "请输入 Hysteria2 绑定域名: " domain
    if [ -z "$domain" ]; then
        log_error "Hysteria2 需要可解析到本机的域名以签发 TLS 证书。"
        exit 1
    fi
    echo "$domain"
}

write_env_var() {
    printf '%s=%q\n' "$1" "$2" >> "$HYSTERIA2_ENV_FILE"
}

configure_hysteria2() {
    local domain port password obfs_password masquerade_url

    domain="$(require_domain)"
    port="${EASYNET_HYSTERIA2_PORT:-443}"
    password="${EASYNET_HYSTERIA2_PASSWORD:-$(random_secret)}"
    obfs_password="${EASYNET_HYSTERIA2_OBFS_PASSWORD:-$(random_secret)}"
    masquerade_url="${EASYNET_HYSTERIA2_MASQUERADE_URL:-https://www.bing.com/}"

    log_info "配置 Hysteria2..."
    mkdir -p "$HYSTERIA2_CONFIG_DIR"

    cat > "$HYSTERIA2_CONFIG_FILE" <<EOF
listen: :$port

tls:
  acme:
    domains:
      - $domain

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

    : > "$HYSTERIA2_ENV_FILE"
    write_env_var HYSTERIA2_DOMAIN "$domain"
    write_env_var HYSTERIA2_PORT "$port"
    write_env_var HYSTERIA2_PASSWORD "$password"
    write_env_var HYSTERIA2_OBFS_PASSWORD "$obfs_password"
    write_env_var HYSTERIA2_SNI "$domain"

    chmod 600 "$HYSTERIA2_CONFIG_FILE" "$HYSTERIA2_ENV_FILE"
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
    if command -v qrencode &>/dev/null; then
        qrencode -t utf8 "$config_url"
    else
        echo "未安装 qrencode，无法显示二维码。"
    fi
    echo "========================================"
}

main() {
    install_hysteria2
    configure_hysteria2
    restart_hysteria2
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
