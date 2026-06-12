# EasyNet - 境外 VPS 代理服务器部署方案

[![Tests](https://github.com/EasyIndie/EasyNet/actions/workflows/tests.yml/badge.svg)](https://github.com/EasyIndie/EasyNet/actions/workflows/tests.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Keep a Changelog](https://img.shields.io/badge/Keep%20a%20Changelog-2.0.0-%23E05735)](CHANGELOG.md)

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 6 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 6 种代理协议（Xray+Reality、Hysteria2、Trojan-Go、V2Ray、Shadowsocks、WireGuard）
- 🔒 强安全架构：TLS 加密、WebSocket 随机路径、Edge Gateway 本地回环隐蔽分发
- ⚡ 性能优化：BBR 拥塞控制加速
- 🔄 自动化运维：系统更新、证书续期 hook、日志限额与 logrotate
- 🤖 无交互部署：支持 `.env` 或环境变量进行一键安装
- 🔗 节点订阅：配置域名后自动生成 URI / Clash / sing-box 订阅链接和二维码
- 📱 全平台客户端支持（推荐：Clash Verge Rev / Clash Meta for Android / Shadowrocket / sing-box）
- 💰 成本可控（$5-$10/月）
- 🛡️ 安全稳定，自带单元测试保护核心逻辑

## 协议对比与防探测等级

如果你只想快速决策：

- 日常优先 `Xray+Reality`；需要 UDP/QUIC 补充时用 `balanced`
- 订阅承载与协议部署解耦；配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 后会自动生成订阅链接和订阅二维码
- `Shadowsocks` 和 `WireGuard` 仅建议在特定场景使用

简要对比：

| 协议               | 优点             | 缺点          | 防探测等级       |
| ---------------- | -------------- | ----------- | ----------- |
| **Xray+Reality** | 无需域名，超强隐蔽，反代名站 | 客户端要求较高     | 🥇 极高 (推荐)  |
| **Hysteria2**    | QUIC/UDP 性能好，支持 salamander 混淆 | 需要域名与 UDP 可达 | 🥇 高 (推荐补充) |
| **Trojan-Go**    | 安全性高，标准HTTPS伪装 | 需要真实域名证书    | 🥈 高 (推荐)   |
| **V2Ray**        | 配合TLS混淆，灵活性强   | 配置较复杂       | 🥈 较高       |
| **Shadowsocks**  | 简单快速，0-RTT     | 全随机流量易被识别   | 🥉 中等/偏低    |
| **WireGuard**    | 超快速度，极低延迟      | UDP特征明显易被阻断 | 🥉 低 (适合中转) |

## 项目结构

```
EasyNet/
├── scripts/              # 部署脚本目录
│   ├── core/             # 可复用核心函数与 metadata 契约
│   ├── exposure/edge/    # Edge Gateway、订阅路径、证书续期 hook
│   ├── protocols/        # 独立协议模块（新架构）
│   │   ├── xray-reality/
│   │   ├── hysteria2/
│   │   ├── trojan-go/
│   │   ├── v2ray/
│   │   ├── shadowsocks/
│   │   └── wireguard/
│   ├── deploy.sh         # 一键部署脚本
│   ├── uninstall.sh      # 模块化卸载脚本
│   ├── show_subscription.sh
│   ├── rotate_subscription.sh
│   └── smoke_test.sh     # 真实部署快速检查
├── tests/                # 单元测试与架构约束测试
├── docs/                   # 精简文档目录
│   ├── deployment.md       # 部署、协议选择、订阅承载说明
│   ├── clients.md          # 全平台客户端说明
│   └── troubleshooting-guide.md
└── README.md
```

## 快速开始

- 环境：
  - 系统：`Ubuntu 22.04+` / `Debian 11+`
  - CPU及内存：`1C1G` 起步
  - 端口：至少开放 `80/tcp`、`443/tcp`；`balanced` 还需要 `8443/tcp` 和 `443/udp`
- 推荐协议：日常优先 `Xray+Reality`；需要 UDP/QUIC 补充时使用 `balanced`
- 客户端：
  - Windows/macOS/Linux 用 `Clash Verge Rev`
  - Android 用 `Clash Meta for Android`
  - iOS 用 `Shadowrocket`
  - Raspberry Pi / 卡片机用 `sing-box`

### 手动部署

```bash
git clone https://github.com/your-repo/EasyNet.git
cd EasyNet
./scripts/deploy.sh
```

最短流程：

1. 运行脚本并按提示选择协议
2. 保存部署输出的密码、UUID、Reality 参数和订阅链接
3. 运行 `./scripts/smoke_test.sh` 快速检查服务、端口、防火墙和订阅入口
4. 在客户端中按类型导入订阅：
   - `Clash Verge Rev` 使用部署输出中的 Clash 订阅
   - `Shadowrocket` 使用部署输出中的 URI 订阅
   - 树莓派 / 卡片机使用部署输出中的“树莓派快速安装”两行命令
   - 忘记链接时运行 `./scripts/show_subscription.sh` 重新显示订阅链接和二维码
   - 怀疑订阅链接泄露时运行 `./scripts/rotate_subscription.sh` 主动轮换

### 自动部署

```bash
EASYNET_PROFILE=balanced EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

### 卸载部署

```bash
EASYNET_UNINSTALL_CHOICE=0 ./scripts/uninstall.sh
```

也可以按模块卸载：

```bash
EASYNET_UNINSTALL_MODULE=xray-reality ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=edge-exposure ./scripts/uninstall.sh
```

## 文档

- [部署说明](./docs/deployment.md)
- [客户端说明](./docs/clients.md)
- [故障排查指南](./docs/troubleshooting-guide.md)

## 贡献指南 / Contributing

Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) to get started.

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## 许可证

Copyright © 2026 EasyIndie

本项目采用 **GNU Affero General Public License v3.0 (AGPL v3)** 发布。

AGPL v3 是一个强 copyleft 许可证，它要求：
- ✅ 任何人可以自由使用、修改、分享本软件
- ✅ 修改后的版本如果通过网络提供服务，**必须向用户公开修改后的完整源码**
- ❌ 不得将本软件或其修改版本闭源商业化

这意味着任何基于本项目的二次开发、衍生产品或 SaaS 服务都必须以 AGPL v3 开源发布。这是标准开源许可证中对"被商用抄袭"防御力最强的选择。

完整的许可证文本见 [LICENSE](./LICENSE) 文件。
