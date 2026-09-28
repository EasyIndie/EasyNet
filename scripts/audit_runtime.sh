#!/bin/bash
# EasyNet 运行时安全体检（只读取证）
#
# 用法（需 root，在目标 VPS 上运行）：
#   bash scripts/audit_runtime.sh
#
# 只读：不修改任何系统状态，仅输出体检报告。任何一项 [失败] 都会让退出码非零，
# 可用于发版前验收 / 变更后回归 / 定期巡检。报告中的订阅路径前缀会脱敏。
#
# 覆盖：系统概览 / 服务 / 版本 / 敏感文件权限 / 进程命令行密钥 / systemd 沙箱 /
# 端口与防火墙 / TLS 与安全头 / 订阅路径 / SSH / fail2ban / cron / journald /
# Reality 自偷 / 端口跳跃 / 证书到期。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/env.sh"

STATE_DIR="$(easynet_state_dir)"
DOMAIN="${EASYNET_DOMAIN:-}"
DOMAIN_FILE="$STATE_DIR/exposure/edge/domain.txt"
[ -z "$DOMAIN" ] && [ -f "$DOMAIN_FILE" ] && DOMAIN="$(cat "$DOMAIN_FILE" 2>/dev/null || true)"

PASS=0; WARN=0; FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  \033[32m[通过]\033[0m %s\n' "$*"; }
warn() { WARN=$((WARN + 1)); printf '  \033[33m[警告]\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m[失败]\033[0m %s\n' "$*"; }
h1()   { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }

require_root() {
    [ "$(id -u)" = "0" ] || { echo "请以 root 运行（sudo bash $0）" >&2; exit 2; }
}

# 判断一个文件是否为「组/其它不可读」：权限数字最后一位（other）须为 0。
# 只接受 root 或 group 可读（640/600/750 等），拒绝 644/755/666 等。
not_world_readable() {
    local file="$1" mode
    [ -e "$file" ] || return 0
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    [ -n "$mode" ] || return 1
    [ "$((mode % 10))" = "0" ]
}

svc_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# 输出非 loopback 的监听端口，格式 "<端口>/<tcp|udp>"（去重）。
listening_ports() {
    ss -lntup 2>/dev/null \
        | awk '
            NR == 1 { next }
            $5 ~ /%/ { next }
            $5 ~ /^127\.|^\[::1\]|^\*:53 |^127\.0\.0\.53/ { next }
            $1 == "tcp" || $1 == "udp" {
                addr = $5
                port = addr
                sub(/^.*:/, "", port)
                if (port ~ /^[0-9]+$/) {
                    # 跳过 UDP 临时端口（服务进程的出站 DNS 等，非对外监听服务）
                    if ($1 == "udp" && port >= 32768) next
                    print port "/" $1
                }
            }
        ' | awk 'NF && !seen[$0]++'
}

ufw_has_rule() {
    local spec="$1" port proto out
    port="${spec%/*}"
    proto="${spec#*/}"
    out="$(ufw status 2>/dev/null || true)"
    grep -qE "${port}/${proto}.*(ALLOW|LIMIT)" <<< "$out"
}

require_root

h1 "系统概览"
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    info "${PRETTY_NAME:-$ID} ($(uname -r))"
fi
info "公网 IP: ${EASYNET_PUBLIC_IP:-$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || echo 未知)}"
info "内存: $(free -h 2>/dev/null | awk 'NR==2 {print $3 " / " $2}' || echo 未知)  load: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}' || echo 未知)"

h1 "服务状态"
for unit in xray.service hysteria-server.service shadowsocks-rust-server.service awg-quick@wg0.service nginx.service fail2ban.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        if svc_active "$unit"; then
            ok "$unit active"
        else
            bad "$unit 未运行"
        fi
    fi
done

h1 "二进制版本"
if command -v xray >/dev/null 2>&1; then
    info "xray: $(xray version 2>/dev/null | awk 'NR==1 {print $2}')"
fi
if command -v hysteria >/dev/null 2>&1; then
    info "hysteria: $(hysteria version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | awk 'NR==1')"
fi
if command -v ssserver >/dev/null 2>&1; then
    info "ssserver: $(ssserver --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | awk 'NR==1')"
fi
info "nginx: $(nginx -v 2>&1 | sed -n 's|.*nginx/||p')"

h1 "敏感文件权限"
for f in \
    "${EASYNET_STATE_DIR:-/var/lib/easynet}" \
    "${EASYNET_STATE_DIR:-/var/lib/easynet}/exposure/edge/subscription_path_prefix.txt" \
    /etc/hysteria/config.yaml \
    /etc/hysteria/easynet.env \
    /usr/local/etc/xray/config.json \
    /etc/shadowsocks-rust/config.json \
    /etc/amnezia/amneziawg/wg0.conf; do
    if [ -e "$f" ]; then
        if not_world_readable "$f"; then
            ok "$f 权限 $(stat -c '%a' "$f")"
        else
            bad "$f world-readable（$(stat -c '%a' "$f")）"
        fi
    fi
done

h1 "进程命令行密钥泄漏"
leak=0
for p in xray hysteria ssserver awg; do
    pid="$(pgrep -x "$p" 2>/dev/null | awk 'NR==1')"
    [ -n "$pid" ] || continue
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    if grep -qiE '\-k |password|psk|--password' <<< "$cmdline"; then
        bad "$p 命令行疑似含密钥"
        leak=1
    fi
done
[ "$leak" = "0" ] && ok "各服务命令行无密钥泄漏"

h1 "systemd 沙箱"
for unit in xray.service hysteria-server.service shadowsocks-rust-server.service; do
    [ "$(systemctl show -p LoadState --value "$unit" 2>/dev/null)" = "loaded" ] || continue
    protect_sys="$(systemctl show -p ProtectSystem --value "$unit" 2>/dev/null || true)"
    no_new_priv="$(systemctl show -p NoNewPrivileges --value "$unit" 2>/dev/null || true)"
    if [ "$protect_sys" = "strict" ]; then
        ok "$unit ProtectSystem=strict"
    else
        warn "$unit 未启用 ProtectSystem=strict（当前: ${protect_sys:-无}）"
    fi
    if [ "$no_new_priv" = "yes" ]; then
        ok "$unit NoNewPrivileges=yes"
    else
        warn "$unit 未启用 NoNewPrivileges（当前: ${no_new_priv:-无}）"
    fi
    cap="$(systemctl show -p CapabilityBoundingSet --value "$unit" 2>/dev/null || true)"
    info "  ${unit} CapabilityBoundingSet=${cap:-空}"
done

h1 "端口与防火墙"
info "对外监听端口:"
listening_ports | sed 's/^/    /'
ufw_out="$(ufw status 2>/dev/null || true)"
if grep -q "Status: active" <<< "$ufw_out"; then
    ok "UFW active（default deny incoming）"
    local_ports="$(listening_ports)"
    while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        if ufw_has_rule "$spec"; then
            ok "端口 ${spec} 有 UFW 放行规则"
        else
            warn "端口 ${spec} 无对应 UFW 规则（如非故意开放请检查）"
        fi
    done <<< "$local_ports"
else
    bad "UFW 未启用"
fi

h1 "TLS 与安全头"
if [ -n "$DOMAIN" ]; then
    for v in tls1 tls1_1; do
        tls_out="$( (sleep 2; echo) | timeout 8 openssl s_client -connect "$DOMAIN:443" -"$v" 2>/dev/null || true)"
        if grep -q "Protocol  :" <<< "$tls_out"; then
            bad "TLS ${v} 仍可用（应拒绝）"
        else
            ok "TLS ${v} 已拒绝"
        fi
    done
    for v in tls1_2 tls1_3; do
        tls_out="$( (sleep 2; echo) | timeout 8 openssl s_client -connect "$DOMAIN:443" -"$v" 2>/dev/null || true)"
        if grep -q "Protocol  :" <<< "$tls_out"; then
            ok "TLS ${v} 可用"
        else
            warn "TLS ${v} 不可用"
        fi
    done
    info "安全头:"
    curl -sSI "https://$DOMAIN/" 2>/dev/null \
        | grep -iE "^(server|strict-transport|content-type-options|x-frame-options|x-content-type-options)" \
        | sed 's/^/    /'
else
    warn "未检测到域名，跳过 TLS 检查"
fi

h1 "订阅路径"
prefix="$(cat "$STATE_DIR/exposure/edge/subscription_path_prefix.txt" 2>/dev/null || true)"
if [ -n "$DOMAIN" ] && [ -n "$prefix" ]; then
    shown="/s/....${prefix: -4}"
    info "订阅前缀: ${shown}（已脱敏）"
    code="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOMAIN/sub" 2>/dev/null || echo 000)"
    if [ "$code" = "404" ]; then
        ok "直连 /sub 返回 404（直连路径默认关闭）"
    else
        warn "直连 /sub 返回 ${code}（预期 404）"
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' "https://$DOMAIN${prefix}/sub" 2>/dev/null || echo 000)"
    if [ "$code" = "200" ]; then
        ok "随机路径 /sub 返回 200"
    else
        bad "随机路径 /sub 返回 ${code}（预期 200）"
    fi
else
    warn "未配置域名/订阅前缀，跳过订阅检查"
fi

h1 "SSH 加固"
pa="$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')"
pr="$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')"
if [ "$pa" = "no" ]; then
    ok "PasswordAuthentication no"
else
    warn "PasswordAuthentication=${pa:-?}（仍允许密码登录）"
fi
if [ "$pr" = "prohibit-password" ]; then
    ok "PermitRootLogin prohibit-password"
else
    warn "PermitRootLogin=${pr:-?}"
fi

h1 "fail2ban"
if svc_active fail2ban.service; then
    banned="$(fail2ban-client status sshd 2>/dev/null | sed -n 's/.*Currently banned:[[:space:]]*\([0-9]*\).*/\1/p')"
    info "fail2ban sshd jail: 当前封禁 ${banned:-0}"
    ok "fail2ban active"
else
    bad "fail2ban 未运行"
fi

h1 "cron 与 journald"
cron_out="$(crontab -l 2>/dev/null || true)"
if grep -q "EASYNET_MANAGED_RESTART" <<< "$cron_out"; then
    ok "每日服务重启 cron 存在"
else
    warn "无每日重启 cron"
fi
if grep -q "EASYNET_MANAGED_MONITOR" <<< "$cron_out"; then
    ok "监控 cron 存在"
else
    warn "无监控 cron（未配置推送渠道时属正常）"
fi
if grep -qE '^SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
    ok "journald 上限: $(grep -E '^SystemMaxUse=' /etc/systemd/journald.conf | sed 's/^SystemMaxUse=//')"
else
    warn "journald 未设置上限"
fi

h1 "Reality 自偷"
if [ -f /usr/local/etc/xray/config.json ]; then
    dest="$(jq -r '.inbounds[0].streamSettings.realitySettings.dest // empty' /usr/local/etc/xray/config.json 2>/dev/null || true)"
    sni="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' /usr/local/etc/xray/config.json 2>/dev/null || true)"
    flow="$(jq -r '.inbounds[0].settings.clients[0].flow // empty' /usr/local/etc/xray/config.json 2>/dev/null || true)"
    info "dest=${dest:-?}  SNI=${sni:-?}  flow=${flow:-?}"
    if [ "$dest" = "127.0.0.1:443" ] && [ "$sni" = "$DOMAIN" ]; then
        ok "自偷模式（SNI→DNS 与内容自洽）"
    else
        warn "非自偷模式或 SNI 与域名不一致"
    fi
else
    warn "未部署 Xray"
fi

h1 "端口跳跃"
if [ -f /etc/hysteria/config.yaml ]; then
    listen="$(grep -E '^listen:' /etc/hysteria/config.yaml 2>/dev/null | sed 's/^listen:[[:space:]]*//')"
    info "hysteria listen: ${listen:-?}"
    if [ "${listen:-}" != "${listen/,/}" ]; then
        nft_out="$(nft list ruleset 2>/dev/null || true)"
        if grep -q "redirect to" <<< "$nft_out"; then
            ok "端口跳跃 redirect 规则已安装"
        else
            bad "端口跳跃配置了范围但未找到 nftables redirect"
        fi
    fi
    if grep -qE '^obfs:' /etc/hysteria/config.yaml 2>/dev/null && grep -q 'salamander' /etc/hysteria/config.yaml 2>/dev/null; then
        ok "salamander 混淆已启用"
    else
        warn "未启用 salamander 混淆"
    fi
else
    warn "未部署 Hysteria2"
fi

h1 "证书到期"
if [ -n "$DOMAIN" ]; then
    cert="${EASYNET_EDGE_CERT_FILE:-/etc/ssl/easynet-edge/fullchain.crt}"
    if [ -f "$cert" ]; then
        enddate="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
        info "证书到期: ${enddate:-?}"
        if openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null 2>&1; then
            ok "证书 7 天内不会过期"
        else
            bad "证书将在 7 天内过期"
        fi
    else
        warn "未找到 Edge 证书: $cert"
    fi
fi

h1 "总结"
printf '  \033[32m通过 %d\033[0m  \033[33m警告 %d\033[0m  \033[31m失败 %d\033[0m\n' "$PASS" "$WARN" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '  结论: \033[31m存在失败项\033[0m\n'
    exit 1
fi
printf '  结论: \033[32m体检通过\033[0m\n'
exit 0
