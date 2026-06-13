# EasyNet Shadowsocks 2022 sing-box outbound renderer
# Usage: jq -c -f render_singbox.jq <metadata.json>
.client.clash as $c
| ($c.name // .module) as $tag
| {
    type: "shadowsocks",
    tag: $tag,
    server: $c.server,
    server_port: $c.port,
    method: $c.cipher,
    password: $c.password
  }
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
