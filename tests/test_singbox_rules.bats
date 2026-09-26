#!/usr/bin/env bats

load test_helper

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export PROJECT_ROOT
    SUBSCRIPTION_LIB="$PROJECT_ROOT/scripts/core/subscription.sh"

    export TMP_DIR="$(mktemp -d)"
    export STATE_DIR="$TMP_DIR/state"
    export WEB_ROOT="$TMP_DIR/web"
    mkdir -p "$STATE_DIR/exposure/edge" "$STATE_DIR/modules/hysteria2"
    echo "example.com" >"$STATE_DIR/exposure/edge/domain.txt"
    echo "https" >"$STATE_DIR/exposure/edge/scheme.txt"
    echo "443" >"$STATE_DIR/exposure/edge/port.txt"

    cat >"$STATE_DIR/modules/hysteria2/metadata.json" <<'JSON'
{"schemaVersion":1,"module":"hysteria2","enabled":true,"protocol":"hysteria2","port":443,"client":{"uri":"hysteria2://pass@example.com:443#EasyNet-Hysteria2","clash":{"name":"EasyNet-Hysteria2","type":"hysteria2","server":"example.com","port":443,"password":"hp"}}}
JSON

    # shellcheck disable=SC1090
    source "$SUBSCRIPTION_LIB"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ---------- 清单解析 ----------

@test "规则清单能解析出 tag（含 action 缺省为 direct）" {
    tags="$(easynet_singbox_rules_tags)"
    echo "$tags" | grep -qx "cn-domains"
    echo "$tags" | grep -qx "cn-ips"
    echo "$tags" | grep -qx "ads"
}

@test "清单的 action 字段被解析（缺省 direct）" {
    printf 'tx|geosite|cn|reject\nty|geosite|cn\n' >"$TMP_DIR/rules.conf"
    export EASYNET_SINGBOX_RULES_CONF="$TMP_DIR/rules.conf"
    specs="$(easynet_singbox_rules_specs)"
    echo "$specs" | grep -qx 'tx|geosite|cn|reject'
    echo "$specs" | grep -qx 'ty|geosite|cn|direct'
}

@test "清单里的注释与空行被忽略" {
    printf '# comment\n\ncn-domains|geosite|cn|direct\n' >"$TMP_DIR/rules.conf"
    export EASYNET_SINGBOX_RULES_CONF="$TMP_DIR/rules.conf"
    [ "$(easynet_singbox_rules_tags)" = "cn-domains" ]
}

# ---------- 订阅端点 ----------

@test "订阅端点清单包含规则集与 manifest" {
    export EASYNET_STATE_DIR="$STATE_DIR"
    specs="$(easynet_subscription_endpoint_specs)"
    echo "$specs" | grep -q '^rules/cn-domains.srs|rules/cn-domains.srs|application/octet-stream$'
    echo "$specs" | grep -q '^rules/manifest.json|rules/manifest.json|application/json$'
    echo "$specs" | grep -q '^singbox|singbox|application/json$'
}

# ---------- 订阅内容 ----------

@test "生成的 sing-box 订阅带分流规则且 final 仍是 Proxy" {
    export EASYNET_STATE_DIR="$STATE_DIR"
    export EASYNET_WEB_ROOT="$WEB_ROOT"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true

    [ -s "$WEB_ROOT/singbox" ]
    jq -e '.route.final == "Proxy"' "$WEB_ROOT/singbox" >/dev/null
    # sniff + 私网直连 + 清单里的 3 条（cn-domains / cn-ips / ads）
    [ "$(jq '.route.rules | length' "$WEB_ROOT/singbox")" -eq 5 ]
    jq -e '.route.rules[0].action == "sniff"' "$WEB_ROOT/singbox" >/dev/null
    jq -e '.route.rules[1].ip_is_private == true and .route.rules[1].outbound == "DIRECT"' "$WEB_ROOT/singbox" >/dev/null
    jq -e '[.route.rules[].outbound] | index("REJECT")' "$WEB_ROOT/singbox" >/dev/null
    [ "$(jq '.route.rule_set | length' "$WEB_ROOT/singbox")" -eq 3 ]
    jq -e '.route.rule_set[] | select(.tag == "cn-domains") | .type == "remote"' "$WEB_ROOT/singbox" >/dev/null
    jq -e '.route.rule_set[] | select(.tag == "cn-domains") | .url | endswith("rules/cn-domains.srs")' "$WEB_ROOT/singbox" >/dev/null
    jq -e '.route.rule_set[] | select(.tag == "cn-domains") | .download_detour == "DIRECT"' "$WEB_ROOT/singbox" >/dev/null
}

@test "清单为空时优雅降级：无 rule_set、仍是合法配置" {
    printf '# empty\n' >"$TMP_DIR/empty.conf"
    export EASYNET_SINGBOX_RULES_CONF="$TMP_DIR/empty.conf"
    export EASYNET_STATE_DIR="$STATE_DIR"
    export EASYNET_WEB_ROOT="$WEB_ROOT"
    EASYNET_STATE_DIR="$STATE_DIR" EASYNET_WEB_ROOT="$WEB_ROOT" \
        EASYNET_SINGBOX_RULES_CONF="$TMP_DIR/empty.conf" \
        bash "$PROJECT_ROOT/scripts/generate_subscription.sh" >/dev/null 2>&1 || true

    [ -s "$WEB_ROOT/singbox" ]
    jq -e '.route.final == "Proxy"' "$WEB_ROOT/singbox" >/dev/null
    jq -e 'has("rule_set") | not' "$WEB_ROOT/singbox" >/dev/null
    [ "$(jq '.route.rules | length' "$WEB_ROOT/singbox")" -eq 2 ]
}
