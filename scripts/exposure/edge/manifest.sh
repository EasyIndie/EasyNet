#!/bin/bash
# EasyNet exposure manifest - sourced by orchestrators
# Declares the Edge Gateway (Nginx + acme.sh + subscription host) as
# a discoverable uninstallable module, eliminating hardcoded special
# treatment in uninstall.sh.

MANIFEST_VERSION=1
MODULE_NAME="edge"
MODULE_DISPLAY_NAME="Edge Gateway"
MODULE_TYPE="exposure"
