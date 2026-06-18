#!/bin/bash
# EasyNet Shadowsocks 2022 Clash YAML proxy renderer
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
cipher=$(jq -r '.client.clash.cipher // empty' "$METADATA_FILE")
password=$(jq -r '.client.clash.password // empty' "$METADATA_FILE")

cat << EOF
  - name: "$(yaml_escape "$name")"
    type: ss
    server: "$(yaml_escape "$server")"
    port: $port
    cipher: "$(yaml_escape "$cipher")"
    password: "$(yaml_escape "$password")"
    udp: true
EOF
