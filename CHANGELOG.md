# 变更日志

项目所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
本项目遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

## [0.0.7] - 2026-06-12

### 新增
- **Hysteria2 Port Hopping**：新增 `EASYNET_HYSTERIA2_PORT_HOPPING` 和 `EASYNET_HYSTERIA2_PORT_HOP_INTERVAL` 环境变量，支持端口跳变（port hopping），ISP 封锁单个端口后自动切换

## [0.0.6] - 2026-06-12

### 变更
- **Shadowsocks 2022 Edition**：从 `shadowsocks-libev` + `chacha20-ietf-poly1305` 升级为 `shadowsocks-rust` + `2022-blake3-aes-256-gcm`，修复 AEAD 安全漏洞并增加完整重放保护
- **Xray Reality XHTTP 传输**：新增 `EASYNET_REALITY_TRANSPORT` 环境变量（默认 `tcp`，可选 `xhttp`），支持 HTTP/3 伪装传输与 XMUX 多路复用
- Shadowsocks 防探测等级上调至 40（原 50）
- 新增 `EASYNET_REALITY_XHTTP_MODE` 和 `EASYNET_REALITY_XMUX_CONCURRENCY` 环境变量
- .env.example 注释更新，Shadowsocks 标签改为 "Shadowsocks 2022"

## [0.0.5] - 2026-06-12

### 移除
- 移除 Trojan-Go 协议模块（上游自 2023 年停更，无安全补丁）
- 移除 V2Ray 协议模块（VMess 为 GFW 重点目标，功能与 Xray 完全重叠）
- 协议从 6 个精简为 4 个：Xray+Reality、Hysteria2、Shadowsocks、WireGuard

### 新增
- Edge Gateway 根路径反代伪装：默认代理到 Bing，消除 EasyNet 服务器指纹
- Xray Reality serverNames 多目标支持：逗号分隔多目标分散流量
- 新增 `EASYNET_EDGE_MASQUERADE_URL` 环境变量
- 新增订阅输出端到端测试（`test_subscription_output.bash`，22 个用例）

### 变更
- 所有项目文档统一使用简体中文
- Clash YAML 生成逻辑拆分到独立模块 `scripts/core/subscription_clash.sh`
- generate_subscription.sh 从 525 行精简至 299 行
- 部署菜单编号递补（1=Hysteria2, 2=Shadowsocks, 3=WireGuard, 4=Xray+Reality）

## [0.0.4] - 2026-06-12

### 新增
- Manifest 版本化：所有协议 manifest 声明 `MANIFEST_VERSION=1`，discovery 层增加版本校验以保护插件契约
- 部署前配置预检（`scripts/core/validate.sh`）：检查必需工具、端口冲突、域名解析和操作系统兼容性

### 变更
- 将 sing-box outbound 的 jq 逻辑提取为独立文件 `scripts/core/singbox_outbound.jq`，便于独立维护和测试

## [0.0.3] - 2026-06-12

### 新增
- CI 自动测试工作流（GitHub Actions）
- VPS 提供商列表文档
- sing-box 客户端 Tun 模式支持

### 修复
- sing-box 客户端安装脚本：DNS 解析器、订阅地址、二维码生成
- GitHub Actions 工作流警告
- sing-box 客户端订阅解析

### 变更
- 全面更新 README，增加协议对比、项目结构和部署文档
- 改进 sing-box 客户端安装流程

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

[0.0.7]: https://github.com/EasyIndie/EasyNet/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/EasyIndie/EasyNet/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/EasyIndie/EasyNet/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/EasyIndie/EasyNet/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/EasyIndie/EasyNet/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/EasyIndie/EasyNet/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/EasyIndie/EasyNet/releases/tag/0.0.1
