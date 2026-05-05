#!/bin/bash

if ! declare -F log_warn >/dev/null 2>&1; then
    log_warn() { echo "[WARN] $1"; }
fi

trim_env_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

strip_env_quotes() {
    local value="$1"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s' "$value"
}

load_easynet_env_file() {
    local env_file="$1"
    local line key value

    [ -f "$env_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(trim_env_value "$line")"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        [[ "$line" == export[[:space:]]* ]] && line="${line#export }"
        [[ "$line" == *=* ]] || continue

        key="$(trim_env_value "${line%%=*}")"
        value="$(trim_env_value "${line#*=}")"

        if [[ ! "$key" =~ ^EASYNET_[A-Z0-9_]+$ ]]; then
            log_warn "忽略不受支持的 .env 变量: $key"
            continue
        fi

        value="$(strip_env_quotes "$value")"
        export "$key=$value"
    done < "$env_file"
}
