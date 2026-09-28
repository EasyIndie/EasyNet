#!/bin/bash
# EasyNet Hysteria2 Clash YAML proxy renderer
# Usage: bash render_clash.sh <metadata.json>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/../../core" &>/dev/null && pwd)"
source "$CORE_DIR/subscription_clash.sh"

METADATA_FILE="$1"
[ -f "$METADATA_FILE" ] || exit 1

name=$(jq -r '.client.clash.name // .module' "$METADATA_FILE")
server=$(jq -r '.client.clash.server // empty' "$METADATA_FILE")
port=$(jq -r '.client.clash.port // empty' "$METADATA_FILE")
password=$(jq -r '.client.clash.password // empty' "$METADATA_FILE")
sni=$(jq -r '.client.clash.sni // empty' "$METADATA_FILE")
obfs=$(jq -r '.client.clash.obfs // empty' "$METADATA_FILE")
obfs_password=$(jq -r '.client.clash."obfs-password" // empty' "$METADATA_FILE")
up=$(jq -r '.client.clash.up // "100 Mbps"' "$METADATA_FILE")
down=$(jq -r '.client.clash.down // "100 Mbps"' "$METADATA_FILE")
hop_range=$(jq -r '.client.clash."hop-range" // empty' "$METADATA_FILE")
hop_interval=$(jq -r '.client.clash."hop-interval" // empty' "$METADATA_FILE")

# mihomo 的 hop-interval 是**整数秒**，不是 sing-box 的时长字符串：
# 发 "30s" 会被当成端口范围解析 → `invalid range: 30s`，整份订阅被拒绝导入
# （Clash Verge 实测）。元数据存的是中立值时长相时长（"30s"），这里按客户端方言转换：
# 纯数字直接沿用；30s/1m/1h 归一化成秒；无法识别的省略该字段（mihomo 用默认值）。
mihomo_hop_interval_seconds() {
    local raw="$1" num unit
    [ -n "$raw" ] || return 0
    num="${raw%%[!0-9]*}"
    [ -n "$num" ] || return 0
    unit="${raw#"$num"}"
    num=$((10#${num}))
    case "$unit" in
        ''|s|sec|secs|second|seconds) printf '%s\n' "$num" ;;
        m|min|mins|minute|minutes) printf '%s\n' "$((num * 60))" ;;
        h|hr|hrs|hour|hours) printf '%s\n' "$((num * 3600))" ;;
        *) return 0 ;;
    esac
}

cat << EOF
  - name: "$(yaml_escape "$name")"
    type: hysteria2
    server: "$(yaml_escape "$server")"
    port: $port
    password: "$(yaml_escape "$password")"
    sni: "$(yaml_escape "$sni")"
    skip-cert-verify: false
    obfs: "$(yaml_escape "$obfs")"
    obfs-password: "$(yaml_escape "$obfs_password")"
    up: "$(yaml_escape "$up")"
    down: "$(yaml_escape "$down")"
EOF
    # mihomo port hopping: `ports` accepts a "start-end" string (or a list),
    # `hop-interval` must be an integer number of seconds.
    if [ -n "${hop_range:-}" ]; then
        printf '    ports: "%s"\n' "$(yaml_escape "$hop_range")"
        hop_seconds="$(mihomo_hop_interval_seconds "${hop_interval:-}")"
        if [ -n "$hop_seconds" ]; then
            printf '    hop-interval: %s\n' "$hop_seconds"
        fi
    fi
