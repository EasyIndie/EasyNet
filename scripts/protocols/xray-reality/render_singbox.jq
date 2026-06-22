# EasyNet Xray+Reality sing-box outbound renderer
# Usage: jq -c -f render_singbox.jq <metadata.json>
# Note: sing-box does NOT support xhttp transport (Xray-only).
# For TCP Reality (standard) the config has no transport block.
.client.clash as $c
| ($c.name // .module) as $tag
| if $c.network == "xhttp" and ($c["xhttp-opts"].xmux.concurrency | type == "number" and . > 0) then
    {
        type: "vless",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        uuid: $c.uuid,
        flow: ($c.flow // ""),
        network: "tcp",
        tls: {
            enabled: true,
            server_name: $c.servername,
            utls: { enabled: true, fingerprint: ($c["client-fingerprint"] // "chrome") },
            reality: { enabled: true, public_key: $c["reality-opts"]["public-key"], short_id: $c["reality-opts"]["short-id"] }
        },
        xmux: { concurrency: $c["xhttp-opts"].xmux.concurrency }
    }
  elif $c.network == "xhttp" then
    {
        type: "vless",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        uuid: $c.uuid,
        flow: ($c.flow // ""),
        network: "tcp",
        tls: {
            enabled: true,
            server_name: $c.servername,
            utls: { enabled: true, fingerprint: ($c["client-fingerprint"] // "chrome") },
            reality: { enabled: true, public_key: $c["reality-opts"]["public-key"], short_id: $c["reality-opts"]["short-id"] }
        }
    }
  else
    {
        type: "vless",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        uuid: $c.uuid,
        flow: ($c.flow // ""),
        network: ($c.network // "tcp"),
        tls: {
            enabled: true,
            server_name: $c.servername,
            utls: { enabled: true, fingerprint: ($c["client-fingerprint"] // "chrome") },
            reality: { enabled: true, public_key: $c["reality-opts"]["public-key"], short_id: $c["reality-opts"]["short-id"] }
        }
    }
  end
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
