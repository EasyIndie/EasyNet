#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/test_helper.bash"

test_start "Path Generation and Fallback Logic"

# Test 1: Random path generation using urandom
# Equivalent to: head -c 4 /dev/urandom | xxd -p | awk '{print "/"$1}'
generate_random_path() {
    head -c 4 /dev/urandom | xxd -p | awk '{print "/"$1}'
}

path1=$(generate_random_path)
path2=$(generate_random_path)

# Verify paths start with /
assert_equals "/" "${path1:0:1}" "Generated path starts with /"

# Verify path length is 9 (1 for '/' + 8 hex chars)
assert_equals "9" "${#path1}" "Generated path has correct length"

# Verify paths are random (should not match)
if [ "$path1" != "$path2" ]; then
    assert_equals "true" "true" "Generated paths are randomly unique"
else
    assert_equals "true" "false" "Generated paths are randomly unique"
fi

# Test 2: Fallback Logic simulation
# Simulate the logic of replacing default /default-path with a secure random path
simulate_path_recovery() {
    local current_path="$1"
    
    if [ "$current_path" == "/default-path" ] || [ -z "$current_path" ]; then
        generate_random_path
    else
        echo "$current_path"
    fi
}

recovered_path=$(simulate_path_recovery "/default-path")
if [ "$recovered_path" != "/default-path" ] && [[ "$recovered_path" == /* ]]; then
    assert_equals "true" "true" "Default path /default-path is replaced with secure path"
else
    assert_equals "true" "false" "Default path /default-path is replaced with secure path"
fi

valid_path="/a6d31173"
kept_path=$(simulate_path_recovery "$valid_path")
assert_equals "$valid_path" "$kept_path" "Valid custom path is preserved"

empty_path_recovery=$(simulate_path_recovery "")
if [ -n "$empty_path_recovery" ] && [[ "$empty_path_recovery" == /* ]]; then
    assert_equals "true" "true" "Empty path is replaced with secure path"
else
    assert_equals "true" "false" "Empty path is replaced with secure path"
fi

test_end
