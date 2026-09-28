#!/usr/bin/env bats
# Smoke tests for the runtime monitor module (scripts/core/monitor.sh).
# These only exercise sourceability + the pure helper functions; they never
# send real notifications or touch crontab.

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    source "$PROJECT_ROOT/scripts/core/monitor.sh"
}

@test "monitor_notify_channel defaults to none" {
    unset EASYNET_MONITOR_NOTIFY
    run monitor_notify_channel
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "monitor_send returns 0 for none channel without sending" {
    unset EASYNET_MONITOR_NOTIFY
    run monitor_send "test message"
    [ "$status" -eq 0 ]
}

@test "monitor_send returns 1 for ntfy channel without a URL" {
    export EASYNET_MONITOR_NOTIFY="ntfy"
    unset EASYNET_MONITOR_NTFY_TOPIC_URL
    run monitor_send "test message"
    [ "$status" -eq 1 ]
}

@test "monitor_send returns 1 for telegram channel without credentials" {
    export EASYNET_MONITOR_NOTIFY="telegram"
    unset EASYNET_MONITOR_TELEGRAM_BOT_TOKEN EASYNET_MONITOR_TELEGRAM_CHAT_ID
    run monitor_send "test message"
    [ "$status" -eq 1 ]
}

@test "monitor_send rejects an unknown channel" {
    export EASYNET_MONITOR_NOTIFY="carrier-pigeon"
    run monitor_send "test message"
    [ "$status" -eq 1 ]
}

@test "monitor_install_cron skips silently when no channel is configured" {
    unset EASYNET_MONITOR_NOTIFY
    run monitor_install_cron
    [ "$status" -eq 0 ]
}

@test "monitor_install_cron skips when ntfy channel lacks its URL" {
    export EASYNET_MONITOR_NOTIFY="ntfy"
    unset EASYNET_MONITOR_NTFY_TOPIC_URL
    run monitor_install_cron
    [ "$status" -eq 0 ]
}
