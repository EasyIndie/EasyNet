# 服务器部署指南

## 前置准备

### 1. 选择 VPS 服务商

推荐以下高性价比方案（$5-$10/月）：

- **搬瓦工 (BandwagonHost)**
  - $49.99/年套餐
  - 1GB 内存，20GB SSD
  - 1TB 月流量
  - 香港/日本/新加坡节点可选

- **Vultr**
  - $5/月套餐
  - 1GB 内存，25GB SSD
  - 1TB 月流量
  - 东京/新加坡节点

- **DigitalOcean**
  - $5/月套餐
  - 1GB 内存，25GB SSD
  - 1TB 月流量
  - 新加坡/法兰克福节点

### 2. 准备域名

- 需要一个域名用于申请 SSL 证书
- 推荐使用 Cloudflare 免费 CDN
- 配置 DNS A 记录指向 VPS IP

## 部署步骤

### 1. 登录 VPS

```bash
ssh root@your-server-ip
```

### 2. 下载项目

```bash
git clone https://github.com/your-repo/EasyNet.git
cd EasyNet
chmod +x scripts/deploy.sh scripts/server/*.sh scripts/generate_subscription.sh
```

### 3. 运行部署脚本

```bash
./scripts/deploy.sh
```

选择要部署的协议（推荐选择 Trojan-Go）。

### 4. 自动化无交互部署（可选）

对于熟悉命令行的进阶用户，支持通过环境变量静默部署，无需手动选择：
```bash
EASYNET_SERVICE_CHOICE=6 EASYNET_DOMAIN=your-domain.com ./scripts/deploy.sh
```

### 5. 记录配置信息

部署完成后，记录以下信息：
- 服务器 IP
- 域名
- 端口
- 密码/UUID
- WebSocket 路径

## 验证部署

### 检查服务状态

```bash
systemctl status trojan-go
systemctl status v2ray
systemctl status shadowsocks-libev-server
systemctl status wg-quick@wg0
systemctl status xray
```

### 日志与备份维护

限制日志大小（脚本已自动配置为 500M）并查看实时日志：
```bash
journalctl -u trojan-go -f -n 50
journalctl -u v2ray -f -n 50
```

配置备份：
当需要迁移服务器时，可使用自带的脚本打包配置：
```bash
./scripts/backup.sh
```

## 性能优化

### 确认 BBR 已启用

```bash
sysctl net.ipv4.tcp_congestion_control
```

应该输出：`net.ipv4.tcp_congestion_control = bbr`

### 测试网络速度

在服务器上运行：
```bash
curl -sL yabs.sh | bash
```

## 常见问题

### 端口被占用

检查 443 端口占用情况：
```bash
netstat -tlnp | grep :443
```

### SSL 证书问题

重新申请证书：
```bash
~/.acme.sh/acme.sh --renew -d your-domain.com
```

### 防火墙问题

确保防火墙允许必要端口：
```bash
ufw status
```

## 安全建议

1. **修改 SSH 端口**：将默认 22 端口改为其他端口
2. **禁用密码登录**：使用 SSH Key 认证
3. **定期更新系统**：保持系统和软件最新
4. **监控流量使用**：避免超出 VPS 流量限制
