#!/bin/bash

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

# Percent-encode using the RFC 3986 "query allowed" set (Apple's
# URLQueryAllowedCharacterSet): sub-delims and :/?@ stay raw, while "{} and
# space are escaped. Matches Shadowrocket's AmneziaWG obfsParam encoding.
urlencode_query() {
    local string="${1}"
    local allowed='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~!$&'"'"'()*+,;=:@/?'
    local strlen=${#string}
    local encoded=""
    local pos c hex
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        if [[ "$allowed" == *"$c"* ]]; then
            encoded+="$c"
        else
            printf -v hex '%%%02X' "'$c"
            encoded+="$hex"
        fi
    done
    printf '%s' "$encoded"
}
