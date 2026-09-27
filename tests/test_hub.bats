#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    export EASYNET_HUB_DIR="$TMP_DIR/hub"
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    export EASYNET_EDGE_CERT_DIR="$TMP_DIR/certs"
    export EASYNET_EDGE_WEB_ROOT="$TMP_DIR/web"
    export EASYNET_ACME_HOME="$TMP_DIR/acme"
    export EASYNET_HUB_NO_PATH_LINK=1
    export HOME="$TMP_DIR/home"
    mkdir -p "$EASYNET_STATE_DIR" "$EASYNET_EDGE_CERT_DIR" "$EASYNET_EDGE_WEB_ROOT" \
        "$EASYNET_ACME_HOME" "$HOME"
}

teardown() {
    rm -rf "$TMP_DIR"
}

build_hub() {
    (cd "$PROJECT_ROOT" && bash -c '
        . scripts/core/env.sh
        . scripts/core/discovery.sh
        . scripts/core/logging.sh
        . scripts/core/hub.sh
        ensure_easynet_hub --quiet
    ')
}

@test "Every protocol manifest declares a config directory" {
    local module
    for module in xray-reality hysteria2 shadowsocks wireguard; do
        run rg -q '^MODULE_CONFIG_DIR="/' "$PROJECT_ROOT/scripts/protocols/$module/manifest.sh"
        [ "$status" -eq 0 ]
    done
    # Discovery must expose it (whitelist-protected accessor)
    run rg -q 'MODULE_CONFIG_DIR\)' "$PROJECT_ROOT/scripts/core/discovery.sh"
    [ "$status" -eq 0 ]
}

@test "Hub converges scattered paths into one directory" {
    build_hub
    [ -f "$EASYNET_HUB_DIR/README.md" ]
    [ -d "$EASYNET_HUB_DIR/logs" ]
    for link in easynet project state certs web acme logs; do
        [ -L "$EASYNET_HUB_DIR/$link" ] || [ -d "$EASYNET_HUB_DIR/$link" ]
    done
    # Per-protocol config dirs come from the manifests
    run rg -q 'configs/xray-reality' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
    run rg -q 'configs/hysteria2' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
}

@test "Hub index lists the real paths so operators know where files live" {
    build_hub
    # The generated index must show real (non-hub) targets for the protocol dirs
    run rg -q '/usr/local/etc/xray' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
    run rg -q '/etc/hysteria' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
    run rg -q '/etc/shadowsocks-rust' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
    run rg -q '/etc/amnezia/amneziawg' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
}

@test "Hub is idempotent and never clobbers real files or dirs" {
    build_hub
    # A real file where a symlink would go must be preserved
    rm -f "$EASYNET_HUB_DIR/certs"
    mkdir -p "$EASYNET_HUB_DIR/certs"
    printf 'user data\n' > "$EASYNET_HUB_DIR/certs/keep.txt"
    build_hub
    [ -f "$EASYNET_HUB_DIR/certs/keep.txt" ]
    [ ! -L "$EASYNET_HUB_DIR/certs" ]
    # Second run must still succeed and keep the index intact
    run rg -c '^| `' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
}

@test "Hub only links targets that exist" {
    # Remove the fake cert dir: the certs entry must be reported as not deployed
    rm -rf "$EASYNET_EDGE_CERT_DIR"
    build_hub
    [ ! -e "$EASYNET_HUB_DIR/certs" ]
    run rg -q '未部署' "$EASYNET_HUB_DIR/README.md"
    [ "$status" -eq 0 ]
}

@test "Hub is wired into the deploy and uninstall flows" {
    run rg -q 'ensure_easynet_hub' "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 0 ]
    run rg -q 'ensure_easynet_hub' "$PROJECT_ROOT/scripts/uninstall.sh"
    [ "$status" -eq 0 ]
}

@test "Hub does not perform destructive operations" {
    # It is pure convenience: only mkdir/ln, never rm/rm -rf/systemctl restart
    run rg -q 'rm -rf|systemctl (restart|stop)|ip link delete' "$PROJECT_ROOT/scripts/core/hub.sh"
    [ "$status" -eq 1 ]
}

@test "easynet CLI is executable and provides the documented commands" {
    [ -x "$PROJECT_ROOT/scripts/easynet" ]
    run bash "$PROJECT_ROOT/scripts/easynet" help
    [ "$status" -eq 0 ]
    for cmd in status where path config edit logs restart sub hub ssh doctor env version; do
        [[ "$output" == *"$cmd"* ]]
    done
}

@test "easynet CLI reports unknown commands with a non-zero status" {
    run bash "$PROJECT_ROOT/scripts/easynet" definitely-not-a-command
    [ "$status" -ne 0 ]
    [[ "$output" == *"未知命令"* ]]
}

@test "easynet CLI resolves a hub entry to its real path" {
    build_hub
    run bash "$PROJECT_ROOT/scripts/easynet" path project
    [ "$status" -eq 0 ]
    [ "$output" = "$PROJECT_ROOT" ]
}

@test "easynet CLI resolves itself when invoked through a symlink" {
    local bin="$TMP_DIR/bin"
    mkdir -p "$bin"
    ln -sf "$PROJECT_ROOT/scripts/easynet" "$bin/easynet"
    run "$bin/easynet" path project
    [ "$status" -eq 0 ]
    [ "$output" = "$PROJECT_ROOT" ]
}

@test "easynet deploy writes its log into the hub and refreshes the index" {
    run rg -q 'easynet_hub_logs_dir' "$PROJECT_ROOT/scripts/easynet"
    [ "$status" -eq 0 ]
    run rg -q 'latest.log' "$PROJECT_ROOT/scripts/easynet"
    [ "$status" -eq 0 ]
    run rg -q 'logs deploy' "$PROJECT_ROOT/scripts/easynet"
    [ "$status" -eq 0 ]
}

@test "easynet CLI maps service aliases to systemd units" {
    run bash -c '
        . "$1/scripts/core/env.sh"; . "$1/scripts/core/discovery.sh"
        . "$1/scripts/core/hub.sh"; . "$1/scripts/core/logging.sh"
        eval "$(sed -n "/^resolve_service()/,/^}/p" "$1/scripts/easynet")"
        resolve_service hysteria2; resolve_service ss; resolve_service wg
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "hysteria-server.service
shadowsocks-rust-server.service
awg-quick@wg0.service" ]
}
