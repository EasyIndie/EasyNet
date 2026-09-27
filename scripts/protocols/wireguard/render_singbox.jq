# EasyNet WireGuard (AmneziaWG) sing-box renderer
#
# EasyNet always deploys AmneziaWG on the server, while mainline sing-box has no
# AmneziaWG support: its WireGuard endpoint rejects the obfuscation fields
# (`json: unknown field "jc"`), and an AmneziaWG server does not answer plain
# WireGuard handshakes. A rendered node could therefore never connect, so this
# module intentionally renders nothing and is omitted from the sing-box
# subscription (including the `Proxy` selector and `Auto` urltest).
#
# Use the URI / Clash subscriptions instead (Shadowrocket, Clash Verge Rev).
#
# To bring the node back once sing-box supports AmneziaWG, restore the endpoint
# renderer from git history (the commit that introduced this stub) and re-add
# the "sing-box renders WireGuard" test.
empty
