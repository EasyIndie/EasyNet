# EasyNet - 境外 VPS 代理服务器部署方案

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 5 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 5 种代理协议（Shadowsocks、V2Ray、Trojan、WireGuard、Xray+Reality）
- 🔒 强安全架构：TLS 加密、WebSocket 随机路径、Nginx 本地回环隐蔽分发
- ⚡ 性能优化：BBR 拥塞控制加速
- 🔄 自动化运维：服务自动更新、配置防丢恢复、系统日志截断防爆盘
- 🤖 无交互部署：支持注入环境变量进行一键 CI/CD 批量安装
- 🔗 节点订阅：自动生成跨平台通用的节点订阅链接，告别繁琐的手动扫码
- 📱 全平台客户端支持（Windows/macOS/Linux/Android/iOS）
- 💰 成本可控（$5-$10/月）
- 🛡️ 安全稳定，自带单元测试保护核心逻辑

## 协议对比与防探测等级

👉 **强烈建议阅读：[《EasyNet 安全性与防探测分析指南》](docs/security-analysis.md)**

了解不同协议在对抗 GFW 深度包检测（DPI）、主动探测以及黑客端口扫描时的具体表现，选择最适合你当前网络环境的翻墙协议。

简要对比：

| 协议 | 优点 | 缺点 | 防探测等级 |
|------|------|------|----------|
| **Xray+Reality** | 无需域名，超强隐蔽，反代名站 | 客户端要求较高 | 🥇 极高 (推荐) |
| **Trojan-Go** | 安全性高，标准HTTPS伪装 | 需要真实域名证书 | 🥈 高 (推荐) |
| **V2Ray** | 配合TLS混淆，灵活性强 | 配置较复杂 | 🥈 较高 |
| **Shadowsocks** | 简单快速，0-RTT | 全随机流量易被识别 | 🥉 中等/偏低 |
| **WireGuard** | 超快速度，极低延迟 | UDP特征明显易被阻断 | 🥉 低 (适合中转) |

## 项目结构

```
EasyNet/
├── scripts/                # 部署脚本目录
│   ├── server/           # 服务器端脚本
│   │   ├── trojan-go.sh
│   │   ├── v2ray.sh
│   │   ├── shadowsocks.sh
│   │   ├── wireguard.sh
│   │   └── xray-reality.sh
│   ├── backup.sh         # 配置备份脚本
│   ├── restore.sh        # 配置还原脚本
│   └── deploy.sh         # 一键部署脚本
├── tests/                  # 单元测试目录
│   ├── test_helper.bash
│   ├── test_env_vars.bash
│   ├── test_json_manipulation.bash
│   ├── test_path_generation.bash
│   ├── test_vmess_generation.bash
│   ├── test_wireguard_generation.bash
│   └── run_all_tests.bash
├── docs/                   # 文档目录
│   ├── server-deployment.md
│   ├── cloudflare-setup.md
│   ├── troubleshooting-guide.md
│   ├── security-analysis.md # 安全性与防探测分析
│   └── clients/          # 客户端配置指南
│       ├── windows.md
│       ├── macos.md
│       ├── android.md
│       ├── ios.md
│       ├── wireguard.md
│       └── xray-reality.md
├── README.md
└── QUICKSTART.md
```

## 快速开始

### 服务器要求

- CPU: 1核
- 内存: 1GB+
- 存储: 20GB SSD
- 系统: Ubuntu 22.04+ / Debian 11+
- 位置: 香港、日本、新加坡等亚洲节点
- 预算: $5-$10/月

### 一键部署

```bash
git clone https://github.com/your-repo/EasyNet.git
cd EasyNet/scripts
chmod +x deploy.sh server/*.sh generate_subscription.sh
./deploy.sh
```

部署菜单选项：

1. 部署 Trojan-Go (推荐)
2. 部署 V2Ray
3. 部署 Shadowsocks-libev
4. 部署 WireGuard
5. 部署 Xray+Reality
6. 全部部署
7. 退出

部署完成后，脚本会自动生成一个通用的**节点订阅链接**（例如：`https://your-domain.com/sub`）。你只需要将这个链接复制到你的代理客户端（如 Clash Verge, Shadowrocket, V2RayN 等）中，即可一键导入所有节点，无需再一个个手动扫码配置！

### 自动化无交互部署（适合 CI/CD）

通过设置环境变量，可以跳过所有 `read -p` 手动输入提示，实现全自动化安装：

```bash
# 例如：全量部署 (6) 并且设置域名为 proxy.example.com
EASYNET_SERVICE_CHOICE=6 EASYNET_DOMAIN=proxy.example.com ./deploy.sh
```

## 文档

### 服务器文档

- [快速入门指南](QUICKSTART.md)
- [服务器部署指南](docs/server-deployment.md)
- [Cloudflare CDN 配置](docs/cloudflare-setup.md)

### 客户端文档

- [Windows 客户端配置](docs/clients/windows.md)
- [macOS 客户端配置](docs/clients/macos.md)
- [Android 客户端配置](docs/clients/android.md)
- [iOS 客户端配置](docs/clients/ios.md)
- [WireGuard 客户端配置](docs/clients/wireguard.md)
- [Xray+Reality 客户端配置](docs/clients/xray-reality.md)

## 许可证

MIT License
