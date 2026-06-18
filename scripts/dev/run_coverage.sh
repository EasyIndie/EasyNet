#!/bin/bash
# EasyNet Code Coverage Helper
#
# Usage: bash scripts/dev/run_coverage.sh [test_file ...]
#
# Prerequisites:
#   gem install bashcov  (or: sudo gem install bashcov)
#
# If bashcov is not available, falls back to running bats directly
# with timing output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
COVERAGE_DIR="$PROJECT_ROOT/coverage"

cd "$PROJECT_ROOT"

if command -v bashcov &>/dev/null; then
    echo "==> Running tests with bashcov coverage..."
    mkdir -p "$COVERAGE_DIR"

    if [ $# -gt 0 ]; then
        TEST_FILES=("$@")
    else
        TEST_FILES=(tests/*.bats)
    fi

    for test_file in "${TEST_FILES[@]}"; do
        echo "    Covering: $test_file"
        bashcov -- "$(command -v bats)" "$test_file" 2>/dev/null || true
    done

    # Merge coverage data (bashcov generates per-file results)
    echo "==> Coverage data written to:"
    ls -la "$COVERAGE_DIR/" 2>/dev/null || echo "    (check bashcov output directory)"
    echo "==> Coverage report generated."
else
    echo "==> bashcov not found. Run 'gem install bashcov' to install."
    echo "==> Falling back to bats without coverage."

    if [ $# -gt 0 ]; then
        bats --timing --pretty "$@"
    else
        bats --timing --pretty tests/*.bats
    fi

    echo ""
    echo "Hint: to measure code coverage, install bashcov:"
    echo "  sudo gem install bashcov"
    echo "  brew install bashcov  # on macOS"
fi
