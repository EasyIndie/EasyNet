#!/usr/bin/env bats
# 本仓库是公开的：运行标识（真实域名 / 服务器 IP / 订阅路径前缀）不得入库。
#
# 为什么这些字符串要以 base64 存放？
#   否则这个测试文件本身就会把要防止泄露的标识写进公开仓库 —— 自相矛盾。
# 新增需要保护的标识时：printf '%s' '<值>' | base64 然后加进下面的数组。
#
# 背景：域名本身通过 Certificate Transparency 日志（Let's Encrypt / Cloudflare 签发）
# 已是公开可查的，隐藏仓库并不能隐藏域名；这里防的是「不要在文档/注释/提交里主动
# 扩散运维细节」，以及避免以后误把订阅路径等真正敏感的值提交进来。
#
# ⚠️ 本文件最初的版本因为 $PROJECT_ROOT 未定义而「静默通过」过一次。因此这里加了
#    哨兵断言：先证明搜索确实能命中一个已知存在的字符串，再相信禁止项的结果。

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
}

FORBIDDEN_B64=(
    'am9rZXJodWIuY24='                                # 主域名后缀
    'NjYuNDIuNTIuMjQz'                                # 测试 VPS IP
    'NjQuMTc2LjgyLjUy'                                # 正式 VPS IP
    'OTgzZmUwYTZjOGFkMjZmYmVjZDFmOWI0M2Q3ZmJjZTI='    # 测试环境订阅路径前缀
    'NzkwYTRkODQ2ZmE5YTA5ZDVjNGZjYzIxZDY2ZmQwMzU='    # 正式环境订阅路径前缀
)

# 仓库里必然存在的哨兵字符串（.env.example 中的变量名）
CANARY='EASYNET_PROFILE'

search_repo() { # search_repo <pattern> → 命中的文件列表（排除 .git 与本测试文件）
    grep -rIl --exclude-dir=.git -e "$1" "$PROJECT_ROOT" 2>/dev/null |
        grep -v 'test_no_private_identifiers' || true
}

@test "identifier scan itself works (canary)" {
    [ -d "$PROJECT_ROOT" ] || { echo "# PROJECT_ROOT 未定义或不存在: '$PROJECT_ROOT'" >&3; return 1; }
    run search_repo "$CANARY"
    [ -n "$output" ] || {
        echo "# 哨兵 '$CANARY' 未命中 —— 说明搜索机制失效，禁止项检查结果不可信" >&3
        return 1
    }
}

@test "no real operational identifiers are committed to this public repo" {
    local pattern decoded hit
    for pattern in "${FORBIDDEN_B64[@]}"; do
        decoded="$(printf '%s' "$pattern" | base64 -d 2>/dev/null)"
        [ -n "$decoded" ] || { echo "# base64 解码失败: $pattern" >&3; return 1; }
        hit="$(search_repo "$decoded")"
        if [ -n "$hit" ]; then
            echo "# 禁止入库的标识「${decoded:0:6}…」出现在:" >&3
            printf '#   %s\n' $hit >&3
            return 1
        fi
    done
}

@test "deployment examples only use reserved example domains" {
    # 真实域名只能出现在那台机器的 .env（不入库）。仓库内所有 EASYNET_DOMAIN 赋值
    # 必须是 RFC 2606 保留域名、变量引用，或留空。
    local line value bad=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        value="${line#*=}"
        # 去掉引号与行尾注释；不要按空格截断（测试 fixture 里可能有空格）
        value="$(printf '%s' "$value" | tr -d '"' | sed 's/[[:space:]]*#.*$//')"
        # 值里必须出现 RFC 2606 保留域名（或为变量引用/空）。精确的已知标识由
        # 上面的禁止项测试覆盖，这里防的是「随手写下真实域名当示例」。
        case "$value" in
            *example.com*|*example.org*|*example.net*) ;;
            *'$'*|'') ;;
            *) bad="${bad}${line}"$'\n' ;;
        esac
    done < <(grep -rInE '^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?EASYNET_DOMAIN=' \
        --include='*.md' --include='*.sh' --include='*.example' --include='*.bats' \
        --exclude-dir=.git "$PROJECT_ROOT" 2>/dev/null || true)

    if [ -n "$bad" ]; then
        echo "# 部署示例里出现非保留域名（示例请用 example.com）:" >&3
        printf '%s' "$bad" >&3
        return 1
    fi
}
