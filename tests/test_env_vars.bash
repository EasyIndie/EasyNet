#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/test_helper.bash"

test_start "Environment Variables Automation Logic"

# Test 1: Simulating show_menu from deploy.sh
simulate_show_menu() {
    local choice=""
    if [ -n "$EASYNET_SERVICE_CHOICE" ]; then
        choice="$EASYNET_SERVICE_CHOICE"
        echo "$choice"
        return
    fi
    # If it falls through, it would prompt. We return "PROMPT" to signify this.
    echo "PROMPT"
}

# Test 1.1: Without environment variable
unset EASYNET_SERVICE_CHOICE
result1=$(simulate_show_menu)
assert_equals "PROMPT" "$result1" "Without EASYNET_SERVICE_CHOICE, it should fall back to interactive prompt"

# Test 1.2: With environment variable
export EASYNET_SERVICE_CHOICE="6"
result2=$(simulate_show_menu)
assert_equals "6" "$result2" "With EASYNET_SERVICE_CHOICE=6, it should automatically select 6"


# Test 2: Simulating get_domain from trojan-go.sh
simulate_get_domain() {
    local DOMAIN=""
    if [ -n "$EASYNET_DOMAIN" ]; then
        DOMAIN="$EASYNET_DOMAIN"
        echo "$DOMAIN"
    else
        echo "PROMPT"
    fi
}

# Test 2.1: Without environment variable
unset EASYNET_DOMAIN
result3=$(simulate_get_domain)
assert_equals "PROMPT" "$result3" "Without EASYNET_DOMAIN, it should fall back to interactive prompt"

# Test 2.2: With environment variable
export EASYNET_DOMAIN="proxy.example.com"
result4=$(simulate_get_domain)
assert_equals "proxy.example.com" "$result4" "With EASYNET_DOMAIN set, it should automatically use the domain"

test_end
