#!/bin/bash
# EasyNet SSH 加固（可选、独立脚本）
#
# 目标：关闭「root 密码登录」这一根本攻击面，同时用多层保险确保不会把自己关在门外。
#
# 它【不会】被 deploy.sh 调用——只有你显式执行才会改动系统。
#
# 用法：
#   bash scripts/security/harden_ssh.sh check          # 只读体检，给出「是否可安全加固」结论
#   bash scripts/security/harden_ssh.sh apply [--dry-run] [--force]
#   bash scripts/security/harden_ssh.sh confirm        # 10 分钟内验证仍可登录后固化
#   bash scripts/security/harden_ssh.sh revert         # 随时手工回滚
#
# 保险机制（apply 时）：
#   1. 前置校验：至少一把可用公钥，且当前会话是 publickey 认证（否则拒绝，--force 可跳过）
#   2. 写入前备份原有 drop-in
#   3. sshd -t 配置校验，失败立即回滚
#   4. 写入后启动 <delay> 自动回滚定时器；期间执行 confirm 才会保留
#
# 可覆盖的环境变量：
#   EASYNET_SSHD_DROPIN_DIR      drop-in 目录（默认 /etc/ssh/sshd_config.d）
#   EASYNET_SSH_BACKUP_DIR       备份目录（默认 /var/lib/easynet/ssh-backup）
#   EASYNET_SSH_SERVICE          sshd 服务名（默认 ssh）
#   EASYNET_SSH_ROLLBACK_DELAY   自动回滚延迟（默认 10min）
#   EASYNET_SSH_LOOKBACK_DAYS    check 的日志回看天数（默认 30）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_ROOT/scripts/core/logging.sh"

SSHD_DROPIN_DIR="${EASYNET_SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}"
# Must sort before 50-cloud-init.conf: sshd uses the FIRST value it sees and the
# main sshd_config includes this directory at the top.
SSHD_DROPIN_NAME="${EASYNET_SSHD_DROPIN_NAME:-10-easynet-hardening.conf}"
SSHD_DROPIN="${SSHD_DROPIN_DIR}/${SSHD_DROPIN_NAME}"
SSHD_MAIN="${EASYNET_SSHD_CONFIG:-/etc/ssh/sshd_config}"
BACKUP_DIR="${EASYNET_SSH_BACKUP_DIR:-/var/lib/easynet/ssh-backup}"
SSH_SERVICE="${EASYNET_SSH_SERVICE:-ssh}"
ROLLBACK_UNIT="${EASYNET_SSH_ROLLBACK_UNIT:-easynet-ssh-rollback}"
ROLLBACK_DELAY="${EASYNET_SSH_ROLLBACK_DELAY:-10min}"
ROLLBACK_HELPER="${EASYNET_SSH_ROLLBACK_HELPER:-/usr/local/sbin/easynet-ssh-rollback}"
LOOKBACK_DAYS="${EASYNET_SSH_LOOKBACK_DAYS:-30}"

DROPIN_BACKUP="${BACKUP_DIR}/${SSHD_DROPIN_NAME}"
DROPIN_ABSENT_MARKER="${BACKUP_DIR}/${SSHD_DROPIN_NAME}.absent"

die() {
    log_error "$*"
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "请使用 root 运行（或 sudo）。"
}

# ---------- 现状探测 ----------

count_authorized_keys() {
    local user="$1"
    local home
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)" || true
    home="${home:-/root}"
    local file="$home/.ssh/authorized_keys"
    if [ -s "$file" ]; then
        grep -cvE '^[[:space:]]*(#|$)' "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

journal_ssh_auth() {
    journalctl -u "$SSH_SERVICE" --since "${LOOKBACK_DAYS} days ago" --no-pager 2>/dev/null || true
}

# The most recent successful authentication from the current session's client IP.
# Prints "publickey", "password" or "" (unknown).
current_session_method() {
    local ip="${SSH_CLIENT:-}"
    ip="${ip%% *}"
    [ -n "$ip" ] || { printf ''; return 0; }
    journal_ssh_auth | grep -F "from $ip " | grep -E "Accepted " | tail -n1 |
        grep -oE "Accepted (publickey|password)" | awk '{print $2}' || printf ''
}

effective_sshd() {
    if command -v sshd >/dev/null 2>&1 && [ -f "$SSHD_MAIN" ]; then
        sshd -T -f "$SSHD_MAIN" 2>/dev/null || true
    fi
}

cmd_check() {
    local keys current keys_ok=false session_ok=false
    local pk_count pw_count effective verdict

    keys="$(count_authorized_keys root)"
    current="$(current_session_method)"
    effective="$(effective_sshd)"

    pk_count="$(journal_ssh_auth | grep -c 'Accepted publickey' || true)"
    pw_count="$(journal_ssh_auth | grep -c 'Accepted password' || true)"

    echo "========================================"
    echo "  EasyNet SSH 加固体检（只读）"
    echo "========================================"
    echo "root 可用公钥数量 : $keys"
    echo "当前会话认证方式  : ${current:-未知}"
    echo "近 ${LOOKBACK_DAYS} 天登录成功  : publickey=$pk_count  password=$pw_count"
    echo "近 ${LOOKBACK_DAYS} 天爆破失败  : $(journal_ssh_auth | grep -c 'Failed password' || true)"
    echo "--- 当前 sshd 有效配置 ---"
    printf '%s\n' "$effective" |
        grep -iE "^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|maxauthtries|permitemptypasswords)" |
        sed 's/^/  /' || true

    [ "$keys" -ge 1 ] && keys_ok=true
    [ "$current" = "publickey" ] && session_ok=true

    if [ "$keys_ok" = true ] && [ "$session_ok" = true ]; then
        verdict="✅ 可以安全加固（有公钥，且当前就是公钥登录）"
    elif [ "$keys_ok" = true ]; then
        verdict="⚠️  有公钥，但【当前会话不是公钥登录】——先开一个新终端验证公钥能登录，再 apply"
    else
        verdict="❌ 不安全：未发现可用公钥。先安装公钥，否则 apply 会把自己关在门外"
    fi
    echo "----------------------------------------"
    echo "结论: $verdict"
    echo "========================================"
}

# ---------- drop-in 内容 ----------

render_dropin() {
    cat << 'EOF'
# Managed by EasyNet (scripts/security/harden_ssh.sh) - do not edit
#
# Sorts before 50-cloud-init.conf on purpose: sshd uses the FIRST value it sees,
# and /etc/ssh/sshd_config includes this directory before its own body.
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
}

write_rollback_helper() {
    cat > "$ROLLBACK_HELPER" << EOF
#!/bin/bash
# Auto-rollback for EasyNet SSH hardening (armed by harden_ssh.sh apply).
# Restores the previous sshd drop-in unless 'harden_ssh.sh confirm' cancelled it.
set -u
DROPIN="${SSHD_DROPIN}"
BACKUP="${DROPIN_BACKUP}"
if [ -f "\$BACKUP" ]; then
    cp -f "\$BACKUP" "\$DROPIN"
else
    rm -f "\$DROPIN"
fi
systemctl reload "${SSH_SERVICE}" 2>/dev/null || systemctl restart "${SSH_SERVICE}" 2>/dev/null || true
EOF
    chmod 0755 "$ROLLBACK_HELPER"
}

arm_rollback() {
    if ! command -v systemd-run >/dev/null 2>&1; then
        log_warn "未找到 systemd-run，无法启动自动回滚；请立即在另一个终端验证登录。"
        return 0
    fi
    systemctl stop "${ROLLBACK_UNIT}.timer" >/dev/null 2>&1 || true
    systemctl reset-failed "$ROLLBACK_UNIT" >/dev/null 2>&1 || true
    systemd-run --unit="$ROLLBACK_UNIT" --collect --on-active="$ROLLBACK_DELAY" \
        "$ROLLBACK_HELPER" >/dev/null 2>&1 ||
        log_warn "自动回滚定时器启动失败；请立即在另一个终端验证登录。"
}

cmd_apply() {
    local dry_run=false force=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --force) force=true ;;
            *) die "未知参数: $1" ;;
        esac
        shift
    done

    if [ "$dry_run" = true ]; then
        render_dropin
        return 0
    fi

    require_root

    # Idempotent: re-applying when already at the target state must not re-arm
    # the rollback (which would later undo a confirmed hardening) nor overwrite
    # the original pre-hardening backup.
    local rendered
    rendered="$(render_dropin)"
    if [ -f "$SSHD_DROPIN" ] && [ "$rendered" = "$(cat "$SSHD_DROPIN")" ]; then
        log_info "SSH 加固已处于目标状态，无需变更。"
        return 0
    fi

    local keys current
    keys="$(count_authorized_keys root)"
    current="$(current_session_method)"

    if [ "$keys" -lt 1 ]; then
        die "root 未配置任何可用公钥——拒绝加固（会把你自己关在门外）。请先安装公钥。"
    fi
    if [ "$current" != "publickey" ] && [ "$force" != true ]; then
        die "当前会话不是公钥登录，无法确认公钥可用——请先用公钥开一个新终端，或加 --force。"
    fi

    mkdir -p "$BACKUP_DIR" "$SSHD_DROPIN_DIR"

    # Preserve the FIRST backup: a repeated apply must never overwrite the
    # genuine pre-hardening state with an already-hardened file.
    if [ -f "$SSHD_DROPIN" ] && [ ! -f "$DROPIN_BACKUP" ] && [ ! -f "$DROPIN_ABSENT_MARKER" ]; then
        cp -f "$SSHD_DROPIN" "$DROPIN_BACKUP"
    elif [ ! -f "$SSHD_DROPIN" ] && [ ! -f "$DROPIN_BACKUP" ]; then
        : > "$DROPIN_ABSENT_MARKER"
    fi

    render_dropin > "$SSHD_DROPIN"
    chmod 0644 "$SSHD_DROPIN"

    if command -v sshd >/dev/null 2>&1 && ! sshd -t -f "$SSHD_MAIN"; then
        log_error "sshd 配置校验失败，已回滚。"
        if [ -f "$DROPIN_BACKUP" ]; then
            cp -f "$DROPIN_BACKUP" "$SSHD_DROPIN"
        else
            rm -f "$SSHD_DROPIN"
        fi
        exit 1
    fi

    write_rollback_helper
    systemctl reload "$SSH_SERVICE" 2>/dev/null || systemctl restart "$SSH_SERVICE"
    arm_rollback

    echo ""
    log_info "SSH 加固已应用：$SSHD_DROPIN"
    log_warn "请在 ${ROLLBACK_DELAY} 内【另开一个终端】确认仍能登录，然后执行："
    echo "    bash scripts/security/harden_ssh.sh confirm"
    log_warn "若一直不执行 confirm，系统会在 ${ROLLBACK_DELAY} 后自动回滚（不会锁死）。"
}

cmd_confirm() {
    require_root
    systemctl stop "${ROLLBACK_UNIT}.timer" >/dev/null 2>&1 || true
    systemctl reset-failed "$ROLLBACK_UNIT" >/dev/null 2>&1 || true
    log_info "已取消自动回滚；SSH 加固永久生效。"
    log_info "如需回滚: bash scripts/security/harden_ssh.sh revert"
}

cmd_revert() {
    require_root
    systemctl stop "${ROLLBACK_UNIT}.timer" >/dev/null 2>&1 || true
    systemctl reset-failed "$ROLLBACK_UNIT" >/dev/null 2>&1 || true

    if [ -f "$DROPIN_BACKUP" ]; then
        cp -f "$DROPIN_BACKUP" "$SSHD_DROPIN"
        log_info "已恢复备份的 drop-in: $SSHD_DROPIN"
    else
        rm -f "$SSHD_DROPIN"
        log_info "已移除 EasyNet 的 drop-in（恢复到 cloud-init 默认）。"
    fi

    if command -v sshd >/dev/null 2>&1 && ! sshd -t -f "$SSHD_MAIN"; then
        die "回滚后 sshd 配置校验失败，请手工检查 ${SSHD_MAIN}。"
    fi
    systemctl reload "$SSH_SERVICE" 2>/dev/null || systemctl restart "$SSH_SERVICE"
    # The saved state has been consumed: allow a later apply to snapshot afresh.
    rm -f "$DROPIN_BACKUP" "$DROPIN_ABSENT_MARKER"
    log_info "SSH 配置已回滚并重载。"
}

cmd_status() {
    if [ -f "$SSHD_DROPIN" ]; then
        echo "状态: 已应用（${SSHD_DROPIN}）"
        if systemctl is-active --quiet "${ROLLBACK_UNIT}.timer"; then
            echo "回滚定时器: 运行中 —— 执行 confirm 以保留加固"
        else
            echo "回滚定时器: 未运行（已 confirm 或未应用）"
        fi
    else
        echo "状态: 未应用"
    fi
}

usage() {
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        check) cmd_check ;;
        apply) cmd_apply "$@" ;;
        confirm) cmd_confirm ;;
        revert) cmd_revert ;;
        status) cmd_status ;;
        help | -h | --help) usage ;;
        *) die "未知命令: ${cmd}（可用: check|apply|confirm|revert|status）" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
