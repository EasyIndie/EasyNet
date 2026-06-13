#!/usr/bin/env bats

load test_helper

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

@test "URL Encode: + and = should be encoded, / should not" {
    result=$(urlencode "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=")
    [ "$result" = "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/%2B6FgOHI%3D" ]
}

@test "URL Encode: space and comma should be encoded" {
    result=$(urlencode "1.1.1.1, 8.8.8.8")
    [ "$result" = "1.1.1.1%2C%208.8.8.8" ]
}

@test "Sed parsing: PrivateKey should retain trailing =" {
    TEST_CONF=$(mktemp /tmp/easynet-wg-test.XXXXXX)
    cat > "$TEST_CONF" << 'EOF'
[Interface]
PrivateKey = EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=
Address = 10.0.0.2/32

[Peer]
PublicKey = HHjphdrrSzUPbDBlTYatFdDM5sOBL/UGEXCVgl8rKnc=
PresharedKey = PiFNyX5YH24zxhK85tKURTd72mhBNGMO/PNKUXATFv8=
EOF
    extracted=$(grep "PrivateKey" "$TEST_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    rm -f "$TEST_CONF"
    [ "$extracted" = "EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=" ]
}

@test "Sed parsing: PublicKey should retain trailing =" {
    TEST_CONF=$(mktemp /tmp/easynet-wg-test.XXXXXX)
    cat > "$TEST_CONF" << 'EOF'
[Interface]
PrivateKey = EPnilTNXmR9KFH6Z38vTO/hmAr0tkBJfAWs/+6FgOHI=
Address = 10.0.0.2/32

[Peer]
PublicKey = HHjphdrrSzUPbDBlTYatFdDM5sOBL/UGEXCVgl8rKnc=
PresharedKey = PiFNyX5YH24zxhK85tKURTd72mhBNGMO/PNKUXATFv8=
EOF
    extracted=$(grep "PublicKey" "$TEST_CONF" | sed 's/^[^=]*=[[:space:]]*//' | xargs)
    rm -f "$TEST_CONF"
    [ "$extracted" = "HHjphdrrSzUPbDBlTYatFdDM5sOBL/UGEXCVgl8rKnc=" ]
}

@test "IP Extraction: Should remove subnet mask" {
    result=$(echo "10.0.0.2/32" | cut -d'/' -f1)
    [ "$result" = "10.0.0.2" ]
}
