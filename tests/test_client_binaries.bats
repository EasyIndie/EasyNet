#!/usr/bin/env bats
# 客户端二进制镜像（A1）：把 pinned sing-box 发布到 Edge web root，供设备代理失效时自愈。
#
# 纯逻辑测试始终运行；真实发布测试需要一份已校验的原包（client_check 缓存），
# 没有缓存且 CI 未强制时跳过（EASYNET_REQUIRE_CLIENT_CHECK=1 会让 CI 跑真下载）。

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    export PROJECT_ROOT
    # 注意：source edge/deploy.sh 会按 EASYNET_WEB_ROOT 重算 WEB_ROOT，
    # 所以测试必须以 EASYNET_WEB_ROOT 为准，且 teardown 只删自己造的临时目录。
    export EASYNET_WEB_ROOT="$(mktemp -d)"
    export WEB_ROOT="$EASYNET_WEB_ROOT"
    export EASYNET_CLIENT_BIN_DIR="${EASYNET_CLIENT_BIN_DIR:-$BATS_TEST_TMPDIR/client-bin}"
}

teardown() {
    case "${EASYNET_WEB_ROOT:-}" in
        "$BATS_TEST_TMPDIR"* | /tmp/* | /var/folders/*)
            rm -rf "$EASYNET_WEB_ROOT"
            ;;
    esac
}

pins() { bash -c "source '$PROJECT_ROOT/scripts/core/pins.sh'; $1"; }
lib() { bash -c "source '$PROJECT_ROOT/scripts/core/logging.sh'; source '$PROJECT_ROOT/scripts/core/pins.sh'; source '$PROJECT_ROOT/scripts/core/client_binaries.sh'; $1"; }

# ── 平台与资产映射（纯逻辑）────────────────────────────────────────────────

@test "只发布 Linux 平台（客户端安装器只支持 Linux）" {
    run pins 'easynet_client_binary_platforms'
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
    [[ "$output" == *linux_amd64* ]]
    [[ "$output" == *linux_arm64* ]]
    [[ "$output" != *darwin* ]]
}

@test "校验工具覆盖三平台，但发布只取 Linux 两个" {
    run pins 'easynet_client_platforms'
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
    run pins 'easynet_client_binary_platforms'
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

@test "按平台解析 sing-box 资产名、SHA256 与 URL" {
    local platform asset sha url
    for platform in linux_amd64 linux_arm64 darwin_amd64; do
        asset="$(pins "easynet_client_pin_asset_for singbox $platform")"
        sha="$(pins "easynet_client_pin_sha256_for singbox $platform")"
        url="$(pins "easynet_client_pin_url_for singbox $platform")"
        [ -n "$asset" ]
        [ -n "$sha" ]
        [ -n "$url" ]
        [[ "$asset" == "sing-box-${sha:0:0}"*"-${platform//_/-}.tar.gz" ]]
        [[ "$url" == https://github.com/SagerNet/sing-box/releases/download/* ]]
        [ "${#sha}" -eq 64 ]
    done
}

@test "未 pin 的平台返回空（调用方据此跳过，而不是造一个错 URL）" {
    [ -z "$(pins 'easynet_client_pin_asset_for singbox windows_amd64')" ]
    [ -z "$(pins 'easynet_client_pin_sha256_for singbox windows_amd64')" ]
    [ -z "$(pins 'easynet_client_pin_url_for singbox windows_amd64')" ]
}

# ── 端点定义（Edge 路由靠它暴露给设备）────────────────────────────────────

@test "订阅端点包含 bin/ 下的二进制、校验文件与 manifest" {
    run bash -c "source '$PROJECT_ROOT/scripts/core/subscription.sh'; easynet_subscription_endpoint_specs"
    [ "$status" -eq 0 ]
    local asset
    for platform in linux_amd64 linux_arm64; do
        asset="$(pins "easynet_client_pin_asset_for singbox $platform")"
        [[ "$output" == *"bin/${asset}|bin/${asset}|application/gzip"* ]]
        [[ "$output" == *"bin/${asset}.sha256|bin/${asset}.sha256|text/plain"* ]]
    done
    [[ "$output" == *"bin/manifest.json|bin/manifest.json|application/json"* ]]
}

@test "Edge 会为二进制端点生成前缀别名路由" {
    export EASYNET_STATE_DIR="$BATS_TEST_TMPDIR/state"
    # 先 source（deploy.sh 会按自己的规则重算 EDGE_ROUTES_DIR），再覆盖测试用的路径
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/exposure/edge/deploy.sh"
    EDGE_STATE_DIR="$EASYNET_STATE_DIR/exposure/edge"
    EDGE_SUBSCRIPTION_PATH_PREFIX="/s/aaaa1111bbbb2222cccc3333dddd4444"
    EDGE_ROUTES_DIR="$BATS_TEST_TMPDIR/routes"
    mkdir -p "$EDGE_STATE_DIR" "$EDGE_ROUTES_DIR"
    WEB_ROOT="$EASYNET_WEB_ROOT"
    EASYNET_SUBSCRIPTION_DIRECT_PATHS=false

    write_edge_subscription_routes

    local asset
    asset="$(pins 'easynet_client_pin_asset_for singbox linux_arm64')"
    grep -q "location = ${EDGE_SUBSCRIPTION_PATH_PREFIX}/bin/${asset} {" "$EDGE_ROUTES_DIR/subscription.conf"
    grep -A2 "location = ${EDGE_SUBSCRIPTION_PATH_PREFIX}/bin/${asset} {" "$EDGE_ROUTES_DIR/subscription.conf" |
        grep -q "alias ${WEB_ROOT}/bin/${asset};"
}

# ── 发布状态（不依赖网络）─────────────────────────────────────────────────

@test "未发布时状态显示未发布" {
    run lib "easynet_client_binaries_status '$EASYNET_WEB_ROOT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未发布"* ]]
    [[ "$output" == *"manifest.json: 缺失"* ]]
}

@test "已存在但与 pin 不一致的文件被标为异常（不会当成可用）" {
    mkdir -p "$EASYNET_WEB_ROOT/bin"
    local asset
    asset="$(pins 'easynet_client_pin_asset_for singbox linux_arm64')"
    printf 'not-the-real-binary' > "$EASYNET_WEB_ROOT/bin/$asset"
    run lib "easynet_client_binaries_status '$EASYNET_WEB_ROOT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHA256 与 pin 不一致"* ]]
}

# ── 真实发布（需要一份已校验的原包；CI 的 client-validation job 会强制）────

# 需要缓存里至少有一个 Linux 平台的原包（发布只处理 Linux）。
cached_linux_asset() {
    local platform asset
    for platform in $(pins 'easynet_client_binary_platforms'); do
        asset="$(pins "easynet_client_pin_asset_for singbox $platform")"
        if [ -f "$EASYNET_CLIENT_BIN_DIR/$asset" ]; then
            printf '%s' "$asset"
            return 0
        fi
    done
    return 1
}

require_cache() {
    local asset
    asset="$(cached_linux_asset)" && [ -n "$asset" ] && return 0
    asset="$(pins 'easynet_client_pin_asset_for singbox linux_arm64')"
    if [ "${EASYNET_REQUIRE_CLIENT_CHECK:-}" = "1" ]; then
        echo "# EASYNET_REQUIRE_CLIENT_CHECK=1 但缓存里没有 $asset" >&3
        return 1
    fi
    skip "本机无已校验原包缓存（scripts/client_check.sh fetch singbox 可准备）"
}

@test "发布后产出资产、.sha256 与合法 manifest（且只含 Linux 平台）" {
    require_cache
    local asset
    asset="$(cached_linux_asset)"
    run lib "easynet_client_binaries_publish '$EASYNET_WEB_ROOT'"
    [ "$status" -eq 0 ]

    [ -s "$EASYNET_WEB_ROOT/bin/$asset" ]
    [ -s "$EASYNET_WEB_ROOT/bin/$asset.sha256" ]
    grep -q "$(pins "easynet_client_pin_sha256_for singbox ${asset%%-linux-*}" 2>/dev/null || true)" "$EASYNET_WEB_ROOT/bin/$asset.sha256" 2>/dev/null || true

    # manifest 必须是合法 JSON、只含 Linux 平台，且每个条目与实际文件一致
    run jq -e '.tool == "sing-box" and (.files | length >= 1)' "$EASYNET_WEB_ROOT/bin/manifest.json"
    [ "$status" -eq 0 ]
    ! jq -e '.files[] | select(.platform | test("darwin"))' "$EASYNET_WEB_ROOT/bin/manifest.json" >/dev/null
    local n i sha file
    n="$(jq '.files | length' "$EASYNET_WEB_ROOT/bin/manifest.json")"
    for ((i = 0; i < n; i++)); do
        sha="$(jq -r ".files[$i].sha256" "$EASYNET_WEB_ROOT/bin/manifest.json")"
        file="$(jq -r ".files[$i].asset" "$EASYNET_WEB_ROOT/bin/manifest.json")"
        [ -s "$EASYNET_WEB_ROOT/bin/$file" ]
        [ "$(shasum -a 256 "$EASYNET_WEB_ROOT/bin/$file" 2>/dev/null | cut -d' ' -f1 ||
            sha256sum "$EASYNET_WEB_ROOT/bin/$file" | cut -d' ' -f1)" = "$sha" ]
    done
}

@test "重复发布会跳过已就绪的资产（不重新下载）" {
    require_cache
    lib "easynet_client_binaries_publish '$EASYNET_WEB_ROOT'" >/dev/null 2>&1
    local asset before after
    asset="$(cached_linux_asset)"
    before="$(shasum -a 256 "$EASYNET_WEB_ROOT/bin/$asset" 2>/dev/null | cut -d' ' -f1 || sha256sum "$EASYNET_WEB_ROOT/bin/$asset" | cut -d' ' -f1)"
    # 把缓存挪走：若第二次仍成功，说明复用的是已发布文件而不是缓存
    mv "$EASYNET_CLIENT_BIN_DIR/$asset" "$EASYNET_CLIENT_BIN_DIR/$asset.hidden"
    run lib "easynet_client_binaries_publish '$EASYNET_WEB_ROOT'"
    mv "$EASYNET_CLIENT_BIN_DIR/$asset.hidden" "$EASYNET_CLIENT_BIN_DIR/$asset"
    [ "$status" -eq 0 ]
    after="$(shasum -a 256 "$EASYNET_WEB_ROOT/bin/$asset" 2>/dev/null | cut -d' ' -f1 || sha256sum "$EASYNET_WEB_ROOT/bin/$asset" | cut -d' ' -f1)"
    [ "$before" = "$after" ]
}
