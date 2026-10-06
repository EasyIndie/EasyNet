#!/usr/bin/env bats

load test_helper

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    source "$PROJECT_ROOT/scripts/core/crypto.sh"
}

@test "architecture names normalize to canonical server architecture values" {
    uname() { printf '%s\n' "$ARCH_FIXTURE"; }

    ARCH_FIXTURE=x86_64
    [ "$(detect_arch)" = x86_64 ]
    ARCH_FIXTURE=amd64
    [ "$(detect_arch)" = x86_64 ]
    ARCH_FIXTURE=aarch64
    [ "$(detect_arch)" = aarch64 ]
    ARCH_FIXTURE=arm64
    [ "$(detect_arch)" = aarch64 ]
}

@test "ARMv7 and ARMv6 architecture target branches are represented" {
    uname() { printf '%s\n' "$ARCH_FIXTURE"; }

    ARCH_FIXTURE=armv7l
    [ "$(detect_arch)" = armv7l ]
    [ "$(detect_rust_target)" = armv7-unknown-linux-gnueabihf ]
    [ "$(detect_go_arch)" = linux-armv7 ]
    ARCH_FIXTURE=armv6l
    [ "$(detect_arch)" = armv6l ]
    [ "$(detect_rust_target)" = unknown ]
    [ "$(detect_go_arch)" = linux-armv6 ]
}

@test "unknown architecture remains unknown and has no Rust target" {
    uname() { printf '%s\n' "$ARCH_FIXTURE"; }
    ARCH_FIXTURE=riscv64

    [ "$(detect_arch)" = unknown ]
    [ "$(detect_rust_target)" = unknown ]
}

@test "sourcing deploy entrypoint in a non-root subshell does not invoke main" {
    if [ "$EUID" -eq 0 ]; then
        skip "safe observable source check requires non-root; sourcing as root could bootstrap if the entry guard regresses"
    fi

    run bash -c 'source "$1"' _ "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "check_root rejects a non-root invocation" {
    if [ "$EUID" -eq 0 ]; then
        skip "non-root check_root branch requires a non-root test process"
    fi
    run bash -c 'source "$1"; check_root' _ "$PROJECT_ROOT/scripts/deploy.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"请使用 root 权限运行此脚本"* ]]
}
