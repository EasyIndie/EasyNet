#!/bin/bash
# EasyNet test runner — delegates to bats
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "======================================"
echo "    Running All EasyNet Unit Tests    "
echo "======================================"

# Run bats on all .bats files in tests/
# --timing: show test duration
# --pretty: readable output
bats --timing --pretty "$DIR"/*.bats
