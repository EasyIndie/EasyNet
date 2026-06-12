# EasyNet: sing-box outbound converter
# Reads an EasyNet metadata.json and outputs a sing-box outbound JSON object.
# Usage: jq -c -f singbox_outbound.jq <metadata.json>

.client.clash as $c
| ($c.name // .module) as $tag
| if $c.type == "vless" then
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
            utls: {
                enabled: true,
                fingerprint: ($c["client-fingerprint"] // "chrome")
            },
            reality: {
                enabled: true,
                public_key: $c["reality-opts"]["public-key"],
                short_id: $c["reality-opts"]["short-id"]
            }
        }
    }
    + if $c.network == "xhttp" then
        {
            transport: {
                type: "xhttp",
                mode: ($c["xhttp-opts"].mode // "auto")
            }
            +
            if $c["xhttp-opts"].xmux.concurrency then
                { xmux: { concurrency: $c["xhttp-opts"].xmux.concurrency } }
            else {} end
        }
    else {} end
elif $c.type == "hysteria2" then
    {
        type: "hysteria2",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        password: $c.password,
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
elif $c.type == "ss" then
    {
        type: "shadowsocks",
        tag: $tag,
        server: $c.server,
        server_port: $c.port,
        method: $c.cipher,
        password: $c.password
    }
elif $c.type == "wireguard" then
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
else
    empty
end
| walk(if type == "object" then with_entries(select(.value != null and .value != "")) else . end)
