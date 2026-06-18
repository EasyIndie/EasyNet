#!/bin/bash

# EasyNet 订阅生成器
# - /sub: base64 编码的 URI 订阅，适用于 Shadowrocket / v2rayN / v2rayNG
# - /clash: Mihomo YAML 订阅，适用于 Clash Verge Rev / Mihomo
# - /singbox: sing-box JSON 配置，适用于低资源无界面客户端

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/metadata.sh"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"
source "$PROJECT_ROOT/scripts/core/display.sh"
source "$PROJECT_ROOT/scripts/core/discovery.sh"
source "$PROJECT_ROOT/scripts/core/subscription_clash.sh"

WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
SUB_FILE="${WEB_ROOT}/sub"
CLASH_FILE="${WEB_ROOT}/clash"
SINGBOX_FILE="${WEB_ROOT}/singbox"
SINGBOX_CLIENT_INSTALLER_SOURCE="$PROJECT_ROOT/scripts/clients/install_singbox_client.sh"
SINGBOX_CLIENT_INSTALLER_FILE="${WEB_ROOT}/easynet-singbox-client.sh"

SUBSCRIPTION_TMP_DIR="$(mktemp -d /tmp/easynet-subscription.XXXXXX)"
cleanup_subscription_tmp() {
    rm -rf "$SUBSCRIPTION_TMP_DIR"
}
trap cleanup_subscription_tmp EXIT

LINKS_FILE_SAFE="$SUBSCRIPTION_TMP_DIR/links_safe.txt"
CLASH_PROXIES_SAFE="$SUBSCRIPTION_TMP_DIR/clash_proxies_safe.yaml"
CLASH_NAMES_SAFE="$SUBSCRIPTION_TMP_DIR/clash_names_safe.txt"
SINGBOX_OUTBOUNDS_SAFE="$SUBSCRIPTION_TMP_DIR/singbox_outbounds_safe.jsonl"
SINGBOX_ENDPOINTS_SAFE="$SUBSCRIPTION_TMP_DIR/singbox_endpoints_safe.jsonl"
SINGBOX_NAMES_SAFE="$SUBSCRIPTION_TMP_DIR/singbox_names_safe.txt"

for file in \
    "$LINKS_FILE_SAFE" \
    "$CLASH_PROXIES_SAFE" \
    "$CLASH_NAMES_SAFE" \
    "$SINGBOX_OUTBOUNDS_SAFE" \
    "$SINGBOX_ENDPOINTS_SAFE" \
    "$SINGBOX_NAMES_SAFE"; do
    : > "$file"
done

append_proxy_name() {
    local file="$1"
    local name="$2"
    printf '%s\n' "$name" >> "$file"
}

base64_no_wrap() {
    if base64 --help 2>&1 | grep -q -- "-w"; then
        base64 -w 0
    else
        base64 | tr -d '\n'
    fi
}

generate_singbox_config() {
    local output_file="$1"
    local outbounds_file="$2"
    local endpoints_file="$3"
    local names_file="$4"

    [ ! -s "$names_file" ] && return 0

    jq -n \
        --slurpfile node_outbounds "$outbounds_file" \
        --slurpfile node_endpoints "$endpoints_file" \
        --rawfile names_raw "$names_file" \
        '
        ($names_raw | split("\n") | map(select(length > 0))) as $names
        | ({
            log: {
                level: "info",
                timestamp: true
            },
            inbounds: [
                {
                    type: "mixed",
                    tag: "mixed-in",
                    listen: "0.0.0.0",
                    listen_port: 7890
                }
            ],
            outbounds: (
                [
                    {
                        type: "selector",
                        tag: "Proxy",
                        outbounds: (["Auto", "DIRECT"] + $names),
                        default: "Auto"
                    },
                    {
                        type: "urltest",
                        tag: "Auto",
                        outbounds: $names,
                        url: "https://www.gstatic.com/generate_204",
                        interval: "5m",
                        tolerance: 50
                    }
                ]
                + $node_outbounds
                + [
                    { type: "direct", tag: "DIRECT" },
                    { type: "block", tag: "REJECT" }
                ]
            ),
            route: {
                rules: [
                    {
                        inbound: "mixed-in",
                        action: "sniff"
                    }
                ],
                auto_detect_interface: true,
                final: "Proxy"
            }
        } + if ($node_endpoints | length) > 0 then { endpoints: $node_endpoints } else {} end)' > "$output_file"

    chmod 644 "$output_file"
}

publish_singbox_client_installer() {
    if [ ! -f "$SINGBOX_CLIENT_INSTALLER_SOURCE" ]; then
        log_warn "未找到 sing-box 客户端安装脚本: $SINGBOX_CLIENT_INSTALLER_SOURCE"
        return 0
    fi

    install -m 0644 "$SINGBOX_CLIENT_INSTALLER_SOURCE" "$SINGBOX_CLIENT_INSTALLER_FILE"
}


append_metadata_singbox_outbound() {
    local metadata_file="$1"
    local output_file="$2"
    local endpoint_file="$3"
    local module render_jq type target_file

    module=$(jq -r '.module // empty' "$metadata_file")
    [ -z "$module" ] && return 1

    render_jq=$(discovery_module_render_script "$module" "singbox") || return 1

    type=$(jq -r '.client.clash.type // empty' "$metadata_file")
    if [ "$type" = "wireguard" ]; then
        target_file="$endpoint_file"
    else
        target_file="$output_file"
    fi

    jq -c -f "$render_jq" "$metadata_file" >> "$target_file"
}

metadata_security_rank() {
    local rank
    rank=$(discovery_get_manifest_value "$1" "MODULE_SECURITY_RANK") || {
        echo 99
        return 0
    }
    echo "$rank"
}

metadata_files_by_security() {
    local metadata_file module rank

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            log_warn "跳过无效 metadata: $metadata_file" >&2
            continue
        fi
        module=$(jq -r '.module' "$metadata_file")
        rank=$(metadata_security_rank "$module")
        printf '%s\t%s\n' "$rank" "$metadata_file"
    done < <(metadata_list_files) | sort -n -k1,1 | cut -f2-
}

load_metadata_nodes() {
    local metadata_file module uri name

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue

        module=$(jq -r '.module' "$metadata_file")
        uri=$(jq -r '.client.uri' "$metadata_file")
        name=$(jq -r '.client.clash.name // .module' "$metadata_file")

        log_info "从 metadata 提取节点: $module"
        echo "$uri" >> "$LINKS_FILE_SAFE"

        if append_metadata_clash_proxy "$metadata_file" "$CLASH_PROXIES_SAFE"; then
            append_proxy_name "$CLASH_NAMES_SAFE" "$name"
        fi
        if append_metadata_singbox_outbound "$metadata_file" "$SINGBOX_OUTBOUNDS_SAFE" "$SINGBOX_ENDPOINTS_SAFE"; then
            append_proxy_name "$SINGBOX_NAMES_SAFE" "$name"
        fi

    done < <(metadata_files_by_security)
}

show_subscription_links() {
    local sub_domain="$1"
    local sub_scheme="$2"
    local sub_port="$3"
    local origin sub_path clash_path singbox_path installer_path sub_url clash_url singbox_url installer_url
    if [ -z "$sub_domain" ]; then
        echo ""
        log_warn "订阅文件已生成，但没有可公开访问的订阅域名，因此不打印订阅链接和订阅二维码。"
        echo "说明："
        echo "- 配置 EASYNET_DOMAIN 或 EASYNET_SUBSCRIPTION_DOMAIN 后，部署流程会自动启用独立订阅承载。"
        echo "- 如果订阅文件由外部 Web 服务托管，可显式设置 EASYNET_SUBSCRIPTION_DOMAIN。"
        return 0
    fi

    origin=$(easynet_subscription_origin "$sub_domain" "$sub_scheme" "$sub_port")
    sub_path="$(easynet_subscription_endpoint "sub")"
    clash_path="$(easynet_subscription_endpoint "clash")"
    singbox_path="$(easynet_subscription_endpoint "singbox")"
    installer_path="$(easynet_subscription_endpoint "singbox-client.sh")"
    sub_url="${origin}${sub_path}"
    clash_url="${origin}${clash_path}"
    singbox_url="${origin}${singbox_path}"
    installer_url="${origin}${installer_path}"

    echo ""
    echo "========================================"
    echo "  节点订阅链接生成成功！"
    echo "========================================"
    echo "【URI 订阅】适用于 Shadowrocket / v2rayN / v2rayNG："
    echo -e "${GREEN}${sub_url}${NC}"
    show_qrcode "$sub_url" "URI 订阅二维码"
    echo ""
    echo "【Clash/Mihomo 订阅】适用于 Clash Verge Rev / Mihomo："
    echo -e "${GREEN}${clash_url}${NC}"
    show_qrcode "$clash_url" "Clash/Mihomo 订阅二维码"
    echo ""
    echo "【sing-box 配置】适用于 Raspberry Pi / 卡片机 / 无界面 Linux："
    echo -e "${GREEN}${singbox_url}${NC}"
    show_qrcode "$singbox_url" "sing-box 配置二维码"
    echo ""
    echo "树莓派快速安装："
    echo "curl -fsSL \"${installer_url}\" -o easynet-singbox-client.sh"
    echo "sudo bash easynet-singbox-client.sh --config-url \"${singbox_url}\""
    echo ""
    echo "说明："
    echo "- ${sub_path} 为 URI 聚合订阅"
    echo "- ${clash_path} 为 Mihomo YAML 订阅"
    echo "- ${singbox_path} 为 sing-box JSON 配置"
    echo "- ${installer_path} 为 sing-box 客户端安装脚本"
    echo "========================================"
}

load_metadata_nodes

if [ ! -s "$LINKS_FILE_SAFE" ] && [ ! -s "$CLASH_NAMES_SAFE" ]; then
    log_warn "没有找到任何有效的节点配置。"
    exit 0
fi

log_info "生成订阅文件..."
mkdir -p "$WEB_ROOT"
publish_singbox_client_installer

if [ -s "$LINKS_FILE_SAFE" ]; then
    base64_no_wrap < "$LINKS_FILE_SAFE" > "$SUB_FILE"
    chmod 644 "$SUB_FILE"
fi

generate_clash_config "$CLASH_FILE" "$CLASH_PROXIES_SAFE" "$CLASH_NAMES_SAFE"
generate_singbox_config "$SINGBOX_FILE" "$SINGBOX_OUTBOUNDS_SAFE" "$SINGBOX_ENDPOINTS_SAFE" "$SINGBOX_NAMES_SAFE"

show_subscription_links "$(easynet_subscription_domain)" "$(easynet_subscription_scheme)" "$(easynet_subscription_port)"
