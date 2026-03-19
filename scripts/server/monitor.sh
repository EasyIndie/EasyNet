#!/bin/bash

set -e

LOG_DIR="/var/log/easynet"
DATA_DIR="/var/lib/easynet"
TRAFFIC_FILE="$DATA_DIR/traffic.json"
WARNING_THRESHOLD_GB=800

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

init() {
    mkdir -p "$LOG_DIR" "$DATA_DIR"
    if [[ ! -f "$TRAFFIC_FILE" ]]; then
        cat > "$TRAFFIC_FILE" << 'EOF'
{
    "month": "",
    "total_rx": 0,
    "total_tx": 0,
    "daily": []
}
EOF
    fi
}

get_current_month() {
    date +"%Y-%m"
}

get_interface() {
    ip route get 8.8.8.8 | awk '/src/ {print $5}'
}

get_traffic_stats() {
    local interface=$(get_interface)
    if [[ -z "$interface" ]]; then
        log_error "无法获取网络接口"
        return 1
    fi

    local stats=$(cat /proc/net/dev | grep "$interface" | awk '{print $2, $10}')
    local rx=$(echo "$stats" | awk '{print $1}')
    local tx=$(echo "$stats" | awk '{print $2}')

    echo "$rx $tx"
}

bytes_to_gb() {
    echo "scale=2; $1 / 1024 / 1024 / 1024" | bc
}

update_traffic() {
    local current_month=$(get_current_month)
    local saved_month=$(jq -r '.month' "$TRAFFIC_FILE" 2>/dev/null || echo "")

    if [[ "$current_month" != "$saved_month" ]]; then
        log_info "新月份开始，重置流量统计"
        cat > "$TRAFFIC_FILE" << EOF
{
    "month": "$current_month",
    "total_rx": 0,
    "total_tx": 0,
    "daily": []
}
EOF
    fi

    local traffic=$(get_traffic_stats)
    local rx=$(echo "$traffic" | awk '{print $1}')
    local tx=$(echo "$traffic" | awk '{print $2}')

    local total_rx=$(jq '.total_rx' "$TRAFFIC_FILE")
    local total_tx=$(jq '.total_tx' "$TRAFFIC_FILE")

    local new_total_rx=$((total_rx + rx))
    local new_total_tx=$((total_tx + tx))

    jq ".month = \"$current_month\" | .total_rx = $new_total_rx | .total_tx = $new_total_tx" "$TRAFFIC_FILE" > "$TRAFFIC_FILE.tmp"
    mv "$TRAFFIC_FILE.tmp" "$TRAFFIC_FILE"
}

show_traffic() {
    local total_rx=$(jq '.total_rx' "$TRAFFIC_FILE")
    local total_tx=$(jq '.total_tx' "$TRAFFIC_FILE")
    local total=$((total_rx + total_tx))

    local rx_gb=$(bytes_to_gb $total_rx)
    local tx_gb=$(bytes_to_gb $total_tx)
    local total_gb=$(bytes_to_gb $total)
    local month=$(jq -r '.month' "$TRAFFIC_FILE")

    echo "========================================"
    echo "  流量统计 ($month)"
    echo "========================================"
    echo "下载: ${rx_gb} GB"
    echo "上传: ${tx_gb} GB"
    echo "总计: ${total_gb} GB"
    echo "========================================"

    if (( $(echo "$total_gb > $WARNING_THRESHOLD_GB" | bc -l) )); then
        log_warn "警告: 本月流量已超过 ${WARNING_THRESHOLD_GB} GB!"
    fi
}

check_service_status() {
    echo "========================================"
    echo "  服务状态检查"
    echo "========================================"

    for service in trojan-go v2ray shadowsocks-libev-server; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $service: 运行中"
        else
            echo -e "${RED}✗${NC} $service: 未运行"
        fi
    done
    echo "========================================"
}

main() {
    init

    case "${1:-show}" in
        update)
            update_traffic
            ;;
        show)
            show_traffic
            check_service_status
            ;;
        monitor)
            while true; do
                update_traffic
                sleep 300
            done
            ;;
        *)
            echo "用法: $0 [update|show|monitor]"
            echo "  update: 更新流量统计"
            echo "  show:   显示流量统计 (默认)"
            echo "  monitor:持续监控"
            exit 1
            ;;
    esac
}

main "$@"
