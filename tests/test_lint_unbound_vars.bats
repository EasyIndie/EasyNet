#!/usr/bin/env bats
# Lint: ensure set -u scripts don't reference env vars without ${VAR:-} protection.
# This prevents crashes like "EASYNET_SUBSCRIPTION_PATH_PREFIX: unbound variable".
#
# Rationale:
#   Scripts with set -u exit on any unset variable expansion. Environment variables
#   (EASYNET_*, NGINX_*, JOURNALD_*) may not be set at runtime. All references
#   must use the ${VAR:-} form so they expand to empty string when unset.
#
# Notes:
#   - Orchestrators (deploy.sh, uninstall.sh, generate_subscription.sh) now
#     enable set -u, so they are checked here like any other script.
#   - Library files sourced by set -u scripts — they run in the caller's shell
#     context and inherit its set -u, but function-body bare vars are flagged
#     only if the caller's context has set -u. We check scripts that directly
#     enable set -u plus the EXTRA_LIBS list below.

load test_helper

# List of env var prefixes that must always use ${VAR:-} in set -u scripts
# shellcheck disable=SC2034
readonly VAR_PREFIXES='EASYNET_|NGINX_|JOURNALD_|SINGBOX_|HYSTERIA2_|SHADOWSOCKS_|ACME_'

# Files that are sourced by set -u scripts and must also pass the check.
# These library files don't have set -u themselves but run under set -u
# when sourced by a caller that does. We check them unconditionally.
readonly EXTRA_LIBS=(
    "$BATS_TEST_DIRNAME/../scripts/core/subscription.sh"
    "$BATS_TEST_DIRNAME/../scripts/core/validate.sh"
)

@test "Shell variables are braced when followed by a multi-byte character" {
    # bash may swallow the following UTF-8 bytes into the variable name when it
    # writes $VAR immediately before a CJK character (breaks on bash 3.2, the
    # macOS default). Always use ${VAR} in that position.
    local errors=0
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        local hits
        # Portable: BSD grep has no -P, and `grep -P ... || true` silently passed
        # on macOS, hiding real hits. With LC_ALL=C, `[^ -~]` means "any byte
        # outside printable ASCII" on both GNU and BSD grep.
        hits=$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$f" 2>/dev/null || true)
        if [ -n "$hits" ]; then
            echo "# ${f#$BATS_TEST_DIRNAME/../}" >&3
            while IFS= read -r line; do
                echo "#   $line" >&3
            done <<< "$hits"
            errors=$((errors + 1))
        fi
    done < <(grep -rl --include='*' -E '^#!' "$BATS_TEST_DIRNAME/../scripts" 2>/dev/null || true)

    if [ "$errors" -gt 0 ]; then
        echo "# FAIL: $errors file(s) use \$VAR right before a multi-byte char" >&3
        echo "# Use \${VAR} instead of \$VAR in that position." >&3
    fi
    [ "$errors" -eq 0 ]
}

@test "set -u scripts guard env vars with \${VAR:-}" {
    local script_dir="$BATS_TEST_DIRNAME/../scripts"
    local errors=0
    local all_files=()

    # Collect set -u scripts (newline-separated so it works with both GNU and BSD grep)
    while IFS= read -r f; do
        [ -n "$f" ] && all_files+=("$f")
    done < <(grep -rl 'set.*\-[a-z]*u' "$script_dir" 2>/dev/null || true)

    # Add extra libs
    for lib in "${EXTRA_LIBS[@]}"; do
        [ -f "$lib" ] && all_files+=("$lib")
    done

    # Sort and deduplicate (use while-read to avoid mapfile compat issues)
    local sorted=()
    while IFS= read -r f; do
        sorted+=("$f")
    done < <(printf '%s\n' "${all_files[@]}" | sort -u)

    for script in "${sorted[@]}"; do
        local relative="${script#$script_dir/}"
        # Skip library files that set their own CORE_DIR (safe by construction)
        # Pattern: they have top-level EASYNET_*_CORE_DIR=...  then source lines
        # Source lines referencing *_CORE_DIR are excluded below.

        local matches
        # Match both bare $VAR and braced ${VAR} without a default: the
        # braced form crashes just the same under set -u when unset, but was
        # previously unchecked (a real blind spot).
        matches=$(grep -nE '\$('"$VAR_PREFIXES"')|\$\{('"$VAR_PREFIXES"')[A-Z0-9_]*\}' "$script" \
            | grep -v ':-' \
            | grep -v '# ok' \
            | grep -v '^[[:digit:]]*:.*\<source\>.*\$' \
            || true)

        if [ -n "$matches" ]; then
            echo "# $relative" >&3
            while IFS= read -r line; do
                echo "#   $line" >&3
            done <<< "$matches"
            errors=$((errors + 1))
        fi
    done

    if [ "$errors" -gt 0 ]; then
        echo "# FAIL: $errors file(s) have bare env var references" >&3
        echo "# Use \${VAR:-} instead of \$VAR, or append # ok to suppress." >&3
    fi
    [ "$errors" -eq 0 ]
}

@test "pipefail scripts avoid early-terminating pipeline stages" {
    # `producer | head -1` under `set -o pipefail`: head exits after one line, the
    # producer is killed by SIGPIPE and the pipeline reports 141, which `set -e`
    # turns into a hard deployment failure. Use `awk 'NR==1'` (reads everything) or
    # `find ... -print -quit` instead. Append `# ok` with a reason to suppress.
    local errors=0 f hits
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -q 'pipefail' "$f" 2>/dev/null || continue
        hits=$(grep -nE '\|[[:space:]]*head([[:space:]]|$)' "$f" 2>/dev/null | grep -v '# ok' || true)
        if [ -n "$hits" ]; then
            echo "# ${f#$BATS_TEST_DIRNAME/../}" >&3
            while IFS= read -r line; do
                echo "#   $line" >&3
            done <<< "$hits"
            errors=$((errors + 1))
        fi
    done < <(find "$BATS_TEST_DIRNAME/../scripts" -type f 2>/dev/null)

    if [ "$errors" -gt 0 ]; then
        echo "# FAIL: $errors file(s) use \`| head\` under pipefail" >&3
    fi
    [ "$errors" -eq 0 ]
}
