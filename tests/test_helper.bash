#!/bin/bash

# Simple testing framework for Bash
# Usage:
#   source test_helper.bash
#   test_start "Feature name"
#   
#   assert_equals "expected" "actual" "Test description"
#   assert_not_empty "actual" "Test description"
#   
#   test_end

TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_start() {
    echo -e "${YELLOW}=== Running Tests: $1 ===${NC}"
}

test_end() {
    echo -e "\n${YELLOW}=== Test Summary ===${NC}"
    echo "Total: $TEST_COUNT"
    echo -e "Passed: ${GREEN}$TEST_PASSED${NC}"
    
    if [ "$TEST_FAILED" -gt 0 ]; then
        echo -e "Failed: ${RED}$TEST_FAILED${NC}"
        exit 1
    else
        echo -e "Failed: 0"
        exit 0
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    
    ((TEST_COUNT++))
    
    if [ "$expected" == "$actual" ]; then
        ((TEST_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $desc"
    else
        ((TEST_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $desc"
        echo -e "  Expected: '$expected'"
        echo -e "  Actual:   '$actual'"
    fi
}

assert_not_empty() {
    local actual="$1"
    local desc="$2"
    
    ((TEST_COUNT++))
    
    if [ -n "$actual" ]; then
        ((TEST_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: $desc"
    else
        ((TEST_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: $desc"
        echo -e "  Expected: Not empty"
        echo -e "  Actual:   Empty"
    fi
}
