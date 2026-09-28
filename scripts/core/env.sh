#!/bin/bash

easynet_project_root() {
    local source_dir
    source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &>/dev/null && pwd)"
    echo "$source_dir"
}

easynet_state_dir() {
    echo "${EASYNET_STATE_DIR:-/var/lib/easynet}"
}

easynet_metadata_dir() {
    echo "$(easynet_state_dir)/modules"
}

easynet_module_metadata_path() {
    local module_name="$1"
    echo "$(easynet_metadata_dir)/$module_name/metadata.json"
}

easynet_exposure_state_dir() {
    local exposure_name="$1"
    echo "$(easynet_state_dir)/exposure/$exposure_name"
}

# Tighten the state tree to root-only.
#
# The edge state dir holds `subscription_path_prefix.txt` (and the generated
# nginx routes that embed it): that random path is the ONLY secret protecting
# every node credential, so it must not be world-readable. metadata.json is
# already written 600 by metadata.sh; this covers the rest of the tree.
# Nothing that runs unprivileged needs to read /var/lib/easynet.
easynet_secure_state_dir() {
    local dir sub file
    dir="$(easynet_state_dir)"
    [ -d "$dir" ] || return 0

    chmod 700 "$dir" 2>/dev/null || true
    for sub in modules exposure exposure/edge exposure/edge/routes edge; do
        [ -d "$dir/$sub" ] && chmod 700 "$dir/$sub" 2>/dev/null
    done

    file="$dir/exposure/edge/subscription_path_prefix.txt"
    [ -f "$file" ] && chmod 600 "$file" 2>/dev/null
    for file in "$dir"/exposure/edge/routes/*.conf; do
        [ -f "$file" ] && chmod 600 "$file" 2>/dev/null
    done
    return 0
}

easynet_edge_state_dir() {
    easynet_exposure_state_dir "edge"
}

# 防呆：拒绝 rm -rf 一个文件系统关键路径。状态目录与安装目录都可由
# EASYNET_* 覆盖，误设成 "/"、"/var" 等会让后续的 rm -rf 造成灾难。
# 返回 0=安全，1=不安全。
easynet_assert_safe_rm_path() {
    local path="$1"
    [ -n "$path" ] || return 1
    case "$path" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$path" in
        /|/bin|/sbin|/lib|/lib64|/boot|/etc|/usr|/var|/home|/root|/opt|/srv|/proc|/sys|/dev|/run|/tmp|/mnt|/media)
            return 1 ;;
    esac
    return 0
}
