#!/usr/bin/env bats
setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    CONTRACTS="$PROJECT_ROOT/docs/planning/contracts"
    SAMPLE="$BATS_TEST_TMPDIR/sample.json"
    MUTATED="$BATS_TEST_TMPDIR/mutated.json"
    jq '.valid[0]' "$CONTRACTS/errors.examples.json" > "$SAMPLE"
}
check_result() {
    jq -e -f "$CONTRACTS/validate-errors.jq" "$1" >/dev/null || return 1
    if jq -e '.operation != null' "$1" >/dev/null; then
        jq '.operation' "$1" > "$BATS_TEST_TMPDIR/operation.json"
        jq -e -f "$CONTRACTS/validate-operation.jq" "$BATS_TEST_TMPDIR/operation.json" >/dev/null
    fi
}
reject() {
    jq "$1" "$SAMPLE" > "$MUTATED"
    run check_result "$MUTATED"
    [ "$status" -ne 0 ]
}
@test "all stable failure codes validate with independent Operation checks" {
    jq -c '.valid[]' "$CONTRACTS/errors.examples.json" > "$BATS_TEST_TMPDIR/valid.jsonl"
    while IFS= read -r value; do
        printf '%s\n' "$value" > "$MUTATED"
        run check_result "$MUTATED"
        [ "$status" -eq 0 ]
    done < "$BATS_TEST_TMPDIR/valid.jsonl"
}
@test "unknown versions fields codes raw messages and unsafe local actions reject" {
    for mutation in '.schemaVersion = 2' '.schemaVersion = "1"' '.result = null' \
        '.result.code = null' '.result.code = {}' '.result.binding = []' \
        '.extra = true' '.result.extra = true' \
        '.result.binding.extra = true' '.result.code = "future-code"' \
        '.result.messageKey = "token-example"' '.result.message = "secret"' \
        '.result.stderr = "upstream"' '.result.URI = "scheme://secret"' \
        '.result.messageArgs = ["secret"]' '.result.binding.operationId = "/path"' \
        '.result.nextAction = "retry"' '.result.remoteOutcome = "failed"' \
        '.result.evidenceRef = "receipt_fake"' '.operation = {}'; do
        reject "$mutation"
    done
    jq '.valid[4]' "$CONTRACTS/errors.examples.json" > "$SAMPLE"
    reject '.result.nextAction = "autoaccept"'
    reject '.result.nextAction = "retry"'
}
@test "remote errors require same binding outcome receipt and legal history" {
    jq '.valid[-1]' "$CONTRACTS/errors.examples.json" > "$SAMPLE"
    for mutation in '.operation = null' '.result.binding.targetId = "target_other"' \
        '.result.binding.operationId = "op_other"' \
        '.result.binding.planHash = ("sha256:" + ("b" * 64))' \
        '.result.evidenceRef = null' '.result.evidenceRef = "receipt_other"' \
        '.result.remoteOutcome = "unknown"' '.result.nextAction = "retry"' \
        '.operation.history[0].remoteState = "running"'; do
        reject "$mutation"
    done
    jq '.valid[-2]' "$CONTRACTS/errors.examples.json" > "$SAMPLE"
    reject '.result.nextAction = "retry"'
    reject '.result.code = "remote-failed" | .result.messageKey = "error.remote-failed"'
    reject '.result.remoteOutcome = "failed"'
    reject '.operation.history[-1].remoteState = "failed"'
}
@test "every result string rejects LF CR TAB NUL DEL suffixes" {
    jq '.valid[-1]' "$CONTRACTS/errors.examples.json" > "$SAMPLE"
    jq -c 'paths(strings)' "$SAMPLE" > "$BATS_TEST_TMPDIR/paths.jsonl"
    while IFS= read -r path; do
        for suffix in '\n' '\r' '\t' '\u0000' '\u007f'; do
            reject "setpath($path; getpath($path) + \"$suffix\")"
        done
    done < "$BATS_TEST_TMPDIR/paths.jsonl"
}
