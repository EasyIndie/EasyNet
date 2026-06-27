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
    local xray_version xray_sha256
    log_info "安装 Xray..."

    # 2026-06: v26.3.27 is the minimum safe version (fixes Aparecium NewSessionTicket gap).
    # Check https://github.com/XTLS/Xray-core/releases for the latest release.
    # v26.3.27+ bundles uTLS v1.8.2+ which fixes CVE-2026-26995 (missing padding) and
    # CVE-2026-27017 (ECH/GREASE mismatch) that allow TLS fingerprint detection.
    xray_version="${EASYNET_XRAY_VERSION:-26.3.27}"

    xray_sha256="${EASYNET_XRAY_INSTALL_SHA256:-}"
    if [ -z "$xray_sha256" ]; then
        log_warn "EASYNET_XRAY_INSTALL_SHA256 未设置，将跳过安装脚本的完整性验证"
        log_warn "建议设置此变量以防止供应链攻击: export EASYNET_XRAY_INSTALL_SHA256=<sha256>"
    fi

    run_downloaded_script \
        "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh" \
        "$xray_sha256" \
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
                        "flow": ""
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
                    "fingerprint": "",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 1800000,
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
                    "fingerprint": "",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 1800000,
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
    local xhttp_mode="${EASYNET_REALITY_XHTTP_MODE:-stream-one}"
    local xmux_concurrency="${EASYNET_REALITY_XMUX_CONCURRENCY:-0}"
    local xmux_conn_idle="${EASYNET_REALITY_XMUX_CONN_IDLE:-60}"
    local fingerprint="${EASYNET_REALITY_FINGERPRINT:-chrome}"
    # maxTimeDiff in milliseconds: 1800000 = 30 minutes. Set to 0 to disable.
    local max_time_diff="${EASYNET_REALITY_MAX_TIME_DIFF:-1800000}"

    # Warn about XHTTP + sing-box incompatibility
    if [ "$transport" = "xhttp" ]; then
        log_warn "XHTTP 传输仅 Xray-core 支持，sing-box 客户端将自动降级为 TCP"
        log_warn "如需 sing-box 客户端支持，请使用 TCP 传输 (EASYNET_REALITY_TRANSPORT=tcp)"
    fi

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

            # Inject preserved keys + fingerprint + optional xmux
            JQ_ARGS=(--arg pk "$existing_private_key" --arg sid "$existing_short_id" --arg fp "$fingerprint" --argjson mtd "$max_time_diff")
            # shellcheck disable=SC2016  # $pk, $sid, $fp, $mtd etc. are jq --arg/--argjson vars, not bash
            JQ_FILTER='.inbounds[0].streamSettings.realitySettings.privateKey = $pk |
                         .inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid |
                         .inbounds[0].streamSettings.realitySettings.fingerprint = $fp |
                         .inbounds[0].streamSettings.realitySettings.maxTimeDiff = $mtd'
            if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
                JQ_ARGS+=(--argjson xmux_cc "$xmux_concurrency" --argjson xmux_idle "$xmux_conn_idle")
                # shellcheck disable=SC2016  # $xmux_cc, $xmux_idle are jq --argjson vars
                JQ_FILTER+=' | .inbounds[0].streamSettings.xhttpSettings.xmux = { "concurrency": $xmux_cc, "connIdleTime": $xmux_idle }'
            fi
            jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && \
                mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"

            log_info "配置已更新为 $transport 传输方式"
            systemctl restart xray
            return  # Skip subsequent logic (already fully handled)
        fi

    else
        UUID=$(generate_uuid)
        # SECURITY: 默认伪装目标 www.bing.com 相比 www.microsoft.com 受到的DPI监控较少。
        # 最佳实践: 使用 EASYNET_REALITY_DEST 设置与你 VPS 同机房/同ASN 的低调域名。
        # 使用 bgp.tools 查找邻居域名，要求: TLS 1.3 + X25519 + HTTP/2, 非 Cloudflare, 中国可访问。
        # 避免使用: apple.com, google.com, microsoft.com, icloud.com（已被重点监控）。
        DEST="${EASYNET_REALITY_DEST:-www.bing.com:443}"
        SERVER_NAMES="${EASYNET_REALITY_SERVER_NAME:-www.bing.com,www.cloudflare.com}"

        # Warn if using default camouflage domain (widely shared, easier to fingerprint)
        if [ -z "${EASYNET_REALITY_DEST:-}" ] && [ -z "${EASYNET_REALITY_SERVER_NAME:-}" ]; then
            log_warn "使用默认伪装域名 www.bing.com — 多个 EasyNet 实例共享同一伪装目标"
            log_warn "建议设置 EASYNET_REALITY_DEST 为同机房邻居域名，提高抗检测能力"
            log_warn "使用 bgp.tools 查找同 ASN 域名: https://bgp.tools"
            log_warn "要求: TLS 1.3 + X25519 + HTTP/2, 非 Cloudflare, 从中国可访问"
        fi
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

        # Single combined jq — inject privateKey, shortId, fingerprint, maxTimeDiff, optional xmux
        JQ_ARGS=(--arg pk "$PRIVATE_KEY" --arg sid "$SHORT_ID" --arg fp "$fingerprint" --argjson mtd "$max_time_diff")
        # shellcheck disable=SC2016  # $pk, $sid, $fp, $mtd etc. are jq --arg/--argjson vars, not bash
        JQ_FILTER='.inbounds[0].streamSettings.realitySettings.privateKey = $pk |
                     .inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid |
                     .inbounds[0].streamSettings.realitySettings.fingerprint = $fp |
                     .inbounds[0].streamSettings.realitySettings.maxTimeDiff = $mtd'

        if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
            JQ_ARGS+=(--argjson xmux_cc "$xmux_concurrency" --argjson xmux_idle "$xmux_conn_idle")
            # shellcheck disable=SC2016  # $xmux_cc, $xmux_idle are jq --argjson vars
            JQ_FILTER+=' | .inbounds[0].streamSettings.xhttpSettings.xmux = { "concurrency": $xmux_cc, "connIdleTime": $xmux_idle }'
        fi

        jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$XRAY_DIR/config.json" > "${XRAY_DIR}/config.json.tmp" && \
            mv "${XRAY_DIR}/config.json.tmp" "$XRAY_DIR/config.json"

        log_info "配置文件已生成 (transport=$transport)"
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
    local uuid public_key short_id server_names public_ip config_url transport xhttp_mode fingerprint max_time_diff

    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null)
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    public_ip=$(get_public_ip)
    transport=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$config_file")
    xhttp_mode=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "$config_file")
    fingerprint=$(jq -r '.inbounds[0].streamSettings.realitySettings.fingerprint // "chrome"' "$config_file")
    max_time_diff=$(jq -r '.inbounds[0].streamSettings.realitySettings.maxTimeDiff // 0' "$config_file")

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
    echo "TLS 指纹: $fingerprint"
    echo "时间偏移限制: ${max_time_diff}ms"
    if [ "$transport" = "xhttp" ]; then
        echo "XHTTP 模式: $xhttp_mode"
        echo "流控: xtls-rprx-vision"
    fi
    echo ""

    if [ "$transport" = "xhttp" ]; then
        config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=$fingerprint&pbk=$public_key&sid=$short_id&type=xhttp&mode=$xhttp_mode#EasyNet-Reality"
    else
        echo "流控: xtls-rprx-vision"
        config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=$fingerprint&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
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
