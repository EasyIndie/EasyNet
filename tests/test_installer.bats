#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export INSTALLER="$PROJECT_ROOT/scripts/install.sh"

    # sha256sum is guaranteed on Ubuntu/Debian (CI + target), but macOS dev
    # machines only ship shasum. Provide a shim so functional tests run locally.
    if ! command -v sha256sum >/dev/null 2>&1 && command -v shasum >/dev/null 2>&1; then
        SHIM_DIR="$(mktemp -d /tmp/easynet-sha256shim.XXXXXX)"
        cat > "$SHIM_DIR/sha256sum" <<'SHIM'
#!/bin/bash
if [ "${1:-}" = "-c" ]; then
    exec shasum -a 256 -c "$2"
fi
exec shasum -a 256 "$@"
SHIM
        chmod +x "$SHIM_DIR/sha256sum"
        export PATH="$SHIM_DIR:$PATH"
    fi
}

teardown() {
    [ -n "${SHIM_DIR:-}" ] && rm -rf "$SHIM_DIR"
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    return 0
}

# Build a fake release package at <release_dir>/ with an executable stub
# scripts/deploy.sh plus a sha256sum -c compatible checksum file.
build_fake_release() {
    local release_dir="$1"
    local pkg_dir="$release_dir/pkg"

    mkdir -p "$pkg_dir/scripts"
    printf '#!/bin/bash\necho DEPLOY_STUB "$@"\n' > "$pkg_dir/scripts/deploy.sh"
    chmod +x "$pkg_dir/scripts/deploy.sh"
    tar czf "$release_dir/easynet.tar.gz" -C "$pkg_dir" scripts
    (cd "$release_dir" && sha256sum easynet.tar.gz > easynet.tar.gz.sha256)
}

# -- Static analysis --

@test "Installer has an entrypoint guard so functions can be sourced by tests" {
    run rg -q 'BASH_SOURCE\[0\].*==.*\$0' "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer verifies SHA256 and fails closed on a missing checksum" {
    run rg -q "sha256sum -c" "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q "校验文件缺失或为空" "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer downloads into a temporary directory and never pipes curl to bash" {
    run rg -q "mktemp -d" "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q "curl[^|]*\|[[:space:]]*bash|wget[^|]*\|[[:space:]]*bash" "$INSTALLER"
    [ "$status" -eq 1 ]
}

@test "Installer preserves an existing .env on reinstall" {
    run rg -q "保留现有配置" "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q 'cp "\$INSTALL_DIR/.env"' "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer delegates to scripts/deploy.sh and forwards arguments" {
    run rg -q 'exec bash "\$INSTALL_DIR/scripts/deploy.sh" "\$@"' "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer supports version pinning and install dir override" {
    run rg -q "EASYNET_VERSION" "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q "EASYNET_INSTALL_DIR" "$INSTALLER"
    [ "$status" -eq 0 ]
    run rg -q "EASYNET_SKIP_SHA256" "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "Installer supports install-only mode to skip deployment" {
    run rg -q 'EASYNET_INSTALL_ONLY' "$INSTALLER"
    [ "$status" -eq 0 ]
}

# -- Functional --

@test "Installer prints usage on --help without touching the system" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"EasyNet 自举安装器"* ]]
}

@test "Installer builds latest and pinned release URLs" {
    run env EASYNET_RELEASE_BASE_URL="https://example.com/releases" EASYNET_VERSION="latest" \
        bash -c "source \"$INSTALLER\"; release_url easynet.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com/releases/latest/download/easynet.tar.gz" ]

    run env EASYNET_RELEASE_BASE_URL="https://example.com/releases" EASYNET_VERSION="0.0.8" \
        bash -c "source \"$INSTALLER\"; release_url easynet.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com/releases/download/0.0.8/easynet.tar.gz" ]
}

@test "Installer release version is not clobbered by os-release VERSION" {
    run env EASYNET_VERSION="test" bash -c '
        source "$1"
        if [ -f /etc/os-release ]; then . /etc/os-release; fi
        release_url easynet.tar.gz
    ' _ "$INSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/download/test/easynet.tar.gz" ]]
}

@test "Installer keeps release version after check_os reads os-release" {
    [ -f /etc/os-release ] || skip "no /etc/os-release on this platform"
    run env EASYNET_VERSION="test" bash -c '
        source "$1"
        check_os >/dev/null 2>&1
        release_url easynet.tar.gz
    ' _ "$INSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/download/test/easynet.tar.gz" ]]
}

@test "Installer downloads, verifies and installs the package to EASYNET_INSTALL_DIR" {
    TMP_DIR="$(mktemp -d /tmp/easynet-installer-test.XXXXXX)"
    release="$TMP_DIR/release/download/test"
    mkdir -p "$release"
    build_fake_release "$release"
    target="$TMP_DIR/target"

    run env \
        EASYNET_RELEASE_BASE_URL="file://$TMP_DIR/release" \
        EASYNET_VERSION="test" \
        EASYNET_INSTALL_DIR="$target" \
        bash -c "source \"$INSTALLER\"; work=\$(mktemp -d); install_package \"\$work\"; rm -rf \"\$work\""
    [ "$status" -eq 0 ]
    [ -x "$target/scripts/deploy.sh" ]

    # a release tarball carries no .git, so the installer records the version
    [ -f "$target/VERSION" ]
    [ "$(cat "$target/VERSION")" = "test" ]

    run "$target/scripts/deploy.sh" hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOY_STUB hello"* ]]
}

@test "Installer aborts and leaves no install when SHA256 does not match" {
    TMP_DIR="$(mktemp -d /tmp/easynet-installer-test.XXXXXX)"
    release="$TMP_DIR/release/download/test"
    mkdir -p "$release"
    build_fake_release "$release"
    printf 'deadbeef  easynet.tar.gz\n' > "$release/easynet.tar.gz.sha256"
    target="$TMP_DIR/target"

    run env \
        EASYNET_RELEASE_BASE_URL="file://$TMP_DIR/release" \
        EASYNET_VERSION="test" \
        EASYNET_INSTALL_DIR="$target" \
        bash -c "source \"$INSTALLER\"; work=\$(mktemp -d); install_package \"\$work\""
    [ "$status" -ne 0 ]
    [ ! -e "$target/scripts/deploy.sh" ]
}

@test "Installer can skip checksum verification explicitly" {
    TMP_DIR="$(mktemp -d /tmp/easynet-installer-test.XXXXXX)"
    release="$TMP_DIR/release/download/test"
    pkg="$TMP_DIR/pkg"
    mkdir -p "$release" "$pkg/scripts"
    printf '#!/bin/bash\necho ok\n' > "$pkg/scripts/deploy.sh"
    chmod +x "$pkg/scripts/deploy.sh"
    tar czf "$release/easynet.tar.gz" -C "$pkg" scripts

    run env \
        EASYNET_RELEASE_BASE_URL="file://$TMP_DIR/release" \
        EASYNET_VERSION="test" \
        EASYNET_SKIP_SHA256="true" \
        EASYNET_INSTALL_DIR="$TMP_DIR/target" \
        bash -c "source \"$INSTALLER\"; work=\$(mktemp -d); install_package \"\$work\"; rm -rf \"\$work\""
    [ "$status" -eq 0 ]
    [ -x "$TMP_DIR/target/scripts/deploy.sh" ]
}

@test "Installer preserves an existing .env across reinstall" {
    TMP_DIR="$(mktemp -d /tmp/easynet-installer-test.XXXXXX)"
    release="$TMP_DIR/release/download/test"
    mkdir -p "$release"
    build_fake_release "$release"
    target="$TMP_DIR/target"
    mkdir -p "$target"
    printf 'EASYNET_PROFILE=balanced\n' > "$target/.env"

    run env \
        EASYNET_RELEASE_BASE_URL="file://$TMP_DIR/release" \
        EASYNET_VERSION="test" \
        EASYNET_INSTALL_DIR="$target" \
        bash -c "source \"$INSTALLER\"; work=\$(mktemp -d); install_package \"\$work\"; rm -rf \"\$work\""
    [ "$status" -eq 0 ]
    [ "$(cat "$target/.env")" = "EASYNET_PROFILE=balanced" ]
}
