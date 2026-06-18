#!/bin/bash

EASYNET_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_CORE_DIR/metadata.sh"
source "$EASYNET_CORE_DIR/logging.sh"

# Auto-detect the SSH port(s) the system is actually listening on,
# so that ufw --force enable never locks us out.
firewall_detect_ssh_ports() {
    local ports=()
    local line port

    # Try ss first (modern), fall back to netstat or lsof
    if command -v ss &>/dev/null; then
        while IFS= read -r line; do
            port="${line##*:}"
            port="${port%%[!0-9]*}"
            [[ -n "$port" && "$port" =~ ^[0-9]+$ ]] && ports+=("$port")
        done < <(ss -tnlp 2>/dev/null | grep -i sshd)
    elif command -v netstat &>/dev/null; then
        while IFS= read -r line; do
            port="${line##*:}"
            port="${port%%[!0-9]*}"
            [[ -n "$port" && "$port" =~ ^[0-9]+$ ]] && ports+=("$port")
        done < <(netstat -tnlp 2>/dev/null | grep -i sshd)
    fi

    # Deduplicate and output
    printf '%s\n' "${ports[@]}" | awk 'NF && !seen[$0]++'
}

firewall_base_rules() {
    local port

    # Always include well-known service ports
    printf '%s\n' "22/tcp" "80/tcp" "443/tcp"

    # Dynamically include any non-standard SSH ports in use
    while IFS= read -r port; do
        [ -z "$port" ] && continue
        # 22/tcp is already in the static list above; skip to avoid noise
        [ "$port" = "22" ] && continue
        printf '%s/tcp\n' "$port"
        log_info "已自动检测 SSH 非标准端口 $port/tcp 并加入防火墙白名单"
    done < <(firewall_detect_ssh_ports)
}

firewall_metadata_rules() {
    local metadata_file rule

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            continue
        fi
        # For string port ranges (e.g. "20000-30000"), convert hyphen to colon
        # for UFW compatibility; integer ports pass through unchanged.
        while IFS= read -r rule; do
            [ -z "$rule" ] && continue
            rule="${rule/-/:}"
            echo "$rule"
        done < <(jq -r '.firewall[]? | "\(.port)/\(.proto)"' "$metadata_file")
    done < <(metadata_list_files)
}

firewall_all_rules() {
    {
        firewall_base_rules
        firewall_metadata_rules
    } | awk 'NF && !seen[$0]++'
}

firewall_apply_rules() {
    if ! command -v ufw &>/dev/null; then
        return 0
    fi

    local rule
    while IFS= read -r rule; do
        [ -z "$rule" ] && continue

        # Try short-form first (e.g. "443/udp", "20000:30000/udp");
        # fall back to long-form for port ranges on UFW versions that reject the compact syntax.
        if ! ufw allow "$rule" 2>/dev/null; then
            # Check if this is a port range — the short form failed, try long-form
            if [[ "$rule" =~ ^([0-9]+:[0-9]+)/(tcp|udp)$ ]]; then
                local port_range="${BASH_REMATCH[1]}"
                local proto="${BASH_REMATCH[2]}"
                if ufw allow proto "$proto" to any port "$port_range" 2>/dev/null; then
                    continue
                fi
            fi
            log_warn "无法添加 UFW 规则(已跳过): $rule"
        fi
    done < <(firewall_all_rules)

    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi

    if [[ -f /etc/default/ufw ]]; then
        sed -i 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/g' /etc/default/ufw
        ufw reload &>/dev/null || true
    fi
}
