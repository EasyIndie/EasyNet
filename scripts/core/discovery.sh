#!/bin/bash
# EasyNet Protocol Discovery Library
# Auto-discovers protocol modules by scanning protocols/*/manifest.sh
# Part of the architecture decoupling: protocols self-declare,
# orchestrators discover rather than hardcode.

EASYNET_DISCOVERY_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

discovery_protocols_dir() {
    echo "$(cd "$EASYNET_DISCOVERY_CORE_DIR/../protocols" &>/dev/null && pwd)"
}

# List all discovered module names (one per line, sorted alphabetically)
discovery_list_modules() {
    local protocols_dir manifest_path name
    protocols_dir="$(discovery_protocols_dir)"
    if [ ! -d "$protocols_dir" ]; then
        return 0
    fi
    for manifest_path in "$protocols_dir"/*/manifest.sh; do
        [ -f "$manifest_path" ] || continue
        name="$(basename "$(dirname "$manifest_path")")"
        echo "$name"
    done | sort
}

# Check if a module name has a valid manifest
discovery_module_exists() {
    local module_name="$1"
    local protocols_dir
    protocols_dir="$(discovery_protocols_dir)"
    [ -f "$protocols_dir/$module_name/manifest.sh" ]
}

# Source a module's manifest and export its variables into the calling scope
# Returns 0 on success, 1 if manifest not found
discovery_load_manifest() {
    local module_name="$1"
    local manifest_path
    manifest_path="$(discovery_protocols_dir)/$module_name/manifest.sh"
    if [ ! -f "$manifest_path" ]; then
        return 1
    fi
    # Clear previous manifest variables to avoid stale values
    unset MODULE_NAME MODULE_DISPLAY_NAME MODULE_PROTOCOL
    unset MODULE_CLASH_TYPE MODULE_SINGBOX_TYPE MODULE_SECURITY_RANK
    unset MODULE_DEFAULT_PORT MODULE_DEFAULT_PUBLIC_PORT
    unset MODULE_EDGE_MODE MODULE_PROFILES MODULE_NGINX_ROUTE_TEMPLATE
    unset MODULE_SYSTEMD_SERVICES MODULE_FIREWALL_RULES MODULE_ENV_PREFIX
    source "$manifest_path"
}

# Get a specific variable from a module's manifest
discovery_get_manifest_value() {
    local module_name="$1"
    local var_name="$2"
    local value
    if ! discovery_load_manifest "$module_name"; then
        return 1
    fi
    eval "value=\"\${$var_name:-}\""
    echo "$value"
}

# Validate that a loaded manifest has all required fields
discovery_validate_manifest() {
    local required_vars=(
        MODULE_NAME MODULE_DISPLAY_NAME MODULE_CLASH_TYPE
        MODULE_SINGBOX_TYPE MODULE_SECURITY_RANK MODULE_EDGE_MODE
    )
    local var
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "[ERROR] Manifest for '${MODULE_NAME:-unknown}' missing required: $var" >&2
            return 1
        fi
    done
    # Validate MODULE_NAME matches directory (sanity check)
    if [ -n "${MODULE_NAME:-}" ] && [ "${MODULE_NAME##*/}" != "$MODULE_NAME" ]; then
        echo "[ERROR] Manifest MODULE_NAME contains path separators: $MODULE_NAME" >&2
        return 1
    fi
    # Validate EDGE_MODE
    case "${MODULE_EDGE_MODE:-}" in
        none|backend|shared_tls) ;;
        *)
            echo "[ERROR] Manifest for '$MODULE_NAME' has invalid MODULE_EDGE_MODE='$MODULE_EDGE_MODE'" >&2
            return 1
            ;;
    esac
    return 0
}

# Check if a module has optional per-protocol render scripts
discovery_has_render_script() {
    local module_name="$1"
    local render_type="$2"  # "clash" or "singbox"
    local protocols_dir
    protocols_dir="$(discovery_protocols_dir)"
    [ -x "$protocols_dir/$module_name/render_${render_type}.sh" ]
}

# Get the deploy entrypoint for a module
discovery_module_entrypoint() {
    local module_name="$1"
    local deploy_path="$(discovery_protocols_dir)/$module_name/deploy.sh"
    if [ -x "$deploy_path" ]; then
        echo "$deploy_path"
        return 0
    fi
    return 1
}

# Get the uninstall entrypoint for a module
discovery_uninstall_entrypoint() {
    local module_name="$1"
    local uninstall_path="$(discovery_protocols_dir)/$module_name/uninstall.sh"
    if [ -x "$uninstall_path" ]; then
        echo "$uninstall_path"
        return 0
    fi
    return 1
}

# Display module menu (index -> name mapping)
# Returns module name for a given 1-based index
discovery_module_by_index() {
    local index="$1"
    discovery_list_modules | sed -n "${index}p"
}
