#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export DIAG="$PROJECT_ROOT/scripts/diagnose_reachability.sh"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    return 0
}

# -- Static analysis --

@test "Reachability diagnostic has an entrypoint guard" {
    run rg -q 'BASH_SOURCE\[0\].*==.*\$0' "$DIAG"
    [ "$status" -eq 0 ]
}

@test "Reachability diagnostic documents GFW/ISP return-path blocking" {
    run rg -q "回程被拦截" "$DIAG"
    [ "$status" -eq 0 ]
    run rg -q "GFW" "$DIAG"
    [ "$status" -eq 0 ]
}

@test "Reachability diagnostic supports packet capture classification" {
    run rg -q "diag_classify" "$DIAG"
    [ "$status" -eq 0 ]
    run rg -q "return_blocked" "$DIAG"
    [ "$status" -eq 0 ]
    run rg -q "tcpdump" "$DIAG"
    [ "$status" -eq 0 ]
}

@test "Reachability diagnostic uses check-host.net global probe" {
    run rg -q "check-host.net" "$DIAG"
    [ "$status" -eq 0 ]
}

# -- Classification logic --

@test "Classifies completed handshake as reachable" {
    TMP_DIR="$(mktemp -d)"
    cat > "$TMP_DIR/dump" <<'EOF'
11:46:23.256553 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
11:46:23.256629 IP 45.32.124.132.443 > 114.240.151.109.50216: Flags [S.], seq 2, ack 1, length 0
11:46:23.286000 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [.], ack 2, length 0
EOF
    run bash -c "source \"$DIAG\"; diag_classify \"$TMP_DIR/dump\""
    [ "$output" = "reachable" ]
}

@test "Classifies SYN + SYN-ACK without ACK as return-path blocked" {
    TMP_DIR="$(mktemp -d)"
    cat > "$TMP_DIR/dump" <<'EOF'
11:46:23.256553 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
11:46:23.256629 IP 45.32.124.132.443 > 114.240.151.109.50216: Flags [S.], seq 2, ack 1, length 0
11:46:24.256285 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
11:46:25.258724 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
EOF
    run bash -c "source \"$DIAG\"; diag_classify \"$TMP_DIR/dump\""
    [ "$output" = "return_blocked" ]
}

@test "Classifies client SYN only as server not responding" {
    TMP_DIR="$(mktemp -d)"
    cat > "$TMP_DIR/dump" <<'EOF'
11:46:23.256553 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
11:46:24.256285 IP 114.240.151.109.50216 > 45.32.124.132.443: Flags [S], seq 1, win 65535, length 0
EOF
    run bash -c "source \"$DIAG\"; diag_classify \"$TMP_DIR/dump\""
    [ "$output" = "no_synack" ]
}

@test "Classifies empty capture as no client request" {
    TMP_DIR="$(mktemp -d)"
    : > "$TMP_DIR/dump"
    run bash -c "source \"$DIAG\"; diag_classify \"$TMP_DIR/dump\""
    [ "$output" = "no_request" ]
}

@test "Verdict for return_blocked mentions replacing IP and not reinstalling" {
    run bash -c "source \"$DIAG\"; diag_report_verdict return_blocked"
    [[ "$output" == *"回程被拦截"* ]]
    [[ "$output" == *"更换服务器公网 IP"* ]]
    [[ "$output" == *"重装 EasyNet 无法解决"* ]]
}
