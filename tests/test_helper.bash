# BATS-compatible test helper for EasyNet
# Provides assert_equals for migration compatibility.
# New tests should use native bats assertions: [ "$a" = "$b" ]
#
# Usage in .bats files:
#   load test_helper

assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-}"
    if [ "$expected" != "$actual" ]; then
        echo "# FAIL: $desc" >&3
        echo "#   expected: '$expected'" >&3
        echo "#   actual:   '$actual'" >&3
        return 1
    fi
}

assert_not_empty() {
    local actual="$1"
    local desc="${2:-}"
    if [ -z "$actual" ]; then
        echo "# FAIL: $desc" >&3
        echo "#   Expected: not empty" >&3
        echo "#   Actual:   empty" >&3
        return 1
    fi
}
