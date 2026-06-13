#!/bin/bash

EASYNET_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_CORE_DIR/env.sh"

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

    # Structural contract validation (fast path — fails early on malformed files)
    jq -e '
        type == "object" and
        (.schemaVersion | type == "number") and
        (.["module"] | type == "string" and length > 0) and
        (.enabled | type == "boolean") and
        (.protocol | type == "string" and length > 0) and
        (.client.uri | type == "string" and length > 0) and
        (.client.clash | type == "object")
    ' "$metadata_path" >/dev/null 2>&1 || {
        echo "[ERROR] Metadata 结构不完整: $metadata_path" >&2
        return 1
    }

    # Semantic validation — port range, URI format, firewall entries
    local module_name port uri invalid_fw
    module_name=$(jq -r '.module // "unknown"' "$metadata_path")
    port=$(jq -r '.port // 0' "$metadata_path")

    # Port must be 1-65535 when present (0 or empty means port was not set)
    if [ -n "$port" ] && [ "$port" -ne 0 ] 2>/dev/null; then
        if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ] 2>/dev/null; then
            echo "[ERROR] metadata '$module_name' 端口无效: $port (须在 1-65535 范围内)" >&2
            return 1
        fi
    fi

    # client.uri must have a valid URI scheme
    uri=$(jq -r '.client.uri // ""' "$metadata_path")
    if [[ ! "$uri" =~ ^[a-zA-Z][a-zA-Z0-9+.-]+:// ]]; then
        echo "[ERROR] metadata '$module_name' 缺少有效的 client URI" >&2
        return 1
    fi

    # Each firewall entry must have valid port and proto
    invalid_fw=$(jq -r '
        .firewall[]? | select(
            (.port | type != "number") or
            .port < 1 or .port > 65535 or
            (.proto != "tcp" and .proto != "udp")
        ) | "\(.port)/\(.proto)"
    ' "$metadata_path")
    if [ -n "$invalid_fw" ]; then
        echo "[ERROR] metadata '$module_name' 包含无效防火墙规则: $(echo "$invalid_fw" | tr '\n' ' ')" >&2
        return 1
    fi

    return 0
}

metadata_list_files() {
    local metadata_root
    metadata_root="$(easynet_metadata_dir)"
    if [ ! -d "$metadata_root" ]; then
        return 0
    fi
    find "$metadata_root" -mindepth 2 -maxdepth 2 -name metadata.json -type f | sort
}
