#!/bin/bash

EASYNET_DOWNLOAD_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_DOWNLOAD_CORE_DIR/logging.sh"

download_file() {
    local url="$1"
    local output="$2"
    local sha256="${3:-}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$output" "$url" || return 1
    else
        log_error "需要 curl 或 wget 下载安装文件。"
        return 1
    fi

    if [ -n "$sha256" ]; then
        printf '%s  %s\n' "$sha256" "$output" | sha256sum -c - || return 1
    fi
}

run_downloaded_script() {
    local url="$1"
    local sha256="${2:-}"
    shift 2 || true
    local tmp_script status

    tmp_script="$(mktemp /tmp/easynet-install.XXXXXX)"
    if ! download_file "$url" "$tmp_script" "$sha256"; then
        rm -f "$tmp_script"
        return 1
    fi
    chmod 700 "$tmp_script"
    set +e
    bash "$tmp_script" "$@"
    status=$?
    set -e
    rm -f "$tmp_script"
    return $status
}
