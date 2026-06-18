# EasyNet WireGuard sing-box endpoint renderer
# sing-box v1.11+ migrated WireGuard from outbound to endpoint format:
#   server/server_port → peers[].address/port
#   peer_public_key    → peers[].public_key
#   pre_shared_key     → peers[].pre_shared_key
#   local_address      → address
#
# Note: AmneziaWG obfuscation (jc/jmin/jmax) is not included here;
# mainline sing-box releases do not support these fields in the
# WireGuard endpoint. The server runs standard WireGuard, so standard
# WireGuard clients connect fine without them.
# Usage: jq -c -f render_singbox.jq <metadata.json>
.client.clash as $c
| ($c.name // .module) as $tag
| {
    type: "wireguard",
    tag: $tag,
    address: [($c.ip | if contains("/") then . else . + "/32" end)],
    private_key: $c["private-key"],
    mtu: ($c.mtu // 1360),
    peers: [
        {
            address: $c.server,
            port: $c.port,
            public_key: $c["public-key"],
            pre_shared_key: $c["pre-shared-key"],
            allowed_ips: ["0.0.0.0/0"],
            persistent_keepalive_interval: 25
        }
    ]
}
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
