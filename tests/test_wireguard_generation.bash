#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/test_helper.bash"

test_start "WireGuard URI Generation & URL Encoding Logic"

# Test 1: URL Encode Function
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9/] ) o="${c}" ;;
            * )               printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

test_encode_1=$(urlencode "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=")
assert_equals "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/%2B6FgOHI%3D" "$test_encode_1" "URL Encode: + and = should be encoded, / should not"

test_encode_2=$(urlencode "1.1.1.1, 8.8.8.8")
assert_equals "1.1.1.1%2C%208.8.8.8" "$test_encode_2" "URL Encode: space and comma should be encoded"


# Test 2: Config file parsing with sed (simulating the bug fix for base64 trailing '=')
TEST_CONF=$(mktemp)
cat > "$TEST_CONF" << 'EOF'
[Interface]
PrivateKey = EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=
Address = 10.0.0.2/32

[Peer]
PublicKey = HHjphdrrSzUPbDBlTYatFdDM5sOBL/UGEXCVgl8rKnc=
PresharedKey = PiFNyX5YH24zxhK85tKURTd72mhBNGMO/PNKUXATFv8=
EOF

# Use the exact sed logic from the script
extracted_priv=$(grep "PrivateKey" "$TEST_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
extracted_pub=$(grep "PublicKey" "$TEST_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)

assert_equals "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=" "$extracted_priv" "Sed parsing: PrivateKey should retain trailing ="
assert_equals "HHjphdrrSzUPbDBlTYatFdDM5sOBL/UGEXCVgl8rKnc=" "$extracted_pub" "Sed parsing: PublicKey should retain trailing ="

# Clean up
rm -f "$TEST_CONF"


# Test 3: URI Construction (IP Extraction)
test_addr="10.0.0.2/32"
ip_only=$(echo "$test_addr" | cut -d'/' -f1)
assert_equals "10.0.0.2" "$ip_only" "IP Extraction: Should remove subnet mask"

test_end
