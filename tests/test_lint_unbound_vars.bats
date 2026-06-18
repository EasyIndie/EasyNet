#!/usr/bin/env bats
# Lint: ensure set -u scripts don't reference env vars without ${VAR:-} protection.
# This prevents crashes like "EASYNET_SUBSCRIPTION_PATH_PREFIX: unbound variable".
#
# Rationale:
#   Scripts with set -u exit on any unset variable expansion. Environment variables
#   (EASYNET_*, NGINX_*, JOURNALD_*) may not be set at runtime. All references
#   must use the ${VAR:-} form so they expand to empty string when unset.
#
# Exceptions (not in set -u scripts so not checked here):
#   - scripts/deploy.sh (orchestrator, no set -u)
#   - Library files sourced by set -u scripts — they run in the caller's shell
#     context and inherit its set -u, but function-body bare vars are flagged
#     only if the caller's context has set -u. We check only the scripts that
#     directly enable set -u.

load test_helper

# List of env var prefixes that must always use ${VAR:-} in set -u scripts
# shellcheck disable=SC2034
readonly VAR_PREFIXES='EASYNET_|NGINX_|JOURNALD_|SINGBOX_|HYSTERIA2_|SHADOWSOCKS_|ACME_'

# Files that are sourced by set -u scripts and must also pass the check.
# These library files don't have set -u themselves but run under set -u
# when sourced by a caller that does. We check them unconditionally.
readonly EXTRA_LIBS=(
    "$BATS_TEST_DIRNAME/../scripts/core/subscription.sh"
)

@test "set -u scripts guard env vars with \${VAR:-}" {
    local script_dir="$BATS_TEST_DIRNAME/../scripts"
    local errors=0
    local all_files=()

    # Collect set -u scripts
    while IFS= read -r -d '' f; do
        all_files+=("$f")
    done < <(grep -rlZ 'set.*\-[a-z]*u' "$script_dir" 2>/dev/null || true)

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
        matches=$(grep -nE '\$('"$VAR_PREFIXES"')' "$script" \
            | grep -v ':-' \
            | grep -v '# ok' \
            | grep -v '^[[:digit:]]*:.*\<source\>.*\$' \
            || true)

        if [ -n "$matches" ]; then
            echo "# $relative" >&3
            while IFS= read -r line; do
                echo "#   $line" >&3
            done <<< "$matches"
            ((errors++))
        fi
    done

    if [ "$errors" -gt 0 ]; then
        echo "# FAIL: $errors file(s) have bare env var references" >&3
        echo "# Use \${VAR:-} instead of \$VAR, or append # ok to suppress." >&3
    fi
    [ "$errors" -eq 0 ]
}
