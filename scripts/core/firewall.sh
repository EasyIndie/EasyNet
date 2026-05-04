#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/metadata.sh"

firewall_base_rules() {
    printf '%s\n' "22/tcp" "80/tcp" "443/tcp"
}

firewall_metadata_rules() {
    local metadata_file

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            continue
        fi
        jq -r '.firewall[]? | "\(.port)/\(.proto)"' "$metadata_file"
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
        ufw allow "$rule"
    done < <(firewall_all_rules)

    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi

    if [[ -f /etc/default/ufw ]]; then
        sed -i 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/g' /etc/default/ufw
        ufw reload &>/dev/null || true
    fi
}
