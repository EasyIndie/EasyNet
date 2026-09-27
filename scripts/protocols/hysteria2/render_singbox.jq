# EasyNet Hysteria2 sing-box outbound renderer
# Usage: jq -c -f render_singbox.jq <metadata.json>
.client.clash as $c
| ($c.name // .module) as $tag
| {
    type: "hysteria2",
    tag: $tag,
    server: $c.server,
    server_port: $c.port,
    password: $c.password,
    # Port hopping: sing-box expects "start:end" in server_ports.
    server_ports: (if ($c["hop-range"] // "") == "" then null
                   else $c["hop-range"] | split("-") | ["\(.[0]):\(.[1])"] end),
    hop_interval: ($c["hop-interval"] // null),
    obfs: {
        type: ($c.obfs // "salamander"),
        password: $c["obfs-password"]
    },
    tls: {
        enabled: true,
        server_name: $c.sni,
        insecure: ($c["skip-cert-verify"] // false)
    }
  }
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
