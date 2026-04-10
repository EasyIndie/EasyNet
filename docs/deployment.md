# EasyNet 部署说明

## 适用场景

这份文档只保留部署 EasyNet 所需的最核心信息，适合首次搭建和后续快速复用。

## 部署前准备

- VPS：1 核、1GB 内存、20GB SSD 起步
- 系统：Ubuntu 22.04+ 或 Debian 11+
- 位置：优先香港、日本、新加坡
- 域名：Trojan-Go / V2Ray / 订阅链接需要域名
- 端口：确保 `80`、`443` 可入站访问

## 协议选择

| 协议 | 推荐度 | 适用场景 |
|------|--------|----------|
| Xray+Reality | 高 | 抗封锁优先，允许使用支持 Reality 的客户端 |
| Trojan-Go | 高 | 日常主力方案，兼容性和隐蔽性平衡 |
| V2Ray | 中 | 作为 Trojan-Go 的兼容补充 |
| Shadowsocks | 低 | 仅在特定客户端或测试场景使用 |
| WireGuard | 低 | 适合中转、低延迟、独立 VPN 场景 |

结论：
- 日常优先：`Xray+Reality` 或 `Trojan-Go`
- 兼容性补充：`V2Ray`
- 特定用途：`WireGuard`

## 快速部署

### 1. 登录服务器

```bash
ssh root@your-server-ip
```

### 2. 拉取项目

```bash
apt update && apt install -y git
git clone https://github.com/your-repo/EasyNet.git
cd EasyNet
chmod +x scripts/deploy.sh scripts/server/*.sh scripts/generate_subscription.sh
```

### 3. 执行部署

```bash
./scripts/deploy.sh
```

推荐：
- 单协议优先选 `Trojan-Go`
- 想一次部署全部协议可选 `6`

### 4. 自动化部署

方式一：使用 `.env`

```bash
cp .env.example .env
./scripts/deploy.sh
```

方式二：命令行传参

```bash
EASYNET_SERVICE_CHOICE=6 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

## Cloudflare 关键说明

- 首次签发证书时必须使用 `DNS Only`，不要开橙云
- 证书签发完成后，可将 Trojan-Go / V2Ray / 订阅链接切到橙云
- `Xray+Reality`、`Shadowsocks`、`WireGuard` 不能依赖 Cloudflare 橙云代理协议本身
- Cloudflare SSL 模式建议使用 `Full` 或 `Full (strict)`
- 订阅链接 `/sub` 与 `/sub_full` 依赖 Trojan-Go + Nginx 回落链路提供

## 部署完成后要保存的信息

- 服务器 IP
- 域名
- 端口
- 密码 / UUID / PublicKey / ShortID
- WebSocket 路径
- 订阅链接：`/sub`、`/sub_full`

## 验证部署

### 服务状态

```bash
systemctl status trojan-go
systemctl status v2ray
systemctl status shadowsocks-libev-server
systemctl status wg-quick@wg0
systemctl status xray
```

### 订阅链接

- 安全订阅：`https://your-domain.com/sub`
- 完整订阅：`https://your-domain.com/sub_full`

### 其他检查

```bash
sysctl net.ipv4.tcp_congestion_control
./scripts/backup.sh
```

## 需要时再看

- 客户端导入与平台差异：`docs/clients.md`
- 出现故障时：`docs/troubleshooting-guide.md`
