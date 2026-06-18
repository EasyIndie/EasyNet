#!/usr/bin/env bats
# download.sh error-handling tests
#
# These tests verify that download_file() and run_downloaded_script()
# handle network failures, checksum mismatches, and missing tools
# correctly — without making real HTTP requests.

load test_helper

setup() {
    export TMP_DIR=$(mktemp -d)
    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."

    export FAKE_BIN="$TMP_DIR/fake_bin"
    mkdir -p "$FAKE_BIN"

    export OUTPUT_DIR="$TMP_DIR/output"
    mkdir -p "$OUTPUT_DIR"

    # Source dependencies once
    source "$PROJECT_ROOT/scripts/core/logging.sh"
    source "$PROJECT_ROOT/scripts/core/download.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Helper: create a fake curl in FAKE_BIN
make_fake_curl() {
    local script="$1"  # the script content
    cat > "$FAKE_BIN/curl" <<'SCRIPT'
#!/bin/bash
SCRIPT
    printf '%s\n' "$script" >> "$FAKE_BIN/curl"
    chmod +x "$FAKE_BIN/curl"
}

# Helper: create a fake wget in FAKE_BIN
make_fake_wget() {
    local script="$1"
    cat > "$FAKE_BIN/wget" <<'SCRIPT'
#!/bin/bash
SCRIPT
    printf '%s\n' "$script" >> "$FAKE_BIN/wget"
    chmod +x "$FAKE_BIN/wget"
}

# ============================================================
# download_file — curl mode
# ============================================================

@test "download_file: uses curl and writes output file" {
    local out="$OUTPUT_DIR/test_dl.txt"
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; echo "downloaded content" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    PATH="$FAKE_BIN:$PATH" run download_file "https://example.com/file" "$out"
    echo "status=$status" >&3
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    grep -q "downloaded content" "$out"
}

@test "download_file: curl failure propagates as non-zero exit" {
    local out="$OUTPUT_DIR/fail_dl.txt"
    make_fake_curl 'exit 22'

    PATH="$FAKE_BIN:$PATH" run download_file "https://example.invalid/fail" "$out"
    # download_file propagates failure via || return 1 (exit code 1)
    [ "$status" -eq 1 ]
}

@test "download_file: fails on SHA256 mismatch" {
    local wrong_sha="0000000000000000000000000000000000000000000000000000000000000000"
    local out="$OUTPUT_DIR/sha_fail.txt"
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; echo "some content" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    PATH="$FAKE_BIN:$PATH" run download_file "https://example.com/file" "$out" "$wrong_sha"
    [ "$status" -ne 0 ]
}

@test "download_file: passes on matching SHA256" {
    local content="some content"
    local correct_sha
    correct_sha=$(printf '%s' "$content" | sha256sum | cut -d' ' -f1)
    local out="$OUTPUT_DIR/sha_ok.txt"
    make_fake_curl "while [[ \$# -gt 0 ]]; do case \"\$1\" in -o) shift; printf 'some content' > \"\$1\"; break ;; *) shift ;; esac; done; exit 0"

    PATH="$FAKE_BIN:$PATH" run download_file "https://example.com/file" "$out" "$correct_sha"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
}

# ============================================================
# download_file — wget fallback
# ============================================================

@test "download_file: falls back to wget when curl is not found" {
    local out="$OUTPUT_DIR/wget_test.txt"
    make_fake_wget 'while [[ $# -gt 0 ]]; do case "$1" in -O) shift; echo "wget content" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    # Override 'command' in a subshell so command -v curl returns 1
    # (forcing download_file to try wget)
    PATH="$FAKE_BIN:$PATH" bash -c '
        source "$0/scripts/core/logging.sh"
        source "$0/scripts/core/download.sh"
        command() {
            if [ "$1" = "-v" ] && [ "$2" = "curl" ]; then return 1; fi
            builtin command "$@"
        }
        download_file "https://example.com/file" "$1" 2>/dev/null
    ' "$PROJECT_ROOT" "$out"

    [ -f "$out" ]
    grep -q "wget content" "$out"
}

# ============================================================
# download_file — missing tools
# ============================================================

@test "download_file: returns 1 when neither curl nor wget available" {
    local out="$OUTPUT_DIR/no_tool.txt"

    # Override 'command' so both curl and wget vanish
    command() {
        if [ "$1" = "-v" ] && { [ "$2" = "curl" ] || [ "$2" = "wget" ]; }; then
            return 1
        fi
        builtin command "$@"
    }

    run download_file "https://example.com/file" "$out"
    local rc=$status
    unset -f command 2>/dev/null || true
    [ "$rc" -eq 1 ]
}

# ============================================================
# download_file — output file validation
# ============================================================

@test "download_file: creates zero-byte output on empty download" {
    local out="$OUTPUT_DIR/empty_dl.txt"
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; : > "$1"; break ;; *) shift ;; esac; done; exit 0'

    PATH="$FAKE_BIN:$PATH" run download_file "https://example.com/empty" "$out"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
}

# ============================================================
# run_downloaded_script — cleanup behaviour
# ============================================================

@test "run_downloaded_script: cleans up temp file after success" {
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; printf "#!/bin/bash\nexit 0\n" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    local tmp_count_before
    tmp_count_before=$(ls -1 /tmp/easynet-install.* 2>/dev/null | wc -l)
    PATH="$FAKE_BIN:$PATH" run run_downloaded_script "https://example.com/install.sh"
    local tmp_count_after
    tmp_count_after=$(ls -1 /tmp/easynet-install.* 2>/dev/null | wc -l)
    [ "$tmp_count_after" -le "$tmp_count_before" ]
}

@test "run_downloaded_script: cleans up temp file even on script failure" {
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; printf "#!/bin/bash\nexit 42\n" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    local tmp_count_before
    tmp_count_before=$(ls -1 /tmp/easynet-install.* 2>/dev/null | wc -l)
    PATH="$FAKE_BIN:$PATH" run run_downloaded_script "https://example.com/install-fail.sh"
    local rc=$status
    local tmp_count_after
    tmp_count_after=$(ls -1 /tmp/easynet-install.* 2>/dev/null | wc -l)
    [ "$tmp_count_after" -le "$tmp_count_before" ]
    [ "$rc" -eq 42 ]
}

@test "run_downloaded_script: returns the script exit code on success" {
    make_fake_curl 'while [[ $# -gt 0 ]]; do case "$1" in -o) shift; printf "#!/bin/bash\nexit 0\n" > "$1"; break ;; *) shift ;; esac; done; exit 0'

    PATH="$FAKE_BIN:$PATH" run run_downloaded_script "https://example.com/install-ok.sh"
    [ "$status" -eq 0 ]
}

@test "run_downloaded_script: returns non-zero when download fails" {
    make_fake_curl 'exit 22'

    PATH="$FAKE_BIN:$PATH" run run_downloaded_script "https://example.invalid/missing.sh"
    # download_file now propagates curl failure via || return 1
    [ "$status" -ne 0 ]
}
