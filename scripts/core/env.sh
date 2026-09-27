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

# Tighten the state tree to root-only.
#
# The edge state dir holds `subscription_path_prefix.txt` (and the generated
# nginx routes that embed it): that random path is the ONLY secret protecting
# every node credential, so it must not be world-readable. metadata.json is
# already written 600 by metadata.sh; this covers the rest of the tree.
# Nothing that runs unprivileged needs to read /var/lib/easynet.
easynet_secure_state_dir() {
    local dir sub file
    dir="$(easynet_state_dir)"
    [ -d "$dir" ] || return 0

    chmod 700 "$dir" 2>/dev/null || true
    for sub in modules exposure exposure/edge exposure/edge/routes edge; do
        [ -d "$dir/$sub" ] && chmod 700 "$dir/$sub" 2>/dev/null
    done

    file="$dir/exposure/edge/subscription_path_prefix.txt"
    [ -f "$file" ] && chmod 600 "$file" 2>/dev/null
    for file in "$dir"/exposure/edge/routes/*.conf; do
        [ -f "$file" ] && chmod 600 "$file" 2>/dev/null
    done
    return 0
}

easynet_edge_state_dir() {
    easynet_exposure_state_dir "edge"
}
