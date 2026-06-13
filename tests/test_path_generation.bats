#!/usr/bin/env bats

load test_helper

# Simulated random path generator (same logic as test subject)
generate_random_path() {
    head -c 4 /dev/urandom | xxd -p | awk '{print "/"$1}'
}

@test "Generated path starts with /" {
    path=$(generate_random_path)
    [ "${path:0:1}" = "/" ]
}

@test "Generated path has correct length" {
    path=$(generate_random_path)
    [ "${#path}" = "9" ]
}

@test "Generated paths are randomly unique" {
    path1=$(generate_random_path)
    path2=$(generate_random_path)
    [ "$path1" != "$path2" ]
}

@test "Default path /default-path is replaced with secure path" {
    simulate_path_recovery() {
        local current_path="$1"
        if [ "$current_path" = "/default-path" ] || [ -z "$current_path" ]; then
            generate_random_path
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
            generate_random_path
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
            generate_random_path
        else
            echo "$current_path"
        fi
    }
    result=$(simulate_path_recovery "")
    [ -n "$result" ]
    [[ "$result" == /* ]]
}
