#!/bin/bash
# EasyNet Network Module
# Network helper functions: public IP detection, DNS resolution.
# Source this file, then call:
#   get_public_ip

get_public_ip() {
    if [ -n "${EASYNET_PUBLIC_IP:-}" ]; then
        echo "$EASYNET_PUBLIC_IP"
        return
    fi
    curl -s https://ipinfo.io/ip || curl -s https://ifconfig.me || curl -s https://api.ipify.org
}
