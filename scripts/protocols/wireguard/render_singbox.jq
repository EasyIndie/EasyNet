# EasyNet WireGuard (+Amnezia obfs) sing-box outbound renderer
# Usage: jq -c -f render_singbox.jq <metadata.json>
.client.clash as $c
| ($c.name // .module) as $tag
| if $c.jc then
    {
        type: "wireguard",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        local_address: [($c.ip | if contains("/") then . else . + "/32" end)],
        private_key: $c["private-key"],
        peer_public_key: $c["public-key"],
        pre_shared_key: $c["pre-shared-key"],
        mtu: ($c.mtu // 1360),
        jc: $c.jc,
        jmin: $c.jmin,
        jmax: $c.jmax
    }
  else
    {
        type: "wireguard",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        local_address: [($c.ip | if contains("/") then . else . + "/32" end)],
        private_key: $c["private-key"],
        peer_public_key: $c["public-key"],
        pre_shared_key: $c["pre-shared-key"],
        mtu: ($c.mtu // 1360)
    }
  end
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
