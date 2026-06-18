#!/bin/bash
# EasyNet Hysteria2 Clash YAML proxy renderer
# Usage: bash render_clash.sh <metadata.json>
set -e

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
