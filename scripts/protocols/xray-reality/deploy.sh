#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/download.sh"

XRAY_DIR="${XRAY_DIR:-/usr/local/etc/xray}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

install_xray() {
    log_info "安装 Xray..."
    run_downloaded_script \
        "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" \
        "${EASYNET_XRAY_INSTALL_SHA256:-}" \
        install
}

configure_reality() {
    log_info "配置 Xray+Reality..."
    mkdir -p "$XRAY_DIR"

    if [ -f "$XRAY_DIR/config.json" ] && grep -q "privateKey" "$XRAY_DIR/config.json"; then
        log_info "检测到已有的 Xray 配置，跳过生成新密钥，直接使用现有配置。"
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_DIR/config.json")
        PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_DIR/config.json")
        PUBLIC_KEY=$(cat "$XRAY_DIR/public.key" 2>/dev/null || echo "")
        PUBLIC_IP=$(get_public_ip)
    else
        UUID=$(generate_uuid)
        PUBLIC_IP=$(get_public_ip)
        DEST="${EASYNET_REALITY_DEST:-www.microsoft.com:443}"
        SERVER_NAMES="${EASYNET_REALITY_SERVER_NAME:-www.microsoft.com}"
        PORT="${EASYNET_REALITY_PORT:-8443}"

        cat > "$XRAY_DIR/config.json" << EOF
{
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$DEST",
                    "xver": 0,
                    "serverNames": [
                        "$SERVER_NAMES"
                    ],
                    "privateKey": "",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        ""
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]
}
EOF

        log_info "生成 Reality 密钥..."
        local actual_xray_bin
        actual_xray_bin=$(command -v xray || echo "$XRAY_BIN")
        KEYS=$("$actual_xray_bin" x25519)
        PRIVATE_KEY=$(echo "$KEYS" | grep -iE "Private[ \-]*Key" | awk '{print $NF}')
        PUBLIC_KEY=$(echo "$KEYS" | grep -iE "(Public[ \-]*Key|Password)" | awk '{print $NF}')

        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
            log_error "未能从 xray x25519 输出提取密钥。"
            exit 1
        fi

        echo "$PUBLIC_KEY" > "$XRAY_DIR/public.key"
        chmod 644 "$XRAY_DIR/public.key"

        SHORT_ID=$(openssl rand -hex 8)

        jq --arg pk "$PRIVATE_KEY" --arg sid "$SHORT_ID" '
            .inbounds[0].streamSettings.realitySettings.privateKey = $pk |
            .inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid
        ' "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"

        log_info "配置文件已生成"
    fi
}

create_systemd_service() {
    log_info "配置 Xray 服务..."
    systemctl enable xray
    systemctl restart xray
}

ensure_short_id() {
    local config_file="$XRAY_DIR/config.json"
    local short_id
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    if [ "$short_id" == "null" ] || [ -z "$short_id" ]; then
        short_id=$(openssl rand -hex 8)
        jq --arg sid "$short_id" '.inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        systemctl restart xray
    fi
}

show_config() {
    local config_file="$XRAY_DIR/config.json"
    local uuid public_key short_id server_names public_ip config_url

    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null)
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    public_ip=$(get_public_ip)

    echo ""
    echo "========================================"
    echo "  Xray+Reality 部署成功"
    echo "========================================"
    echo "服务器 IP: $public_ip"
    echo "端口: $PORT"
    echo "UUID: $uuid"
    echo "公钥: $public_key"
    echo "Short ID: $short_id"
    echo "目标网站: $server_names"
    echo "流控: xtls-rprx-vision"
    echo ""

    config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
    echo "客户端配置:"
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
    install_xray
    configure_reality
    create_systemd_service
    ensure_short_id
    "$SCRIPT_DIR/export.sh"
    show_config
}

main "$@"
