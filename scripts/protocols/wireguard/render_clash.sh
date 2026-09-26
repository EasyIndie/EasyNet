#!/bin/bash
# EasyNet AmneziaWG Clash YAML proxy renderer
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
ip=$(jq -r '.client.clash.ip // empty' "$METADATA_FILE")
private_key=$(jq -r '.client.clash."private-key" // empty' "$METADATA_FILE")
public_key=$(jq -r '.client.clash."public-key" // empty' "$METADATA_FILE")
pre_shared_key=$(jq -r '.client.clash."pre-shared-key" // empty' "$METADATA_FILE")
mtu=$(jq -r '.client.clash.mtu // 1360' "$METADATA_FILE")
dns_count=$(jq '.client.clash.dns | length' "$METADATA_FILE")

awg_jc=$(jq -r '.client.clash."amnezia-wg-option".jc // empty' "$METADATA_FILE")

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

if [ -n "$awg_jc" ] && [ "$awg_jc" != "null" ]; then
    cat << EOF
    amnezia-wg-option:
      jc: $awg_jc
      jmin: $(jq -r '.client.clash."amnezia-wg-option".jmin' "$METADATA_FILE")
      jmax: $(jq -r '.client.clash."amnezia-wg-option".jmax' "$METADATA_FILE")
      s1: $(jq -r '.client.clash."amnezia-wg-option".s1' "$METADATA_FILE")
      s2: $(jq -r '.client.clash."amnezia-wg-option".s2' "$METADATA_FILE")
      h1: "$(jq -r '.client.clash."amnezia-wg-option".h1' "$METADATA_FILE")"
      h2: "$(jq -r '.client.clash."amnezia-wg-option".h2' "$METADATA_FILE")"
      h3: "$(jq -r '.client.clash."amnezia-wg-option".h3' "$METADATA_FILE")"
      h4: "$(jq -r '.client.clash."amnezia-wg-option".h4' "$METADATA_FILE")"
EOF
fi

echo "    dns:"
for (( i=0; i<dns_count; i++ )); do
    dns_item=$(jq -r ".client.clash.dns[$i]" "$METADATA_FILE")
    printf '      - "%s"\n' "$(yaml_escape "$dns_item")"
done
