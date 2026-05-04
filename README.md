# EasyNet - 境外 VPS 代理服务器部署方案

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 5 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 5 种代理协议（Shadowsocks、V2Ray、Trojan、WireGuard、Xray+Reality）
- 🔒 强安全架构：TLS 加密、WebSocket 随机路径、Nginx 本地回环隐蔽分发
- ⚡ 性能优化：BBR 拥塞控制加速
- 🔄 自动化运维：服务自动更新、系统日志截断防爆盘
- 🤖 无交互部署：支持注入环境变量进行一键 CI/CD 批量安装
- 🔗 节点订阅：自动生成跨平台通用的节点订阅链接，告别繁琐的手动扫码
- 📱 全平台客户端支持（推荐：Clash Verge Rev / Clash Meta for Android / Shadowrocket）
- 💰 成本可控（$5-$10/月）
- 🛡️ 安全稳定，自带单元测试保护核心逻辑

## 协议对比与防探测等级

如果你只想快速决策：

- 日常优先 `Xray+Reality` 或 `Trojan-Go`，兼容性补充用 `V2Ray`
- `Shadowsocks` 和 `WireGuard` 仅建议在特定场景使用

简要对比：

| 协议               | 优点             | 缺点          | 防探测等级       |
| ---------------- | -------------- | ----------- | ----------- |
| **Xray+Reality** | 无需域名，超强隐蔽，反代名站 | 客户端要求较高     | 🥇 极高 (推荐)  |
| **Trojan-Go**    | 安全性高，标准HTTPS伪装 | 需要真实域名证书    | 🥈 高 (推荐)   |
| **V2Ray**        | 配合TLS混淆，灵活性强   | 配置较复杂       | 🥈 较高       |
| **Shadowsocks**  | 简单快速，0-RTT     | 全随机流量易被识别   | 🥉 中等/偏低    |
| **WireGuard**    | 超快速度，极低延迟      | UDP特征明显易被阻断 | 🥉 低 (适合中转) |

## 项目结构

```
EasyNet/
├── scripts/              # 部署脚本目录
│   ├── server/           # 服务器端脚本
│   │   ├── trojan-go.sh
│   │   ├── v2ray.sh
│   │   ├── shadowsocks.sh
│   │   ├── wireguard.sh
│   │   └── xray-reality.sh
│   └── deploy.sh         # 一键部署脚本
├── tests/                # 单元测试目录
│   ├── test_helper.bash
│   ├── test_env_vars.bash
│   ├── test_json_manipulation.bash
│   ├── test_path_generation.bash
│   ├── test_vmess_generation.bash
│   ├── test_wireguard_generation.bash
│   └── run_all_tests.bash
├── docs/                   # 精简文档目录
│   ├── deployment.md       # 部署、协议选择、Cloudflare 说明
│   ├── clients.md          # 全平台客户端说明
│   └── troubleshooting-guide.md
└── README.md
```

## 快速开始

- 环境：
  - 系统：`Ubuntu 22.04+` / `Debian 11+`
  - CPU及内存：`1C1G` 起步
  - 端口：开放 `80/443`
- 推荐协议：日常优先 `Xray+Reality` 或 `Trojan-Go`
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
3. 在客户端中按类型导入订阅：
   - `Clash Verge Rev` 使用 `https://your-domain.com/clash`
   - `Shadowrocket` 使用 `https://your-domain.com/sub`

### 自动部署

```bash
EASYNET_SERVICE_CHOICE=6 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

## 文档

- [部署说明](./docs/deployment.md)
- [客户端说明](./docs/clients.md)
- [故障排查指南](./docs/troubleshooting-guide.md)
