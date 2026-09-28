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
#   EASYNET_MONITOR_UPSTREAM=false      # 可选：关掉「版本漂移 + CVE」上游检查
#   EASYNET_MONITOR_CVE=false           # 可选：只关 CVE，保留版本漂移
#
# 未配置推送渠道时，check 仍可用于手工体检；deploy.sh 不会安装 cron。

MONITOR_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$MONITOR_CORE_DIR/logging.sh"
source "$MONITOR_CORE_DIR/env.sh"
source "$MONITOR_CORE_DIR/env_file.sh"
source "$MONITOR_CORE_DIR/metadata.sh"
source "$MONITOR_CORE_DIR/cron.sh"
source "$MONITOR_CORE_DIR/subscription.sh"
source "$MONITOR_CORE_DIR/pins.sh"

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

# ── 上游维度检查（部署后持续告警；CI 的 pin 落后检查覆盖不到） ─────
#   1) 版本漂移：运行中的二进制版本 != release pin（发现手工替换 / 升级半途失败）
#   2) 已知漏洞：用 OSV.dev 查运行版本对应的 CVE（best-effort，失败静默）
# EASYNET_MONITOR_UPSTREAM=false 整段关闭；EASYNET_MONITOR_CVE=false 只关 CVE。

# release pin 里该组件的版本号（未知则空）。
monitor_pin_version() {
    case "${1:-}" in
        xray)        printf '%s' "${EASYNET_PIN_XRAY_VERSION:-}" ;;
        hysteria2)   printf '%s' "${EASYNET_PIN_HYSTERIA2_VERSION:-}" ;;
        shadowsocks) printf '%s' "${EASYNET_PIN_SHADOWSOCKS_VERSION:-}" ;;
    esac
}

# 从任意命令输出里取第一个 semver 形态的版本（去掉前导 v）。
monitor_parse_version() {
    grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | sed 's/^v//' || true
}

# 当前运行的二进制版本（未安装 / 解析失败则空）。
monitor_running_version() {
    local out=""
    case "${1:-}" in
        xray)
            if command -v xray >/dev/null 2>&1; then
                out="$(xray version 2>/dev/null | head -n1)"
            fi
            ;;
        hysteria2)
            if command -v hysteria >/dev/null 2>&1; then
                out="$(hysteria version 2>/dev/null | head -n1)"
            fi
            ;;
        shadowsocks)
            if command -v ssserver >/dev/null 2>&1; then
                out="$(ssserver --version 2>/dev/null | head -n1)"
            fi
            ;;
    esac
    printf '%s' "$out" | monitor_parse_version
}

# OSV.dev 坐标：<生态>|<包名>。
monitor_osv_package() {
    case "${1:-}" in
        xray)        printf 'Go|github.com/XTLS/Xray-core' ;;
        hysteria2)   printf 'Go|github.com/apernet/hysteria' ;;
        shadowsocks) printf 'crates.io|shadowsocks' ;;
    esac
}

# 查询 OSV.dev，逐条打印 "<id>: <summary>"；无漏洞或查询失败都无输出。
monitor_osv_vulns() {
    local comp="${1:-}" version="${2:-}" coords ecosystem name json
    [ -n "$version" ] || return 0
    coords="$(monitor_osv_package "$comp")"
    [ -n "$coords" ] || return 0
    ecosystem="${coords%%|*}"
    name="${coords#*|}"
    json="$(curl -fsS --connect-timeout 10 --max-time 20 \
        -H 'Content-Type: application/json' \
        -d "{\"version\":\"${version}\",\"package\":{\"name\":\"${name}\",\"ecosystem\":\"${ecosystem}\"}}" \
        https://api.osv.dev/v1/query 2>/dev/null || true)"
    [ -n "$json" ] || return 0
    # 只报有 fixed 版本的漏洞：无修复版本的公告报了也无法处理，只会造成告警疲劳。
    printf '%s' "$json" | jq -r '
        .vulns[]?
        | ([.affected[]?.ranges[]?.events[]? | select(has("fixed")) | .fixed] | sort) as $fx
        | select(($fx | length) > 0)
        | "\(.id): \(.summary // "无摘要")（修复于 \($fx[0])）"
    ' 2>/dev/null || true
}

# 上游维度告警行（无则无输出）。
monitor_upstream_findings() {
    local comp running pinned vulns line
    [ "${EASYNET_MONITOR_UPSTREAM:-true}" = "false" ] && return 0
    for comp in xray hysteria2 shadowsocks; do
        running="$(monitor_running_version "$comp")"
        [ -n "$running" ] || continue
        pinned="$(monitor_pin_version "$comp")"
        if [ -n "$pinned" ] && [ "$running" != "$pinned" ]; then
            printf '版本漂移: %s 运行 %s，release pin 为 %s\n' "$comp" "$running" "$pinned"
        fi
        if [ "${EASYNET_MONITOR_CVE:-true}" != "false" ]; then
            vulns="$(monitor_osv_vulns "$comp" "$running")"
            while IFS= read -r line; do
                [ -n "$line" ] && printf '已知漏洞: %s %s: %s\n' "$comp" "$running" "$line"
            done <<< "$vulns"
        fi
    done
}

# 与上次记录的上游发现比较，打印**新增**项；随后把当前完整列表写入状态文件。
# 同一 CVE / 漂移只在首次出现时告警，不再每天刷屏（monitor run 用；check 不走这里）。
monitor_upstream_diff() {
    local current="${1:-}" state_file prev line
    state_file="$(easynet_state_dir)/monitor/upstream_state"
    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    prev="$(cat "$state_file" 2>/dev/null || true)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qxF "$line" <<< "$prev" || printf '%s\n' "$line"
    done <<< "$current"
    printf '%s\n' "$current" | sed '/^$/d' > "$state_file" 2>/dev/null || true
}

# 健康检查（服务 / 端点 / 证书）。每发现一项失败输出一行（无失败则无输出）。
monitor_health_failures() {
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

# 全量检查（健康 + 上游），供 `monitor check` 手工查看。
monitor_failures() {
    monitor_health_failures
    monitor_upstream_findings
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
    local state_dir health upstream_all upstream_new findings text host now
    state_dir="$(easynet_state_dir)/monitor"

    # 健康问题每次都报（服务/端点/证书是即时状态）；上游发现（版本漂移 + 可修复
    # CVE）只报**新增**，避免同一漏洞每天刷屏。
    health="$(monitor_health_failures)"
    upstream_all="$(monitor_upstream_findings)"
    upstream_new="$(monitor_upstream_diff "$upstream_all")"

    if [ -n "$health" ] && [ -n "$upstream_new" ]; then
        findings="$(printf '%s\n%s' "$health" "$upstream_new")"
    elif [ -n "$health" ]; then
        findings="$health"
    else
        findings="$upstream_new"
    fi

    if [ -z "$findings" ]; then
        mkdir -p "$state_dir" 2>/dev/null && date +%s > "$state_dir/last_ok" 2>/dev/null || true
        log_info "监控检查通过"
        return 0
    fi

    host="$(hostname)"
    now="$(date '+%F %T')"
    text="$(printf '[EasyNet] %s 检查告警 %s\n' "$host" "$now")${findings}"
    log_warn "$(printf '%s\n' "$findings")"
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
            sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            ;;
        *)
            log_error "未知子命令: ${1:-}（可用: run | check）"
            exit 1
            ;;
    esac
fi
