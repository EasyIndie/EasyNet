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

# ============================================================
# Extended helpers for config syntax and error-handling tests
# ============================================================

# Source a script and run a function, capturing its stdout, stderr
# and exit status in bats-friendly globals:
#   $output   — combined stdout+stderr
#   $status   — exit code
# Usage:
#   run_function "path/to/script.sh" "function_name" "arg1" "arg2"
run_function() {
    local script="$1"
    local func="$2"
    shift 2
    local rc=0
    local out_file err_file
    out_file=$(mktemp /tmp/easynet-test-stdout.XXXXXX)
    err_file=$(mktemp /tmp/easynet-test-stderr.XXXXXX)

    # Source in a subshell so we don't pollute the test environment
    (
        # shellcheck disable=SC1090  # dynamic path per call
        source "$script" >"$out_file" 2>"$err_file"
        "$func" "$@" >>"$out_file" 2>>"$err_file"
    ) && rc=0 || rc=$?

    # shellcheck disable=SC2034  # used by calling test assertions (bats-compat)
    output="$(cat "$out_file" 2>/dev/null; cat "$err_file" 2>/dev/null)"
    # shellcheck disable=SC2034  # used by calling test assertions (bats-compat)
    status=$rc
    rm -f "$out_file" "$err_file"
}

# Assert that a file contains the given extended regex pattern.
# Optionally specify a description message.
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local desc="${3:-}"

    if [ ! -f "$file" ]; then
        echo "# FAIL: $desc — file not found: $file" >&3
        return 1
    fi

    if ! grep -qE "$pattern" "$file"; then
        echo "# FAIL: $desc" >&3
        echo "#   file: $file" >&3
        echo "#   pattern: $pattern" >&3
        echo "#   content:" >&3
        sed 's/^/#     /' "$file" >&3
        return 1
    fi
}

# Assert that a file does NOT contain the given extended regex pattern.
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local desc="${3:-}"

    if [ ! -f "$file" ]; then
        return 0  # missing file trivially does not contain pattern
    fi

    if grep -qE "$pattern" "$file"; then
        echo "# FAIL: $desc" >&3
        echo "#   file: $file" >&3
        echo "#   pattern: $pattern (should NOT be present)" >&3
        echo "#   matched line:" >&3
        grep -nE "$pattern" "$file" | sed 's/^/#     /' >&3
        return 1
    fi
}

# Create a fake executable command in a temporary directory.
# The fake script:
#   - writes its args to a "call_log" file (one line per invocation)
#   - returns the given exit code (default 0)
#   - optionally prints the given stdout (default empty)
# Usage:
#   FAKE_DIR=$(mktemp -d)
#   create_fake_command "$FAKE_DIR" "systemctl" 0 "ran ok"
#   PATH="$FAKE_DIR:$PATH" systemctl restart myservice
#   # call_log at "$FAKE_DIR/systemctl.call_log" contains invocation record
create_fake_command() {
    local dir="$1"
    local name="$2"
    local exit_code="${3:-0}"
    local stdout_text="${4:-}"

    cat > "$dir/$name" <<'FAKE_SCRIPT'
#!/bin/bash
LOG="$(dirname "$0")/'"$name"'.call_log"
echo "$(basename "$0") $*" >> "$LOG"
FAKE_SCRIPT
    if [ -n "$stdout_text" ]; then
        printf '%s\n' "echo '$stdout_text'" >> "$dir/$name"
    fi
    printf 'exit %d\n' "$exit_code" >> "$dir/$name"
    chmod +x "$dir/$name"
}

# Read the call log created by create_fake_command.
# Returns empty string if no calls were made.
read_fake_calls() {
    local dir="$1"
    local name="$2"
    local log_file="$dir/$name.call_log"
    if [ -f "$log_file" ]; then
        cat "$log_file"
    fi
}

# Reset a fake command's call log (for test isolation).
reset_fake_calls() {
    local dir="$1"
    local name="$2"
    rm -f "$dir/$name.call_log"
}
