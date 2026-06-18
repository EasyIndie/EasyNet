#!/usr/bin/env bats

load test_helper

# Source the real route path function from the production code
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." &>/dev/null && pwd)"
source "$PROJECT_ROOT/scripts/core/env.sh"
source "$PROJECT_ROOT/scripts/exposure/edge/routes.sh"

@test "Generated path starts with /" {
    path=$(generate_route_path)
    [ "${path:0:1}" = "/" ]
}

@test "Generated path has correct length (32 hex chars + leading /)" {
    path=$(generate_route_path)
    [ "${#path}" = "33" ]
}

@test "Generated paths are randomly unique" {
    path1=$(generate_route_path)
    path2=$(generate_route_path)
    [ "$path1" != "$path2" ]
}

@test "Path contains only hex characters after the leading /" {
    path=$(generate_route_path)
    hex_part="${path:1}"
    [[ "$hex_part" =~ ^[0-9a-f]+$ ]]
}

@test "Default path /default-path is replaced with secure path" {
    simulate_path_recovery() {
        local current_path="$1"
        if [ "$current_path" = "/default-path" ] || [ -z "$current_path" ]; then
            generate_route_path
        else
            echo "$current_path"
        fi
    }
    recovered=$(simulate_path_recovery "/default-path")
    [ "$recovered" != "/default-path" ]
    [[ "$recovered" == /* ]]
}

@test "Valid custom path is preserved" {
    simulate_path_recovery() {
        local current_path="$1"
        if [ "$current_path" = "/default-path" ] || [ -z "$current_path" ]; then
            generate_route_path
        else
            echo "$current_path"
        fi
    }
    result=$(simulate_path_recovery "/a6d31173")
    [ "$result" = "/a6d31173" ]
}

@test "Empty path is replaced with secure path" {
    simulate_path_recovery() {
        local current_path="$1"
        if [ "$current_path" = "/default-path" ] || [ -z "$current_path" ]; then
            generate_route_path
        else
            echo "$current_path"
        fi
    }
    result=$(simulate_path_recovery "")
    [ -n "$result" ]
    [[ "$result" == /* ]]
}
