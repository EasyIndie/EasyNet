#!/bin/bash

EASYNET_SUBSCRIPTION_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_SUBSCRIPTION_CORE_DIR/env.sh"
source "$EASYNET_SUBSCRIPTION_CORE_DIR/metadata.sh"

easynet_subscription_domain() {
    if [ -n "$EASYNET_SUBSCRIPTION_DOMAIN" ]; then
        echo "$EASYNET_SUBSCRIPTION_DOMAIN"
        return
    fi

    local subscription_domain_file
    subscription_domain_file="$(easynet_edge_state_dir)/domain.txt"
    if [ -f "$subscription_domain_file" ]; then
        cat "$subscription_domain_file"
        return
    fi

    return 1
}

easynet_subscription_scheme() {
    if [ -n "$EASYNET_SUBSCRIPTION_SCHEME" ]; then
        echo "$EASYNET_SUBSCRIPTION_SCHEME"
        return
    fi

    local subscription_scheme_file
    subscription_scheme_file="$(easynet_edge_state_dir)/scheme.txt"
    if [ -f "$subscription_scheme_file" ]; then
        cat "$subscription_scheme_file"
        return
    fi

    echo "https"
}

easynet_subscription_port() {
    if [ -n "$EASYNET_SUBSCRIPTION_URL_PORT" ]; then
        echo "$EASYNET_SUBSCRIPTION_URL_PORT"
        return
    fi

    local subscription_port_file
    subscription_port_file="$(easynet_edge_state_dir)/port.txt"
    if [ -f "$subscription_port_file" ]; then
        cat "$subscription_port_file"
        return
    fi

    return 0
}

easynet_subscription_origin() {
    local domain="$1"
    local scheme="$2"
    local port="$3"

    if [ -n "$port" ] && { [ "$scheme" != "https" ] || [ "$port" != "443" ]; } && { [ "$scheme" != "http" ] || [ "$port" != "80" ]; }; then
        echo "${scheme}://${domain}:${port}"
    else
        echo "${scheme}://${domain}"
    fi
}

easynet_normalize_path_prefix() {
    local path_prefix="$1"
    [ -z "$path_prefix" ] && return 0
    path_prefix="/${path_prefix#/}"
    path_prefix="${path_prefix%/}"
    echo "$path_prefix"
}

easynet_subscription_path_prefix() {
    if [ -n "$EASYNET_SUBSCRIPTION_PATH_PREFIX" ]; then
        easynet_normalize_path_prefix "$EASYNET_SUBSCRIPTION_PATH_PREFIX"
        return
    fi

    local path_file
    path_file="$(easynet_edge_state_dir)/subscription_path_prefix.txt"
    if [ -f "$path_file" ]; then
        easynet_normalize_path_prefix "$(cat "$path_file")"
        return
    fi
}

easynet_subscription_endpoint() {
    local endpoint="$1"
    local path_prefix
    path_prefix="$(easynet_subscription_path_prefix)"

    if [ -n "$path_prefix" ]; then
        echo "${path_prefix}/${endpoint#/}"
    else
        echo "/${endpoint#/}"
    fi
}

easynet_subscription_endpoint_specs() {
    cat <<'EOF'
sub|sub|text/plain
clash|clash|application/x-yaml
singbox|singbox|application/json
EOF
}

easynet_write_subscription_routes() {
    local route_file="$1"
    local web_root="$2"
    local current_prefix="$3"
    local previous_prefix="${4:-}"
    local prefix endpoint file_name content_type

    > "$route_file"
    for prefix in "$current_prefix" "$previous_prefix"; do
        [ -z "$prefix" ] && continue
        while IFS='|' read -r endpoint file_name content_type; do
            [ -z "$endpoint" ] && continue
            cat >> "$route_file" <<EOF
location = ${prefix}/${endpoint} {
    alias ${web_root}/${file_name};
    default_type ${content_type};
}

EOF
        done < <(easynet_subscription_endpoint_specs)
    done
}

easynet_subscription_url() {
    local endpoint="$1"
    local domain scheme port origin
    domain="$(easynet_subscription_domain)"
    [ -z "$domain" ] && return 1

    scheme="$(easynet_subscription_scheme)"
    port="$(easynet_subscription_port)"
    origin="$(easynet_subscription_origin "$domain" "$scheme" "$port")"
    echo "${origin}$(easynet_subscription_endpoint "$endpoint")"
}
