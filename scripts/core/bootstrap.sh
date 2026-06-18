#!/bin/bash
# EasyNet Bootstrap Module
# System initialization: package updates, dependencies, kernel tuning, security.
# Source this file, then call:
#   bootstrap_system
#   bootstrap_security

EASYNET_BOOTSTRAP_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_BOOTSTRAP_CORE_DIR/logging.sh"
source "$EASYNET_BOOTSTRAP_CORE_DIR/firewall.sh"
source "$EASYNET_BOOTSTRAP_CORE_DIR/maintenance.sh"
source "$EASYNET_BOOTSTRAP_CORE_DIR/cron.sh"

bootstrap_system() {
    update_system
    install_dependencies
    enable_bbr
}

bootstrap_security() {
    setup_firewall
    setup_auto_update
    setup_cron_jobs
}
