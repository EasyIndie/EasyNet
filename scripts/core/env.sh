#!/bin/bash

easynet_project_root() {
    local source_dir
    source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
    echo "$source_dir"
}

easynet_state_dir() {
    echo "${EASYNET_STATE_DIR:-/var/lib/easynet}"
}

easynet_metadata_dir() {
    echo "$(easynet_state_dir)/modules"
}

easynet_module_metadata_path() {
    local module_name="$1"
    echo "$(easynet_metadata_dir)/$module_name/metadata.json"
}

easynet_exposure_state_dir() {
    local exposure_name="$1"
    echo "$(easynet_state_dir)/exposure/$exposure_name"
}

easynet_nginx_state_dir() {
    easynet_exposure_state_dir "nginx"
}

easynet_subscription_state_dir() {
    easynet_exposure_state_dir "subscription"
}
