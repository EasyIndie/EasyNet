#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

get_public_ip() {
    curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
}

install_xray() {
    log_info "安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

configure_reality() {
    log_info "配置 Xray+Reality..."
    mkdir -p "$XRAY_DIR"

    # 检查是否是恢复模式（配置已存在）
    if [ -f "$XRAY_DIR/config.json" ] && grep -q "privateKey" "$XRAY_DIR/config.json"; then
        log_info "检测到已有的 Xray 配置，跳过生成新密钥，直接使用现有配置。"
        
        # 使用 jq 安全地提取配置
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_DIR/config.json")
        PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_DIR/config.json")
        DEST=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest // empty' "$XRAY_DIR/config.json")
        SERVER_NAMES=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_DIR/config.json")
        
        # 兼容处理 Short ID，如果是 null 或者 empty 则设为空字符串
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_DIR/config.json")
        if [ "$SHORT_ID" == "null" ] || [ -z "$SHORT_ID" ]; then
            SHORT_ID=""
        fi
        
        PUBLIC_KEY=$(cat "$XRAY_DIR/public.key" 2>/dev/null || echo "请查看备份前的记录")
        PUBLIC_IP=$(get_public_ip)
    else
        UUID=$(generate_uuid)
        PUBLIC_IP=$(get_public_ip)
        DEST="www.microsoft.com:443"
        SERVER_NAMES="www.microsoft.com"
        PORT=8443

        cat > "$XRAY_DIR/config.json" << EOF
{
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 8443,
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
        
        # 动态获取 Xray 二进制文件路径，防止安装路径不是默认的 /usr/local/bin/xray
        local actual_xray_bin=$(command -v xray || echo "/usr/local/bin/xray")
        
        # 强制重新生成以确保全局变量有效
        KEYS=$("$actual_xray_bin" x25519)
        
        # 兼容不同版本的 xray 输出格式 (旧版: "Private key:", 新版: "PrivateKey:")
        PRIVATE_KEY=$(echo "$KEYS" | grep -iE "Private[ \-]*Key" | awk '{print $NF}')
        
        # 兼容不同版本的 xray 输出格式 (旧版: "Public key:", 新版: "Password:")
        PUBLIC_KEY=$(echo "$KEYS" | grep -iE "(Public[ \-]*Key|Password)" | awk '{print $NF}')
        
        # 确保提取到了内容，如果没有则直接写死一个备用方案（极少发生）
        if [ -z "$PUBLIC_KEY" ]; then
            log_warn "未能成功从 x25519 提取公钥，可能是 xray 版本输出格式有变。"
        fi
        
        # 将 PUBLIC_KEY 保存到一个临时文件或写入配置，以便后续提取
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
    
    # 放行防火墙端口
    if command -v ufw &>/dev/null; then
        ufw allow $PORT/tcp
    fi
}

show_config() {
    local config_file="$XRAY_DIR/config.json"
    
    # 确保 jq 存在
    if ! command -v jq &> /dev/null; then
        log_error "jq 工具未安装，无法解析配置文件。请先运行 deploy.sh 安装依赖。"
        return 1
    fi
    
    local uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$config_file")
    local public_key=$(cat "$XRAY_DIR/public.key" 2>/dev/null)
    local short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$config_file")
    local server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    
    if [ "$short_id" == "null" ]; then
        short_id=""
    fi
    
    # 【修复】由于在全新部署或恢复部署时，配置文件中的 shortIds 确实可能被写入了空字符串 ""，
    # 但在最初生成时，如果是新生成的话它是有值的。为了避免恢复出来的配置中 short_id 丢失（如果文件里确实为空），
    # 我们需要在恢复模式下发现它为空时，为它重新生成并写回文件，确保客户端总能获取到合法的 short_id。
    if [ -z "$short_id" ]; then
        short_id=$(openssl rand -hex 8)
        # 使用 jq 安全更新 JSON
        jq --arg sid "$short_id" '.inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        systemctl restart xray
    fi
    if [ -z "$server_names" ] || [ "$server_names" == "null" ]; then
        server_names=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$config_file")
    fi
    local public_ip=$(get_public_ip)

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
    
    local config_url="vless://$uuid@$public_ip:$PORT?encryption=none&security=reality&sni=$server_names&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision#EasyNet-Reality"
    echo "客户端配置:"
    echo "$config_url"
    echo ""
    echo "配置二维码:"
    if command -v qrencode &> /dev/null; then
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
    show_config
}

main "$@"
