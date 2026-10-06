#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    EXAMPLES="$PROJECT_ROOT/docs/planning/contracts/operation.examples.json"
    CHECKER="$PROJECT_ROOT/docs/planning/contracts/validate-operation.jq"
    SAMPLE="$BATS_TEST_TMPDIR/sample.json"
    MUTATED="$BATS_TEST_TMPDIR/mutated.json"
    jq '.valid[0]' "$EXAMPLES" > "$SAMPLE"
}
reject() {
    jq "$1" "$SAMPLE" > "$MUTATED"
    run jq -e -f "$CHECKER" "$MUTATED"
    [ "$status" -ne 0 ]
    [ "$output" = false ]
}

@test "positive histories accept terminal outcomes cancel request reconcile and local exit" {
    jq -c '.valid[]' "$EXAMPLES" > "$BATS_TEST_TMPDIR/valid.jsonl"
    while IFS= read -r history; do
        printf '%s\n' "$history" > "$MUTATED"
        run jq -e -f "$CHECKER" "$MUTATED"
        [ "$status" -eq 0 ]
        [ "$output" = true ]
    done < "$BATS_TEST_TMPDIR/valid.jsonl"
}
@test "negative histories reject resurrection local success unconfirmed cancel and changed binding" {
    jq -c '.invalid[]' "$EXAMPLES" > "$BATS_TEST_TMPDIR/invalid.jsonl"
    while IFS= read -r history; do
        printf '%s\n' "$history" > "$MUTATED"
        run jq -e -f "$CHECKER" "$MUTATED"
        [ "$status" -ne 0 ]
        [ "$output" = false ]
    done < "$BATS_TEST_TMPDIR/invalid.jsonl"
}
@test "malformed references payloads fields and repeated starts reject" {
    for mutation in '.history[1].stdout = "raw"' '.history[1].uri = "scheme://secret"' \
        '.history[1].secret = "secret"' '.history[1].evidenceRef = "/receipt"' \
        '.history[1].evidenceRef = "receipt_"' '.history[1].planHash = "sha256:abc"' \
        '.history[1].operationId = 1' '.history[1].targetId = ""' '.extra = 1' \
        '.schemaVersion = 2' '.history = []' '.history[0].action = "retry"' \
        '.history[2] = .history[1]' '.history[2].localState = "disconnected"' \
        '.history[2].remoteState = "planned"'; do
        reject "$mutation"
    done
}
@test "all string fields reject trailing LF CR TAB NUL DEL" {
    jq -c 'paths(strings)' "$SAMPLE" > "$BATS_TEST_TMPDIR/paths.jsonl"
    while IFS= read -r path; do
        for suffix in '\n' '\r' '\t' '\u0000' '\u007f'; do
            reject "setpath($path; getpath($path) + \"$suffix\")"
        done
    done < "$BATS_TEST_TMPDIR/paths.jsonl"
}
