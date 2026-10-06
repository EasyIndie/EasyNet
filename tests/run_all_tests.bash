#!/bin/bash
# EasyNet test runner — delegates to bats.
#
# 默认「快速模式」：跳过依赖网络 / 真客户端二进制的用例
# （manifest 里标记为 file_tags=network|client 的文件），适合日常迭代。
# 需要全量（含 URL 探活与真客户端校验）时传 --full 或 EASYNET_TEST_FULL=1。
#
# 若本机装有 GNU parallel 或 rush，会自动并行（按文件拆分；用例内共享状态
# 不并行，避免相互踩踏）。并发度可用 EASYNET_TEST_JOBS 覆盖，默认 CPU 核数。
#
#   bash tests/run_all_tests.bash            # 快速模式
#   bash tests/run_all_tests.bash --full     # 全量
#   EASYNET_TEST_JOBS=8 bash tests/run_all_tests.bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FULL="${EASYNET_TEST_FULL:-0}"
for arg in "$@"; do
    case "$arg" in
        --full) FULL=1 ;;
        --fast) FULL=0 ;;
    esac
done

JOBS=()
if command -v parallel >/dev/null 2>&1 || command -v rush >/dev/null 2>&1; then
    jobs="${EASYNET_TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)}"
    JOBS=(--jobs "$jobs" --no-parallelize-within-files)
fi

FILTER=()
if [ "$FULL" != "1" ]; then
    FILTER=(--filter-tags '!network,!client')
fi

echo "======================================"
echo "    Running All EasyNet Unit Tests    "
if [ "$FULL" = "1" ]; then
    echo "    mode: full (network + real clients)"
else
    echo "    mode: fast (skips network/client; use --full for all)"
fi
echo "======================================"

bats --timing --pretty "${JOBS[@]}" "${FILTER[@]}" "$DIR"/*.bats
