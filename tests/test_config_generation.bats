#!/usr/bin/env bats
# Config generation dry-run tests
#
# Mock all system-affecting operations (download, systemctl, apt, etc.)
# and run each protocol's configure_*() function to verify that:
#   1. Config files are created
#   2. Config syntax is valid
#   3. Key fields are populated correctly
#
# This catches config format regressions when protocol versions change
# (e.g. Xray upgrade, Shadowsocks version bump) without needing a real VPS.

load test_helper

setup() {
    export TMP_DIR
    TMP_DIR=$(mktemp -d)

    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."

    # ---- State & network ----
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    export EASYNET_PUBLIC_IP="203.0.113.10"

    # ---- Mock binaries ----
    MOCK_BIN_DIR="$TMP_DIR/mock-bin"
    mkdir -p "$MOCK_BIN_DIR"

    # wg (WireGuard key generation)
    cat > "$MOCK_BIN_DIR/wg" <<'MOCK'
#!/bin/bash
case "${1:-}" in
    genkey)  echo "mOCKwGPrivateKeyBase64Encoded==" ;;
    pubkey)  echo "mOCKwGPublicKeyBase64Encoded=="  ;;
    genpsk)  echo "mOCKwGPresharedKeyBase64Encoded=" ;;
    *)       echo "mock wg: unknown: $*"; exit 1 ;;
esac
MOCK
    chmod +x "$MOCK_BIN_DIR/wg"

    # awg (AmneziaWG key generation; WireGuard module now uses awg/awg-quick)
    cat > "$MOCK_BIN_DIR/awg" <<'MOCK'
#!/bin/bash
case "${1:-}" in
    genkey)  echo "mOCKwGPrivateKeyBase64Encoded==" ;;
    pubkey)  echo "mOCKwGPublicKeyBase64Encoded=="  ;;
    genpsk)  echo "mOCKwGPresharedKeyBase64Encoded=" ;;
    *)       echo "mock awg: unknown: $*" >&2; exit 1 ;;
esac
MOCK
    chmod +x "$MOCK_BIN_DIR/awg"

    # xray (Reality key generation via x25519)
    cat > "$MOCK_BIN_DIR/xray" <<'MOCK'
#!/bin/bash
if [ "${1:-}" = "x25519" ]; then
    echo "Private key: mOCKxRayPrivateKeyBase64Encoded="
    echo "Public key:  mOCKxRayPublicKeyBase64Encoded="
    exit 0
fi
echo "mock xray: unknown: $*"
exit 1
MOCK
    chmod +x "$MOCK_BIN_DIR/xray"

    # ssserver (so Shadowsocks install check passes)
    cat > "$MOCK_BIN_DIR/ssserver" <<'MOCK'
#!/bin/bash
echo "ssserver mock v1.22.0"
MOCK
    chmod +x "$MOCK_BIN_DIR/ssserver"

    PATH="$MOCK_BIN_DIR:$PATH"
    export PATH

    # ---- TLS certs (needed by Hysteria2) ----
    export EASYNET_EDGE_CERT_DIR="$TMP_DIR/certs"
    mkdir -p "$EASYNET_EDGE_CERT_DIR"
    echo "fake-certificate-content" > "$EASYNET_EDGE_CERT_DIR/fullchain.crt"
    echo "fake-private-key-content" > "$EASYNET_EDGE_CERT_DIR/private.key"

    # ---- Core infrastructure ----
    source "$PROJECT_ROOT/scripts/core/logging.sh"

    # ---- Mock system commands (before sourcing any deploy.sh) ----
    eval 'systemctl() { echo "[mock] systemctl $*" >&2; }'
    export -f systemctl
    eval 'apt()     { echo "[mock] apt $*" >&2; }'
    eval 'apt-get() { echo "[mock] apt-get $*" >&2; }'
    eval 'dnf()     { echo "[mock] dnf $*" >&2; }'
    export -f apt apt-get dnf
    eval 'sysctl()  { echo "[mock] sysctl $*" >&2; }'
    export -f sysctl
    eval 'ip() {
        if [ "$1" = "route" ]; then echo "default via 10.0.0.1 dev eth0"
        else command ip "$@"; fi
    }'
    export -f ip

    # ---- Source core modules ----
    source "$PROJECT_ROOT/scripts/core/download.sh"
    source "$PROJECT_ROOT/scripts/core/network.sh"
    source "$PROJECT_ROOT/scripts/core/display.sh"
    source "$PROJECT_ROOT/scripts/core/crypto.sh"

    # ---- Override network/display ----
    eval 'get_public_ip() { echo "203.0.113.10"; }'
    eval 'show_qrcode()  { echo "[mock] QR for: $2"; }'
    eval 'random_secret() { echo "mock-secret-12345"; }'
    eval 'generate_uuid() { echo "11111111-1111-4111-8111-111111111111"; }'
    eval 'generate_psk()  { echo "mOCKpskForTestingPurposesOnly="; }'
    export -f get_public_ip show_qrcode random_secret generate_uuid generate_psk

    # ---- Mock low-level curl/wget to prevent real downloads ----
    eval 'curl() {
        local outfile=""
        local i=0
        for arg in "$@"; do
            if [ "$arg" = "-o" ]; then
                # Next arg is the output file
                local next=$((i+2))
                if [ $next -le $# ]; then
                    outfile="${@:$next:1}"
                fi
                break
            fi
            i=$((i+1))
        done
        if [ -n "$outfile" ]; then
            echo "#!/bin/bash" > "$outfile"
            echo "echo mocked" >> "$outfile"
            chmod +x "$outfile"
        fi
        return 0
    }'
    export -f curl
    eval 'wget() { return 0; }'
    export -f wget
}

teardown() {
    rm -rf "$TMP_DIR"
}

# -------------------------------------------------------------------------
# Helper: source protocol deploy.sh without triggering main()
#
# All protocol deploy.sh end with "main $@" and define SCRIPT_DIR/CORE_DIR
# using BASH_SOURCE[0]. When sourced from a temp file, BASH_SOURCE[0]
# would point to the temp file, breaking path resolution.
#
# Strategy: use sed to:
#   1. Replace SCRIPT_DIR/CORE_DIR with correct absolute paths
#   2. Remove the last line ("main $@")
#
# After sourcing, re-mock download functions because deploy.sh
# re-sources download.sh which overrides our earlier mocks.
# -------------------------------------------------------------------------
source_protocol() {
    local script="$1"
    local script_dir core_dir tmp

    script_dir="$(cd "$(dirname "$script")" && pwd)"
    core_dir="$(cd "$script_dir/../../core" && pwd)"

    tmp=$(mktemp)
    # - Replace self-computed SCRIPT_DIR/CORE_DIR with correct absolute paths
    # - Remove entrypoint execution: bare `main "$@"` (last line) or a guarded
    #   `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi` block
    sed -e "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$script_dir\"|" \
        -e "s|^CORE_DIR=.*|CORE_DIR=\"$core_dir\"|" \
        -e '/^main "\$@"$/d' \
        -e '/BASH_SOURCE\[0\].*==.*\$0/,/^fi$/d' "$script" > "$tmp"

    source "$tmp"
    rm -f "$tmp"

    # Re-mock download functions (deploy.sh re-sourced download.sh)
    eval 'run_downloaded_script() { :; }'
    eval 'download_file()         { :; }'
    export -f run_downloaded_script download_file

    # Restore safe shell options (deploy.sh uses set -euo pipefail)
    set +euo pipefail
}

# -------------------------------------------------------------------------
# Xray Reality
# -------------------------------------------------------------------------

@test "Xray: config generation produces valid config.json" {
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"

    # Mock openssl for deterministic short ID
    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ] || { echo "# configure_reality failed: $output" >&3; return 1; }

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    [ -f "$config" ] || { echo "# config.json not found at $config" >&3; return 1; }

    run jq empty "$config"
    [ "$status" -eq 0 ] || { echo "# invalid JSON" >&3; return 1; }

    run jq -r '.inbounds[0].protocol' "$config"
    [ "$output" = "vless" ]
    run jq -r '.inbounds[0].streamSettings.security' "$config"
    [ "$output" = "reality" ]
    run jq -r '.inbounds[0].streamSettings.network' "$config"
    [ "$output" = "tcp" ]
    run jq -r '.inbounds[0].settings.clients[0].flow' "$config"
    [ "$output" = "xtls-rprx-vision" ]
    run jq -r '.inbounds[0].port' "$config"
    [ "$output" = "8443" ]
    # Verify xhttpSettings not present in tcp mode
    run jq '.inbounds[0].streamSettings.xhttpSettings // empty' "$config"
    [ -z "$output" ]
}

@test "Xray: public.key and shortId are generated" {
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"

    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "deadbeefdeadbeef"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ]

    local xray_dir="${XRAY_DIR:-$TMP_DIR/xray}"
    [ -f "$xray_dir/public.key" ] || { echo "# public.key missing" >&3; return 1; }
    run cat "$xray_dir/public.key"
    [[ "$output" == *"PublicKeyBase64"* ]]

    local config="$xray_dir/config.json"
    run jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$config"
    [ "$output" = "deadbeefdeadbeef" ]
}

@test "Xray: xhttp transport generates config with xhttpSettings" {
    export EASYNET_REALITY_TRANSPORT=xhttp
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"

    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ] || { echo "# configure_reality failed: $output" >&3; return 1; }

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    [ -f "$config" ] || { echo "# config.json not found" >&3; return 1; }

    # xhttp transport assertions
    run jq -r '.inbounds[0].streamSettings.network' "$config"
    [ "$output" = "xhttp" ]
    run jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // empty' "$config"
    [ "$output" = "stream-one" ]
    # flow must be empty for xhttp (xtls-rprx-vision is TCP-only)
    run jq -r '.inbounds[0].settings.clients[0].flow // empty' "$config"
    [ -z "$output" ]
}

@test "Xray: transport switch from tcp to xhttp preserves UUID and keys" {
    export XRAY_DIR="$TMP_DIR/xray-switch"
    mkdir -p "$XRAY_DIR"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"

    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    # Step 1: Deploy with default TCP
    run configure_reality
    [ "$status" -eq 0 ]

    local uuid_tcp
    uuid_tcp=$(jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_DIR/config.json")
    local pk_tcp
    pk_tcp=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_DIR/config.json")
    local sid_tcp
    sid_tcp=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_DIR/config.json")
    local network_tcp
    network_tcp=$(jq -r '.inbounds[0].streamSettings.network' "$XRAY_DIR/config.json")
    [ "$network_tcp" = "tcp" ]

    # Step 2: Re-deploy with xhttp transport
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    export EASYNET_REALITY_TRANSPORT=xhttp
    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "bbccddee00112233"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ] || { echo "# second configure_reality failed: $output" >&3; return 1; }

    # Verify transport changed
    local network_xhttp
    network_xhttp=$(jq -r '.inbounds[0].streamSettings.network' "$XRAY_DIR/config.json")
    [ "$network_xhttp" = "xhttp" ]

    # Verify UUID, privateKey, shortId preserved
    local uuid_xhttp
    uuid_xhttp=$(jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_DIR/config.json")
    [ "$uuid_xhttp" = "$uuid_tcp" ]
    local pk_xhttp
    pk_xhttp=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_DIR/config.json")
    [ "$pk_xhttp" = "$pk_tcp" ]
    local sid_xhttp
    sid_xhttp=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_DIR/config.json")
    [ "$sid_xhttp" = "$sid_tcp" ]

    # public.key should persist
    [ -f "$XRAY_DIR/public.key" ]
    run cat "$XRAY_DIR/public.key"
    [[ "$output" == *"PublicKeyBase64"* ]]

    # xhttpSettings should exist
    run jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // empty' "$XRAY_DIR/config.json"
    [ "$output" = "stream-one" ]
    # flow must be cleared after switch to xhttp (xtls-rprx-vision is TCP-only)
    run jq -r '.inbounds[0].settings.clients[0].flow // empty' "$XRAY_DIR/config.json"
    [ -z "$output" ]
}

# -------------------------------------------------------------------------
# Xray Reality self-steal
# -------------------------------------------------------------------------

@test "Xray: self-steal mode uses local Edge target and own-domain SNI" {
    export EASYNET_REALITY_MODE=self
    export EASYNET_DOMAIN="world.example.com"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"

    eval 'openssl() {
        if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"
        else command openssl "$@"; fi
    }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ] || { echo "# configure_reality failed: $output" >&3; return 1; }

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    run jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$config"
    [ "$output" = "127.0.0.1:443" ]
    run jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$config"
    [ "$output" = "world.example.com" ]
}

@test "Xray: auto mode self-steals when domain and Edge certificate are present" {
    export EASYNET_REALITY_MODE=auto
    export EASYNET_DOMAIN="world.example.com"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ]

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    run jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$config"
    [ "$output" = "127.0.0.1:443" ]
}

@test "Xray: auto mode borrows an external site when no domain is set" {
    unset EASYNET_DOMAIN
    export EASYNET_REALITY_MODE=auto
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ]

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    run jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$config"
    [ "$output" = "www.bing.com:443" ]
}

@test "Xray: self-steal mode without a domain fails" {
    unset EASYNET_DOMAIN
    export EASYNET_REALITY_MODE=self
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -ne 0 ]
}

@test "Xray: switching borrow to self updates target and preserves keys" {
    export XRAY_DIR="$TMP_DIR/xray-self"
    mkdir -p "$XRAY_DIR"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    export EASYNET_REALITY_MODE=borrow
    run configure_reality
    [ "$status" -eq 0 ]
    local pk_before sid_before
    pk_before=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_DIR/config.json")
    sid_before=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_DIR/config.json")
    run jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$XRAY_DIR/config.json"
    [ "$output" = "www.bing.com:443" ]

    export EASYNET_REALITY_MODE=self
    export EASYNET_DOMAIN="world.example.com"
    run configure_reality
    [ "$status" -eq 0 ]

    run jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$XRAY_DIR/config.json"
    [ "$output" = "127.0.0.1:443" ]
    run jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$XRAY_DIR/config.json"
    [ "$output" = "world.example.com" ]
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_DIR/config.json")" = "$pk_before" ]
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_DIR/config.json")" = "$sid_before" ]
}

@test "Xray: re-running an unchanged config skips restart" {
    export XRAY_DIR="$TMP_DIR/xray-idem"
    mkdir -p "$XRAY_DIR"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ]
    run configure_reality
    [ "$status" -eq 0 ]
    [[ "$output" == *"配置未变化，跳过重启"* ]]
}

@test "Xray: fallback rate limiting is applied when configured" {
    export EASYNET_REALITY_MODE=borrow
    export EASYNET_REALITY_LIMIT_FALLBACK_UPLOAD="0:1048576:2097152"
    export EASYNET_REALITY_LIMIT_FALLBACK_DOWNLOAD="10485760:5242880:10485760"
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ] || { echo "# configure_reality failed: $output" >&3; return 1; }

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.limitFallbackUpload.bytesPerSec' "$config")" = "1048576" ]
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.limitFallbackUpload.burstBytesPerSec' "$config")" = "2097152" ]
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.limitFallbackDownload.afterBytes' "$config")" = "10485760" ]
    [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.limitFallbackDownload.bytesPerSec' "$config")" = "5242880" ]
}

@test "Xray: fallback rate limiting is absent by default" {
    export EASYNET_REALITY_MODE=borrow
    source_protocol "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    eval 'openssl() { if [ "$1" = "rand" ] && [ "$2" = "-hex" ]; then echo "aabbccddeeff0011"; else command openssl "$@"; fi }'
    export -f openssl
    export XRAY_BIN="xray"

    run configure_reality
    [ "$status" -eq 0 ]

    local config="${XRAY_DIR:-$TMP_DIR/xray}/config.json"
    [ "$(jq '.inbounds[0].streamSettings.realitySettings.limitFallbackUpload // empty' "$config")" = "" ]
}

# -------------------------------------------------------------------------
# Shadowsocks
# -------------------------------------------------------------------------

@test "Shadowsocks: config generation produces valid config.json" {
    source_protocol "$PROJECT_ROOT/scripts/protocols/shadowsocks/deploy.sh"

    export CONFIG_DIR="$TMP_DIR/ss-config"
    run configure_shadowsocks
    [ "$status" -eq 0 ] || { echo "# configure_shadowsocks failed: $output" >&3; return 1; }

    local config="$CONFIG_DIR/config.json"
    [ -f "$config" ] || { echo "# config.json not found" >&3; return 1; }

    run jq empty "$config"
    [ "$status" -eq 0 ] || { echo "# invalid JSON" >&3; return 1; }

    run jq -r '.servers[0].server_port' "$config"
    [ "$output" = "8388" ]
    run jq -r '.servers[0].method' "$config"
    [ "$output" = "2022-blake3-aes-256-gcm" ]
    run jq -r '.servers[0].password' "$config"
    [ -n "$output" ]
    run jq -r '.servers[0].server' "$config"
    [ "$output" = "0.0.0.0" ]
}

# -------------------------------------------------------------------------
# WireGuard
# -------------------------------------------------------------------------

@test "WireGuard: server config produces valid wg0.conf" {
    export WG_DIR="$TMP_DIR/wg"
    export CLIENT_CONFIG_DIR="$WG_DIR/clients"

    source_protocol "$PROJECT_ROOT/scripts/protocols/wireguard/deploy.sh"
    source "$PROJECT_ROOT/scripts/core/url.sh"

    run configure_server
    [ "$status" -eq 0 ] || { echo "# configure_server failed: $output" >&3; return 1; }

    local config="${WG_CONFIG:-$WG_DIR/wg0.conf}"
    [ -f "$config" ] || { echo "# wg0.conf not found at $config" >&3; return 1; }

    grep -q "\[Interface\]" "$config" || { echo "# missing [Interface]"; return 1; }
    grep -q "PrivateKey" "$config"     || { echo "# missing PrivateKey"; return 1; }
    grep -q "ListenPort" "$config"     || { echo "# missing ListenPort"; return 1; }
    # AmneziaWG obfuscation parameters must be present
    grep -q "^Jc = " "$config"         || { echo "# missing Jc"; return 1; }
    grep -q "^S1 = " "$config"         || { echo "# missing S1"; return 1; }
    grep -q "^H4 = " "$config"         || { echo "# missing H4"; return 1; }

    run grep "ListenPort" "$config" | awk '{print $3}'
    [ "$output" = "51820" ]

    # server_public.key
    [ -f "$WG_DIR/server_public.key" ] || { echo "# server_public.key missing"; return 1; }
}

@test "WireGuard: client config is generated correctly" {
    export WG_DIR="$TMP_DIR/wg"
    export CLIENT_CONFIG_DIR="$WG_DIR/clients"
    export EASYNET_PUBLIC_IP="203.0.113.10"

    source_protocol "$PROJECT_ROOT/scripts/protocols/wireguard/deploy.sh"
    source "$PROJECT_ROOT/scripts/core/url.sh"

    run configure_server
    [ "$status" -eq 0 ]
    run add_client "client1" 1
    [ "$status" -eq 0 ] || { echo "# add_client failed: $output" >&3; return 1; }

    local client_conf="$CLIENT_CONFIG_DIR/client1.conf"
    [ -f "$client_conf" ] || { echo "# client1.conf not found"; return 1; }

    grep -q "\[Interface\]" "$client_conf" && grep -q "\[Peer\]" "$client_conf" || {
        echo "# missing Interface or Peer sections"; return 1
    }
    grep -q "Endpoint" "$client_conf" || { echo "# missing Endpoint"; return 1; }
    # AmneziaWG params must be copied into the client config (server/client must match)
    local server_jc client_jc
    server_jc=$(grep "^Jc = " "${WG_CONFIG:-$WG_DIR/wg0.conf}" | awk '{print $3}')
    client_jc=$(grep "^Jc = " "$client_conf" | awk '{print $3}')
    [ -n "$client_jc" ] && [ "$server_jc" = "$client_jc" ] || { echo "# Jc mismatch ($server_jc vs $client_jc)"; return 1; }
    run grep "Endpoint" "$client_conf" | sed 's/.*= *//'
    [[ "$output" == *"203.0.113.10"* ]]
}

@test "AmneziaWG: generated obfuscation parameters are valid and unique" {
    export WG_DIR="$TMP_DIR/wg-params"
    export CLIENT_CONFIG_DIR="$WG_DIR/clients"
    source_protocol "$PROJECT_ROOT/scripts/protocols/wireguard/deploy.sh"

    run configure_server
    [ "$status" -eq 0 ] || { echo "# configure_server failed: $output" >&3; return 1; }

    local config="${WG_CONFIG:-$WG_DIR/wg0.conf}"
    local jc jmin jmax s1 s2 values unique h
    jc=$(awk -F' = ' '/^Jc = /{print $2}' "$config")
    jmin=$(awk -F' = ' '/^Jmin = /{print $2}' "$config")
    jmax=$(awk -F' = ' '/^Jmax = /{print $2}' "$config")
    s1=$(awk -F' = ' '/^S1 = /{print $2}' "$config")
    s2=$(awk -F' = ' '/^S2 = /{print $2}' "$config")

    [ "$jc" -ge 1 ] && [ "$jc" -le 128 ] || { echo "# Jc out of range: $jc"; return 1; }
    [ "$jmin" -lt "$jmax" ] && [ "$jmax" -le 1280 ] || { echo "# Jmin/Jmax invalid: $jmin/$jmax"; return 1; }
    [ "$s1" -ge 15 ] && [ "$s1" -le 150 ] || { echo "# S1 out of range: $s1"; return 1; }
    [ "$s2" -ge 15 ] && [ "$s2" -le 150 ] || { echo "# S2 out of range: $s2"; return 1; }
    [ "$((s1 + 56))" -ne "$s2" ] || { echo "# S1+56 == S2 violates AmneziaWG"; return 1; }

    values=$(awk -F' = ' '/^H[1-4] = /{print $2}' "$config")
    unique=$(printf '%s\n' "$values" | sort -u | wc -l | tr -d ' ')
    [ "$unique" = "4" ] || { echo "# H1-H4 not unique: $values"; return 1; }
    while IFS= read -r h; do
        [ "$h" -ge 5 ] && [ "$h" -le 2147483647 ] || { echo "# H out of range: $h"; return 1; }
    done <<< "$values"
}

# -------------------------------------------------------------------------
# Hysteria2
# -------------------------------------------------------------------------

@test "Hysteria2: config generation produces valid config.yaml" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"

    export HYSTERIA2_CONFIG_DIR="$TMP_DIR/hy2"
    export EASYNET_DOMAIN="proxy.example.com"

    source_protocol "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"

    run configure_hysteria2
    [ "$status" -eq 0 ] || { echo "# configure_hysteria2 failed: $output" >&3; return 1; }

    local config="${HYSTERIA2_CONFIG_FILE:-$HYSTERIA2_CONFIG_DIR/config.yaml}"
    [ -f "$config" ] || { echo "# config.yaml not found at $config" >&3; return 1; }

    grep -q "listen:" "$config"      || { echo "# missing listen:"; return 1; }
    grep -q "tls:" "$config"         || { echo "# missing tls:"; return 1; }
    grep -q "cert:" "$config"        || { echo "# missing cert:"; return 1; }
    grep -q "auth:" "$config"        || { echo "# missing auth:"; return 1; }
    grep -q "masquerade:" "$config"  || { echo "# missing masquerade:"; return 1; }
    grep -q "obfs:" "$config"        || { echo "# missing obfs:"; return 1; }
    grep -q "salamander" "$config"   || { echo "# missing salamander"; return 1; }

    run grep "listen:" "$config" | awk '{print $2}' | tr -d ':'
    [ "$output" = "443" ]

    run grep "cert:" "$config" | awk '{print $2}'
    [[ "$output" == *"fullchain.crt" ]]

    # Env file
    local env_file="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"
    [ -f "$env_file" ] || { echo "# easynet.env missing"; return 1; }
    grep -q "HYSTERIA2_DOMAIN" "$env_file"     || { echo "# HYSTERIA2_DOMAIN"; return 1; }
    grep -q "HYSTERIA2_PASSWORD" "$env_file"   || { echo "# HYSTERIA2_PASSWORD"; return 1; }
}

@test "Hysteria2 port hopping is enforced by the server listen range" {
    # Regression: the server config used to carry a `portHopping:` block, which is a
    # client-side option. The server ignored it entirely, so clients that hopped
    # were sent to ports nothing was listening on. The server must instead listen on
    # "<base>,<range>" -- hysteria then redirects the range to the base via nftables.
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    export HYSTERIA2_CONFIG_DIR="$TMP_DIR/hy2hop"
    export EASYNET_DOMAIN="proxy.example.com"
    export EASYNET_HYSTERIA2_PORT_HOPPING="20000-30000"
    source_protocol "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"

    run configure_hysteria2
    [ "$status" -eq 0 ]

    local config="${HYSTERIA2_CONFIG_FILE:-$HYSTERIA2_CONFIG_DIR/config.yaml}"
    run grep -c "^listen: :443,20000-30000$" "$config"
    [ "$output" = "1" ] || { echo "# listen line is: $(grep '^listen' "$config")" >&3; return 1; }

    # the client-only block must not be written into the server config
    run grep -c "portHopping:" "$config"
    [ "$output" = "0" ]
}

@test "Hysteria2 rejects a malformed port hopping range" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    export HYSTERIA2_CONFIG_DIR="$TMP_DIR/hy2bad"
    export EASYNET_DOMAIN="proxy.example.com"
    export EASYNET_HYSTERIA2_PORT_HOPPING="30000-20000"   # reversed
    source_protocol "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"

    run configure_hysteria2
    [ "$status" -eq 0 ]

    local config="${HYSTERIA2_CONFIG_FILE:-$HYSTERIA2_CONFIG_DIR/config.yaml}"
    run grep -c "^listen: :443$" "$config"
    [ "$output" = "1" ] || { echo "# listen line is: $(grep '^listen' "$config")" >&3; return 1; }

    local env_file="${HYSTERIA2_ENV_FILE:-$HYSTERIA2_CONFIG_DIR/easynet.env}"
    run grep -c "HYSTERIA2_PORT_HOPPING" "$env_file"
    [ "$output" = "0" ]
}

@test "Hysteria2 sandbox allows AF_NETLINK (needed for nft redirects)" {
    run grep -q 'AF_INET AF_INET6 AF_UNIX AF_NETLINK' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    [ "$status" -eq 0 ] || { echo "# port hopping dies without AF_NETLINK" >&3; return 1; }
}
