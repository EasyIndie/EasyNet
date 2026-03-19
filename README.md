# EasyNet - 境外 VPS 代理服务器部署方案

## 项目概述

一套完整的境外 VPS 部署方案，实现在受限网络环境下的稳定科学上网服务。支持 5 种主流协议，满足不同场景需求。

## 核心特性

- 🚀 支持 5 种代理协议（Shadowsocks、V2Ray、Trojan、WireGuard、Xray+Reality）
- 🔒 强安全架构：TLS 加密、WebSocket 随机路径、Nginx 本地回环隐蔽分发
- ⚡ 性能优化：BBR 拥塞控制加速
- 🔄 自动化运维：服务自动更新、配置防丢恢复、系统日志截断防爆盘
- 🤖 无交互部署：支持注入环境变量进行一键 CI/CD 批量安装
- 📱 全平台客户端支持（Windows/macOS/Linux/Android/iOS）
- 💰 成本可控（$5-$10/月）
- 🛡️ 安全稳定，自带单元测试保护核心逻辑

## 协议对比

| 协议 | 优点 | 缺点 | 推荐场景 |
|------|------|------|----------|
| **Trojan-Go** | 安全性高，伪装好 | 需要域名证书 | 长期稳定使用 |
| **WireGuard** | 超快速度，低延迟 | 配置略复杂 | 追求极致性能 |
| **Xray+Reality** | 无需域名，超强隐蔽 | 客户端支持较少 | 高安全需求 |
| **V2Ray** | 功能强大，灵活 | 配置复杂 | 高级用户 |
| **Shadowsocks** | 简单快速 | 安全性一般 | 临时使用 |

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
│   └── run_all_tests.bash
├── docs/                   # 文档目录
│   ├── server-deployment.md
│   ├── cloudflare-setup.md
│   ├── troubleshooting-guide.md
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
chmod +x deploy.sh server/*.sh
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
