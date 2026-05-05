# EasyNet - 境外 VPS 代理服务器部署方案

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 6 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 6 种代理协议（Xray+Reality、Hysteria2、Trojan-Go、V2Ray、Shadowsocks、WireGuard）
- 🔒 强安全架构：TLS 加密、WebSocket 随机路径、Edge Gateway 本地回环隐蔽分发
- ⚡ 性能优化：BBR 拥塞控制加速
- 🔄 自动化运维：服务自动更新、系统日志截断防爆盘
- 🤖 无交互部署：支持注入环境变量进行一键 CI/CD 批量安装
- 🔗 节点订阅：自动生成跨平台通用的节点订阅链接，告别繁琐的手动扫码
- 📱 全平台客户端支持（推荐：Clash Verge Rev / Clash Meta for Android / Shadowrocket）
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
│   ├── exposure/         # 入口暴露层（Edge Gateway、订阅路径等）
│   ├── protocols/        # 独立协议模块（新架构）
│   │   ├── xray-reality/
│   │   ├── hysteria2/
│   │   ├── trojan-go/
│   │   ├── v2ray/
│   │   ├── shadowsocks/
│   │   └── wireguard/
│   ├── deploy.sh         # 一键部署脚本
│   └── uninstall.sh      # 模块化卸载脚本
├── tests/                # 单元测试目录
│   ├── test_helper.bash
│   ├── test_env_vars.bash
│   ├── test_json_manipulation.bash
│   ├── test_path_generation.bash
│   ├── test_protocol_metadata.bash
│   ├── test_vmess_generation.bash
│   ├── test_wireguard_generation.bash
│   └── run_all_tests.bash
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
  - 端口：开放 `80/443`
- 推荐协议：日常优先 `Xray+Reality`；需要 UDP/QUIC 补充时使用 `balanced`
- 客户端：
  - Windows/macOS/Linux 用 `Clash Verge Rev`
  - Android 用 `Clash Meta for Android`
  - iOS 用 `Shadowrocket`

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
   - 忘记链接时运行 `./scripts/show_subscription.sh` 重新显示订阅链接和二维码
   - 怀疑订阅链接泄露时运行 `./scripts/rotate_subscription.sh` 主动轮换

### 自动部署

```bash
EASYNET_SERVICE_CHOICE=0 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
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
