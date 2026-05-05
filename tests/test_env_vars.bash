#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/test_helper.bash"
source "$PROJECT_ROOT/scripts/deploy.sh"

test_start "Environment Variables Automation Logic"

# Test 1: environment selection branches from deploy.sh
run_env_selection_for_test() {
    choice=""
    if ! select_from_env >/dev/null; then
        echo "PROMPT"
        return
    fi
    echo "$choice"
}

# Test 1.1: Without environment variable
unset EASYNET_SERVICE_CHOICE
unset EASYNET_MODULE
unset EASYNET_PROFILE
result1=$(run_env_selection_for_test)
assert_equals "PROMPT" "$result1" "Without EASYNET_SERVICE_CHOICE, it should fall back to interactive prompt"

# Test 1.2: With environment variable
export EASYNET_SERVICE_CHOICE="0"
unset EASYNET_MODULE
unset EASYNET_PROFILE
result2=$(run_env_selection_for_test)
assert_equals "0" "$result2" "With EASYNET_SERVICE_CHOICE=0, it should automatically select all modules"

# Test 1.3: With module environment variable
unset EASYNET_SERVICE_CHOICE
unset EASYNET_PROFILE
export EASYNET_MODULE="xray-reality"
result_module=$(run_env_selection_for_test)
assert_equals "xray-reality" "$result_module" "With EASYNET_MODULE=xray-reality, it should select Xray Reality"

export EASYNET_MODULE="wireguard"
result_wireguard_module=$(run_env_selection_for_test)
assert_equals "wireguard" "$result_wireguard_module" "With EASYNET_MODULE=wireguard, it should select WireGuard"

export EASYNET_MODULE="trojan-go"
result_trojan_module=$(run_env_selection_for_test)
assert_equals "trojan-go" "$result_trojan_module" "With EASYNET_MODULE=trojan-go, it should select Trojan-Go"

export EASYNET_MODULE="v2ray"
result_v2ray_module=$(run_env_selection_for_test)
assert_equals "v2ray" "$result_v2ray_module" "With EASYNET_MODULE=v2ray, it should select V2Ray"

export EASYNET_MODULE="hysteria2"
result_hysteria2_module=$(run_env_selection_for_test)
assert_equals "hysteria2" "$result_hysteria2_module" "With EASYNET_MODULE=hysteria2, it should select Hysteria2"

unset EASYNET_MODULE
export EASYNET_PROFILE="strict"
result_profile=$(run_env_selection_for_test)
assert_equals "profile:strict" "$result_profile" "With EASYNET_PROFILE=strict, it should select strict profile"


# Test 2: Simulating protocol domain selection from EASYNET_DOMAIN
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

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ENV_FILE="$TMP_DIR/.env"
cat > "$ENV_FILE" <<'ENV'
# comment
EASYNET_DOMAIN="proxy env.example.com"
EASYNET_PROFILE=balanced
UNSAFE_COMMAND=$(touch /tmp/easynet-should-not-exist)
TROJAN_VERSION=0.0.0
export EASYNET_SUBSCRIPTION_DOMAIN='sub.example.com'
ENV

unset EASYNET_DOMAIN
unset EASYNET_PROFILE
unset EASYNET_SUBSCRIPTION_DOMAIN
unset TROJAN_VERSION
load_env_file_path "$ENV_FILE"

assert_equals "proxy env.example.com" "$EASYNET_DOMAIN" "Env parser preserves quoted EASYNET value with spaces"
assert_equals "balanced" "$EASYNET_PROFILE" "Env parser loads plain EASYNET value"
assert_equals "sub.example.com" "$EASYNET_SUBSCRIPTION_DOMAIN" "Env parser supports export prefix and single quotes"
assert_equals "" "${TROJAN_VERSION:-}" "Env parser ignores non-EASYNET variables"
assert_equals "false" "$([ -e /tmp/easynet-should-not-exist ] && echo true || echo false)" "Env parser does not execute command substitutions"

test_end
