# EasyNet 部署说明

## 适用场景

这份文档只保留部署 EasyNet 所需的最核心信息，适合首次搭建和后续快速复用。

## 部署前准备

- VPS：1 核、1GB 内存、20GB SSD 起步
- 系统：Ubuntu 22.04+ 或 Debian 11+
- 位置：优先香港、日本、新加坡
- 域名：Trojan-Go / V2Ray / Hysteria2 / 订阅链接需要域名
- 端口：确保 `80`、`443` 可入站访问

## 协议选择

| 协议           | 推荐度 | 适用场景                      |
| ------------ | --- | ------------------------- |
| Xray+Reality | 高   | 抗封锁优先，允许使用支持 Reality 的客户端 |
| Hysteria2    | 高   | UDP/QUIC 场景，适合与 Reality 组成双主力方案 |
| Trojan-Go    | 高   | 日常主力方案，兼容性和隐蔽性平衡          |
| V2Ray        | 中   | 作为 Trojan-Go 的兼容补充        |
| Shadowsocks  | 低   | 仅在特定客户端或测试场景使用            |
| WireGuard    | 低   | 适合中转、低延迟、独立 VPN 场景        |

结论：

- 日常优先：`Xray+Reality`，需要 UDP/QUIC 补充时加 `Hysteria2`
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
```

### 3. 执行部署

```bash
./scripts/deploy.sh
```

推荐：

- 单协议优先选 `Xray+Reality`
- 想一次部署全部协议可选 `0`
- 部署编号 `1` 到 `6` 按安全性和抗 DPI 能力从高到低排序

说明：各协议模块部署后会导出标准 metadata，订阅生成器只读取 metadata。旧入口和旧配置导入器已移除，新部署统一走 `scripts/protocols/*` 与 `scripts/exposure/*`。订阅链接只在存在 Nginx 暴露层域名或显式设置 `EASYNET_SUBSCRIPTION_DOMAIN` 时打印。

### 4. 自动化部署

方式一：使用 `.env`

```bash
cp .env.example .env
./scripts/deploy.sh
```

方式二：命令行传参

```bash
EASYNET_SERVICE_CHOICE=0 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

方式三：按模块部署

```bash
EASYNET_MODULE=xray-reality ./scripts/deploy.sh
EASYNET_MODULE=trojan-go ./scripts/deploy.sh
EASYNET_MODULE=v2ray EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
EASYNET_MODULE=shadowsocks ./scripts/deploy.sh
EASYNET_MODULE=wireguard ./scripts/deploy.sh
EASYNET_MODULE=hysteria2 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

方式四：按策略部署

```bash
EASYNET_PROFILE=strict ./scripts/deploy.sh
EASYNET_PROFILE=balanced ./scripts/deploy.sh
EASYNET_PROFILE=compat EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

策略说明：

- `strict`：只部署 `xray-reality`
- `balanced`：部署 `xray-reality` + `hysteria2`
- `compat`：部署当前全部兼容模块

交互部署编号：

- `0`：全部部署
- `1`：`xray-reality`
- `2`：`hysteria2`
- `3`：`trojan-go`
- `4`：`v2ray`
- `5`：`shadowsocks`
- `6`：`wireguard`
- `7`：退出

## Cloudflare 关键说明

- 首次签发证书时必须使用 `DNS Only`，不要开橙云
- 证书签发完成后，可将 Trojan-Go / V2Ray / 订阅链接切到橙云
- `Xray+Reality`、`Shadowsocks`、`WireGuard` 不能依赖 Cloudflare 橙云代理协议本身
- Cloudflare SSL 模式建议使用 `Full` 或 `Full (strict)`
- 订阅链接 `/sub`、`/sub_full`、`/clash`、`/clash_full` 依赖 Trojan-Go + Nginx 回落链路提供

## 验证部署

### 服务状态

```bash
systemctl status trojan-go
systemctl status v2ray
systemctl status shadowsocks-libev-server
systemctl status wg-quick@wg0
systemctl status xray
systemctl status hysteria-server.service
```

### 订阅链接

- Shadowrocket / v2rayN / v2rayNG：`https://your-domain.com/sub`
- Shadowrocket / v2rayN / v2rayNG 完整订阅：`https://your-domain.com/sub_full`
- Clash Verge Rev / Mihomo：`https://your-domain.com/clash`
- Clash Verge Rev / Mihomo 完整订阅：`https://your-domain.com/clash_full`

### 其他检查

```bash
sysctl net.ipv4.tcp_congestion_control
```

## 需要时再看

- 客户端导入与平台差异：[客户端说明](./clients.md)
- 出现故障时：[故障排查指南](./troubleshooting-guide.md)
