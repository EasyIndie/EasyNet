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

# ── 上游维度：版本漂移 + CVE（CI 的 pin 落后检查覆盖不到）─────────────────

@test "monitor_pin_version 读取 release pin 的版本" {
    run monitor_pin_version xray
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" = "$EASYNET_PIN_XRAY_VERSION" ]
}

@test "monitor_parse_version 兼容 xray / hysteria / ssserver 输出格式" {
    [ "$(printf 'Xray 26.3.27 (go1.24.0)' | monitor_parse_version)" = "26.3.27" ]
    [ "$(printf 'Version: v2.12.3' | monitor_parse_version)" = "2.12.3" ]
    [ "$(printf 'shadowsocks 1.25.0' | monitor_parse_version)" = "1.25.0" ]
    [ -z "$(printf 'no version here' | monitor_parse_version)" ]
}

@test "monitor_osv_package 映射到 OSV 坐标" {
    [ "$(monitor_osv_package xray)" = "Go|github.com/XTLS/Xray-core" ]
    [ "$(monitor_osv_package hysteria2)" = "Go|github.com/apernet/hysteria" ]
    [ "$(monitor_osv_package shadowsocks)" = "crates.io|shadowsocks" ]
    [ -z "$(monitor_osv_package unknown)" ]
}

@test "monitor_running_version 解析运行的二进制版本" {
    local dir
    dir="$(mktemp -d)"
    create_fake_command "$dir" xray 0 "Xray 99.9.9 (fake)"
    run env PATH="$dir:$PATH" bash -c "source '$PROJECT_ROOT/scripts/core/monitor.sh'; monitor_running_version xray"
    [ "$status" -eq 0 ]
    [ "$output" = "99.9.9" ]
    rm -rf "$dir"
}

@test "monitor_upstream_findings 报告版本漂移（运行 != pin）" {
    local dir
    dir="$(mktemp -d)"
    create_fake_command "$dir" xray 0 "Xray 99.9.9 (fake)"
    run env PATH="$dir:$PATH" EASYNET_MONITOR_CVE=false \
        bash -c "source '$PROJECT_ROOT/scripts/core/monitor.sh'; monitor_upstream_findings"
    [ "$status" -eq 0 ]
    [[ "$output" == *"版本漂移: xray"* ]]
    [[ "$output" == *"99.9.9"* ]]
    rm -rf "$dir"
}

@test "monitor_upstream_findings 可用 EASYNET_MONITOR_UPSTREAM=false 关闭" {
    local dir
    dir="$(mktemp -d)"
    create_fake_command "$dir" xray 0 "Xray 99.9.9 (fake)"
    run env PATH="$dir:$PATH" EASYNET_MONITOR_UPSTREAM=false \
        bash -c "source '$PROJECT_ROOT/scripts/core/monitor.sh'; monitor_upstream_findings"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    rm -rf "$dir"
}
