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
# Edge TLS certificate location; used to auto-detect self-steal mode.
EDGE_CERT_FILE="${EASYNET_EDGE_CERT_FILE:-${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}/fullchain.crt}"

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
    local transport="$1" uuid="$2" port="$3" dest="$4" server_names_arr="$5" xhttp_mode="$6" out_file="${7:-$XRAY_DIR/config.json}"
    if [ "$transport" = "xhttp" ]; then
        cat > "$out_file" << EOF
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
        cat > "$out_file" << EOF
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
    chmod 600 "$out_file"
}

# Resolve the REALITY camouflage target.
#
# Modes (EASYNET_REALITY_MODE):
#   auto   - 'self' when a local Edge TLS certificate exists, else 'borrow' (default)
#   self   - self-steal: reuse our own domain (which resolves to this host) as the
#            camouflage SNI and the local Edge site as fallback. This survives the
#            SNI->DNS consistency check that borrowed domains fail.
#   borrow - borrow an external site (legacy; weaker against SNI->DNS checks)
#
# Prints: "<dest>|<serverNames-csv>|<mode>"
resolve_reality_target() {
    local mode="${EASYNET_REALITY_MODE:-auto}"
    local dest="" server_names=""

    case "$mode" in
        auto)
            if [ -n "${EASYNET_DOMAIN:-}" ] && [ -f "$EDGE_CERT_FILE" ]; then
                mode="self"
            else
                mode="borrow"
            fi
            ;;
        self | borrow) ;;
        *)
            log_error "EASYNET_REALITY_MODE 取值无效: $mode（应为 auto|self|borrow）"
            exit 1
            ;;
    esac

    if [ "$mode" = "self" ]; then
        if [ -z "${EASYNET_DOMAIN:-}" ]; then
            log_error "EASYNET_REALITY_MODE=self 需要 EASYNET_DOMAIN（自有域名）。"
            exit 1
        fi
        if [ ! -f "$EDGE_CERT_FILE" ]; then
            log_error "EASYNET_REALITY_MODE=self 需要本机 Edge TLS 证书: $EDGE_CERT_FILE"
            log_error "请先部署 Edge Gateway，或改用 EASYNET_REALITY_MODE=borrow。"
            exit 1
        fi
        # Borrow our own domain: the client Hello's SNI resolves to this host, so it
        # survives the SNI->DNS consistency check. Fallback goes to the local Edge
        # HTTPS site, which serves the real certificate for that domain.
        dest="${EASYNET_REALITY_DEST:-127.0.0.1:${EASYNET_EDGE_HTTPS_PORT:-443}}"
        server_names="${EASYNET_REALITY_SERVER_NAME:-${EASYNET_DOMAIN:-}}"
    else
        dest="${EASYNET_REALITY_DEST:-www.bing.com:443}"
        server_names="${EASYNET_REALITY_SERVER_NAME:-www.bing.com,www.cloudflare.com}"
    fi

    printf '%s|%s|%s' "$dest" "$server_names" "$mode"
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

    # Resolve camouflage target: dest + serverNames + mode
    local target dest reality_mode server_names
    target="$(resolve_reality_target)"
    dest="${target%%|*}"
    server_names="${target#*|}"
    reality_mode="${server_names##*|}"
    server_names="${server_names%|*}"

    if [ "$reality_mode" = "self" ]; then
        log_info "Reality 自偷模式：SNI=${server_names}，伪装目标=${dest}（本机 Edge）"
    else
        log_warn "Reality 借用外部站点：SNI=${server_names}，伪装目标=${dest}"
        log_warn "借用他人域名无法通过「SNI→DNS 一致性检查」；建议部署 Edge 并启用 EASYNET_REALITY_MODE=self（auto 会自动启用）"
        if [ -z "${EASYNET_REALITY_DEST:-}" ] && [ -z "${EASYNET_REALITY_SERVER_NAME:-}" ]; then
            log_warn "当前使用默认伪装目标 www.bing.com — 多个 EasyNet 实例共享，更易被指纹化"
        fi
    fi

    # Warn about XHTTP + sing-box incompatibility
    if [ "$transport" = "xhttp" ]; then
        log_warn "XHTTP 传输仅 Xray-core 支持，sing-box 客户端将自动降级为 TCP"
        log_warn "如需 sing-box 客户端支持，请使用 TCP 传输 (EASYNET_REALITY_TRANSPORT=tcp)"
    fi

    local server_names_arr
    server_names_arr=$(jq -Rn --arg names "$server_names" '
        $names | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))
    ')

    local config_file="$XRAY_DIR/config.json"
    local have_existing=false
    local uuid="" port="" private_key="" short_id="" public_key=""

    if [ -f "$config_file" ] && grep -q '"privateKey"' "$config_file"; then
        have_existing=true
        uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
        port=$(jq -r '.inbounds[0].port // empty' "$config_file")
        private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$config_file")
        short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
        public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null || echo "")
        log_info "检测到已有 Xray 配置，保留 UUID / 私钥 / Short ID。"
    fi

    [ -n "$uuid" ] || uuid=$(generate_uuid)
    [ -n "$port" ] || port="${EASYNET_REALITY_PORT:-8443}"

    if [ -z "$private_key" ]; then
        log_info "生成 Reality 密钥..."
        local actual_xray_bin keys
        actual_xray_bin=$(command -v xray || echo "$XRAY_BIN")
        keys=$("$actual_xray_bin" x25519)
        private_key=$(echo "$keys" | grep -iE "Private[ \-]*Key" | awk '{print $NF}')
        public_key=$(echo "$keys" | grep -iE "(Public[ \-]*Key|Password)" | awk '{print $NF}')

        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            log_error "未能从 xray x25519 输出提取密钥。"
            exit 1
        fi

        echo "$public_key" > "$XRAY_DIR/public.key"
        chmod 644 "$XRAY_DIR/public.key"
    fi
    [ -n "$short_id" ] || short_id=$(openssl rand -hex 8)

    PORT="$port"

    # Render the desired config into a temp file, then swap only when it changes.
    local new_config
    new_config=$(mktemp "${XRAY_DIR}/config.json.XXXXXX")
    write_xray_config_template "$transport" "$uuid" "$port" "$dest" "$server_names_arr" "$xhttp_mode" "$new_config"

    local JQ_ARGS JQ_FILTER
    JQ_ARGS=(--arg pk "$private_key" --arg sid "$short_id" --arg fp "$fingerprint" --argjson mtd "$max_time_diff")
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
    jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$new_config" > "${new_config}.tmp" && mv "${new_config}.tmp" "$new_config"

    # Skip restart when the rendered config is identical to the current one.
    if [ "$have_existing" = true ] && diff <(jq -S . "$config_file") <(jq -S . "$new_config") >/dev/null 2>&1; then
        rm -f "$new_config"
        log_info "Reality 配置未变化，跳过重启。"
        return 0
    fi

    chmod 600 "$new_config"
    mv "$new_config" "$config_file"
    log_info "配置文件已生成 (transport=$transport, mode=$reality_mode)"
    if [ "$transport" = "xhttp" ] && [ "$xmux_concurrency" -gt 0 ] 2>/dev/null; then
        log_info "XMUX 多路复用已启用: concurrency=$xmux_concurrency"
    fi
    systemctl restart xray
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
    local uuid public_key short_id server_names public_ip config_url transport xhttp_mode fingerprint max_time_diff dest

    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null)
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest // empty' "$config_file")
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
    echo "伪装目标: $dest"
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
