# EasyNet — 境外 VPS 代理服务器部署方案

[![Tests](https://github.com/EasyIndie/EasyNet/actions/workflows/tests.yml/badge.svg)](https://github.com/EasyIndie/EasyNet/actions/workflows/tests.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Keep a Changelog](https://img.shields.io/badge/Keep%20a%20Changelog-2.0.0-%23E05735)](CHANGELOG.md)

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 4 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 4 种代理协议，全部内置混淆对抗 DPI：
  - **Xray+Reality** — TLS 指纹模仿 + XHTTP/HTTP3 传输 + Fragment 包分片 + XMUX 多路复用
  - **Hysteria2** — QUIC/UDP + Salamander 混淆 + Port Hopping 端口跳变
  - **Shadowsocks 2022** — BLAKE3-AES-256-GCM 加密，完整重放保护
  - **WireGuard (+Amnezia obfs)** — 默认启用 Jc/Jmin/Jmax 垃圾包填充消除 UDP 指纹
- 🔒 强安全架构：REALITY 无证书 TLS、Finalmask Fragment、Edge Gateway 反代伪装
- ⚡ 性能优化：BBR 拥塞控制、XHTTP 多路复用 (XMUX)、QUIC 0-RTT
- 🔄 自动化运维：系统更新、证书续期 hook（自动修正权限并重启服务）、日志限额与 logrotate
- 🤖 无交互部署：支持 `.env` 或环境变量进行一键安装
- 🔗 节点订阅：配置域名后自动生成 URI / Clash / sing-box 订阅链接和二维码
- 📱 全平台客户端支持（推荐：Clash Verge Rev / Clash Meta for Android / Shadowrocket / sing-box）
- 💰 成本可控（$5–$15/月）
- 🛡️ 安全稳定，自带 262 个测试用例（23 套件）保护核心逻辑

## 协议对比与防探测等级

如果你想快速决策：

- 日常优先 `Xray+Reality`；需要 UDP/QUIC 补充时用 `balanced`
- 订阅承载与协议部署解耦；配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 后会自动生成订阅链接和订阅二维码
- `Shadowsocks 2022` 和 `WireGuard` 可通过环境变量启用额外混淆

简要对比：

| 协议 | 传输/混淆 | 优点 | 防探测等级 |
|------|-----------|------|-----------|
| **Xray+Reality** | TCP/XHTTP + REALITY + Fragment + XMUX | 无需域名，TLS 指纹模仿，包分片抗 ML，多路复用 | 🥇 极高（推荐） |
| **Hysteria2** | QUIC/UDP + Salamander + Port Hopping | 端口跳变抗封锁，HTTP/3 伪装 | 🥇 高（推荐补充） |
| **Shadowsocks 2022** | TCP+UDP / BLAKE3-AES-256-GCM | 2022 Edition 强加密，重放保护 | 🥈 中等+ |
| **WireGuard (+Amnezia obfs)** | UDP + Jc/Jmin/Jmax 垃圾包 | 可启用混淆消除 UDP 指纹 | 🥈 中等（启用混淆后） |


## 支持的协议
<!-- EasyNet 协议支持表 — 由 docs/generate-protocol-table.sh 自动生成 -->
<!-- 手动修改无效，请通过修改 protocols/*/manifest.sh 后重新生成 -->

| 协议 | 安全等级 | 默认端口 | Edge 模式 | 部署策略 |
|------|:--------:|:--------:|:---------:|----------|
| Hysteria2 | 20 | 443 | 共享 TLS | balanced, compat |
| Shadowsocks 2022 | 40 | 8388 | — | compat |
| WireGuard (+Amnezia obfs) | 60 | 51820 | — | compat |
| Xray+Reality | 10 | 8443 | — | strict, balanced, compat |

## 项目结构

```
EasyNet/
├── scripts/                    # 部署脚本目录
│   ├── core/                   # 可复用核心函数（19 文件）
│   │   ├── discovery.sh        #   插件系统（manifest 加载、校验、排序）
│   │   ├── metadata.sh         #   metadata.json 写入/校验
│   │   ├── bootstrap.sh        #   系统初始化（apt、BBR、防火墙、自动更新）
│   │   ├── firewall.sh         #   UFW 规则管理
│   │   ├── cron.sh             #   每日服务重启
│   │   ├── profiles.sh         #   部署策略（strict/balanced/compat）
│   │   ├── download.sh         #   下载 + SHA256 校验 + 执行
│   │   ├── crypto.sh           #   密钥生成、架构检测
│   │   ├── network.sh          #   公网 IP 检测
│   │   ├── display.sh          #   QR 码显示
│   │   ├── validate.sh         #   部署前预检
│   │   ├── env.sh / env_file.sh#   状态目录路径、.env 解析
│   │   ├── subscription*.sh    #   订阅生成（含 subscription_clash.sh）
│   │   ├── logging.sh          #   统一日志函数
│   │   ├── maintenance.sh      #   系统维护工具
│   │   ├── url.sh              #   URL 编解码
│   │   ├── uninstall.sh        #   安全路径/防火墙/服务删除
│   │   └── metadata.schema.json#   metadata JSON Schema
│   ├── protocols/              # 协议模块（4 种）
│   │   ├── hysteria2/          #   6 文件：manifest、deploy、export、
│   │   ├── xray-reality/       #   uninstall、render_clash、render_singbox.jq
│   │   ├── shadowsocks/
│   │   └── wireguard/
│   ├── exposure/edge/          # Edge Gateway（Nginx + acme.sh + 订阅 + 证书续期）
│   │   ├── manifest.sh         #   自身模块声明
│   │   ├── deploy.sh / export.sh / uninstall.sh
│   │   ├── routes.sh           #   Nginx 路由配置生成
│   │   └── cert_renew_hook.sh  #   证书续期后处理（权限修正 + 服务重启）
│   ├── clients/                # 客户端安装器（独立运行于终端设备）
│   │   └── install_singbox_client.sh
│   ├── deploy.sh               # 一键部署入口
│   ├── uninstall.sh            # 模块化卸载入口
│   ├── generate_subscription.sh# 订阅文件重新生成
│   ├── show_subscription.sh    # 重新显示订阅链接和二维码
│   ├── rotate_subscription.sh  # 轮换订阅入口（支持 --grace 迁移宽限）
│   └── smoke_test.sh           # 部署后快速检查
├── tests/                      # 单元测试（23 个 bats 套件，262 个用例）
├── docs/                       # 文档目录
│   ├── deployment.md           #   部署、协议选择、订阅承载、完整配置项
│   ├── clients.md              #   全平台客户端说明与常见问题
│   ├── troubleshooting-guide.md#   故障排查指南
│   ├── architecture-review.md  #   架构与代码质量评估报告
│   └── generate-protocol-table.sh  # 协议支持表自动生成工具
├── tools/                      # 辅助工具（二维码生成等）
├── .env.example                # 环境变量配置模板
├── CHANGELOG.md                # 变更日志
└── README.md                   # 项目概览（本文件）
```

## 快速开始

- 环境：
  - 系统：`Ubuntu 22.04+` / `Debian 11+`
  - CPU 及内存：`1C1G` 起步
  - 端口：至少开放 `22/tcp`、`80/tcp`、`443/tcp`；按需增加各协议默认端口
- 推荐协议：日常优先 `Xray+Reality`；需要 UDP/QUIC 补充时使用 `balanced` 策略
- 客户端：
  - Windows/macOS/Linux 用 `Clash Verge Rev`
  - Android 用 `Clash Meta for Android`
  - iOS 用 `Shadowrocket`
  - Raspberry Pi / 卡片机用 `sing-box`

### 手动部署

```bash
git clone https://github.com/EasyIndie/EasyNet.git
cd EasyNet
./scripts/deploy.sh
```

最短流程：

1. 运行脚本并按提示选择协议（交互菜单按抗 DPI 能力从高到低排列）
2. 保存部署输出的密码、密钥参数和订阅链接
3. 运行 `./scripts/smoke_test.sh` 快速检查服务、端口、防火墙和订阅入口
4. 在客户端中按类型导入订阅：
   - `Clash Verge Rev` 使用部署输出中的 Clash 订阅（`clash` 端点）
   - `Shadowrocket` / `v2rayN` / `v2rayNG` 使用 URI 订阅（`sub` 端点）
   - `sing-box` 使用 sing-box 配置（`singbox` 端点）
   - Raspberry Pi / 卡片机使用 sing-box 配置 + 两行安装命令
   - 忘记链接时运行 `./scripts/show_subscription.sh` 重新显示订阅链接和二维码
   - 怀疑订阅链接泄露时运行 `./scripts/rotate_subscription.sh` 主动轮换

### 自动部署

```bash
# 按策略部署（推荐）
EASYNET_PROFILE=balanced EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh

# 按模块名称部署
EASYNET_MODULE=xray-reality ./scripts/deploy.sh

# 按编号部署（0 = 全部）
EASYNET_SERVICE_CHOICE=0 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh

# 最强抗 DPI 配置示例
EASYNET_PROFILE=balanced \
  EASYNET_DOMAIN=proxy.example.com \
  EASYNET_REALITY_TRANSPORT=xhttp \
  EASYNET_REALITY_FRAGMENT=tlshello \
  EASYNET_REALITY_XMUX_CONCURRENCY=4 \
  EASYNET_HYSTERIA2_PORT_HOPPING=20000-30000 \
  EASYNET_WIREGUARD_OBFS=true \
  ./scripts/deploy.sh
```

所有环境变量详见 [`.env.example`](./.env.example) 和[部署说明](./docs/deployment.md)。

### 卸载部署

```bash
# 全部卸载
EASYNET_UNINSTALL_CHOICE=0 ./scripts/uninstall.sh

# 按模块卸载
EASYNET_UNINSTALL_MODULE=xray-reality ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=edge ./scripts/uninstall.sh
```

> 交互菜单中的编号由模块发现自动生成（卸载按字母序排列），当前顺序：edge → hysteria2 → shadowsocks → wireguard → xray-reality → 退出。

## 文档

- [部署说明](./docs/deployment.md) — 部署、协议选择、订阅承载、完整配置项清单
- [客户端说明](./docs/clients.md) — 全平台客户端安装、导入与常见问题
- [故障排查指南](./docs/troubleshooting-guide.md) — 分协议、分场景的排障流程
- [架构评估报告](./docs/architecture-review.md) — 代码质量与架构改进建议

## 贡献指南

欢迎贡献！请阅读[贡献指南](CONTRIBUTING.md)开始。

- [行为准则](CODE_OF_CONDUCT.md)
- [安全策略](SECURITY.md)
- [变更日志](CHANGELOG.md)

## 许可证

Copyright © 2026 EasyIndie

本项目采用 **GNU Affero General Public License v3.0 (AGPL v3)** 发布。

AGPL v3 是一个强 copyleft 许可证，它要求：
- ✅ 任何人可以自由使用、修改、分享本软件
- ✅ 修改后的版本如果通过网络提供服务，**必须向用户公开修改后的完整源码**
- ❌ 不得将本软件或其修改版本闭源商业化

这意味着任何基于本项目的二次开发、衍生产品或 SaaS 服务都必须以 AGPL v3 开源发布。这是标准开源许可证中对"被商用抄袭"防御力最强的选择。

完整的许可证文本见 [LICENSE](./LICENSE) 文件。
