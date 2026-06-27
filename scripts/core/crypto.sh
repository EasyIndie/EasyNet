#!/bin/bash
# EasyNet Crypto Module
# Cryptographic helpers: secure random generation, UUID, arch detection.
# Source this file, then call:
#   generate_uuid
#   generate_psk
#   random_secret
#   detect_arch          -> "x86_64" | "aarch64" | "armv7l"

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

generate_psk() {
    # 2022-blake3-aes-256-gcm uses a 32-byte key
    openssl rand -base64 32
}

random_secret() {
    # 256-bit (32 bytes) random secret — used by Hysteria2 for password & obfs password
    openssl rand -hex 32
}

# Normalize architecture name: returns "x86_64" | "aarch64" | "armv7l" | "unknown"
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)       echo "x86_64" ;;
        aarch64|arm64)      echo "aarch64" ;;
        armv7l|armv7*)      echo "armv7l" ;;
        armv6l|armv6*)      echo "armv6l" ;;
        *)                  echo "unknown" ;;
    esac
}

# Rust-style architecture target (for shadowsocks-rust binary downloads)
detect_rust_target() {
    local arch
    arch=$(detect_arch)
    case "$arch" in
        x86_64)  echo "x86_64-unknown-linux-gnu" ;;
        aarch64) echo "aarch64-unknown-linux-gnu" ;;
        armv7l)  echo "armv7-unknown-linux-gnueabihf" ;;
        *)       echo "unknown" ;;
    esac
}

# Go-style architecture target (for sing-box binary downloads)
detect_go_arch() {
    local arch
    arch=$(detect_arch)
    case "$arch" in
        x86_64)  echo "linux-amd64" ;;
        aarch64) echo "linux-arm64" ;;
        armv7l)  echo "linux-armv7" ;;
        armv6l)  echo "linux-armv6" ;;
        *)       echo "unknown" ;;
    esac
}
