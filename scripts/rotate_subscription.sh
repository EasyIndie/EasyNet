#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/scripts/core/logging.sh"
source "$PROJECT_ROOT/scripts/core/subscription.sh"

EDGE_STATE_DIR="${EASYNET_EDGE_STATE_DIR:-$(easynet_edge_state_dir)}"
EDGE_ROUTES_DIR="$EDGE_STATE_DIR/routes"
WEB_ROOT="${EASYNET_WEB_ROOT:-/var/www/html}"
PATH_FILE="$EDGE_STATE_DIR/subscription_path_prefix.txt"
PREVIOUS_PATH_FILE="$EDGE_STATE_DIR/subscription_path_prefix.previous.txt"
ROUTE_FILE="$EDGE_ROUTES_DIR/subscription.conf"
KEEP_PREVIOUS="${EASYNET_SUBSCRIPTION_ROTATION_GRACE:-false}"

usage() {
    cat <<EOF
Usage: $0 [--grace]

Options:
  --grace   Keep the previous subscription links active during migration.
EOF
}

normalize_path_prefix() {
    local path_prefix="$1"
    path_prefix="/${path_prefix#/}"
    path_prefix="${path_prefix%/}"
    echo "$path_prefix"
}

new_random_prefix() {
    echo "/s/$(openssl rand -hex 16)"
}

write_subscription_routes() {
    local current_prefix="$1"
    local previous_prefix="${2:-}"

    mkdir -p "$EDGE_ROUTES_DIR"
    cat > "$ROUTE_FILE" <<EOF
location = ${current_prefix}/sub {
    alias ${WEB_ROOT}/sub;
    default_type text/plain;
}

location = ${current_prefix}/clash {
    alias ${WEB_ROOT}/clash;
    default_type application/x-yaml;
}
EOF

    if [ -n "$previous_prefix" ]; then
        cat >> "$ROUTE_FILE" <<EOF

location = ${previous_prefix}/sub {
    alias ${WEB_ROOT}/sub;
    default_type text/plain;
}

location = ${previous_prefix}/clash {
    alias ${WEB_ROOT}/clash;
    default_type application/x-yaml;
}
EOF
    fi
}

reload_nginx() {
    if [ "${EASYNET_SKIP_NGINX_RELOAD:-false}" = "true" ]; then
        return 0
    fi

    if command -v nginx &>/dev/null; then
        nginx -t
    fi

    if command -v systemctl &>/dev/null; then
        systemctl reload nginx || systemctl restart nginx
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --grace)
                KEEP_PREVIOUS="true"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    local old_prefix new_prefix previous_route_prefix=""

    parse_args "$@"

    if [ ! -f "$PATH_FILE" ]; then
        log_error "未找到 Edge 订阅路径状态: $PATH_FILE"
        log_error "请先部署 Edge Gateway，或运行 ./scripts/deploy.sh 完成部署。"
        exit 1
    fi

    old_prefix="$(normalize_path_prefix "$(cat "$PATH_FILE")")"
    new_prefix="$(new_random_prefix)"
    while [ "$new_prefix" = "$old_prefix" ]; do
        new_prefix="$(new_random_prefix)"
    done

    mkdir -p "$EDGE_STATE_DIR" "$EDGE_ROUTES_DIR"
    echo "$old_prefix" > "$PREVIOUS_PATH_FILE"
    echo "$new_prefix" > "$PATH_FILE"

    if [ "$KEEP_PREVIOUS" = "true" ]; then
        previous_route_prefix="$old_prefix"
        log_warn "已启用迁移宽限：旧订阅链接仍会暂时可用。再次不带 --grace 轮换即可移除旧入口。"
    fi

    write_subscription_routes "$new_prefix" "$previous_route_prefix"
    bash "$PROJECT_ROOT/scripts/generate_subscription.sh"
    reload_nginx

    log_info "订阅链接已轮换。旧前缀: $old_prefix"
    log_info "订阅链接已轮换。新前缀: $new_prefix"
    bash "$PROJECT_ROOT/scripts/show_subscription.sh"
}

main "$@"
