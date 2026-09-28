#!/bin/bash
# EasyNet 伪装站渲染器（Edge 的 location / 返回的「普通站点」）
#
# 为什么不能反代第三方大站（旧默认是 https://www.bing.com）：
#   透明反代会把「我在镜像别人」直接写在响应里，任何探针都能立刻判定这是反代：
#     - <link rel="canonical" href="https://www.bing.com/">  页面自称是第三方站点
#     - Set-Cookie: ...; domain=.bing.com                    跨域 Cookie（浏览器必然丢弃）
#     - UserAgentReductionOptOut 的 base64 里含 third-party origin
#     - 镜像了第三方的 /robots.txt、/sitemap.xml、/favicon.ico
#     - 任意 Host 都返回同一个第三方首页（catch-all 镜像）
#   这类内容层特征比 TLS 指纹更容易被自动化识别（内容哈希比对即可）。
#   正确做法是**自洽**：域名、证书、内容三者一致 —— 由本域名自己托管一个普通站点。
#
# 本模块负责生成/安装这样一个站点：
#   - 完全自包含（内联 CSS、零外部请求、内联 SVG favicon），不出现任何工具名；
#   - 用 cksum(域名) 做种子从文案/配色池确定性抽取 —— 同一域名重部署结果稳定，
#     不同部署之间内容不同（否则所有 EasyNet 实例长得一样，本身就是工具指纹）；
#   - 支持 EASYNET_EDGE_SITE_DIR 指定的自带站点（生产环境最推荐的强伪装）；
#   - 手工改过的 index.html 不会被覆盖（删除该文件即可恢复默认生成）。

# 文案与配色池。注意：值内不要出现 "|"（渲染时用 sed 以 | 作分隔符）。
easynet_edge_site_taglines() {
    cat <<'EOF'
记录一些想法、笔记和小项目。
个人主页 · 不定期更新。
这里放一些日常记录和随手写的东西。
一个小站，用来放点文字和发布一些小工具。
EOF
}

easynet_edge_site_abouts() {
    cat <<'EOF'
这个站点主要用来整理平时的工作笔记，偶尔也会写一点关于网络、工具和阅读的记录。
平时做一些软件相关的事情，这里放一些阶段性总结和随手记。
用这个页面存放我的笔记、收藏和一些自己做的小东西，更新不算频繁。
这里是我个人的一块自留地，写点技术笔记，也放一些生活记录。
EOF
}

easynet_edge_site_sections() {
    cat <<'EOF'
笔记|按主题整理的长期笔记，想到什么写什么。
项目|一些自己做的小工具和实验，大多开源在代码托管平台上。
关于|更详细的介绍和联系方式，需要的时候再补充。
EOF
}

easynet_edge_site_footers() {
    cat <<'EOF'
保留所有权利。
本页面内容为个人记录，转载请注明出处。
感谢访问。
EOF
}

# robots.txt 变体池：`<key>|<内容>`，一行一个变体（抽取逻辑按行取值，所以内容里的
# 换行写成 \n，渲染时用 printf %b 还原）；key 为 `none` 表示**不生成**该文件。
# 两台不同部署的 robots.txt 曾逐字节相同（md5 一致）—— 一个恒定文件本身就是
# "同源模板"的指纹，所以这里按域名种子在真实站点的常见写法里挑一个。
easynet_edge_site_robots_pool() {
    cat <<'EOF'
allow|User-agent: *\nAllow: /
deny-admin|User-agent: *\nDisallow: /admin/\nDisallow: /private/
crawl-delay|User-agent: *\nCrawl-delay: 10
explicit-allow|User-agent: *\nDisallow:
deny-all|User-agent: *\nDisallow: /
none|
EOF
}

# 强调色池（十六进制，渲染安全）
easynet_edge_site_accents() {
    cat <<'EOF'
#2563eb
#0f766e
#b45309
#7c3aed
#be123c
#0369a1
#15803d
#a16207
EOF
}

# 用域名做确定性种子：POSIX cksum（macOS/Linux 都有），重部署结果稳定。
easynet_edge_site_seed() {
    printf '%s' "${1:-example.com}" | cksum | awk '{print $1}'
}

# 从一行一项的池里按种子+偏移取一项。
# 用法: easynet_edge_site_pick <seed> <shift> <pool-command>
easynet_edge_site_pick() {
    local seed="$1" shift_by="$2" pool_cmd="$3"
    local items count idx
    items="$("$pool_cmd")"
    count="$(printf '%s\n' "$items" | grep -c .)"
    [ "$count" -gt 0 ] || { printf ''; return 0; }
    # 用整数除法错开各池的取值，避免同一偏移量导致多项总是同步变化
    idx=$(( (seed / (10 ** shift_by)) % count ))
    printf '%s' "$(printf '%s\n' "$items" | sed -n "$((idx + 1))p")"
}

# 品牌名：取域名首个标签，首字母大写（world.example.com -> World）
easynet_edge_site_brand() {
    local domain="${1:-}" label
    label="${domain%%.*}"
    printf '%s' "${label:0:1}" | tr '[:lower:]' '[:upper:]'
    printf '%s\n' "${label:1}"
}

easynet_edge_site_404_html() {
    local brand="$1" accent="$2" year="$3"
    cat <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>404 - ${brand}</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='7' fill='%23${accent#\#}'/></svg>">
<style>
:root { --accent: ${accent}; --text: #1f2328; --muted: #6b7280; }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
  font: 16px/1.7 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  color: var(--text); background: #fff; padding: 24px; }
main { max-width: 34rem; text-align: center; }
h1 { font-size: 3.5rem; margin: 0; color: var(--accent); font-weight: 700; letter-spacing: -0.02em; }
p { color: var(--muted); margin: 0.75rem 0 1.75rem; }
a { color: var(--accent); text-decoration: none; border: 1px solid currentColor; border-radius: 6px; padding: 0.5rem 1.1rem; display: inline-block; }
a:hover { opacity: 0.75; }
</style>
</head>
<body>
<main>
  <h1>404</h1>
  <p>你访问的页面不存在，或者已经被移动了。</p>
  <a href="/">返回首页</a>
</main>
<footer style="position:fixed;bottom:1rem;left:0;right:0;text-align:center;color:var(--muted);font-size:.8rem">&copy; ${year} ${brand}</footer>
</body>
</html>
EOF
}

easynet_edge_site_index_html() {
    local brand="$1" domain="$2" accent="$3" year="$4" tagline="$5" about="$6" sections="$7" footer="$8"
    local section_html="" name body
    while IFS='|' read -r name body; do
        [ -n "$name" ] || continue
        section_html+="      <h2>${name}</h2>
      <p>${body}</p>
"
    done <<< "$sections"

    cat <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${brand}</title>
<meta name="description" content="${tagline}">
<link rel="canonical" href="https://${domain}/">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='7' fill='%23${accent#\#}'/></svg>">
<style>
:root { --accent: ${accent}; --text: #1f2328; --muted: #6b7280; --line: #e5e7eb; }
* { box-sizing: border-box; }
body { margin: 0; color: var(--text); background: #fff;
  font: 16px/1.75 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; }
header { border-bottom: 1px solid var(--line); }
.wrap { max-width: 46rem; margin: 0 auto; padding: 0 24px; }
header .wrap { display: flex; align-items: baseline; justify-content: space-between; padding-top: 26px; padding-bottom: 26px; }
.brand { font-size: 1.35rem; font-weight: 700; letter-spacing: -0.01em; }
.brand span { color: var(--accent); }
.top-note { color: var(--muted); font-size: 0.85rem; }
main { padding: 56px 0 24px; }
.lead { font-size: 1.5rem; font-weight: 600; margin: 0 0 0.6rem; letter-spacing: -0.01em; }
.tagline { color: var(--muted); margin: 0 0 2.6rem; }
section { margin: 0 0 2.1rem; }
h2 { font-size: 1.02rem; margin: 0 0 0.35rem; }
h2::before { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 2px;
  background: var(--accent); margin-right: 9px; vertical-align: 1px; }
p { margin: 0 0 0.9rem; }
footer { border-top: 1px solid var(--line); color: var(--muted); font-size: 0.85rem; padding: 22px 0 34px; margin-top: 2rem; }
a { color: var(--accent); }
@media (max-width: 480px) { .lead { font-size: 1.25rem; } main { padding-top: 36px; } }
</style>
</head>
<body>
<header>
  <div class="wrap">
    <div class="brand">${brand}<span>.</span></div>
    <div class="top-note">${domain}</div>
  </div>
</header>
<main class="wrap">
  <p class="lead">${tagline}</p>
  <p class="tagline">${about}</p>
${section_html}
</main>
<footer>
  <div class="wrap">&copy; ${year} ${brand} · ${footer}</div>
</footer>
</body>
</html>
EOF
}

# 渲染默认伪装站到 <web_root>。仅写 index.html / 404.html / robots.txt。
easynet_edge_site_render() {
    local web_root="$1" domain="$2"
    local seed brand accent year tagline about sections footer

    seed="$(easynet_edge_site_seed "$domain")"
    brand="$(easynet_edge_site_brand "$domain")"
    accent="$(easynet_edge_site_pick "$seed" 1 easynet_edge_site_accents)"
    tagline="$(easynet_edge_site_pick "$seed" 2 easynet_edge_site_taglines)"
    about="$(easynet_edge_site_pick "$seed" 3 easynet_edge_site_abouts)"
    footer="$(easynet_edge_site_pick "$seed" 4 easynet_edge_site_footers)"
    sections="$(easynet_edge_site_sections)"
    year="$(date +%Y)"

    mkdir -p "$web_root"
    easynet_edge_site_index_html "$brand" "$domain" "$accent" "$year" \
        "$tagline" "$about" "$sections" "$footer" > "$web_root/index.html"
    easynet_edge_site_404_html "$brand" "$accent" "$year" > "$web_root/404.html"
    # robots.txt：按种子选变体；选中 none 时删除旧文件（不生成）
    local robots_pick robots_key robots_body
    robots_pick="$(easynet_edge_site_pick "$seed" 5 easynet_edge_site_robots_pool)"
    robots_key="${robots_pick%%|*}"
    robots_body="${robots_pick#*|}"
    if [ "$robots_key" = "none" ]; then
        rm -f "$web_root/robots.txt"
    else
        printf '%b\n' "$robots_body" > "$web_root/robots.txt"
    fi
    chmod 644 "$web_root/index.html" "$web_root/404.html" 2>/dev/null || true
    [ -f "$web_root/robots.txt" ] && chmod 644 "$web_root/robots.txt" 2>/dev/null || true
}

# 安装伪装站。
# 用法: easynet_edge_site_install <web_root> <domain> <state_dir> [site_dir]
#   site_dir 非空（EASYNET_EDGE_SITE_DIR）→ 始终以它为准覆盖 web_root
#   否则 → 生成默认站点；但若 index.html 已存在且不是我们生成的，则保留不动
# 递归依赖 sha256sum(macOS 无)->shasum -a 256->cksum，任一可用即可。
easynet_edge_site_file_hash() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        cksum "$file" | awk '{print $1}'
    fi
}

easynet_edge_site_install() {
    local web_root="$1" domain="$2" state_dir="$3" site_dir="${4:-}"
    local marker="$state_dir/camouflage_site.state" seed expected recorded wanted

    seed="$(easynet_edge_site_seed "$domain")"
    expected="generated:${seed}"

    if [ -n "$site_dir" ]; then
        if [ ! -d "$site_dir" ]; then
            log_error "EASYNET_EDGE_SITE_DIR 不存在或不是目录: $site_dir"
            exit 1
        fi
        mkdir -p "$web_root" "$state_dir"
        cp -R "$site_dir"/. "$web_root"/ || {
            log_error "复制自带站点失败: $site_dir → $web_root"
            exit 1
        }
        printf 'external:%s\n' "$site_dir" > "$marker"
        log_info "伪装站已使用自带内容: $site_dir → $web_root"
        return 0
    fi

    mkdir -p "$state_dir"
    recorded="$(cat "$marker" 2>/dev/null || true)"
    # 手工改过的 index.html 不能覆盖：只有当它仍然是我们上次生成的**那一份**
    # （内容哈希与记录一致）时才重新生成。删除该文件即可恢复默认伪装站。
    if [ -f "$web_root/index.html" ] && [ "$recorded" != "$expected:$(easynet_edge_site_file_hash "$web_root/index.html")" ]; then
        log_info "检测到自定义 $web_root/index.html，保留不动（删除该文件可恢复默认伪装站）"
        printf 'external:%s\n' "manual" > "$marker"
        return 0
    fi

    easynet_edge_site_render "$web_root" "$domain"
    wanted="$expected:$(easynet_edge_site_file_hash "$web_root/index.html")"
    printf '%s\n' "$wanted" > "$marker"
    log_info "伪装站已就绪: $web_root/index.html（自洽静态站，无第三方内容）"
}
