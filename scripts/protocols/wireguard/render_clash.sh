#!/bin/bash
# EasyNet WireGuard (+Amnezia obfs) Clash YAML proxy renderer
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
ip=$(jq -r '.client.clash.ip // empty' "$METADATA_FILE")
private_key=$(jq -r '.client.clash."private-key" // empty' "$METADATA_FILE")
public_key=$(jq -r '.client.clash."public-key" // empty' "$METADATA_FILE")
pre_shared_key=$(jq -r '.client.clash."pre-shared-key" // empty' "$METADATA_FILE")
mtu=$(jq -r '.client.clash.mtu // 1360' "$METADATA_FILE")
jc=$(jq -r '.client.clash.jc // empty' "$METADATA_FILE")
jmin=$(jq -r '.client.clash.jmin // empty' "$METADATA_FILE")
jmax=$(jq -r '.client.clash.jmax // empty' "$METADATA_FILE")
dns_count=$(jq '.client.clash.dns | length' "$METADATA_FILE")

cat << EOF
  - name: "$(yaml_escape "$name")"
    type: wireguard
    server: "$(yaml_escape "$server")"
    port: $port
    ip: "$(yaml_escape "$ip")"
    private-key: "$(yaml_escape "$private_key")"
    public-key: "$(yaml_escape "$public_key")"
    pre-shared-key: "$(yaml_escape "$pre_shared_key")"
    udp: true
    mtu: $mtu
EOF

if [ -n "$jc" ] && [ "$jc" != "null" ]; then
    cat << EOF
    jc: $jc
    jmin: $jmin
    jmax: $jmax
EOF
fi

echo "    dns:"
for (( i=0; i<dns_count; i++ )); do
    dns_item=$(jq -r ".client.clash.dns[$i]" "$METADATA_FILE")
    printf '      - "%s"\n' "$(yaml_escape "$dns_item")"
done
