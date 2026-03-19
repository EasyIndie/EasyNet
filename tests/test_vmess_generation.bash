#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/test_helper.bash"

test_start "V2Ray VMess URL Generation Logic"

# Simulate the V2Ray VMess generation logic from v2ray.sh
generate_vmess_url() {
    local uuid="$1"
    local domain="$2"
    local path="$3"
    
    # In reality, this checks for null or empty
    if [ -z "$domain" ] || [ "$domain" == "null" ]; then
        echo "ERROR: Missing domain"
        return 1
    fi
    
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "EasyNet-V2Ray",
  "add": "1.2.3.4",
  "port": 443,
  "id": "${uuid}",
  "aid": 0,
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "${path}",
  "tls": "tls",
  "sni": "${domain}"
}
EOF
)
    
    # We just test the JSON string here instead of base64 encoding to verify fields
    echo "$vmess_json"
}

# Test 1: Valid inputs
uuid="test-uuid"
domain="proxy.example.com"
path="/testpath"

vmess_output=$(generate_vmess_url "$uuid" "$domain" "$path")
extracted_sni=$(echo "$vmess_output" | jq -r '.sni')
extracted_host=$(echo "$vmess_output" | jq -r '.host')

assert_equals "$domain" "$extracted_sni" "VMess JSON correctly includes SNI"
assert_equals "$domain" "$extracted_host" "VMess JSON correctly includes Host"

# Test 2: Empty domain (simulating the SNI issue)
error_output=$(generate_vmess_url "$uuid" "" "$path")
assert_equals "ERROR: Missing domain" "$error_output" "VMess generation fails when domain is empty"

# Test 3: Null domain
error_output_null=$(generate_vmess_url "$uuid" "null" "$path")
assert_equals "ERROR: Missing domain" "$error_output_null" "VMess generation fails when domain is null string"

test_end
