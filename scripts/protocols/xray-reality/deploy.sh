#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/logging.sh"
source "$CORE_DIR/download.sh"
source "$CORE_DIR/network.sh"
source "$CORE_DIR/display.sh"
source "$CORE_DIR/crypto.sh"

XRAY_DIR="${XRAY_DIR:-/usr/local/etc/xray}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"

install_xray() {
    local xray_version
    log_info "安装 Xray..."
    xray_version="${EASYNET_XRAY_VERSION:-26.3.27}"
    run_downloaded_script \
        "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh" \
        "${EASYNET_XRAY_INSTALL_SHA256:-}" \
        install --version "v${xray_version}"
}

# Write xray config.json template based on transport type
# Parameters: transport, uuid, port, dest, server_names_arr, xhttp_mode
write_xray_config_template() {
    local transport="$1" uuid="$2" port="$3" dest="$4" server_names_arr="$5" xhttp_mode="$6"
    if [ "$transport" = "xhttp" ]; then
        cat > "$XRAY_DIR/config.json" << EOF
{
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$dest",
                    "xver": 0,
                    "serverNames": $server_names_arr,
                    "privateKey": "",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        ""
                    ]
                },
                "xhttpSettings": {
                    "mode": "$xhttp_mode"
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
    else
        cat > "$XRAY_DIR/config.json" << EOF
{
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
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
                    "dest": "$dest",
                    "xver": 0,
                    "serverNames": $server_names_arr,
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
    fi
    chmod 600 "$XRAY_DIR/config.json"
}

configure_reality() {
    log_info "配置 Xray+Reality..."
    mkdir -p "$XRAY_DIR"

    local transport="${EASYNET_REALITY_TRANSPORT:-tcp}"
    local xhttp_mode="${EASYNET_REALITY_XHTTP_MODE:-auto}"
    local xmux_concurrency="${EASYNET_REALITY_XMUX_CONCURRENCY:-0}"
    local fragment="${EASYNET_REALITY_FRAGMENT:-tlshello}"
    local fragment_length="${EASYNET_REALITY_FRAGMENT_LENGTH:-100-200}"
    local fragment_interval="${EASYNET_REALITY_FRAGMENT_INTERVAL:-10-20}"

    if [ -f "$XRAY_DIR/config.json" ] && grep -q "privateKey" "$XRAY_DIR/config.json"; then
        log_info "检测到已有的 Xray 配置，跳过生成新密钥，直接使用现有配置。"
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_DIR/config.json")
        PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_DIR/config.json")
        PUBLIC_KEY=$(cat "$XRAY_DIR/public.key" 2>/dev/null || echo "")

        # Check if transport type has changed — regenerate template if so
        local current_transport
        current_transport=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$XRAY_DIR/config.json")
        if [ "$current_transport" != "$transport" ]; then
            log_info "传输方式从 ${current_transport} 切换为 ${transport}，重新生成配置..."
            local existing_private_key
            existing_private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$XRAY_DIR/config.json")
            local existing_short_id
            existing_short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_DIR/config.json")
            local existing_dest
            existing_dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest // "www.microsoft.com:443"' "$XRAY_DIR/config.json")
            local existing_server_names_arr
            existing_server_names_arr=$(jq -c '.inbounds[0].streamSettings.realitySettings.serverNames // ["www.microsoft.com","cloudflare.com"]' "$XRAY_DIR/config.json")

            write_xray_config_template "$transport" "$UUID" "$PORT" "$existing_dest" "$existing_server_names_arr" "$xhttp_mode"

            # Inject preserved keys + optional fragment/xmux
            JQ_ARGS=(--arg pk "$existing_private_key" --arg sid "$existing_short_id")
            # shellcheck disable=SC2016  # $pk, $sid etc. are jq --arg vars, not bash
            JQ_FILTER='.inbounds[0].streamSettings.realitySettings.privateKey = $pk |
                         .inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid'
            if [ -n "$fragment" ] && [ "$transport" = "tcp" ]; then
                JQ_ARGS+=(--arg f_packets "$fragment" --arg f_length "$fragment_length" --arg f_interval "$fragment_interval")
                # shellcheck disable=SC2016  # $f_* are jq --arg vars
                JQ_FILTER+=' | .inbounds[0].streamSettings.fragmentSettings = { "packets": $f_packets, "length": $f_length, "interval": $f_interval }'
            fi
            if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
                JQ_ARGS+=(--argjson xmux_cc "$xmux_concurrency")
                # shellcheck disable=SC2016  # $xmux_cc is a jq --argjson var
                JQ_FILTER+=' | .inbounds[0].streamSettings.xhttpSettings.xmux = { "concurrency": $xmux_cc, "connIdleTime": 60 }'
            fi
            jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && \
                mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"

            log_info "配置已更新为 $transport 传输方式"
            systemctl restart xray
            return  # Skip subsequent logic (already fully handled)
        fi

        # Update Fragment settings on existing config (only applies to tcp transport)
        if [ -n "$fragment" ]; then
            if [ "$transport" = "tcp" ]; then
                jq --arg packets "$fragment" \
                   --arg length "$fragment_length" \
                   --arg interval "$fragment_interval" \
                   '.inbounds[0].streamSettings.fragmentSettings = { "packets": $packets, "length": $length, "interval": $interval }' \
                   "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"
                log_info "Fragment 混淆已启用: packets=$fragment length=$fragment_length interval=$fragment_interval"
                systemctl restart xray
            else
                log_info "注意: Fragment 不适用于 $transport 传输方式，已跳过（仅支持 tcp）"
            fi
        fi
    else
        UUID=$(generate_uuid)
        DEST="${EASYNET_REALITY_DEST:-www.microsoft.com:443}"
        SERVER_NAMES="${EASYNET_REALITY_SERVER_NAME:-www.microsoft.com,cloudflare.com}"
        # Build JSON array from comma-separated server names using jq
        SERVER_NAMES_ARR=$(jq -Rn --arg names "$SERVER_NAMES" '
            $names | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))
        ')
        PORT="${EASYNET_REALITY_PORT:-8443}"

        # Build config.json template via shared function
        write_xray_config_template "$transport" "$UUID" "$PORT" "$DEST" "$SERVER_NAMES_ARR" "$xhttp_mode"

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

        # Single combined jq — inject privateKey, shortId, optional fragment, optional xmux
        JQ_ARGS=(--arg pk "$PRIVATE_KEY" --arg sid "$SHORT_ID")
        # shellcheck disable=SC2016  # $pk, $sid etc. are jq --arg vars, not bash
        JQ_FILTER='.inbounds[0].streamSettings.realitySettings.privateKey = $pk |
                     .inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid'

        if [ -n "$fragment" ] && [ "$transport" = "tcp" ]; then
            JQ_ARGS+=(--arg f_packets "$fragment" --arg f_length "$fragment_length" --arg f_interval "$fragment_interval")
            # shellcheck disable=SC2016  # $f_* are jq --arg vars
            JQ_FILTER+=' | .inbounds[0].streamSettings.fragmentSettings = { "packets": $f_packets, "length": $f_length, "interval": $f_interval }'
        fi
        if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
            JQ_ARGS+=(--argjson xmux_cc "$xmux_concurrency")
            # shellcheck disable=SC2016  # $xmux_cc is a jq --argjson var
            JQ_FILTER+=' | .inbounds[0].streamSettings.xhttpSettings.xmux = { "concurrency": $xmux_cc, "connIdleTime": 60 }'
        fi

        jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && \
            mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"

        log_info "配置文件已生成 (transport=$transport)"
        if [ -n "$fragment" ]; then
            if [ "$transport" = "tcp" ]; then
                log_info "Fragment 混淆已启用: packets=$fragment length=$fragment_length interval=$fragment_interval"
            else
                log_info "注意: Fragment 不适用于 $transport 传输方式，已跳过（仅支持 tcp）"
            fi
        fi
        if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
            log_info "XMUX 多路复用已启用: concurrency=$xmux_concurrency"
        fi
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
    local uuid public_key short_id server_names public_ip config_url transport xhttp_mode

    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null)
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    public_ip=$(get_public_ip)
    transport=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$config_file")
    xhttp_mode=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "$config_file")
    fragment_packets=$(jq -r '.inbounds[0].streamSettings.fragmentSettings.packets // empty' "$config_file")
    fragment_length=$(jq -r '.inbounds[0].streamSettings.fragmentSettings.length // empty' "$config_file")

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
    echo "传输方式: $transport"
    if [ "$transport" = "xhttp" ]; then
        echo "XHTTP 模式: $xhttp_mode"
    fi
    if [ -n "$fragment_packets" ]; then
        echo "Fragment 混淆: $fragment_packets / $fragment_length"
    fi
    echo "流控: xtls-rprx-vision"
    echo ""

    if [ "$transport" = "xhttp" ]; then
        config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=chrome&pbk=$public_key&sid=$short_id&type=xhttp&mode=$xhttp_mode&flow=xtls-rprx-vision#EasyNet-Reality"
    else
        config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
    fi
    echo "客户端配置:"
    echo "$config_url"
    echo ""
    echo "配置二维码:"
    show_qrcode "$config_url" "配置二维码"
    echo "========================================"
}

main() {
    install_xray
    configure_reality
    create_systemd_service
    ensure_short_id
    show_config
}

main "$@"
