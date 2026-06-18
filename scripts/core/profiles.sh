#!/bin/bash
# EasyNet Profile Definitions
# Moves profile-to-module mapping from hardcoded case statements
# to a data-driven structure. Compatible with Bash 3 (macOS).

EASYNET_PROFILES_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_PROFILES_CORE_DIR/discovery.sh"

# ============================================================
# Profile Definitions
# ============================================================
# Format: variable naming convention profiles_<name>="<module list>"
# Special value "__all__" means all discovered modules.
#
# strict    - Maximum security/anti-DPI (Xray+Reality only)
# balanced  - Strong security + good performance
# compat    - Maximum compatibility (all protocols)

_profile_data_strict="xray-reality"
_profile_data_balanced="xray-reality hysteria2"
_profile_data_compat="__all__"

# ============================================================
# Profile Resolution Functions
# ============================================================

# Internal: look up profile definition by name
_profile_get() {
    local profile_name="$1"
    local var="_profile_data_${profile_name}"
    echo "${!var}"
}

# List all available profile names (one per line)
profile_list_names() {
    # Enumerate variables matching _profile_data_* prefix
    set | grep '^_profile_data_' | sed 's/^_profile_data_//' | sed 's/=.*//' | sort
}

# Check if a profile name exists
profile_exists() {
    local val
    val=$(_profile_get "$1")
    [ -n "$val" ]
}

# Resolve a profile to a list of module names (one per line),
# sorted by MODULE_SECURITY_RANK (lower rank = stronger anti-DPI)
# Returns 0 on success, 1 if profile unknown
profile_resolve() {
    local profile_name="$1"
    local mod rank
    local modules
    modules=$(_profile_get "$profile_name")

    if [ -z "$modules" ]; then
        return 1
    fi

    if [ "$modules" = "__all__" ]; then
        discovery_list_modules_by_security
        return 0
    fi

    # For specific profile lists, sort by security rank
    echo "$modules" | tr ' ' '\n' | while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        rank=$(discovery_get_manifest_value "$mod" "MODULE_SECURITY_RANK") || rank=99
        printf '%d\t%s\n' "$rank" "$mod"
    done | sort -n -k1,1 | cut -f2-
    return 0
}

# Check if a specific module belongs to a profile
profile_module_belongs() {
    local profile_name="$1"
    local module_name="$2"
    local modules
    modules=$(_profile_get "$profile_name")

    [ -z "$modules" ] && return 1
    [ "$modules" = "__all__" ] && return 0

    local m
    set -f
    for m in $modules; do
        [ "$m" = "$module_name" ] && { set +f; return 0; }
    done
    set +f
    return 1
}

# Validate profile name (used for EASYNET_PROFILE env var)
profile_validate() {
    local profile_name="$1"
    if profile_exists "$profile_name"; then
        return 0
    fi
    echo "[ERROR] Unknown profile: $profile_name. Available: $(profile_list_names | tr '\n' ' ')" >&2
    return 1
}
