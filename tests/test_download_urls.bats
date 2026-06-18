#!/usr/bin/env bats
# Download URL reachability tests
#
# Verify that all protocol install scripts and dependencies can be
# downloaded from their respective URLs. A 404 here means deployment
# will fail on a real VPS.
#
# Note: These tests require network access and will be skipped
# if the network is unavailable. CI runs these with network.

load test_helper

# Set connect timeout (seconds) to avoid hanging on slow/broken networks
TIMEOUT=10

# Helper: check if a URL returns a successful HTTP status (2xx or 3xx)
# Retries once on failure to handle transient network issues.
# Usage: url_ok <url>
url_ok() {
    local url="$1"
    local code
    local attempt
    for attempt in 1 2; do
        code=$(curl -fsSL -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" --max-time 15 "$url" 2>/dev/null || echo "000")
        if [ "$code" != "000" ] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
            return 0
        fi
        [ "$attempt" = 1 ] && sleep 3
    done
    return 1
}

# Helper: skip test if network is unavailable
check_network() {
    if ! curl -fsS --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        skip "网络不可用，跳过 URL 探活测试"
    fi
}

# ============================================================
# Xray
# ============================================================

@test "Xray install-release.sh URL 可达" {
    check_network
    url_ok "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh"
}

# ============================================================
# Hysteria2
# ============================================================

@test "Hysteria2 get.hy2.sh URL 可达" {
    check_network
    url_ok "https://get.hy2.sh/"
}

# ============================================================
# Shadowsocks
# ============================================================

@test "Shadowsocks release page (v1.24.0) URL 可达" {
    check_network
    url_ok "https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.24.0"
}

@test "Shadowsocks binary (x86_64) URL 可达" {
    check_network
    url_ok "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.24.0/shadowsocks-v1.24.0.x86_64-unknown-linux-gnu.tar.xz"
}

@test "Shadowsocks binary (aarch64) URL 可达" {
    check_network
    url_ok "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.24.0/shadowsocks-v1.24.0.aarch64-unknown-linux-gnu.tar.xz"
}

# ============================================================
# acme.sh (Edge Gateway TLS)
# ============================================================

@test "acme.sh installer URL 可达" {
    check_network
    url_ok "https://get.acme.sh"
}
