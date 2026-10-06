#!/usr/bin/env bats
# bats file_tags=network
# Download URL + pin integrity tests
#
# EasyNet installs every dependency from a pinned release asset in
# scripts/core/pins.sh. A 404 or a hash mismatch here means deployment will fail
# on a real VPS (or worse, that we would install unverified bytes).
#
# Note: These tests require network access and are skipped when it is unavailable.
# CI runs them with network.

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/core/crypto.sh"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/core/pins.sh"
}

# Connect timeout (seconds) to avoid hanging on slow/broken networks
TIMEOUT=10

# Helper: check if a URL returns a successful HTTP status (2xx or 3xx)
# Retries once on failure to handle transient network issues.
# Uses HEAD so reachability does not download the whole ~20MB release asset
# (`-o /dev/null` with GET still transfers the body). Falls back to a 1-byte
# Range GET for servers that reject HEAD. Usage: url_ok <url>
url_ok() {
    local url="$1"
    local code
    local attempt
    for attempt in 1 2; do
        code=$(curl -fsSIL -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" --max-time 15 "$url" 2>/dev/null || echo "000")
        case "$code" in
            2* | 3*) return 0 ;;
        esac
        code=$(curl -fsSL -o /dev/null -w "%{http_code}" -H "Range: bytes=0-0" --connect-timeout "$TIMEOUT" --max-time 15 "$url" 2>/dev/null || echo "000")
        if [ "$code" != "000" ] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
            return 0
        fi
        [ "$attempt" = 1 ] && sleep 3
    done
    return 1
}

# Helper: verify the remote artifact really hashes to the pinned value
# Usage: pinned_artifact_ok <url> <expected_sha256>
pinned_artifact_ok() {
    local url="$1" expected="$2"
    local actual
    actual=$(curl -fsSL --connect-timeout "$TIMEOUT" --max-time 120 "$url" 2>/dev/null | sha256sum | awk '{print $1}')
    [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

# Helper: skip test if network is unavailable
check_network() {
    if ! curl -fsS --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        skip "网络不可用，跳过 URL 探活测试"
    fi
}

# ============================================================
# Pin table sanity (no network)
# ============================================================

@test "pins.sh exposes a version and SHA256 for every component" {
    for component in xray hysteria2 shadowsocks acme; do
        local pin version sha
        pin="$(easynet_resolve_pin "$component")" || return 1
        version="${pin%%|*}"
        sha="${pin#*|}"
        [ -n "$version" ] || return 1
        case "$sha" in
            [0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
                [ "${#sha}" -eq 64 ] || return 1
                ;;
            *) # acme resolves on every arch; others need a supported arch
                [ "$component" = "acme" ] && continue
                skip "当前架构 ($(detect_arch)) 无 pin"
                ;;
        esac
    done
}

@test "overriding a version without a checksum is refused" {
    run env EASYNET_XRAY_VERSION=99.99.99 bash -c "
        . '$PROJECT_ROOT/scripts/core/logging.sh'
        . '$PROJECT_ROOT/scripts/core/crypto.sh'
        . '$PROJECT_ROOT/scripts/core/pins.sh'
        easynet_resolve_pin xray
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"无法校验"* ]]
    # ... unless explicitly allowed
    run env EASYNET_XRAY_VERSION=99.99.99 EASYNET_ALLOW_UNPINNED=1 bash -c "
        . '$PROJECT_ROOT/scripts/core/logging.sh'
        . '$PROJECT_ROOT/scripts/core/crypto.sh'
        . '$PROJECT_ROOT/scripts/core/pins.sh'
        easynet_resolve_pin xray
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"99.99.99|"* ]]
}

# ============================================================
# Xray
# ============================================================

@test "Xray pinned release asset URL 可达" {
    check_network
    local asset
    asset="$(easynet_pin_asset xray)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    url_ok "https://github.com/XTLS/Xray-core/releases/download/v${EASYNET_PIN_XRAY_VERSION}/${asset}"
}

@test "Xray pinned SHA256 matches the published .dgst" {
    check_network
    local asset digest
    asset="$(easynet_pin_asset xray)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    digest=$(curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout "$TIMEOUT" --max-time 30 \
        "https://github.com/XTLS/Xray-core/releases/download/v${EASYNET_PIN_XRAY_VERSION}/${asset}.dgst" 2>/dev/null |
        awk -F'= ' '/SHA2-256/{print $2}')
    [ -n "$digest" ]
    [ "$digest" = "$(easynet_pin_sha256 xray)" ]
}

# ============================================================
# Hysteria2
# ============================================================

@test "Hysteria2 pinned release asset URL 可达" {
    check_network
    local asset
    asset="$(easynet_pin_asset hysteria2)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    url_ok "https://github.com/apernet/hysteria/releases/download/app/v${EASYNET_PIN_HYSTERIA2_VERSION}/${asset}"
}

@test "Hysteria2 pinned SHA256 matches the published hashes.txt" {
    check_network
    local asset expected
    asset="$(easynet_pin_asset hysteria2)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    expected=$(curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout "$TIMEOUT" --max-time 30 \
        "https://github.com/apernet/hysteria/releases/download/app/v${EASYNET_PIN_HYSTERIA2_VERSION}/hashes.txt" 2>/dev/null |
        awk -v a="build/$asset" '$2 == a {print $1}')
    [ -n "$expected" ]
    [ "$expected" = "$(easynet_pin_sha256 hysteria2)" ]
}

# ============================================================
# Shadowsocks
# ============================================================

@test "Shadowsocks pinned release asset URL 可达" {
    check_network
    local asset
    asset="$(easynet_pin_asset shadowsocks)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    url_ok "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${EASYNET_PIN_SHADOWSOCKS_VERSION}/${asset}"
}

@test "Shadowsocks pinned SHA256 matches the published .sha256" {
    check_network
    local asset expected
    asset="$(easynet_pin_asset shadowsocks)"
    [ -n "$asset" ] || skip "当前架构无 pin"
    expected=$(curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout "$TIMEOUT" --max-time 30 \
        "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${EASYNET_PIN_SHADOWSOCKS_VERSION}/${asset}.sha256" 2>/dev/null |
        awk '{print $1}')
    [ -n "$expected" ]
    [ "$expected" = "$(easynet_pin_sha256 shadowsocks)" ]
}

# ============================================================
# acme.sh (Edge Gateway TLS)
# ============================================================

@test "acme.sh installer URL 可达" {
    check_network
    url_ok "https://get.acme.sh"
}

# ============================================================
# Self-managed installs (no third-party install scripts)
# ============================================================

@test "protocol installs do not run third-party install scripts" {
    # get.hy2.sh / Xray-install / install-release.sh were unpinned, moving targets
    # executed as root. They must not come back.
    run rg -q 'https://get\.hy2\.sh|raw\.githubusercontent\.com/XTLS/Xray-install|install-release\.sh' \
        "$PROJECT_ROOT/scripts/protocols" "$PROJECT_ROOT/scripts/exposure"
    [ "$status" -eq 1 ]
}

@test "install functions use the pinned resolver and verify the hash" {
    for f in xray-reality hysteria2 shadowsocks; do
        run rg -q 'easynet_resolve_pin ' "$PROJECT_ROOT/scripts/protocols/$f/deploy.sh"
        [ "$status" -eq 0 ]
        # hash passed to download_file / download helper
        run rg -q 'download_file "\$url"|download_file "\$url" ' "$PROJECT_ROOT/scripts/protocols/$f/deploy.sh"
        [ "$status" -eq 0 ]
    done
    run rg -q 'easynet_resolve_pin acme' "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "what we install ourselves, we also own (systemd unit)" {
    run rg -q 'write_xray_systemd_unit' "$PROJECT_ROOT/scripts/protocols/xray-reality/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q 'write_hysteria2_systemd_unit' "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q 'useradd --system --no-create-home --shell /usr/sbin/nologin hysteria' \
        "$PROJECT_ROOT/scripts/protocols/hysteria2/deploy.sh"
    [ "$status" -eq 0 ]
}

@test "a replaced binary forces a service restart" {
    # Installing a new binary without restarting leaves the old image running.
    for pair in "xray-reality:XRAY_BINARY_CHANGED" "hysteria2:HYSTERIA2_BINARY_CHANGED" "shadowsocks:SS_BINARY_CHANGED"; do
        local f="${pair%%:*}" flag="${pair##*:}"
        run rg -q "$flag=true" "$PROJECT_ROOT/scripts/protocols/$f/deploy.sh"
        [ "$status" -eq 0 ]
    done
}
