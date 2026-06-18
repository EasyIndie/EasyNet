# 变更日志

项目所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
本项目遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

## [0.0.4] - 2026-06-19

### 优化
- **CI 加速**：shellcheck 二进制缓存（`actions/cache@v4`），去掉 integration-test 不需要的 nginx 依赖，apt 安装使用 `--no-install-recommends`，平均每个 job 节省 20-30s
- **VERSION 文件移除**：发布流程全自动化，不再需要手动更新 VERSION 文件。打 tag → push → CI 测试通过后自动 Release

### 文档
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

[0.0.4]: https://github.com/EasyIndie/EasyNet/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/EasyIndie/EasyNet/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/EasyIndie/EasyNet/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/EasyIndie/EasyNet/releases/tag/0.0.1
