#!/bin/bash
# EasyNet Clash/Mihomo Subscription Module
# Generates Clash YAML proxies and config from EasyNet metadata.
# Source this file, then call:
#   append_metadata_clash_proxy <metadata.json> <output_proxies.yaml>
#   generate_clash_config <output.yaml> <proxies.yaml> <names.txt>

# Logging guard (may already be defined by the caller)
if ! declare -F log_warn >/dev/null 2>&1; then
    log_warn() { echo "[WARN] $1"; }
fi

# Escape special YAML characters (backslash and double-quote)
yaml_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

# Generate a YAML proxy name list from a names file
generate_proxy_list() {
    local names_file="$1"
    local indent="$2"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        printf '%s- "%s"\n' "$indent" "$(yaml_escape "$name")"
    done < "$names_file"
}

# ============================================================
# Clash config generation
# ============================================================

generate_clash_config() {
    local output_file="$1"
    local proxies_file="$2"
    local names_file="$3"

    [ ! -s "$names_file" ] && return 0

    cat > "$output_file" <<'HEADER'
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true

proxies:
HEADER

    # shellcheck disable=SC2129  # grouping is less clear for heredoc sections
    cat "$proxies_file" >> "$output_file"

    cat >> "$output_file" <<'GROUPS'
proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "Auto"
      - "DIRECT"
GROUPS

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<'AUTO'
  - name: "Auto"
    type: url-test
    url: "https://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    proxies:
AUTO

    generate_proxy_list "$names_file" "      " >> "$output_file"

    cat >> "$output_file" <<'RULES'

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
RULES

    chmod 644 "$output_file"
}

# ============================================================
# Clash proxy render — delegates to per-module render scripts
# ============================================================

append_metadata_clash_proxy() {
    local metadata_file="$1"
    local output_file="$2"
    local module render_script

    module=$(jq -r '.module // empty' "$metadata_file")
    [ -z "$module" ] && return 1

    render_script=$(discovery_module_render_script "$module" "clash") || {
        log_warn "没有 Clash 渲染脚本: $module ($metadata_file)"
        return 1
    }

    bash "$render_script" "$metadata_file" >> "$output_file"
}
