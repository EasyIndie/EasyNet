#!/bin/bash
# EasyNet Xray+Reality Clash YAML proxy renderer
# Usage: bash render_clash.sh <metadata.json>
set -e

METADATA_FILE="$1"
[ -f "$METADATA_FILE" ] || exit 1

yaml_escape() { local v="$1"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; printf '%s' "$v"; }

name=$(jq -r '.client.clash.name // .module' "$METADATA_FILE")
server=$(jq -r '.client.clash.server // empty' "$METADATA_FILE")
port=$(jq -r '.client.clash.port // empty' "$METADATA_FILE")
uuid=$(jq -r '.client.clash.uuid // empty' "$METADATA_FILE")
network=$(jq -r '.client.clash.network // "tcp"' "$METADATA_FILE")
flow=$(jq -r '.client.clash.flow // empty' "$METADATA_FILE")
servername=$(jq -r '.client.clash.servername // empty' "$METADATA_FILE")
client_fingerprint=$(jq -r '.client.clash."client-fingerprint" // empty' "$METADATA_FILE")
public_key=$(jq -r '.client.clash."reality-opts"."public-key" // empty' "$METADATA_FILE")
short_id=$(jq -r '.client.clash."reality-opts"."short-id" // empty' "$METADATA_FILE")
xhttp_mode=$(jq -r '.client.clash."xhttp-opts".mode // empty' "$METADATA_FILE")
xmux_cc=$(jq -r '.client.clash."xhttp-opts".xmux.concurrency // empty' "$METADATA_FILE")

cat << EOF
  - name: "$(yaml_escape "$name")"
    type: vless
    server: "$(yaml_escape "$server")"
    port: $port
    uuid: "$(yaml_escape "$uuid")"
    network: "$(yaml_escape "$network")"
    udp: true
    tls: true
    flow: "$(yaml_escape "$flow")"
    servername: "$(yaml_escape "$servername")"
    client-fingerprint: "$(yaml_escape "$client_fingerprint")"
    reality-opts:
      public-key: "$(yaml_escape "$public_key")"
      short-id: "$(yaml_escape "$short_id")"
EOF

if [ -n "$xhttp_mode" ]; then
    cat << EOF
    xhttp-opts:
      mode: "$(yaml_escape "$xhttp_mode")"
EOF
    if [ -n "$xmux_cc" ] && [ "$xmux_cc" != "null" ] && [ "$xmux_cc" -gt 0 ] 2>/dev/null; then
        cat << EOF
      xmux:
        concurrency: $xmux_cc
EOF
    fi
fi
