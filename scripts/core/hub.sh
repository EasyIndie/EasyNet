#!/bin/bash
# EasyNet operational hub.
#
# Every path EasyNet touches is scattered across the FHS because upstream
# installers and systemd units hard-code them (Xray -> /usr/local/etc/xray,
# Hysteria2 -> /etc/hysteria, AmneziaWG -> /etc/amnezia/amneziawg, nginx ->
# /etc/nginx, state -> /var/lib/easynet, ...). Moving those files would break
# upstream upgrades and re-deploy idempotency, so instead the hub collects
# *symlinks* to all of them under a single directory (~/.easynet) plus a
# generated README index. Operators open one directory and find everything.
#
# The hub is pure convenience: no service reads from it, and deleting it is
# always safe (`easynet hub --refresh` recreates it).

EASYNET_HUB_ENTRIES=()

easynet_hub_dir() {
    printf '%s' "${EASYNET_HUB_DIR:-${HOME:-/root}/.easynet}"
}

easynet_hub_logs_dir() {
    printf '%s/logs' "$(easynet_hub_dir)"
}

# easynet_hub_link <relative-name> <target>
# Creates the symlink only when the target exists, and never clobbers a real
# file or directory that a human put there.
easynet_hub_link() {
    local name="${1:-}" target="${2:-}"
    local link
    link="$(easynet_hub_dir)/${name}"
    [ -n "$name" ] && [ -n "$target" ] || return 0
    [ -e "$target" ] || [ -L "$target" ] || return 0
    mkdir -p "$(dirname "$link")"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        return 0
    fi
    ln -sfn "$target" "$link"
}

# easynet_hub_add <relative-name> <target> <note>
# Registers an index entry and creates the matching symlink.
easynet_hub_add() {
    local name="${1:-}" target="${2:-}" note="${3:-}"
    easynet_hub_link "$name" "$target"
    EASYNET_HUB_ENTRIES+=("${name}|${target}|${note}")
}

# shellcheck disable=SC2016  # markdown backticks in the generated README are literal
easynet_hub_render_index() {
    local hub
    hub="$(easynet_hub_dir)"
    printf '# EasyNet 运维工作目录\n\n'
    printf '本目录是 EasyNet 所有相关路径的**统一索引**（全部为符号链接）。\n'
    printf '真实文件仍保存在系统标准位置（上游安装器与 systemd 单元硬编码），\n'
    printf '此处只做收敛，方便维护人员在一个地方查看与操作。\n\n'
    printf '删除本目录不影响任何服务运行；重建：`easynet hub --refresh`。\n\n'
    printf '统一入口：`%s/easynet <命令>`（或直接用 `easynet`，若已加入 PATH）。\n\n' "$hub"
    printf '| 入口 | 真实路径 | 说明 |\n|---|---|---|\n'
    local entry name target note
    for entry in "${EASYNET_HUB_ENTRIES[@]:-}"; do
        [ -n "$entry" ] || continue
        name="${entry%%|*}"
        target="${entry#*|}"
        note="${target#*|}"
        target="${target%%|*}"
        printf '| `%s` | `%s` | %s%s |\n' "$name" "$target" "$note" \
            "$([ -e "$target" ] || printf ' *(未部署)*')"
    done
    printf '\n## 常用命令\n\n'
    printf '```bash\n'
    printf 'easynet status          # 总览：服务 / 订阅 / 证书 / SSH\n'
    printf 'easynet where           # 本索引（路径总表）\n'
    printf 'easynet path xray       # 打印真实路径，便于 cd "$(easynet path xray)"\n'
    printf 'easynet config hysteria2 # 查看/编辑某个协议的配置\n'
    printf 'easynet logs xray       # 跟踪日志\n'
    printf 'easynet restart xray    # 重启服务\n'
    printf 'easynet sub             # 显示订阅链接与二维码\n'
    printf 'easynet hub --refresh   # 重建本目录索引\n'
    printf '```\n'
}

easynet_hub_write_index() {
    local hub
    hub="$(easynet_hub_dir)"
    mkdir -p "$hub"
    easynet_hub_render_index > "$hub/README.md"
}

# ensure_easynet_hub [--quiet]
# Idempotently (re)builds the hub. Safe to call on every deploy.
ensure_easynet_hub() {
    local quiet="${1:-}"
    local project hub state_dir
    project="$(easynet_project_root)"
    hub="$(easynet_hub_dir)"
    state_dir="$(easynet_state_dir)"

    EASYNET_HUB_ENTRIES=()
    mkdir -p "$hub/logs" "$hub/configs" "$hub/security"

    easynet_hub_add "easynet" "$project/scripts/easynet" "统一运维命令入口"
    easynet_hub_add "project" "$project" "EasyNet 程序目录"
    easynet_hub_add "env" "$project/.env" "部署配置（EASYNET_* 变量）"
    easynet_hub_add "state" "$state_dir" "运行状态：metadata / 订阅 / 路径前缀"
    easynet_hub_add "logs" "$hub/logs" "部署日志（deploy 输出）"

    # Edge Gateway
    easynet_hub_add "certs" "${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}" "Edge TLS 证书与私钥"
    easynet_hub_add "web" "${EASYNET_EDGE_WEB_ROOT:-/var/www/html}" "订阅与规则集静态根目录"
    easynet_hub_add "nginx-site" "/etc/nginx/sites-available/easynet-edge" "Edge 网关 Nginx 站点配置"
    easynet_hub_add "acme" "${EASYNET_ACME_HOME:-$HOME/.acme.sh}" "acme.sh 证书签发状态"

    # Per-protocol configuration (declared by each plugin's manifest)
    local module manifest_dir config_dir display
    manifest_dir="$(discovery_protocols_dir)"
    if [ -d "$manifest_dir" ]; then
        while IFS= read -r module; do
            [ -n "$module" ] || continue
            config_dir="$(discovery_get_manifest_value "$module" MODULE_CONFIG_DIR 2>/dev/null)" || config_dir=""
            [ -n "$config_dir" ] || continue
            display="$(discovery_get_manifest_value "$module" MODULE_DISPLAY_NAME 2>/dev/null)" || display="$module"
            easynet_hub_add "configs/$module" "$config_dir" "${display} 配置目录"
        done < <(discovery_list_modules_by_security 2>/dev/null)
    fi

    # Services / units
    easynet_hub_add "systemd" "/etc/systemd/system" "systemd 单元与 drop-in 加固"

    # Security
    easynet_hub_add "security/harden-ssh" "$project/scripts/security/harden_ssh.sh" "SSH 加固脚本（可选、带回滚）"
    easynet_hub_add "security/sshd-hardening.conf" "${EASYNET_SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}/10-easynet-hardening.conf" "SSH 加固 drop-in（未加固时不存在）"
    easynet_hub_add "security/fail2ban.conf" "/etc/fail2ban/jail.d/easynet.local" "fail2ban jail（自动配置）"

    easynet_hub_write_index

    # Put the CLI on PATH so `easynet` works from anywhere (opt out with
    # EASYNET_HUB_NO_PATH_LINK=1). Only create it, never overwrite a real file.
    if [ "${EASYNET_HUB_NO_PATH_LINK:-}" != "1" ] && [ -d /usr/local/bin ]; then
        local cli="/usr/local/bin/easynet"
        if [ ! -e "$cli" ] || [ -L "$cli" ]; then
            ln -sfn "$project/scripts/easynet" "$cli" 2>/dev/null || true
        fi
    fi

    if [ "$quiet" != "--quiet" ]; then
        if command -v log_info >/dev/null 2>&1; then
            log_info "运维工作目录已就绪: ${hub}（所有路径索引见 ${hub}/README.md）"
        else
            printf '[INFO] 运维工作目录已就绪: %s\n' "$hub"
        fi
    fi
}
