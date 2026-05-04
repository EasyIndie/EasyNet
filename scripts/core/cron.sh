#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/metadata.sh"

cron_metadata_services() {
    local metadata_file

    while IFS= read -r metadata_file; do
        [ -z "$metadata_file" ] && continue
        if ! metadata_validate_file "$metadata_file"; then
            continue
        fi
        jq -r '.systemd.services[]? // empty' "$metadata_file"
    done < <(metadata_list_files)
}

cron_restart_services() {
    cron_metadata_services | awk 'NF && !seen[$0]++'
}

cron_restart_command() {
    local services
    services=$(cron_restart_services | xargs)
    if [ -z "$services" ]; then
        return 1
    fi
    printf '/usr/bin/systemctl restart %s 2>/dev/null\n' "$services"
}

cron_install_restart_job() {
    local command
    command=$(cron_restart_command) || return 0
    (crontab -l 2>/dev/null | grep -v "EASYNET_MANAGED_RESTART"; echo "0 4 * * * $command # EASYNET_MANAGED_RESTART") | crontab -
}
