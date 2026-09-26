#!/bin/bash
# EasyNet 公网可达性 / IP 封锁诊断
#
# 用途：判断「服务器服务正常，但客户端连不上」是否由 VPS 公网 IP 被
# GFW/运营商拦截（典型现象：回程丢包，TCP 握手完不成）导致。
#
# 用法（在 VPS 上以 root 运行）：
#   bash scripts/diagnose_reachability.sh
#   EASYNET_DIAG_CLIENT_IP=<客户端公网IP> bash scripts/diagnose_reachability.sh
#
# 环境变量：
#   EASYNET_DOMAIN                 域名（可选，用于 check-host.net 全局 HTTP 探测）
#   EASYNET_DIAG_CLIENT_IP         客户端公网 IP（可选；设置后进入抓包自动判定）
#   EASYNET_DIAG_CAPTURE_SECONDS   抓包窗口秒数（默认 60）
#   EASYNET_DIAG_SKIP_GLOBAL       设为 1 跳过 check-host.net 全局探测
#
# 抓包判定：
#   捕获到客户端 ACK                  -> 可达（握手完成）
#   有客户端 SYN + 服务器 SYN-ACK，
#   但无 ACK 且客户端反复重传 SYN     -> 回程被 GFW/运营商拦截（更换 IP/机房）
#   只有客户端 SYN、无服务器 SYN-ACK  -> 服务器未回应（查服务/防火墙）
#   完全没有 SYN                      -> 客户端未发起或去程被拦

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/network.sh"

DIAG_CLIENT_IP="${EASYNET_DIAG_CLIENT_IP:-}"
DIAG_CAPTURE_SECONDS="${EASYNET_DIAG_CAPTURE_SECONDS:-60}"
DIAG_SKIP_GLOBAL="${EASYNET_DIAG_SKIP_GLOBAL:-0}"
DIAG_DOMAIN="${EASYNET_DOMAIN:-}"

# 从 tcpdump 文本输出中判定链路状态，输出机器可读结论：
# reachable | return_blocked | no_synack | no_request
diag_classify() {
    local dump_file="$1"
    local syn_client synack_server ack_client

    syn_client="$(grep -cE 'Flags \[S\]' "$dump_file" 2>/dev/null || true)"
    synack_server="$(grep -cE 'Flags \[S\.\]' "$dump_file" 2>/dev/null || true)"
    ack_client="$(grep -cE 'Flags \[\.\]' "$dump_file" 2>/dev/null || true)"
    syn_client="${syn_client:-0}"
    synack_server="${synack_server:-0}"
    ack_client="${ack_client:-0}"

    if [ "$ack_client" -gt 0 ]; then
        echo "reachable"
    elif [ "$syn_client" -gt 0 ] && [ "$synack_server" -gt 0 ]; then
        echo "return_blocked"
    elif [ "$syn_client" -gt 0 ]; then
        echo "no_synack"
    else
        echo "no_request"
    fi
}

diag_report_verdict() {
    case "$1" in
        reachable)
            log_info "判定：可达（捕获到 ACK，TCP 握手完成）。链路正常，请继续排查协议/客户端配置。"
            ;;
        return_blocked)
            log_error "判定：回程被拦截（GFW/运营商）。客户端 SYN 到达服务器、服务器回了 SYN-ACK，但客户端收不到（反复重传 SYN）。"
            log_error "处理：更换服务器公网 IP 或更换机房/线路；重装 EasyNet 无法解决 IP 级封锁。"
            ;;
        no_synack)
            log_warn "判定：服务器未回 SYN-ACK。请检查服务监听与服务器/云防火墙（非墙问题）。"
            ;;
        no_request)
            log_warn "判定：未捕获到客户端请求。客户端可能未发起连接，或去程被拦截。"
            ;;
    esac
}

diag_local_status() {
    local svc
    log_info "本机服务状态:"
    for svc in nginx xray hysteria-server.service; do
        printf '  %-26s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo inactive)"
    done
    log_info "本机目标端口监听:"
    if ss -ltnup 2>/dev/null | grep -qE ':(22|80|443|8443|8388|51820)\b'; then
        ss -ltnup 2>/dev/null | grep -E ':(22|80|443|8443|8388|51820)\b' | sed 's/^/  /'
    else
        echo "  (未发现目标端口监听)"
    fi
}

diag_global_check() {
    local target resp rid result

    if [ "$DIAG_SKIP_GLOBAL" = "1" ]; then
        log_info "已跳过全局探测 (EASYNET_DIAG_SKIP_GLOBAL=1)。"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        log_warn "缺少 curl/jq，跳过 check-host.net 全局探测。"
        return 0
    fi
    if [ -z "$DIAG_DOMAIN" ]; then
        log_warn "未设置 EASYNET_DOMAIN，跳过全局 HTTP 探测（避免证书名不匹配）。"
        return 0
    fi

    target="https://${DIAG_DOMAIN}/sub"
    log_info "通过 check-host.net 从多地探测: ${target}"
    resp="$(curl -s --max-time 20 -H 'Accept: application/json' \
        "https://check-host.net/check-http?host=$(jq -rn --arg v "$target" '$v|@uri')&max_nodes=3" 2>/dev/null || true)"
    rid="$(printf '%s' "$resp" | jq -r '.request_id // empty' 2>/dev/null || true)"
    if [ -z "$rid" ]; then
        log_warn "check-host.net 请求失败（可能被限流），跳过全局探测。"
        return 0
    fi

    sleep 7
    result="$(curl -s --max-time 20 -H 'Accept: application/json' \
        "https://check-host.net/check-result/${rid}" 2>/dev/null || true)"
    if printf '%s' "$result" | jq -r 'to_entries[] | "  \(.key): \(.value[0][2]) http=\(.value[0][3]) ip=\(.value[0][4])"' 2>/dev/null; then
        log_info "若上面显示 OK/200，说明服务器对公网正常；客户端仍失败则问题在客户端网络/链路。"
    else
        log_warn "无法解析 check-host.net 结果。"
    fi
}

diag_capture() {
    local client_ip="$1"
    local seconds="$2"
    local pcap dump verdict

    if ! command -v tcpdump >/dev/null 2>&1; then
        log_info "安装 tcpdump..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y tcpdump >/dev/null 2>&1; then
            log_error "无法安装 tcpdump，跳过抓包判定。"
            return 1
        fi
    fi

    pcap="$(mktemp /tmp/easynet-diag.XXXXXX.pcap)"
    log_info "开始抓包 ${seconds}s。请现在从客户端 ${client_ip} 尝试连接 TCP 443 / 8443（或打开订阅链接）..."
    timeout "$seconds" tcpdump -n -i any "host ${client_ip}" -w "$pcap" >/dev/null 2>&1 || true

    dump="$(mktemp /tmp/easynet-diag.XXXXXX.txt)"
    tcpdump -n -r "$pcap" > "$dump" 2>/dev/null || true
    verdict="$(diag_classify "$dump")"
    rm -f "$pcap" "$dump"
    diag_report_verdict "$verdict"
}

main() {
    if [ "$(id -u)" != "0" ]; then
        log_warn "建议以 root 运行（抓包与防火墙检查需要权限）。"
    fi
    diag_local_status
    diag_global_check
    if [ -n "$DIAG_CLIENT_IP" ]; then
        diag_capture "$DIAG_CLIENT_IP" "$DIAG_CAPTURE_SECONDS"
    else
        log_info "提示：设置 EASYNET_DIAG_CLIENT_IP=<你的公网IP> 可自动判定回程是否被拦截。"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
