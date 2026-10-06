#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    EXAMPLES="$PROJECT_ROOT/docs/planning/contracts/protocol-runtime.examples.json"
    CHECKER="$PROJECT_ROOT/docs/planning/contracts/validate-protocol-runtime.jq"
    MUTATED="$BATS_TEST_TMPDIR/runtime.json"
}
reject() {
    jq "$1" "$EXAMPLES" > "$MUTATED"
    run jq -e -f "$CHECKER" "$MUTATED"
    [ "$status" -ne 0 ]
}

@test "native Hysteria2 and AWG descriptions pass without executing drivers" {
    run jq -e -f "$CHECKER" "$EXAMPLES"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
    jq '.request.runtimeId = "amneziawg-native"' "$EXAMPLES" > "$MUTATED"
    run jq -e -f "$CHECKER" "$MUTATED"
    [ "$status" -eq 0 ]
}
@test "unsupported and unknown methods refuse deterministically" {
    reject '.request = {runtimeId:"amneziawg-native", targetId:"existing-example", method:"exportSingboxNative"}'
    [[ "$output" == *"capability-unsupported"* ]]
    reject '.request.method = "install"'
    [[ "$output" == *"capability-unknown"* ]]
    reject '.request.method = "destroy"'
    [ "$output" = false ]
    reject '.request.method = "nativeWireguard"'
    [ "$output" = false ]
}
@test "duplicates, unknown identities/fields, false WG parity and bad states fail" {
    for mutation in '.schemaVersion = 2' '.runtimes += [.runtimes[0]]' \
        '.request.runtimeId = "missing"' '.runtimes[1].protocolId = "wireguard"' \
        '.runtimes[1].capabilities.nativeWireguard.state = "supported"' \
        '.runtimes[1].capabilities.exportSingboxNative = {state:"supported",evidence:"source-identity"}' \
        '.runtimes[0].capabilities.install.state = "maybe"' '.request.extra = 1' \
        '.runtimes[0].extra = 1' '.runtimes[0].capabilities.describe.extra = 1'; do
        reject "$mutation"
        [ "$output" = false ]
    done
}
@test "LF and CR fail on every descriptor, capability and request string" {
    jq -c 'paths(strings)' "$EXAMPLES" > "$BATS_TEST_TMPDIR/paths.jsonl"
    while IFS= read -r path; do
        for suffix in '\n' '\r'; do
            reject "setpath($path; getpath($path) + \"$suffix\")"
            [ "$output" = false ]
        done
    done < "$BATS_TEST_TMPDIR/paths.jsonl"
}
