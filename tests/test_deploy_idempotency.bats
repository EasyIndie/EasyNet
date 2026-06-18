#!/usr/bin/env bats
# Deployment idempotency tests
#
# Verify that repeated deployment operations do not produce
# duplicate state, duplicate firewall rules, or duplicate cron entries.

load test_helper

setup() {
    export TMP_DIR=$(mktemp -d)
    export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/.."
    export EASYNET_STATE_DIR="$TMP_DIR/state"
    mkdir -p "$EASYNET_STATE_DIR"
    source "$PROJECT_ROOT/scripts/core/logging.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ============================================================
# metadata_write idempotency
# ============================================================

@test "metadata_write: writing same metadata twice does not error" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"

    module="test-module"
    json='{"schemaVersion":1,"module":"test-module","enabled":true,"protocol":"test","port":9999,"client":{"uri":"test://example","clash":{}}}'

    metadata_write "$module" "$json"
    [ -f "$EASYNET_STATE_DIR/modules/$module/metadata.json" ]

    run metadata_write "$module" "$json"
    [ "$status" -eq 0 ]
}

@test "metadata_write: preserves file permissions after overwrite" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"

    module="perm-module"
    json='{"schemaVersion":1,"module":"perm-module","enabled":true,"protocol":"test","port":9999,"client":{"uri":"test://example","clash":{}}}'

    metadata_write "$module" "$json"
    local first_perm
    first_perm=$(stat -f "%Lp" "$EASYNET_STATE_DIR/modules/$module/metadata.json" 2>/dev/null || stat -c "%a" "$EASYNET_STATE_DIR/modules/$module/metadata.json" 2>/dev/null)

    metadata_write "$module" "$json"
    local second_perm
    second_perm=$(stat -f "%Lp" "$EASYNET_STATE_DIR/modules/$module/metadata.json" 2>/dev/null || stat -c "%a" "$EASYNET_STATE_DIR/modules/$module/metadata.json" 2>/dev/null)

    [ -n "$first_perm" ]
    [ "$first_perm" = "$second_perm" ]
}

@test "metadata_write: handles multiple different modules" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"

    for i in 1 2 3; do
        module="multi-module-$i"
        json="{\"schemaVersion\":1,\"module\":\"$module\",\"enabled\":true,\"protocol\":\"test\",\"port\":$((i * 1000)),\"client\":{\"uri\":\"test://example\",\"clash\":{}}}"
        metadata_write "$module" "$json"
    done

    [ -f "$EASYNET_STATE_DIR/modules/multi-module-1/metadata.json" ]
    [ -f "$EASYNET_STATE_DIR/modules/multi-module-2/metadata.json" ]
    [ -f "$EASYNET_STATE_DIR/modules/multi-module-3/metadata.json" ]
}

# ============================================================
# firewall_all_rules idempotency
# ============================================================

@test "firewall_all_rules: deduplicates repeated base rules" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"

    run firewall_all_rules
    local count_443
    count_443=$(echo "$output" | grep -c "443/tcp" || true)
    [ "$count_443" -eq 1 ] || {
        echo "# firewall_all_rules output: $output" >&3
        echo "# 443/tcp count: $count_443" >&3
        return 1
    }
}

@test "firewall_all_rules: calling repeatedly returns same set" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/firewall.sh"

    local first second
    first=$(firewall_all_rules | sort)
    second=$(firewall_all_rules | sort)

    [ "$first" = "$second" ]
}

# ============================================================
# cron idempotency
# ============================================================

@test "cron_restart_command: deduplicates services shared by multiple modules" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    source "$PROJECT_ROOT/scripts/core/cron.sh"

    mkdir -p "$EASYNET_STATE_DIR/modules/mod-a" "$EASYNET_STATE_DIR/modules/mod-b"
    cat > "$EASYNET_STATE_DIR/modules/mod-a/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"mod-a","enabled":true,"protocol":"test","port":9001,"client":{"uri":"test://a","clash":{}},"systemd":{"services":["shared-service.service"]}}
JSON
    cat > "$EASYNET_STATE_DIR/modules/mod-b/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"mod-b","enabled":true,"protocol":"test","port":9002,"client":{"uri":"test://b","clash":{}},"systemd":{"services":["shared-service.service"]}}
JSON

    run cron_restart_command
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | grep -o "shared-service.service" | wc -l)
    [ "$count" -eq 1 ] || {
        echo "# cron_restart_command output: $output" >&3
        echo "# shared-service.service appears $count times" >&3
        return 1
    }
}

@test "cron_restart_command: returns 1 when no services exist" {
    source "$PROJECT_ROOT/scripts/core/metadata.sh"
    source "$PROJECT_ROOT/scripts/core/env.sh"
    source "$PROJECT_ROOT/scripts/core/cron.sh"

    # Empty metadata — no modules present
    run cron_restart_command
    [ "$status" -eq 1 ]
}
