# 变更日志

项目所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
本项目遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

## [未发布]

### 新增
- **Hysteria2 端口跳跃间隔随机化（sing-box）**：订阅生成器现在为 sing-box 客户端输出
  `hop_interval_max`（v1.14+ 的随机跳跃区间），客户端在 `[hop_interval, hop_interval_max]`
  间随机取跳变间隔，跳跃节奏不再固定。由 `EASYNET_HYSTERIA2_PORT_HOP_INTERVAL_MAX` 控制
  （默认 `60s`；设为与 `EASYNET_HYSTERIA2_PORT_HOP_INTERVAL` 相同即退回固定间隔）。
  mihomo / Shadowrocket 维持固定整数——mihomo 的范围方言（`"30-60"`）仅 1.19.x+ 支持，
  写范围会打挂更早的客户端（实测真二进制已纳入 CI 校验）。
- **监控新增「上游维度」告警：版本漂移 + CVE**（`scripts/core/monitor.sh`）：每日检查运行中的
  二进制版本是否与 release pin 一致（发现手工替换 / 升级半途失败），并用 OSV.dev 查询
  Xray / Hysteria2 / Shadowsocks 运行版本的已知漏洞。开关 `EASYNET_MONITOR_UPSTREAM` /
  `EASYNET_MONITOR_CVE`。与 CI 的 `pins.yml`（repo pin vs 上游稳定版）分工，不重复。

### 修复
- **测试不再依赖网络**：`generate_subscription.sh` 会发布客户端二进制镜像（从 GitHub 下载
  pinned sing-box），测试 setup 触发后会在离线/受限环境挂满 `--max-time 300`。现在
  `tests/test_helper.bash` 默认 `EASYNET_PUBLISH_CLIENT_BINARIES=false`，显式测试发布的
  `test_client_binaries.bats` 自行开启。

## [0.0.16] - 2026-09-28

### 新增
- **运行监控告警**（`scripts/core/monitor.sh` + `easynet monitor [run|check]`）：每日检查
  协议服务 / nginx / fail2ban 存活、订阅端点可达、Edge 证书 7 天到期预警；失败时经
  `email` / `ntfy` / `telegram` 推送告警，成功时写心跳 `last_ok`。渠道由
  `EASYNET_MONITOR_*` 配置，仅当渠道 + 凭据齐全时 `deploy.sh` 才安装 cron（
  `EASYNET_MONITOR_CRON`，默认 `0 9 * * *`）。

### 修复
- **`rm -rf` 安全护栏**：`install.sh` 与 `deploy.sh` 回滚路径现在拒绝把
  `EASYNET_INSTALL_DIR` / `EASYNET_STATE_DIR` 指向 `/`、`/etc`、`/var` 等文件系统
  关键目录（与 `core/uninstall.sh` 的 `uninstall_safe_path` 对齐，补齐此前安装/回滚
  两条路径缺失的护栏）。
- **Hysteria2 配置 YAML 值引号化**：auth/obfs 密码与 masquerade url/dir 改为 YAML
  单引号标量（`yaml_squote`），操作者用 `EASYNET_HYSTERIA2_*` 覆盖时，值含 `:`/`#`/`&`
  等特殊字符不再生成非法或被静默截断的配置。
- **下载加超时**：`core/download.sh` 的 curl/wget 增加 connect/max 超时，避免网络抖动时
  部署无限挂起。

## [0.0.15] - 2026-09-28

### 新增
- **客户端二进制镜像（Edge 托管）**，修掉"设备自举死角"：设备（树莓派等）一旦代理失效，
  就无法从 GitHub 下载 sing-box 自救——实测国内直连 GitHub release **卡死**（90 秒 0 字节后
  `curl: (18)`），而订阅站通常是通的。现在部署时会把 pinned 的 sing-box 发布到
  `$WEB_ROOT/bin/`（含 `.sha256` 与 `manifest.json`），通过随机前缀暴露给设备：
  `/s/<前缀>/bin/sing-box-<版本>-<平台>.tar.gz`。best-effort：失败只告警、不中断部署；
  `easynet clients` 可查看/刷新，`easynet clients status` 查看各平台状态。
- **安装器与每日更新支持"订阅站优先、GitHub 兜底"的双源下载**：两个来源都必须通过
  `pins.sh` 的同一个 SHA256，因此镜像不可信也不影响完整性（`--sing-box-url` 仍可强制指定来源）。
- **每日更新服务现在会对齐 sing-box 版本**：以订阅站的 `bin/manifest.json` 为准（安装时写入 env
  的 pin 作回落），版本不一致时从订阅站取包、校验后替换并重启——服务端日后 bump pin，设备会在一天内
  自动跟上（此前更新只刷新配置/规则集，sing-box 本体永远停在安装当天的版本）。
- `docs/clients.md` 新增《设备恢复手册》：正常恢复 / 手工兜底（`file://` + pin 哈希）两条路径。

### 变更
- 新增开关：`EASYNET_PUBLISH_CLIENT_BINARIES=false`（服务端不发布镜像）、
  `EASYNET_SINGBOX_MIRROR=false`（设备端只用 GitHub）。

### 测试
- 新增 `tests/test_client_binaries.bats`（平台/资产/端点映射、Edge 前缀路由、状态、真实发布与幂等）。
- `test_singbox_client_installer.bats` 新增 5 项（双源顺序、显式 URL、镜像开关、env 写入 pin、更新脚本对齐）。

## [0.0.14] - 2026-09-28

### 新增
- **发布前的真客户端校验**（`scripts/client_check.sh`）：按 pin 下载并校验 mihomo / sing-box 二进制，
  用它校验我们生成的 Clash / sing-box 订阅。客户端字段名/类型/单位只能由真客户端判定——
  0.0.13 的 `invalid range: 30s` 事故正是因为当时只有字符串断言（还把错误格式写成了预期值）。
  - CI 新增 job `client-config-validation`，并作为 **release 的前置依赖**：真客户端拒收就发不出 release；
    该 job 设 `EASYNET_REQUIRE_CLIENT_CHECK=1`，拉不到二进制即失败（不允许静默通过）。
  - 二进制按 `scripts/core/pins.sh` 的 `EASYNET_PIN_MIHOMO_*` / `EASYNET_PIN_SINGBOX_*` 固定
    （Linux/amd64、Linux/arm64、Darwin/amd64），缓存里的资产每次使用前重新校验 SHA256。
  - 测试自带哨兵：把 `hop-interval` 写成 `"30s"` 必须被 mihomo 拒绝，否则说明校验器失效。
- **`easynet upgrade [<tag>]`**：release 安装的机器也能一条命令升级（复用官方安装器的
  下载 + SHA256 + staging 替换流程，自动保留 `.env`）。此前只能重跑安装器。
- **`easynet status` 显示分流规则集状态**，未发布时直接给出补救命令（`easynet rules`）。

### 安全
- **客户端安装器（`install_singbox_client.sh`）改为按 pin 安装 sing-box**：此前查 GitHub
  `latest` 且校验和可选——服务端四个组件都有 pin + SHA256，而在用户设备上以 root 运行的安装器
  反而裸拉 latest。现在默认使用仓库内置版本与 SHA256；覆盖版本必须显式提供校验和
  （或 `EASYNET_SINGBOX_SKIP_SHA256=true` 自担风险）。内联常量与 `core/pins.sh` 的一致性有防漂移断言。
- **伪装站的 `robots.txt` 按域名种子随机化**（含"不生成"变体）：此前所有部署的 `robots.txt`
  **逐字节相同**（实测两台机器 md5 一致），一个恒定文件本身就是"同源模板"指纹。

### 变更
- **发版缺少 CHANGELOG 条目时硬失败**（此前只 warn 并以占位文本发布——0.0.13 的 release notes
  就只有 "Release 0.0.13"）。
- **`deploy.sh` 不再安装 `git`**：release 安装（生产唯一推荐路径）用不到它；文档中的
  `git clone` 路径明确标注为"仅开发 / 审计"，生产升级走 `easynet upgrade`。

### 测试
- 新增 `tests/test_client_config_validation.bats`（真客户端校验 + 两类哨兵 + 缓存防替换）。
- `tests/test_singbox_client_installer.bats` 新增 pin 断言与"覆盖版本必须给校验和"等 6 项。

## [0.0.13] - 2026-09-28

### 修复
- **Clash / mihomo 客户端无法导入订阅（`proxy 1: invalid range: 30s`）**：hysteria2 端口跳跃的
  间隔字段在三个客户端是三种方言，元数据里存的是 sing-box 方言 `"30s"`，而 mihomo 的
  `hop-interval` 是**整数秒**字段——它会把 `30s` 拿去当端口范围解析，报出误导性的
  `invalid range: 30s` 并**拒绝整份配置**（不是单节点失败）。
  现在 `render_clash.sh` 按客户端方言换算：`30s→30`、`1m→60`、纯数字沿用；无法识别的值
  **省略该字段**（交给客户端默认值），绝不写非法值。sing-box 侧仍输出 `"30s"`。
- **静态文件服务下 web root 里的订阅文件被直接吐出（凭据泄露）**（0.0.12 引入的回归，随本版修复）：
  0.0.12 把 Edge 根路径从「反代」改成「静态文件服务」后，`/var/www/html/{sub,clash,singbox}` 等
  订阅文件可被 `try_files` 当成静态文件直接返回，`https://<域名>/sub` 即可拿到全部节点凭据
  （旧版走反代所以看不见这些路径）。现在未开启 `EASYNET_SUBSCRIPTION_DIRECT_PATHS` 时，会从
  **同一份端点定义**自动生成 `location = /<file> { return 404; }` 拒绝规则，新增端点自动生效。

### 文档
- `docs/clients.md` 新增《端口跳跃的客户端方言》对照表（sing-box / mihomo / Shadowrocket URI
  三种写法与字段类型），并明确：**修改任何客户端渲染字段必须用真二进制校验**
  （`mihomo -t` / `sing-box check`），不要只做字符串断言。
- 验收流程新增"真客户端配置可解析性"检查（`mihomo -t` 导入 Clash 订阅 +
  `sing-box check` 解析 sing-box 订阅 + 逐节点真实出网）。

## [0.0.12] - 2026-09-28

### 安全
- **伪装站不再反代第三方大站**（旧默认 `https://www.bing.com`）：透明反代会把「这是反代」直接
  写进响应，任何探针一眼可辨 —— `canonical` 指向 `www.bing.com`、响应里塞十几条
  `Set-Cookie: ...; domain=.bing.com`、`UserAgentReductionOptOut` 的 base64 解出来含
  `"origin":"https://www.bing.com:443"`、还镜像了对方的 `/robots.txt` 与 `/sitemap.xml`，
  并且**任意 Host 都返回同一个 bing 首页**。从一台 VPS 的 IP、用自家域名的 LE 证书返回与
  大站首页逐字节相同的内容，是经典镜像特征（内容哈希即可识别）。
  现改为**自托管自洽静态站**：按 `cksum(域名)` 确定性生成文案与配色（同域名重部署稳定、
  不同部署内容不同，避免所有实例长得一样），完全自包含（内联 CSS / 内联 SVG favicon / 零外部请求）、
  不出现任何工具名；附带 `404.html` 与 `robots.txt`。生产可用 `EASYNET_EDGE_SITE_DIR` 放自有内容。
- **Hysteria2 masquerade 同步改为 `file →` 同一份静态站**（旧默认 `proxy → bing`）。
  实测：开启 `obfs: salamander` 后，未经混淆的 QUIC 探针收不到任何响应，UDP 侧本就不易被扫到，
  但配置仍保持文字一致。
- **Reality `borrow` 模式不再提供第三方大站默认值**（原 `www.bing.com:443` /
  `www.bing.com,www.cloudflare.com`）：默认借用大站会让所有实例共用同一伪装目标（集体指纹），
  且从非 CDN 的 VPS IP 声称自己是某大站是不合理的 SNI→IP 映射。现在必须显式填写，否则拒绝部署。
- **禁用发行版自带的 nginx 默认站点**：否则未知 Host 会看到 "Welcome to nginx!" 欢迎页
  （全新安装指纹）。卸载时恢复该软链。

### 修复
- **规则集未发布时客户端启动失败**：`/singbox` 订阅过去无条件写入远程 `rule_set`，
  而服务器上 `.srs` 尚未生成（手动步骤）时客户端拉取 404 会导致 sing-box **直接启动失败**。
  现在未发布即自动省去 `rule_set` 与依赖它的策略规则（部署日志给出 WARN），客户端仍可正常代理。
  （文档一直这么写，代码此前没做到 —— 现在两者一致。）

### 新增
- `easynet rules`：一键构建/更新 sing-box 分流规则集（等价 `./scripts/generate_singbox_rules.sh`）。
- nginx 自愈：为 `nginx.service` 写 `Restart=on-failure` + `RestartSec=5` drop-in
  （发行版默认 `Restart=no`，而 nginx 同时承担伪装站、订阅分发与 Reality 回落目标）。
- Edge 启用 **HTTP/2**（nginx ≥1.25.1 用 `http2 on;`，旧版退回 `listen ... ssl http2`）。

### 测试
- 新增 `tests/test_camouflage_site.bats`（14 项）：无第三方引用 / 无工具名 / 同域名幂等 /
  跨域名不同 / 手工内容不被覆盖 / 自带站点优先 / 默认值不得含大站伪装目标 等。
- `tests/test_edge_config.bats` 改为**直接 source 真实 `deploy.sh`** 断言真实配置
  （此前内联复刻模板，正是这样漏掉了「默认反代 bing」）。

## [0.0.11] - 2026-09-27

### 修复
- **Hysteria2 端口跳跃（Port Hopping）此前从未真正生效**：服务端配置里写的是客户端专有的
  `portHopping:` 块（服务端会静默忽略），而订阅却向客户端宣告 `porthopping=20000-30000` ——
  会跳变的客户端会被送到无人监听的端口。现改为服务端 `listen: :<基础端口>,<范围>`，
  由 hysteria 内建范围支持接管：监听基础端口并**自动创建/回收 nftables 重定向**（范围 → 基础端口）。
  同时把沙箱补上 `AF_NETLINK`（否则服务启动即致命错误：`Unable to initialize Netlink socket`），
  并按各客户端方言输出跳变字段：sing-box `server_ports` + `hop_interval`、mihomo `ports` +
  `hop-interval`、URI 保留 `porthopping` 兼容参数。实测：服务端对 443/20000/23456/25000/29999
  全部返回 204；`hop_interval=5s` 的跳变客户端 35 秒内 7/7 请求成功。
- **`set -o pipefail` + `producer | head -1` 会中止部署**：生产者收到 SIGPIPE 返回 141，`set -e`
  随即退出（实测 `xray version | head -1` 直接让部署中断）。全仓库 12 处改为 `awk 'NR==1'` /
  `find -print -quit` / 单遍 awk，并新增 lint 规则防回归。
- **`install_hysteria2` 在二进制已最新时提前返回**，跳过服务账号/运行时目录/systemd unit 的创建
  （实测：删除 `hysteria` 用户后重部署，服务卡在 `activating`）。现运行时准备无条件执行。
- **卸载后仍对外开放 UDP 端口范围**：元数据把范围存成 `20000-30000`（连字符），UFW 需要
  `20000:30000`（冒号），`ufw delete` 报 `Bad port` 又被 `|| true` 吞掉。现抽出
  `firewall_normalize_rule()` 作为唯一归一化入口，apply 与 uninstall 共用。
- **`scripts/uninstall.sh` 调用了 `core/uninstall.sh` 的函数却没 source 它** → `command not found`
  （exit 127）→ `set -e` 中断整个收尾流程（cron 未刷新、`~/.easynet` 索引未更新）。
- 卸载遗留：systemd 加固 drop-in、上游旧模板单元（`xray@.service`、`hysteria-server@.service`、
  `10-donot_touch_single_conf.conf`）、sing-box 规则集、证书指纹状态、状态目录空骨架。
- `~/.easynet` 索引不再保留指向已删除路径的断链（剪枝只处理 hub 自建链接，不穿透目录软链）。
- lint 的「`$VAR` 紧跟多字节字符」检查此前用 `grep -P`，而 BSD grep 无 `-P` → 本地 macOS 静默通过
  （CI 才发现）。改用可移植写法 `LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]'`。

### 变更
- **所有二进制依赖改为「仓库内 pin 版本 + SHA256 且默认强制校验」**：新增 `scripts/core/pins.sh`
  （Xray `26.3.27`、hysteria2 `2.12.3`、shadowsocks-rust `1.25.0`、acme.sh `3.1.6`，每架构独立哈希，
  来源为厂商自身发布元数据）。哈希不匹配即中止部署。
- **不再执行第三方安装脚本**：Xray 改为直接下载官方 release zip（原来从 `main` 分支取
  `install-release.sh`，脚本本身无法 pin），Hysteria2 改为直接下载官方 release 二进制
  （原来取 `get.hy2.sh`，永远装 latest）。两者改用自写 systemd unit，并自动创建 `hysteria` 系统账号。
- 覆盖版本但未提供 SHA256 → **默认拒绝部署**（`EASYNET_ALLOW_UNPINNED=1` 可强制跳过，不建议）。
- shadowsocks-rust `1.24.0 → 1.25.0`；替换二进制后强制重启服务（否则运行的仍是旧镜像）。
- 新增 `scripts/check_upstream_pins.sh` + `.github/workflows/pins.yml`（每周检查 pin 是否落后上游
  **稳定版**；Xray 的 pre-release 不会被误报）。
- 纠正文档中的一个前提错误：Xray 并非「落后上游 6 个月」——自 `26.4.15` 起其所有 release 均为
  pre-release，`26.3.27` 就是最新稳定版。
- 端口跳跃现已生效，因此**云厂商安全组必须放行整个 UDP 范围**（本机 UFW 由 EasyNet 自动处理）；
  部署输出与会话结束提示都会明确提醒。
- 测试 362 → 386。

## [Unreleased]

### 新增
- **Xray+Reality「自偷」伪装模式**（`EASYNET_REALITY_MODE=auto|self|borrow`）：复用解析到本机的
  自有域名作为 Reality SNI，回退到本机 Edge 站点，以对抗 2026 年出现的「SNI→DNS 一致性检查」
  （审查者记录 (SNI, 目的IP) 后解析 SNI，若不一致即判定可疑；开源 DPI 库 nDPI 已实现）。
  `auto`（默认）检测到本机 Edge 证书时自动启用，否则回退「借用外部站点」。
- **节点国家旗帜 `flag`**：订阅 URI 自动带上 `flag=XX`（ISO 3166-1 alpha-2），供Shadowrocket
  等客户端显示节点国家旗帜；可用 `EASYNET_FLAG` 覆盖，默认通过 ipinfo.io 推断（与公网 IP 探测同源），
  失败则省略。

### 变更
- **sing-box 订阅不再输出 AmneziaWG 节点**：mainline sing-box 不支持 AmneziaWG（其 WireGuard
  endpoint 拒绝 `jc/jmin/...`：`json: unknown field "jc"`），该节点永远连不上，此前还会污染
  `Proxy` 选择器与 `Auto` 测速。现从 sing-box 订阅中整体剔除（含 selector/urltest 引用）；
  URI / Clash 订阅不受影响。若后续 sing-box 支持 AmneziaWG，恢复 `render_singbox.jq` 即可。
- **远端规则集下载迁移到 `http_clients`**：sing-box 1.14 起 `download_detour` 已弃用、1.16 移除。
  订阅改为顶层 `http_clients` + `route.default_http_client`，并在 `DIRECT` 出站显式加
  `udp_fragment: true`（与默认值相同，仅为让出站「非空」——否则 sing-box 报
  `detour to an empty direct outbound makes no sense`）。sing-box 订阅要求 **1.14+**。
- **WireGuard → 真 AmneziaWG**：模块改用 AmneziaWG（`awg`/`awg-quick`，配置目录 `/etc/amnezia/amneziawg`，
  systemd 服务 `awg-quick@wg0`），部署时随机生成并持久化 Jc/Jmin/Jmax/S1/S2/H1-H4 并写入客户端订阅。
  修复此前「服务端为标准 WireGuard、客户端 URI 却携带 jc/jmin/jmax」的不一致。安全等级 60 → 50。
  客户端要求：Clash Verge Rev (mihomo ≥1.19) / Shadowrocket；sing-box 不支持。
- **Reality 回退限速**（`EASYNET_REALITY_LIMIT_FALLBACK_UPLOAD` / `_DOWNLOAD`）：可选限制未通过校验的
  回退连接速率（`afterBytes:bytesPerSec:burstBytesPerSec`），防止节点被当作免费加速/滥用。

### 改进
- Reality 配置改为**幂等渲染**：先在临时文件生成目标配置，与现有配置一致时跳过写入与重启；
  支持在不改动 UUID/私钥/Short ID 的前提下切换传输方式与伪装模式。

### 修复
- **Xray 配置权限**：Xray 以 `nobody` 运行时无法读取 `600 root` 的 `config.json`，导致服务启动失败
  （`open ... permission denied`）。现按 systemd 服务的实际用户设置权限
  （`root` → `600`；其他用户 → `640 root:<group>`）。

### 文档
- 新增 `docs/unified-backend-analysis.md`：评估是否将多协议收敛为统一服务端实现（含
  **sing-box 与 Xray-core 两条路线**），含能力对照、收益/代价、趋势判断与建议路线；
  结论为「维持现状，优先评估 Xray-core」（Xray 保留了 XHTTP/Finalmask，与抗 DPI 定位更契合）。
- 文档与示例域名改用语义中性的 `world.example.com`，补充避开 GFW 关键词与 Reality 自偷的指引。
- sing-box 相关文档同步：订阅要求 1.14+、AmneziaWG 不在 sing-box 订阅中、未发布
  `/rules/*.srs` 会让 `/singbox` 启动失败（需先跑 `generate_singbox_rules.sh`）。

### 测试
- `tests/test_config_generation.bats` 新增 Reality 自偷 / 回退限速 / AmneziaWG 参数用例；
  `tests/test_protocol_metadata.bats` 新增 Shadowrocket obfs / 国家旗帜 / mihomo amnezia-wg-option
  断言并补充 AmneziaWG 夹具；测试总数 314 → 331。

### 安全性（本轮审计）
- **Shadowsocks PSK 不再泄露**：此前 PSK 同时出现在 `ExecStart` 命令行（`/proc/<pid>/cmdline`
  任何本地用户可读）与 world-readable（644）的 `config.json` 中。现改为 `ssserver --config`，
  配置写入 `mode: tcp_and_udp` 并设为 `640 root:nogroup`。
- **`CapabilityBoundingSet=~` 语义修正**：systemd 中 `~` 表示「对空集取反」= 授予全部能力
  （运行时实测 `CapBnd=0x1ffffffffff`）。已改为空集，ssserver 现以零能力运行。
- **新增 systemd 沙箱**：xray / hysteria-server 通过 drop-in（`easynet-hardening.conf`）
  启用 `ProtectSystem=strict`、`ProtectHome`、`PrivateTmp`、`ProtectKernel*`、
  `RestrictNamespaces`、`RestrictAddressFamilies` 等，不覆盖上游 unit（升级友好）。
- **新增 fail2ban**：安装并启用 `sshd` jail（`maxretry=5`、`bantime=1h`），写入
  `/etc/fail2ban/jail.d/easynet.local`，不覆盖用户自己的 `jail.local`。
- **`docs/security-audit.md` 重写**：以 2025–2026 最新公开研究（SNI→DNS 一致性检查、
  Geedge TSG 源码分析、QUIC SNI 过滤）为判据，逐协议给出抗 DPI 判定，并列出未修复项
  （SSH root 密码登录 / 订阅直连路径默认开启）及风险等级。

### 修复
- **sing-box 客户端每日自动更新失效**：`easynet-singbox-update.service` 使用
  `DynamicUser=yes` + `ProtectSystem=full`，既读不到 600 的 `/etc/easynet/singbox-client.env`
  （`Permission denied`），也无法写入 `/etc`，导致客户端**永远无法随服务端变化自动更新**。
  改为以 root 运行 + `ProtectSystem=strict` + `ReadWritePaths`，实测更新成功并自动重启。
- **fail2ban 误封风险**：`mode = aggressive` 的 ddos/extra 规则会匹配「连接被关闭」等正常事件；
  改为默认 `normal`，并把部署时 SSH 会话来源 IP 自动写入 `ignoreip`。

### 文档
- 新增 `docs/audit-2026-09-27.md`：重置后全新部署的验收结论 + 安全性/稳定性/访问速度/
  客户端体验四维审计（含实测数据与 3 项遗留改进）。

### 变更（第四轮：供应链 pin 一等公民化）
- **所有二进制依赖改为「仓库内 pin 版本 + SHA256，且默认强制校验」**：新增
  `scripts/core/pins.sh`（Xray `26.3.27`、hysteria2 `2.12.3`、shadowsocks-rust `1.25.0`、
  acme.sh `3.1.6`，每架构独立哈希）。哈希来源均为厂商自身发布元数据
  （Xray `.dgst` / hysteria `hashes.txt` / SS `.sha256`）。
- **不再执行第三方安装脚本**：Xray 改为直接下载官方 release zip（原来从 `main` 分支取
  `install-release.sh`），Hysteria2 改为直接下载官方 release 二进制（原来取 `get.hy2.sh`）。
  两者随之改为自写 systemd unit，并自动创建 `hysteria` 系统用户。
- **覆盖版本但未提供 SHA256 → 默认拒绝部署**（`EASYNET_ALLOW_UNPINNED=1` 可强制跳过）。
- shadowsocks-rust 升级 `1.24.0 → 1.25.0`；替换二进制后**强制重启服务**（否则运行中的仍是旧镜像）。
- 新增 `scripts/check_upstream_pins.sh` + `.github/workflows/pins.yml`（每周检查 pin 是否落后
  上游**稳定版**；Xray 的 pre-release 不会被误报）。
- **修复一类潜在崩溃**：`set -o pipefail` 下 `producer | head -1` 会让生产者收到 SIGPIPE
  返回 141，`set -e` 随即中止脚本（实测 `xray version | head -1` 直接导致部署中断）。
  全仓库 12 处改为 `awk 'NR==1'` / `find -print -quit` / 单遍 awk，并加 lint 防回归。
- 修正第三轮审计的一个前提错误：Xray「落后 6 个月」不成立——`26.3.27` 是最新稳定版。
- `install_hysteria2` 在二进制已是最新时提前返回，**跳过了服务账号/状态目录/systemd unit 的
  创建**（实测：删除 `hysteria` 用户后重部署，服务卡在 `activating`）。现改为无论是否需要下载
  都执行运行时准备，并由「模拟全新机器」的破坏性测试验证通过。

### 修复（第三轮全面审计）
- **状态目录不再 world-readable**：`/var/lib/easynet` 及其下**订阅路径前缀**（保护全部凭据的唯一
  秘密）原为 `755/644`，任意本地用户可读。新增 `easynet_secure_state_dir()`，状态树收敛为 `700`、
  前缀与生成的路由文件 `600`（`setpriv` 实测 Permission denied）。
- **伪装页不再输出重复且冲突的安全头**：上游（bing）透传 + 自身 `add_header` 导致两个 `HSTS max-age`
  与两个 `X-Frame-Options`，违反 RFC 6797 且本身是指纹。三个 `location /` 增加 `proxy_hide_header`。
- **hysteria-server 崩溃自恢复**：上游 unit 无 `Restart=`（默认 `no`），崩溃后只能等每日 cron。
  沙箱 drop-in 统一补 `Restart=on-failure` + `RestartSec=5`（`kill -9` 实测 5 秒拉起）。
- **客户端 mixed 监听地址可配置**：新增 `--listen-address` / `EASYNET_SINGBOX_LISTEN`（默认保持
  `0.0.0.0` 以支持局域网共享），非 loopback 时显式告警「开放代理」风险；提示文案随实际绑定地址变化。
- **Edge 隐匿 nginx 版本**：`server_tokens off`（原 `Server: nginx/1.28.3 (Ubuntu)`）。
- **lint 盲区修复**：`test_lint_unbound_vars.bats` 原先只查裸 `$VAR`，**不查 `${VAR}`**——后者在
  `set -u` 下同样会崩溃。扩展规则后扫出 3 处并修正（`install_singbox_client.sh`、
  `edge/deploy.sh`、`shadowsocks/deploy.sh`）。
- 文档纠错：上轮报告「仅 TLS 1.3」实为 **TLS 1.2 + 1.3**（1.0/1.1 拒绝，1.2 为刻意保留）；
  「服务端内存 ≈62MB」实为 **≈104MB**（漏计 fail2ban）。
- 新增 `docs/audit-round3.md`（第三轮全面审计：31 项历史问题闭环核验 + 运行态取证）。

### 新增
- **运维工作目录 `~/.easynet` + 统一命令 `easynet`**：EasyNet 涉及的路径天然分散在上游硬编码
  的位置（`/usr/local/etc/xray`、`/etc/hysteria`、`/etc/shadowsocks-rust`、`/etc/amnezia/amneziawg`、
  `/etc/nginx`、`/etc/ssl/easynet-edge`、`/root/.acme.sh`、`/var/lib/easynet`、`/var/www/html`）。
  物理搬迁会破坏上游升级与重装幂等，因此改为生成一个**符号链接索引目录** `~/.easynet`（含
  自动生成的 `README.md` 路径总表），并配套统一 CLI `easynet`
  （`status`/`where`/`path`/`config`/`edit`/`logs`/`restart`/`sub`/`deploy`/`ssh`/`doctor`…）。
  自动软链到 `/usr/local/bin/easynet`；`easynet deploy` 把部署日志收敛到 `~/.easynet/logs/`。
  hub 为纯 `mkdir`/`ln` 操作，删除无副作用，不参与服务运行。
- protocol manifest 新增 `MODULE_CONFIG_DIR`：新增协议时声明配置目录，hub 自动索引。

### 变更
- **订阅直连路径默认关闭**（`EASYNET_SUBSCRIPTION_DIRECT_PATHS` 默认 `true` → `false`）：固定的
  `/sub`、`/clash`、`/singbox` 可被猜中（域名可从证书透明度日志获知），默认仅提供不可猜的随机
  路径。新增 `EASYNET_SUBSCRIPTION_PATH_PREFIX` 校验（拒绝空白/`?`/`#`/`&`，过短告警），可用于
  **固定订阅路径**，使重装服务器后客户端订阅 URL 不变。
- **重部署零中断**：hysteria2 / shadowsocks / amneziawg 增加「渲染 → 比对 → 未变化则跳过重启」；
  xray 仅在沙箱变化或服务未运行时重启；nginx 全链路改用 `reload`。
- **证书续期钩子不再引发重启风暴**：acme.sh 每次部署都会执行 `--install-cert`，此前会触发 hook
  重启全部服务；现按证书指纹比对，仅在证书真正变化时重启（nginx 用 `reload`）。
- 修复 AmneziaWG 的「旧版迁移」逻辑：不再在每次部署时删除正在使用的 `wg0` 接口。

### 新增
- **`scripts/security/harden_ssh.sh`（SSH 加固，可选、独立）**：`check` / `apply` / `confirm` /
  `revert` / `status`。`apply` 前置校验（公钥存在性 + 当前会话为 publickey）、写入前备份、
  `sshd -t` 校验、并武装 **10 分钟自动回滚**（未 `confirm` 则自动恢复，不会锁死）。drop-in 命名为
  `10-easynet-hardening.conf` 以排在 `50-cloud-init.conf` 之前（sshd「首个值生效」）。
  **不参与 `deploy.sh`**，日常迭代流程不受影响。
- 部署时若 sing-box 规则集未发布（`rules/manifest.json` 缺失）会显式告警并给出修复命令。

### 测试
- `tests/test_hardening.bats` 新增 systemd 沙箱单元名归一化、SS 密钥不入命令行、
  fail2ban jail 等用例；另新增 SSH 加固 dry-run/拒绝无公钥/回滚保险、零中断重启、
  订阅默认随机路径、规则集缺失告警等用例。测试总数 331 → 342。
- `tests/test_hub.bats` 新增 13 个用例（hub 索引/幂等/不覆盖真实文件、CLI 命令与自解析、
  manifest 配置目录声明、hub 无破坏性操作）。
- `tests/test_lint_unbound_vars.bats` 新增「`$VAR` 紧跟多字节字符必须写成 `${VAR}`」检查：
  bash 会把后随的 UTF-8 字节并入变量名（macOS bash 3.2 必崩），全仓库 23 处已修正。
  测试总数 342 → 356。

## [0.0.10] - 2026-09-26

### 改进
- **Hysteria2 密码在重部署/升级时保留**：密钥解析改为 `显式环境变量 > 上次部署写入的
  /etc/hysteria/easynet.env > 新随机值`，与 Xray-Reality / Shadowsocks / WireGuard 的保留行为一致。
  此前每次重跑 `deploy.sh` 都会轮换 Hysteria2 密码，导致客户端必须更新订阅；从 0.0.10 起
  后续升级不再轮换。
- `scripts/protocols/hysteria2/deploy.sh` 增加入口守卫，便于单测。

### 测试
- 新增 `tests/test_hysteria2_secret_preservation.bats`（8 用例）；总数 306 → 314（27 套件）。

### 文档
- 部署说明新增《升级到新版本》：说明原地升级方式与各项保留行为。

## [0.0.9] - 2026-09-26

### 新增
- **公网可达性 / IP 封锁诊断**：`scripts/diagnose_reachability.sh`——检查本机服务与监听端口、
  通过 check-host.net 多地探测公网可达性；设置 `EASYNET_DIAG_CLIENT_IP` 后可抓包自动判定
  「可达 / 回程被拦（GFW/运营商）/ 服务器未响应 / 客户端未发起」。
- 新增 `tests/test_diagnose_reachability.bats`（9 用例：静态 + 抓包分类逻辑）。

### 文档
- 故障排查指南新增《服务器 IP 被 GFW/运营商拦截》与《客户端订阅更新超时》：说明 VPS 分配的
  公网 IP 可能已被墙、自动化诊断用法、判定表与处理建议（更换 IP/机房，勿重装）。
- 全面清理过时描述：同步测试计数（306 用例 / 26 套件）；`security-audit.md` 更新已实现项
  （Nginx TLS 加固、sing-box `DynamicUser`、公网 IP 检测改 HTTPS、域名校验、备份用 `mktemp`）；
  `architecture-review.md` 补充 0.0.8 后的修复与诊断脚本；README/CLAUDE 结构树与文档链接补全。

## [0.0.8] - 2026-09-26

### 新增
- **一键安装（免 git clone）**：新增 `scripts/install.sh` 自举安装器：下载 release 包 → 校验 SHA256 →
  解压到 `/opt/easynet`（可配 `EASYNET_INSTALL_DIR`）→ 执行 `scripts/deploy.sh`。失败即中止，
  遵循「无 `curl | bash`、先落地后校验」规范；重复运行 = 原地升级脚本（保留已有 `.env`）。

  ```bash
  curl -fsSL https://github.com/EasyIndie/EasyNet/releases/latest/download/easynet-install.sh -o install.sh
  sudo bash install.sh
  ```

- **CI 发布安装产物**：release 新增 `easynet.tar.gz`、`easynet.tar.gz.sha256`、`easynet-install.sh`
  固定资产，`releases/latest/download/` 稳定可拉。
- 新增配置项：`EASYNET_VERSION`、`EASYNET_INSTALL_DIR`、`EASYNET_SKIP_SHA256`、`EASYNET_INSTALL_ONLY`、
  `EASYNET_REPO`、`EASYNET_RELEASE_BASE_URL`。
- **VPS 验收脚本**：新增 `scripts/acceptance_test.sh`，覆盖校验失败中止、一键安装、`.env` 保留与升级、
  `balanced` 真实部署、订阅生成、全卸载，支持本地 tarball 初步验收模式（一键可复现）。

### 架构
- **部署前 manifest 校验**：`deploy.sh` 新增 `validate_module_manifest()`，部署时调用
  `discovery_validate_manifest()`（fail-fast）；后者补齐 `MODULE_DEFAULT_PORT` 必填及端口范围校验。
- **严格性统一**：`render_clash.sh` ×4 改为 `set -euo pipefail`；`deploy.sh`/`uninstall.sh`/
  `generate_subscription.sh` 补齐 `set -u`；修复 `validate.sh` 的裸变量引用。
- lint 测试移除「deploy.sh 无 set -u」的过时例外，并将 `validate.sh` 纳入检查。

### 测试
- 新增 `tests/test_installer.bats`（12 用例）与 6 个 manifest 校验用例；测试总数 267 → 294（25 套件）。

### 文档
- README/部署文档改为「一键安装」优先，`git clone` 降级为开发/审计选项。
- 架构评估报告新增「0.0.8 收尾更新」章节，记录部署方式改造、架构收尾，以及
  `routes.sh` 硬编码与 `clients/` 无 manifest 两项「保留现状」的决策。

### 本次未做（后续迭代）
- 协议演进（Xray Finalmask、Hysteria2 ECH/Realms、shadowsocks-rust 升级）。
- 安全加固（Nginx TLS 密码套件/HSTS/OCSP、公网 IP 检测改 HTTPS）。

## [0.0.7] - 2026-09-26

### 增强
- **sing-box 客户端分流规则（新）**：
  - 新增 `scripts/generate_singbox_rules.sh`：把官方 GeoIP/Geosite 数据库转成二进制规则集（`.srs`），
    发布到 edge 的 `rules/` 目录，并生成带 sha256 的 `manifest.json`。数据库与构建用 sing-box
    都从官方 release 下载并校验（GitHub API 的 digest 字段）。
  - 新增 `scripts/core/singbox-rules.conf`：规则类别清单（`tag|source|category|action`），加类别只改一行。
  - `/singbox` 订阅现在自带 `route.rule_set`（指向 edge 发布的 `.srs`）与分流规则：
    **私有/回环 → 直连；CN 域名/IP → 直连；广告 → 拒绝；其余仍走代理**（`final` 保持 `Proxy` 不变）。
  - 客户端安装器会把规则集下载到本地并把 `remote` 改写为 `local`：
    **sing-box 启动不再依赖网络拉规则**（实测：远程规则集拉不到会让 sing-box 直接起不来）；
    某类规则集获取失败时自动摘除该类，保证配置始终可启动。
- **客户端每日更新后会重启 sing-box**：此前定时更新只覆盖配置文件、不重启进程，
  新配置（含规则）不会生效。现在仅当配置内容真的变化且服务在运行时才重启。
- 客户端更新新增两道保护：配置**形状守卫**（缺少 `outbounds` 即放弃安装）、
  已应用规则清单留档（`<配置目录>/rules/.manifest.json`，供 `doctor` 查看新鲜度）。

### 文档
- `docs/deployment.md`：新增"sing-box 分流规则集"一节。
- `docs/clients.md`：补充"规则不生效"的排查步骤。

## [0.0.6] - 2026-06-27

### 增强
- **Xray Reality 抗 DPI 增强**：
  - 新增 `EASYNET_REALITY_FINGERPRINT` 可配置 TLS 指纹
    (`chrome`/`firefox`/`ios`/`edge`/`random`)，默认 `chrome`
  - 新增 `EASYNET_REALITY_MAX_TIME_DIFF` 时间偏移检查（默认 30 分钟），设为 0 可禁用
  - 默认伪装域名从 `www.microsoft.com` 更换为 `www.bing.com`
  - URI/Clash 元数据中 `fp` 参数动态读取，不再硬编码 `chrome`
  - Xray-core 默认版本升级至 v26.3.27（修复 Aparecium NewSessionTicket gap，
    CVE-2026-26995 缺省填充检测，CVE-2026-27017 ECH/GREASE 指纹匹配）
  - Xray 安装脚本 SHA256 为空时显示安全警告，提示设置完整性验证
  - sing-box 渲染器添加 XHTTP 降级警告注释
- **密码学增强**：`random_secret()` 熵值从 128 位升级到 256 位（Hysteria2 密码与
  obfs 密码共享调用路径）

### 架构
- **卸载模块按安全等级排序**：`discovery_list_uninstallable_modules()` 改为调用
  `discovery_list_modules_by_security()`，使 `EASYNET_SERVICE_CHOICE`（部署菜单）
  与 `EASYNET_UNINSTALL_CHOICE`（卸载菜单）编号完全一致，避免用户混淆

### 文档
- **安全审计文档合并**：将 `SECURITY_AUDIT.md` + `SECURITY_AUDIT_2026.md`
  合并为 `docs/security-audit.md`，保留 `SECURITY.md`（漏洞报告策略）
- **`.env.example` 维护**：去重条目、补全缺失变量、合并章节、更新编号说明

### CI
- **`actions/cache` 升级至 v6**：依赖升级以消除 Node.js deprecation 警告

## [0.0.5] - 2026-06-23

### 移除
- **Xray Reality Fragment 包分片**：`EASYNET_REALITY_FRAGMENT` 及相关环境变量全部移除。Fragment 与
  `flow: xtls-rprx-vision` 存在已知冲突（两者同时修改 TLS Client Hello 导致间歇性连接失败），且
  Vision 的 uTLS 指纹伪装 + padding 已完整覆盖抗 DPI 功能，Fragment 不再需要。

### 修复
- **Xray Reality XHTTP 配置修复**：XHTTP 传输现在正确添加 `flow: xtls-rprx-vision` 和
  `encryption: none`（VLESS Encryption），消除 Xray-core v26.1.18+ 的 "VLESS without flow is
  deprecated" 警告。
- **XHTTP 默认 mode 改为 `stream-one`**：纯 TCP HTTP/2，避免 `mode=auto` 默认走 UDP/QUIC 被云商 QoS 限速。
- **XHTTP 移除 xtls-rprx-vision flow**：XTLS Vision flow 与 HTTP/2 多路复用存在底层不兼容，
  现仅保留 `encryption: none`，不再设置 `flow` 字段。
- **sing-box 不支持 XHTTP transport**：sing-box 客户端降级为 TCP Reality 配置，消除 XHTTP
  模式下客户端无法连接的兼容性错误。
- **XMUX connIdleTime 可配置**：新增 `EASYNET_REALITY_XMUX_CONN_IDLE` 环境变量（默认 60 秒），替代硬编码值。
- **CI 脚本权限检查跳过 library 文件**：`.sh` 可执行权限检查现在排除 `clients/library/` 目录，
  避免跨平台开发中的误报。
- **测试用例同步**：更新测试用例以匹配 XHTTP 无 flow 的新行为，修复测试断言。
- **xray-reality 脚本可执行权限**：修复 deploy.sh/export.sh 在部分环境中缺少可执行位的问题。

### 架构
- **跨平台开发一致性**：添加 `.gitattributes` + `.editorconfig`，统一换行符为 LF，提交时自动规范化。

### 文档
- 清理所有 Fragment 环境变量、配置示例、兼容性表格、诊断命令等文档。
- 全量文档审查更新：README/CONTRIBUTING/CLAUDE.md 同步 267 条测试计数、协议表按安全排序、
  架构评审文档标注已修复条目、安全审计更新修复状态。
- 新增域名要求对比表及无域名部署方案：说明哪些协议/功能需要域名、无域名时的行为表现、三种
  部署策略（strict 免域名 / 跳过 Hysteria2 / 后续补域名）。

## [0.0.4] - 2026-06-19

### 优化
- **CI 加速**：shellcheck 二进制缓存（`actions/cache@v4`），去掉 integration-test 不需要的 nginx 依赖，apt 安装使用 `--no-install-recommends`，平均每个 job 节省 20-30s
- **VERSION 文件移除**：发布流程全自动化，不再需要手动更新 VERSION 文件。打 tag → push → CI 测试通过后自动 Release

### 修复
- **sing-box Reality xhttp 修复**：客户端 `network` 字段应设为 `tcp` 而非 `xhttp`，修复 xhttp 模式下客户端无法连接的问题

### CI 与测试
- **actions/cache v4→v5**：升级缓存 action 消除 Node.js 20 deprecation 警告

### 文档
- **.env.example 默认 TCP Reality**：Reality 传输方式默认配置从 `xhttp` 调整为 `tcp`，与 CI 测试配置保持一致
- CONTRIBUTING.md 发布检查清单移除 VERSION 相关步骤
- README.md 目录树移除 VERSION 条目

## [0.0.3] - 2026-06-19

### 架构重构
- **插件化协议系统**：基于 manifest/discovery 的自动发现机制，新增协议只需创建 `protocols/<name>/` 目录，无需修改注册代码
- **协议渲染器模块化**：Clash YAML 和 sing-box JSON 输出拆分为每个协议独立的 `render_clash.sh`/`render_singbox.jq`，解耦核心订阅管道
- **Edge Gateway manifest 化**：`exposure/edge/manifest.sh` 声明自身模块，uninstall.sh 通过通用发现机制统一处理，消除硬编码
- **Metadata schema v1 语义验证**：schema.json 下沉至 `core/` 共享，新增端口范围、URI 格式、防火墙规则校验
- **统一日志函数**：消除 4 个入口文件的重复 log_* 定义，统一 source `scripts/core/logging.sh`
- **消除 eval**：`discovery_get_manifest_value` 以白名单 case 分支替代 eval，消除代码注入风险
- **set -e 改进**：全局 `set -e` → `set -eE` + ERR trap，意外失败输出文件名+行号+退出码
- **协议排序集中化**：所有协议排序统一调用 `discovery_list_modules_by_security()`，消除重复排序逻辑
- **协议精简**：移除 Trojan-Go（上游停更）和 V2Ray（VMess 高检测风险），从 6 协议精简为 4 协议

### 协议升级
- **Shadowsocks 2022 Edition**：从 `shadowsocks-libev` + `chacha20-ietf-poly1305` 升级为 `shadowsocks-rust` + `2022-blake3-aes-256-gcm`，修复 AEAD 安全漏洞并增加完整重放保护（v1.24.0）
- **Xray Reality XHTTP 传输**：新增 `EASYNET_REALITY_TRANSPORT`（默认 `tcp`，可选 `xhttp`），支持 HTTP/3 伪装传输与 XMUX 多路复用
- **Xray Finalmask Fragment**：新增 `EASYNET_REALITY_FRAGMENT` 环境变量，TCP 包分片混淆随机化包长分布对抗 ML 指纹识别
- **Hysteria2 Port Hopping**：新增端口跳变支持，ISP 封锁单个端口后自动切换
- **WireGuard AmneziaWG 混淆**：新增 `EASYNET_WIREGUARD_OBFS`，客户端输出含 Jc/Jmin/Jmax 垃圾包参数消除 UDP 指纹
- **Xray 多目标 serverNames**：逗号分隔多域名分散流量特征
- **Edge 根路径反代伪装**：默认反向代理到 Bing，消除 EasyNet 服务器指纹（`EASYNET_EDGE_MASQUERADE_URL`）
- **抗 DPI 默认调优**：`.env.example` 默认启用 XHTTP + Fragment + Port Hopping 配置

### CI 与测试
- **BATS 测试框架迁移**：从自定义 test_helper.bash（73 行）迁移至 bats-core，测试用例从 13 增至 262（23 测试文件）
- **ShellCheck 强制 `--severity=style`**：全量清理 SC2188/SC2155/SC2005/SC2162/SC2034/SC2317 等 40+ 项警告
- **新增端到端测试**：订阅输出（22 用例）、URL 探活（12 用例）、配置生成 dry-run、unbound variable lint
- **CI 矩阵更新**：从 ubuntu-22.04/24.04 升级至 24.04/26.04 LTS
- **Release 流水线**：合并至测试工作流，强制测试通过后方可 Release

### 修复
- **UFW SSH 锁死防护**：自动探测 sshd 非标准端口并注入防火墙白名单；UFW 端口范围规则格式修复
- **Xray 配置竞条件**：合并多次 jq 写入为单次原子调用，消除中间状态不一致窗口
- **xhttp 不兼容处理**：XTLS Vision flow（与 HTTP/2 多路复用冲突）和 Fragment 分片在 xhttp 模式下自动跳过
- **Shadowsocks 兼容性**：适配 v1.24.0 新增 CLI 参数（`--encrypt-method`/`--server-addr`/`-k`），修复端口冲突
- **sing-box 适配**：v1.11+ WireGuard endpoint 格式变更，重装时旧服务停止，订阅解析修复
- **set -u 安全**：全面修复 `EASYNET_*`/`HYSTERIA2_*`/`SINGBOX_*`/`NGINX_*`/`JOURNALD_*` 等裸引用
- **安全审计**：文件权限（chmod 600）+ TLS 加固 + 供应链 SHA256 验证 + systemd 安全加固
- **证书续期**：`cert_renew_hook.sh` 以 `id -gn` 替代硬编码组名，修复 Ubuntu 无 `nobody` 组问题
- **Edgio 同步**：merge 后配置收敛，ShellCheck v0.10.0 新规则抑制（SC2015/SC2317）

### 文档
- 全量重写为简体中文，协议对比表、项目结构、部署文档同步更新
- 新增 VPS 提供商列表、协议支持表自动生成工具
- 新增 CLAUDE.md 项目开发指令
- `.env.example` 全面对齐最新代码配置

## [0.0.2] - 2026-05-05

### 新增
- Hysteria2 协议支持，含 strict/balanced/compat 部署策略
- VPS 提供商文档

### 变更
- 多文件文档改进

## [0.0.1] - 2026-05-04

### 新增
- 初始发布
- 支持 4 种代理协议：Xray+Reality、Hysteria2、Shadowsocks、WireGuard
- 通过 deploy.sh 自动化部署
- 按协议模块卸载
- 基于 Nginx 的 Edge Gateway 暴露层
- 订阅系统：URI / Clash / sing-box 三种格式及二维码生成
- 基于环境变量的配置（.env 文件支持）
- 部署后快速检查脚本
- BBR 拥塞控制和系统加固
- SSL 证书自动续期 hook
- logrotate 和 journald 日志限额
- 单元测试框架（13 个测试套件）

[0.0.11]: https://github.com/EasyIndie/EasyNet/compare/0.0.10...0.0.11
[0.0.10]: https://github.com/EasyIndie/EasyNet/compare/0.0.9...0.0.10
[0.0.9]: https://github.com/EasyIndie/EasyNet/compare/0.0.8...0.0.9
[0.0.8]: https://github.com/EasyIndie/EasyNet/compare/0.0.7...0.0.8
[0.0.7]: https://github.com/EasyIndie/EasyNet/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/EasyIndie/EasyNet/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/EasyIndie/EasyNet/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/EasyIndie/EasyNet/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/EasyIndie/EasyNet/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/EasyIndie/EasyNet/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/EasyIndie/EasyNet/releases/tag/0.0.1
