#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    CONTRACTS="$PROJECT_ROOT/docs/planning/contracts"
    SAMPLE="$BATS_TEST_TMPDIR/sample.json"
    MUTATED="$BATS_TEST_TMPDIR/mutated.json"
    jq '.valid[0]' "$CONTRACTS/events.examples.json" > "$SAMPLE"
}
check_both() {
    jq -e -f "$CONTRACTS/validate-events.jq" "$1" >/dev/null || return 1
    jq '{schemaVersion: 1, history: [.events[].payload]}' "$1" > "$BATS_TEST_TMPDIR/history.json"
    jq -e -f "$CONTRACTS/validate-operation.jq" "$BATS_TEST_TMPDIR/history.json" >/dev/null
}
reject() {
    jq "$1" "$SAMPLE" > "$MUTATED"
    run check_both "$MUTATED"
    [ "$status" -ne 0 ]
}

@test "valid streams pass event framing and independent Operation transitions" {
    jq -c '.valid[]' "$CONTRACTS/events.examples.json" > "$BATS_TEST_TMPDIR/valid.jsonl"
    while IFS= read -r stream; do
        printf '%s\n' "$stream" > "$MUTATED"
        run check_both "$MUTATED"
        [ "$status" -eq 0 ]
    done < "$BATS_TEST_TMPDIR/valid.jsonl"
    # Unknown is an admissible prefix, never a terminal outcome.
    run jq -e '.valid[1].events[-1].payload.remoteState == "unknown"' "$CONTRACTS/events.examples.json"
    [ "$status" -eq 0 ]
}
@test "gaps reordering duplicates identity changes and false terminal histories reject" {
    jq -c '.invalid[]' "$CONTRACTS/events.examples.json" > "$BATS_TEST_TMPDIR/invalid.jsonl"
    while IFS= read -r stream; do
        printf '%s\n' "$stream" > "$MUTATED"
        run check_both "$MUTATED"
        [ "$status" -ne 0 ]
    done < "$BATS_TEST_TMPDIR/invalid.jsonl"
    # Shape alone accepts this illegal transition; Operation must reject it.
    jq '.invalid[-1]' "$CONTRACTS/events.examples.json" > "$MUTATED"
    run jq -e -f "$CONTRACTS/validate-events.jq" "$MUTATED"
    [ "$status" -eq 0 ]
    run check_both "$MUTATED"
    [ "$status" -ne 0 ]
    for mutation in '.events[1].payload.targetId = "target_other"' \
        '.events[1].payload.planHash = ("sha256:" + ("b" * 64))' \
        '.events = .events[1:]' '.events[2].payload.action = "local-exit"' \
        '.events[2].payload.action = "cancel-request"'; do
        reject "$mutation"
    done
}
@test "typed allowlist rejects raw payloads future versions and malformed sequence" {
    for mutation in '.events[0].stdout = "raw"' '.events[0].stderr = "raw"' \
        '.events[1].payload.message = "secret"' '.events[1].payload.configURI = "scheme://secret"' \
        '.events[1].payload.secret = "secret"' '.events[1].payload.evidenceRef = "/receipt"' \
        '.events[0].type = "future.event"' '.events[0].extra = 1' '.schemaVersion = 2' \
        '.events = []' '.extra = 1' '.events[1].seq = 1.5' '.events[1].seq = "2"' \
        '.events[1].seq = 9007199254740992' '.events[0].payload = {}'; do
        reject "$mutation"
    done
}
@test "all string fields reject trailing LF CR TAB NUL DEL through framing checker" {
    jq -c 'paths(strings)' "$SAMPLE" > "$BATS_TEST_TMPDIR/paths.jsonl"
    while IFS= read -r path; do
        for suffix in '\n' '\r' '\t' '\u0000' '\u007f'; do
            jq "setpath($path; getpath($path) + \"$suffix\")" "$SAMPLE" > "$MUTATED"
            run jq -e -f "$CONTRACTS/validate-events.jq" "$MUTATED"
            [ "$status" -ne 0 ]
            [ "$output" = false ]
        done
    done < "$BATS_TEST_TMPDIR/paths.jsonl"
}
