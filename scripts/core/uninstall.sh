#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/metadata.sh"
source "$SCRIPT_DIR/firewall.sh"
source "$SCRIPT_DIR/cron.sh"

uninstall_keep_config() {
    [ "${EASYNET_UNINSTALL_KEEP_CONFIG:-false}" = "true" ]
}

uninstall_purge_packages() {
    [ "${EASYNET_UNINSTALL_PURGE_PACKAGES:-false}" = "true" ]
}

uninstall_safe_path() {
    local path="$1"
    [ -n "$path" ] && [ "$path" != "/" ] && [ "$path" != "/etc" ] && [ "$path" != "/usr" ] && [ "$path" != "/var" ]
}

uninstall_remove_path() {
    local path="$1"
    local label="${2:-$1}"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    if uninstall_keep_config; then
        log_info "保留 $label: $path"
        return 0
    fi

    if ! uninstall_safe_path "$path"; then
        log_warn "跳过不安全路径: $path"
        return 0
    fi

    rm -rf -- "$path"
    log_info "已删除 $label: $path"
}

uninstall_remove_file() {
    local path="$1"
    local label="${2:-$1}"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    if uninstall_keep_config; then
        log_info "保留 $label: $path"
        return 0
    fi

    rm -f -- "$path"
    log_info "已删除 $label: $path"
}

uninstall_rule_is_base() {
    local rule="$1"
    local base_rule
    while IFS= read -r base_rule; do
        [ "$rule" = "$base_rule" ] && return 0
    done < <(firewall_base_rules)
    return 1
}

uninstall_rule_used_by_other_metadata() {
    local rule="$1"
    local excluded_metadata="$2"
    local metadata_file

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        [ "$metadata_file" = "$excluded_metadata" ] && continue
        metadata_validate_file "$metadata_file" || continue
        if jq -e --arg rule "$rule" '.firewall[]? | "\(.port)/\(.proto)" == $rule' "$metadata_file" >/dev/null; then
            return 0
        fi
    done < <(metadata_list_files)

    return 1
}

uninstall_firewall_rules_to_delete() {
    local module="$1"
    local metadata_file rule

    metadata_file="$(easynet_module_metadata_path "$module")"
    [ -f "$metadata_file" ] || return 0
    metadata_validate_file "$metadata_file" || return 0

    while IFS= read -r rule; do
        [ -z "$rule" ] && continue
        uninstall_rule_is_base "$rule" && continue
        uninstall_rule_used_by_other_metadata "$rule" "$metadata_file" && continue
        echo "$rule"
    done < <(jq -r '.firewall[]? | "\(.port)/\(.proto)"' "$metadata_file" | awk 'NF && !seen[$0]++')
}

uninstall_delete_firewall_rules() {
    local module="$1"
    local rule

    if ! command -v ufw &>/dev/null; then
        return 0
    fi

    while IFS= read -r rule; do
        [ -z "$rule" ] && continue
        ufw delete allow "$rule" >/dev/null 2>&1 || true
        log_info "已移除 UFW 规则: $rule"
    done < <(uninstall_firewall_rules_to_delete "$module")
}

uninstall_services_for_module() {
    local module="$1"
    shift || true
    local metadata_file services service

    metadata_file="$(easynet_module_metadata_path "$module")"
    if [ -f "$metadata_file" ] && metadata_validate_file "$metadata_file"; then
        services=$(jq -r '.systemd.services[]? // empty' "$metadata_file" | awk 'NF && !seen[$0]++')
    else
        services=$(printf '%s\n' "$@" | awk 'NF && !seen[$0]++')
    fi

    while IFS= read -r service; do
        [ -z "$service" ] && continue
        systemctl stop "$service" >/dev/null 2>&1 || true
        systemctl disable "$service" >/dev/null 2>&1 || true
        systemctl reset-failed "$service" >/dev/null 2>&1 || true
        log_info "已停止并禁用服务: $service"
    done <<< "$services"
}

uninstall_remove_systemd_unit() {
    local unit="$1"
    uninstall_remove_file "/etc/systemd/system/$unit" "systemd unit"
}

uninstall_remove_module_metadata() {
    local module="$1"
    local metadata_file metadata_dir

    metadata_file="$(easynet_module_metadata_path "$module")"
    metadata_dir="$(dirname "$metadata_file")"
    uninstall_remove_path "$metadata_dir" "$module metadata"
}

uninstall_refresh_runtime_state() {
    systemctl daemon-reload >/dev/null 2>&1 || true
    cron_install_restart_job
}

uninstall_apt_purge() {
    if ! uninstall_purge_packages; then
        return 0
    fi

    if ! command -v apt &>/dev/null; then
        return 0
    fi

    apt purge -y "$@"
    apt autoremove -y
}
