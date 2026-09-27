# 变更日志

项目所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
本项目遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

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
- 新增 `docs/singbox-unification-analysis.md`：评估是否将多协议收敛为统一 sing-box 实现，
  含能力对照、收益/代价、趋势判断与建议路线；本轮结论为「维持现状」。
- 文档与示例域名改用语义中性的 `world.example.com`，补充避开 GFW 关键词与 Reality 自偷的指引。

### 测试
- `tests/test_config_generation.bats` 新增 Reality 自偷 / 回退限速 / AmneziaWG 参数用例；
  `tests/test_protocol_metadata.bats` 新增 Shadowrocket obfs / 国家旗帜 / mihomo amnezia-wg-option
  断言并补充 AmneziaWG 夹具；测试总数 314 → 331。

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
