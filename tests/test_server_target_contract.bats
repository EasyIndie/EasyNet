#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    EXAMPLES="$PROJECT_ROOT/docs/planning/contracts/server-target.examples.json"
    CHECKER="$PROJECT_ROOT/docs/planning/contracts/validate-server-target.jq"
    MUTATED="$BATS_TEST_TMPDIR/target.json"
}

reject_mutation() {
    jq "$1" "$EXAMPLES" > "$MUTATED"
    run jq -e -f "$CHECKER" "$MUTATED"
    [ "$status" -eq 1 ]
    [ "$output" = false ]
}

@test "two targets pass together and independently" {
    run jq -e -f "$CHECKER" "$EXAMPLES"
    [ "$status" -eq 0 ]
    for index in 0 1; do
        jq --argjson index "$index" '.targets = [.targets[$index]]' "$EXAMPLES" > "$MUTATED"
        run jq -e -f "$CHECKER" "$MUTATED"
        [ "$status" -eq 0 ]
        [ "$output" = true ]
    done
}

@test "unsupported versions and hostname command injection are rejected" {
    reject_mutation '.schemaVersion = 2'
    reject_mutation '.schemaVersion = "1"'
    reject_mutation '.targets[0].ssh.host = "example.com;id"'
    # shellcheck disable=SC2016 # Injection fixture must remain literal, never executed.
    reject_mutation '.targets[0].ssh.host = "$(id).example.com"'
    reject_mutation '.targets[0].ssh.host = "-oProxyCommand=sh"'
}

@test "ports require an integer in the SSH range" {
    for value in true 0 65536 1.5 '"22"'; do
        reject_mutation ".targets[0].ssh.port = $value"
    done
}

@test "unknown fields and embedded credential material are rejected" {
    for mutation in '.extra = 1' '.targets[0].extra = 1' \
        '.targets[0].ssh.password = "example-secret"' \
        '.targets[0].credentialRef = "-----BEGIN PRIVATE KEY-----"' \
        '.targets[0].hostTrust = "accepted"' '.targets[1].cloud.owned = true'; do
        reject_mutation "$mutation"
    done
}

@test "duplicate IDs and implicit privilege policies are rejected" {
    reject_mutation '.targets[1].id = .targets[0].id'
    reject_mutation '.targets[1].privilege = {mode: "sudo"}'
    reject_mutation '.targets[0].privilege.mode = "auto"'
    reject_mutation '.targets[0].cloud = .targets[1].cloud'
}

@test "DNS and canonical IPv4 are accepted, ambiguous numeric hosts are rejected" {
    for host in example.com 192.0.2.1 0.0.0.0 255.255.255.255; do
        jq --arg host "$host" '.targets[0].ssh.host = $host' "$EXAMPLES" > "$MUTATED"
        run jq -e -f "$CHECKER" "$MUTATED"
        [ "$status" -eq 0 ]
        [ "$output" = true ]
    done
    for host in 256.0.2.1 192.0.2 192.0.2.1.5 192.00.2.1 127.1 \
        2130706433 0x7f.0.0.1 ::1; do
        reject_mutation ".targets[0].ssh.host = \"$host\""
    done
}

@test "LF and CR cannot trail any restricted identifier or SSH string" {
    for path in '["targets",0,"id"]' '["targets",0,"ssh","host"]' \
        '["targets",0,"ssh","user"]' '["targets",0,"credentialRef"]' \
        '["targets",1,"cloud","provider"]' '["targets",1,"cloud","resourceId"]'; do
        for suffix in '\n' '\r'; do
            reject_mutation "setpath($path; getpath($path) + \"$suffix\")"
        done
    done
}
