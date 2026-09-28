#!/bin/bash
# EasyNet 运行监控：心跳 + 健康检查 + 失败推送。
#
# 独立运行（cron / 手工）：
#   bash /opt/easynet/scripts/core/monitor.sh run      # 检查 + 失败时推送
#   bash /opt/easynet/scripts/core/monitor.sh check    # 只检查并打印，不推送
# 也可被 source 复用函数（deploy.sh 用它安装 cron）。
#
# 推送渠道（写入 .env，EASYNET_* 命名，与项目约定一致）：
#   EASYNET_MONITOR_NOTIFY=ntfy|telegram|email|none
#   EASYNET_MONITOR_NTFY_TOPIC_URL=https://ntfy.sh/<topic>
#   EASYNET_MONITOR_TELEGRAM_BOT_TOKEN=<token>  EASYNET_MONITOR_TELEGRAM_CHAT_ID=<id>
#   EASYNET_MONITOR_EMAIL_TO=admin@example.com
#   EASYNET_MONITOR_CRON="0 9 * * *"    # 可选：覆盖每日检查时间
#
# 未配置推送渠道时，check 仍可用于手工体检；deploy.sh 不会安装 cron。

MONITOR_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$MONITOR_CORE_DIR/logging.sh"
source "$MONITOR_CORE_DIR/env.sh"
source "$MONITOR_CORE_DIR/env_file.sh"
source "$MONITOR_CORE_DIR/metadata.sh"
source "$MONITOR_CORE_DIR/cron.sh"
source "$MONITOR_CORE_DIR/subscription.sh"

MONITOR_CRON="${EASYNET_MONITOR_CRON:-0 9 * * *}"

monitor_notify_channel() {
    printf '%s' "${EASYNET_MONITOR_NOTIFY:-none}"
}

# 找一个可用的发信客户端（mail/mailx/s-nail），没有则返回 1。
monitor_mail_bin() {
    local b
    for b in mail mailx s-nail; do
        command -v "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
    done
    return 1
}

# 逐项健康检查。每发现一项失败输出一行（无失败则无输出）。
monitor_failures() {
    local svc domain url cert

    # 1) 协议服务（按 metadata 枚举）
    local services
    services="$(cron_restart_services 2>/dev/null || true)"
    for svc in $services; do
        [ -n "$svc" ] || continue
        systemctl is-active --quiet "$svc" 2>/dev/null || printf '服务未运行: %s\n' "$svc"
    done

    # 2) Edge / nginx（若已部署）
    if [ -f "$(easynet_edge_state_dir)/domain.txt" ]; then
        systemctl is-active --quiet nginx 2>/dev/null || printf '服务未运行: nginx.service\n'
    fi

    # 3) fail2ban（若已安装）
    if systemctl list-unit-files fail2ban.service >/dev/null 2>&1; then
        systemctl is-active --quiet fail2ban 2>/dev/null || printf '服务未运行: fail2ban.service\n'
    fi

    # 4) 订阅端点可达
    domain="$(easynet_subscription_domain 2>/dev/null || true)"
    if [ -n "$domain" ]; then
        url="$(easynet_subscription_url sub 2>/dev/null || true)"
        if [ -n "$url" ]; then
            curl -fsS --connect-timeout 10 --max-time 30 -o /dev/null "$url" 2>/dev/null \
                || printf '订阅端点不可达: %s\n' "$url"
        fi
    fi

    # 5) Edge 证书到期预警（< 7 天）
    cert="${EASYNET_EDGE_CERT_FILE:-/etc/ssl/easynet-edge/fullchain.crt}"
    if [ -f "$cert" ]; then
        if ! openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null 2>&1; then
            printf 'Edge 证书将在 7 天内过期: %s\n' "$cert"
        fi
    fi
}

# 发送告警。返回 0=已发送或无需发送，1=渠道不可用/凭据不完整。
monitor_send() {
    local text="$1"
    local channel
    channel="$(monitor_notify_channel)"
    case "$channel" in
        ntfy)
            [ -n "${EASYNET_MONITOR_NTFY_TOPIC_URL:-}" ] || return 1
            curl -fsS --connect-timeout 10 --max-time 20 \
                -H "Title: EasyNet 告警 ($(hostname))" \
                -d "$text" "${EASYNET_MONITOR_NTFY_TOPIC_URL:-}" >/dev/null 2>&1
            ;;
        telegram)
            [ -n "${EASYNET_MONITOR_TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${EASYNET_MONITOR_TELEGRAM_CHAT_ID:-}" ] || return 1
            curl -fsS --connect-timeout 10 --max-time 20 \
                --data-urlencode "chat_id=${EASYNET_MONITOR_TELEGRAM_CHAT_ID:-}" \
                --data-urlencode "text=$text" \
                "https://api.telegram.org/bot${EASYNET_MONITOR_TELEGRAM_BOT_TOKEN:-}/sendMessage" >/dev/null 2>&1
            ;;
        email)
            [ -n "${EASYNET_MONITOR_EMAIL_TO:-}" ] || return 1
            local mail_bin
            mail_bin="$(monitor_mail_bin)" || return 1
            printf '%s\n' "$text" | "$mail_bin" -s "EasyNet 告警: $(hostname)" "${EASYNET_MONITOR_EMAIL_TO:-}" 2>/dev/null
            ;;
        none|'')
            return 0
            ;;
        *)
            log_warn "未知的 EASYNET_MONITOR_NOTIFY: $channel"
            return 1
            ;;
    esac
}

monitor_run() {
    local failures text state_dir
    failures="$(monitor_failures)"
    state_dir="$(easynet_state_dir)/monitor"

    if [ -z "$failures" ]; then
        mkdir -p "$state_dir" 2>/dev/null && date +%s > "$state_dir/last_ok" 2>/dev/null || true
        log_info "监控检查通过"
        return 0
    fi

    host="$(hostname)"
    now="$(date '+%F %T')"
    text="$(printf '[EasyNet] %s 检查失败 %s\n' "$host" "$now")${failures}"
    log_warn "$(printf '%s\n' "$failures")"
    if ! monitor_send "$text"; then
        log_warn "告警发送失败（推送渠道未配置或不可用）"
    fi
    return 1
}

# 安装每日监控 cron。仅当推送渠道 + 凭据齐全时才安装；否则跳过（可手工 monitor check）。
monitor_install_cron() {
    local channel cred_ok=false
    channel="$(monitor_notify_channel)"
    case "$channel" in
        ntfy) [ -n "${EASYNET_MONITOR_NTFY_TOPIC_URL:-}" ] && cred_ok=true ;;
        telegram) [ -n "${EASYNET_MONITOR_TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${EASYNET_MONITOR_TELEGRAM_CHAT_ID:-}" ] && cred_ok=true ;;
        email) [ -n "${EASYNET_MONITOR_EMAIL_TO:-}" ] && monitor_mail_bin >/dev/null 2>&1 && cred_ok=true ;;
        none|'')
            log_info "未配置监控推送（EASYNET_MONITOR_NOTIFY），跳过监控 cron。"
            return 0
            ;;
        *)
            log_warn "未知的 EASYNET_MONITOR_NOTIFY: ${channel}，跳过监控 cron。"
            return 0
            ;;
    esac

    if [ "$cred_ok" != "true" ]; then
        log_warn "监控推送渠道 $channel 已启用但凭据不完整，跳过监控 cron。"
        return 0
    fi

    local project command
    project="$(easynet_project_root)"
    command="/usr/bin/bash '$project/scripts/core/monitor.sh' run >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "EASYNET_MANAGED_MONITOR"; echo "$MONITOR_CRON $command # EASYNET_MANAGED_MONITOR") | crontab -
    log_info "监控 cron 已安装（${MONITOR_CRON}，推送渠道: ${channel}）"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    local_env="$(easynet_project_root)/.env"
    [ -f "$local_env" ] && load_easynet_env_file "$local_env"
    case "${1:-run}" in
        run) monitor_run ;;
        check) monitor_failures ;;
        -h | --help | help)
            sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            ;;
        *)
            log_error "未知子命令: ${1:-}（可用: run | check）"
            exit 1
            ;;
    esac
fi
