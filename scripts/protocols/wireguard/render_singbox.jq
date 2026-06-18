# EasyNet WireGuard (+Amnezia obfs) sing-box endpoint renderer
# sing-box v1.11+ migrated WireGuard from outbound to endpoint format:
#   server/server_port → peers[].address/port
#   peer_public_key    → peers[].public_key
#   pre_shared_key     → peers[].pre_shared_key
#   local_address      → address
# Usage: jq -c -f render_singbox.jq <metadata.json>
.client.clash as $c
| ($c.name // .module) as $tag
| if $c.jc then
    {
        type: "wireguard",
        tag: $tag,
        address: [($c.ip | if contains("/") then . else . + "/32" end)],
        private_key: $c["private-key"],
        mtu: ($c.mtu // 1360),
        jc: $c.jc,
        jmin: $c.jmin,
        jmax: $c.jmax,
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
  else
    {
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
  end
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
