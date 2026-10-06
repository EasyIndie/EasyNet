#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    EXAMPLES="$PROJECT_ROOT/docs/planning/contracts/profile.examples.json"
    CHECKER="$PROJECT_ROOT/docs/planning/contracts/validate-profile.jq"
    MUTATED="$BATS_TEST_TMPDIR/profile.json"
}
reject() {
    jq "$1" "$EXAMPLES" > "$MUTATED"
    run jq -e -f "$CHECKER" "$MUTATED"
    [ "$status" -ne 0 ]
    [ "$output" = false ]
}

@test "reference-only native draft descriptors accept DNS and canonical IPv4" {
    run jq -e -f "$CHECKER" "$EXAMPLES"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
}
@test "secret payloads and unknown fields reject at all inventory levels" {
    for mutation in '.uri = "hysteria2://secret@vpn.example.com"' \
        '.profiles[0].password = "secret"' '.profiles[0].token = "secret"' \
        '.profiles[0].config = {password:"secret"}' '.profiles[0].endpoint.key = "secret"' \
        '.profiles[0].configRef = "hysteria2://secret@vpn.example.com"' \
        '.profiles[0].configRef = "/secret/config"' '.profiles[0].configRef = {password:"secret"}'; do
        reject "$mutation"
    done
}
@test "mismatched or unsupported runtime protocol format cannot grant AWG parity" {
    for mutation in '.profiles[0].runtimeId = "sing-box"' \
        '.profiles[1].protocolId = "wireguard"' '.profiles[1].format = "singbox-native"' \
        '.profiles[1].format = "wireguard-native-config"' \
        '.profiles[0].format = "amneziawg-native-config"'; do
        reject "$mutation"
    done
}
@test "bad endpoints revisions duplicate IDs and malformed references reject" {
    for mutation in '.profiles[0].endpoint.host = "256.0.2.1"' \
        '.profiles[0].endpoint.host = "192.00.2.1"' '.profiles[0].endpoint.host = "0xc0.0.2.1"' \
        '.profiles[0].endpoint.host = "2001:db8::1"' '.profiles[0].endpoint.host = "-vpn.example.com"' \
        '.profiles[0].endpoint.port = 0' '.profiles[0].endpoint.port = 65536' \
        '.profiles[0].endpoint.port = 1.5' '.profiles[0].revision = 0' \
        '.profiles[0].revision = 1.5' '.profiles[0].targetId = ""' \
        '.profiles[0].configRef = "config_"' '.profiles += [.profiles[0]]' '.profiles = []' \
        '.schemaVersion = 2' '.profiles[0].revision = "1"' '.profiles[0].endpoint.port = "443"'; do
        reject "$mutation"
    done
}
@test "control characters fail in every profile string" {
    jq -c 'paths(strings)' "$EXAMPLES" > "$BATS_TEST_TMPDIR/paths.jsonl"
    while IFS= read -r path; do
        for suffix in '\n' '\r' '\t' '\u0000' '\u007f'; do
            reject "setpath($path; getpath($path) + \"$suffix\")"
        done
    done < "$BATS_TEST_TMPDIR/paths.jsonl"
}
