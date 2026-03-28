# EasyNet 快速入门指南

## 总览

本指南将帮助你在 30 分钟内完成从 VPS 购买到客户端配置的全过程。

## 时间线

| 步骤 | 时间 | 说明 |
|------|------|------|
| 1. 购买 VPS | 5 分钟 | 选择并购买 VPS |
| 2. 准备域名 | 5 分钟 | 注册域名和配置 DNS |
| 3. 配置 Cloudflare | 10 分钟 | 设置 CDN 和 SSL |
| 4. 部署服务端 | 5 分钟 | 运行一键部署脚本 |
| 5. 配置客户端 | 5 分钟 | 安装和配置客户端软件 |

## 第一步：购买 VPS（约 5 分钟）

### 推荐方案

**搬瓦工 (BandwagonHost)** - 性价比首选
- 价格：$49.99/年（约 $4.17/月）
- 配置：1GB 内存，20GB SSD，1TB 月流量
- 节点：香港 CN2 GIA / 日本软银 / 新加坡
- 购买链接：https://bandwagonhost.com/

**Vultr** - 按量付费灵活选择
- 价格：$5/月起
- 配置：1GB 内存，25GB SSD，1TB 月流量
- 节点：东京 / 新加坡 / 首尔
- 购买链接：https://vultr.com/

**DigitalOcean** - 新人优惠
- 价格：$5/月起，新用户 $200 赠金
- 配置：1GB 内存，25GB SSD，1TB 月流量
- 节点：新加坡 / 法兰克福
- 购买链接：https://digitalocean.com/

### 购买要点

1. **系统选择**：Ubuntu 22.04 LTS 或 Debian 11
2. **位置选择**：香港 > 日本东京 > 新加坡
3. **付款方式**：支持支付宝/信用卡/PayPal

购买后你会收到：
- 服务器 IP 地址
- SSH 端口（默认 22）
- root 密码

## 第二步：准备域名（约 5 分钟）

### 域名注册

推荐以下域名注册商：
- **Namecheap**：https://www.namecheap.com/
- **Namesilo**：https://www.namesilo.com/
- **Cloudflare Registrar**：https://www.cloudflare.com/products/registrar/

选择一个便宜的域名，比如 `.xyz`、`.online`、`.site` 等，首年通常只需 $1-$3。

### 暂时跳过 Cloudflare

如果想快速上手，可以先不配置 Cloudflare，直接用域名解析到 VPS IP。等服务跑通后再配置 Cloudflare。

## 第三步：登录 VPS 并部署（约 10 分钟）

### 登录 VPS

打开终端（Windows 用 PowerShell 或 CMD，macOS/Linux 用终端）：

```bash
ssh root@your-server-ip
```

输入密码后登录。

### 运行部署脚本

```bash
apt update && apt install -y git
git clone https://github.com/your-repo/EasyNet.git
cd EasyNet
chmod +x scripts/deploy.sh scripts/server/*.sh
./scripts/deploy.sh
```

### 按提示操作

1. 选择部署协议（推荐 1 - Trojan-Go）
2. 输入你的域名
3. 等待脚本自动完成

**重要**：部署完成后，务必保存显示的配置信息！

## 第四步：配置客户端（约 5 分钟）

### Windows

1. 下载 NekoBox：https://github.com/MatsuriDayo/nekoray/releases
2. 解压并运行
3. 点击「服务器」→「从剪贴板导入」
4. 粘贴部署脚本生成的链接
5. 右键服务器选择「启动」

详细配置：[Windows 客户端指南](docs/clients/windows.md)

### macOS

1. 下载 NekoBox for macOS：https://github.com/MatsuriDayo/nekoray/releases
2. 拖拽到 Applications 文件夹
3. 打开并导入配置
4. 点击「启动」

详细配置：[macOS 客户端指南](docs/clients/macos.md)

### Android

1. 下载 NekoBox for Android：https://github.com/MatsuriDayo/NekoBoxForAndroid/releases
2. 安装 APK
3. 打开应用并扫描二维码或导入链接
4. 点击「启动」

详细配置：[Android 客户端指南](docs/clients/android.md)

### iOS

1. 使用外区 Apple ID 购买 Shadowrocket ($2.99)
2. 打开 Shadowrocket
3. 扫描二维码或导入链接
4. 点击开关启动

详细配置：[iOS 客户端指南](docs/clients/ios.md)

## 第五步：验证和优化

### 验证连接

访问以下网站测试：
- https://www.google.com - 应该能正常打开
- https://www.youtube.com - 测试视频播放
- https://www.speedtest.net - 测试网速

### 优化建议

1. **配置 Cloudflare CDN**：参考 [Cloudflare 设置指南](docs/cloudflare-setup.md)
2. **监控流量**：在服务器上运行 `bash scripts/server/monitor.sh`
3. **定期备份**：保存好配置信息

## 常见问题速查

### 部署失败

- 检查是否以 root 用户运行
- 确认系统是 Ubuntu/Debian
- 查看错误日志

### 无法连接

- 检查服务器是否运行：`systemctl status trojan-go`
- 确认防火墙配置：`ufw status`
- 检查域名 DNS 解析

### 速度慢

- 尝试更换 VPS 节点
- 确认 BBR 已启用：`sysctl net.ipv4.tcp_congestion_control`
- 配置 Cloudflare CDN

## 下一步

- 阅读完整的 [服务器部署指南](docs/server-deployment.md)
- 配置 [Cloudflare CDN](docs/cloudflare-setup.md)
- 学习如何 [生成二维码](tools/generate-qrcode.py)

## 获取帮助

如果遇到问题：
1. 查看文档目录下的详细指南
2. 检查服务器日志：`journalctl -u trojan-go -f`
3. 确认所有配置信息正确

---

**祝你使用愉快！** 🚀
