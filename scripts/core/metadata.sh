#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/env.sh"

metadata_require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "jq is required for metadata operations" >&2
        return 1
    fi
}

metadata_write() {
    local module_name="$1"
    local metadata_json="$2"
    local metadata_path
    metadata_require_jq
    metadata_path="$(easynet_module_metadata_path "$module_name")"
    mkdir -p "$(dirname "$metadata_path")"
    echo "$metadata_json" | jq . > "$metadata_path"
    chmod 600 "$metadata_path"
}

metadata_validate_file() {
    local metadata_path="$1"
    metadata_require_jq

    jq -e '
        type == "object" and
        (.schemaVersion | type == "number") and
        (.["module"] | type == "string" and length > 0) and
        (.enabled | type == "boolean") and
        (.protocol | type == "string" and length > 0) and
        (.client.uri | type == "string" and length > 0) and
        (.client.clash | type == "object")
    ' "$metadata_path" >/dev/null
}

metadata_list_files() {
    local metadata_root
    metadata_root="$(easynet_metadata_dir)"
    if [ ! -d "$metadata_root" ]; then
        return 0
    fi
    find "$metadata_root" -mindepth 2 -maxdepth 2 -name metadata.json -type f | sort
}
