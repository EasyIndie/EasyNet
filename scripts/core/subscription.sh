#!/bin/bash

EASYNET_SUBSCRIPTION_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_SUBSCRIPTION_CORE_DIR/env.sh"
source "$EASYNET_SUBSCRIPTION_CORE_DIR/metadata.sh"

easynet_subscription_domain() {
    if [ -n "${EASYNET_SUBSCRIPTION_DOMAIN:-}" ]; then
        echo "${EASYNET_SUBSCRIPTION_DOMAIN:-}"
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
    if [ -n "${EASYNET_SUBSCRIPTION_SCHEME:-}" ]; then
        echo "${EASYNET_SUBSCRIPTION_SCHEME:-}"
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
    if [ -n "${EASYNET_SUBSCRIPTION_URL_PORT:-}" ]; then
        echo "${EASYNET_SUBSCRIPTION_URL_PORT:-}"
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
    if [ -n "${EASYNET_SUBSCRIPTION_PATH_PREFIX:-}" ]; then
        easynet_normalize_path_prefix "${EASYNET_SUBSCRIPTION_PATH_PREFIX:-}"
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

    if [ "${EASYNET_SUBSCRIPTION_DIRECT_PATHS:-true}" = "true" ]; then
        # Direct paths: /sub, /clash, /singbox
        echo "/${endpoint#/}"
    elif [ -n "$path_prefix" ]; then
        echo "${path_prefix}/${endpoint#/}"
    else
        echo "/${endpoint#/}"
    fi
}

easynet_singbox_rules_conf() {
    if [ -n "${EASYNET_SINGBOX_RULES_CONF:-}" ]; then
        echo "${EASYNET_SINGBOX_RULES_CONF:-}"
        return
    fi

    echo "$(easynet_project_root)/scripts/core/singbox-rules.conf"
}

# 输出 "<tag>|<source>|<category>|<action>"；注释与空行忽略；action 缺省 direct
easynet_singbox_rules_specs() {
    local conf
    conf="$(easynet_singbox_rules_conf)"
    [ -f "$conf" ] || return 0

    awk -F'|' '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        NF >= 3 {
            for (i = 1; i <= NF; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
            if ($1 == "" || $2 == "" || $3 == "") { next }
            action = ($4 == "" ? "direct" : $4)
            print $1 "|" $2 "|" $3 "|" action
        }
    ' "$conf"
}

easynet_singbox_rules_tags() {
    easynet_singbox_rules_specs | cut -d'|' -f1
}

# 订阅里 route.rule_set 的内容：remote 指向本机 edge 发布的 .srs
easynet_singbox_rule_sets_json() {
    local tag url detour out="["
    detour="${EASYNET_SINGBOX_RULES_DETOUR:-DIRECT}"

    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        url="$(easynet_subscription_url "rules/${tag}.srs" 2>/dev/null || true)"
        [ -n "$url" ] || continue
        out+="$(jq -cn --arg tag "$tag" --arg url "$url" --arg detour "$detour" \
            '{type:"remote", tag:$tag, format:"binary", url:$url, download_detour:$detour, update_interval:"7d"}'),"
    done < <(easynet_singbox_rules_tags)

    printf '%s' "${out%,}]"
}

# 订阅里 route.rules 的策略部分（私有网段那条由调用方补在最前）
easynet_singbox_policy_rules_json() {
    local tag action out="["

    while IFS='|' read -r tag action; do
        [ -z "$tag" ] && continue
        case "${action:-direct}" in
        direct) out+="$(jq -cn --arg t "$tag" '{rule_set:[$t], action:"route", outbound:"DIRECT"}')," ;;
        reject) out+="$(jq -cn --arg t "$tag" '{rule_set:[$t], action:"route", outbound:"REJECT"}')," ;;
        *) continue ;;
        esac
    done < <(easynet_singbox_rules_specs | awk -F'|' '{ print $1 "|" $4 }')

    printf '%s' "${out%,}]"
}

# 规则集文件的订阅端点（随机路径前缀模式用；直接路径模式走 location / 静态托管）
easynet_singbox_rules_endpoint_specs() {
    local tag
    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        printf 'rules/%s.srs|rules/%s.srs|application/octet-stream\n' "$tag" "$tag"
    done < <(easynet_singbox_rules_tags)
    printf 'rules/manifest.json|rules/manifest.json|application/json\n'
}

easynet_subscription_endpoint_specs() {
    cat <<'EOF'
sub|sub|text/plain
clash|clash|application/x-yaml
singbox|singbox|application/json
singbox-client.sh|easynet-singbox-client.sh|text/x-shellscript
EOF
    easynet_singbox_rules_endpoint_specs
}

easynet_write_subscription_routes() {
    local route_file="$1"
    local web_root="$2"
    local current_prefix="$3"
    local previous_prefix="${4:-}"
    local prefix endpoint file_name content_type

    : > "$route_file"
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
