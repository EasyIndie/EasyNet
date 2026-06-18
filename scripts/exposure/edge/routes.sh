#!/bin/bash

EASYNET_EDGE_ROUTES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_EDGE_ROUTES_DIR/../../core/env.sh"
source "$EASYNET_EDGE_ROUTES_DIR/../../core/discovery.sh"

edge_protocol_public_domain() {
    echo "${EASYNET_DOMAIN:-${EASYNET_SUBSCRIPTION_DOMAIN:-}}"
}

edge_route_state_dir() {
    echo "${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
}

edge_routes_dir() {
    echo "$(edge_route_state_dir)/routes"
}

# ------------------------------------------------------------------
# Generate a secure random route path (32 hex chars, prefixed with /)
# ------------------------------------------------------------------
generate_route_path() {
    echo "/$(openssl rand -hex 16)"
}

# ============================================================
# Generic Edge Backend Route (for any EDGE_MODE=backend protocol)
# Uses the protocol's manifest.sh MODULE_NGINX_ROUTE_TEMPLATE,
# falling back to a plain HTTP reverse-proxy template.
# ============================================================
# Helper: convert to uppercase and replace hyphens with underscores (Bash 3 compatible)
_upper() {
    echo "$1" | tr '[:lower:]-' '[:upper:]_'
}

ensure_edge_backend_route() {
    local module="$1"
    local edge_state_dir edge_routes_dir route_path

    if ! discovery_load_manifest "$module" 2>/dev/null; then
        log_error "Cannot set up edge route: unknown module '$module'"
        return 1
    fi

    # Use MODULE_ENV_PREFIX from manifest if defined (for backward compat),
    # otherwise derive from module name (replace hyphens with underscores)
    local env_prefix="${MODULE_ENV_PREFIX:-$(_upper "$module")}"
    edge_state_dir="$(edge_route_state_dir)"
    edge_routes_dir="$(edge_routes_dir)"
    mkdir -p "$edge_routes_dir"

    # Generate or retrieve route path (persisted for idempotency)
    local path_var_name path_file
    path_var_name="EASYNET_${env_prefix}_WS_PATH"
    path_file="$edge_state_dir/${module}_path.txt"
    if [ -n "${!path_var_name:-}" ]; then
        route_path="${!path_var_name}"
    elif [ -f "$path_file" ]; then
        route_path=$(cat "$path_file")
    else
        route_path="/$(openssl rand -hex 16)"
        echo "$route_path" > "$path_file"
    fi

    # Export env vars for the backend protocol to consume
    export "EASYNET_${env_prefix}_PORT=${MODULE_DEFAULT_PORT:-4444}"
    export "EASYNET_${env_prefix}_LISTEN=127.0.0.1"
    export "EASYNET_${env_prefix}_PUBLIC_PORT=${MODULE_DEFAULT_PUBLIC_PORT:-443}"
    export "EASYNET_${env_prefix}_WS_PATH=$route_path"
    export "EASYNET_${env_prefix}_CERT_DIR=${EASYNET_EDGE_CERT_DIR:-/etc/ssl/easynet-edge}"
    export "EASYNET_${env_prefix}_BACKEND_PORT=${MODULE_DEFAULT_PORT:-4444}"

    local backend_port="${MODULE_DEFAULT_PORT:-4444}"

    # Write nginx config: use template from manifest, or default HTTP pass-through
    if [ -n "${MODULE_NGINX_ROUTE_TEMPLATE:-}" ]; then
        # Interpolate template variables using eval heredoc
        eval "cat > \"$edge_routes_dir/${module}.conf\" <<ROUTEEOF
${MODULE_NGINX_ROUTE_TEMPLATE}
ROUTEEOF"
    else
        # Default HTTP reverse-proxy template
        cat > "$edge_routes_dir/${module}.conf" <<EOF
location ${route_path} {
    access_log off;
    proxy_redirect off;
    proxy_pass http://127.0.0.1:${backend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}
EOF
    fi
}
