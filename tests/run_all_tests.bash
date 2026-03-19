#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "======================================"
echo "    Running All EasyNet Unit Tests    "
echo "======================================"

FAILURES=0

for test_script in "$DIR"/test_*.bash; do
    if [ "$(basename "$test_script")" == "test_helper.bash" ]; then
        continue
    fi
    
    echo ""
    echo "Running $test_script..."
    if ! bash "$test_script"; then
        FAILURES=$((FAILURES + 1))
    fi
done

echo ""
echo "======================================"
if [ "$FAILURES" -gt 0 ]; then
    echo -e "\033[0;31m✗ $FAILURES test suite(s) failed.\033[0m"
    exit 1
else
    echo -e "\033[0;32m✓ All test suites passed successfully.\033[0m"
    exit 0
fi
