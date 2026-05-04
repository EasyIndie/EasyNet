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
- 订阅承载与协议部署解耦；配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 后会自动启用独立订阅承载并打印订阅链接和二维码
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

说明：各协议模块部署后会导出标准 metadata，订阅生成器只读取 metadata。旧入口和旧配置导入器已移除，新部署统一走 `scripts/protocols/*` 与 `scripts/exposure/*`。订阅链接只在存在独立订阅承载域名、Nginx 暴露层域名、Trojan-Go metadata 域名，或显式设置 `EASYNET_SUBSCRIPTION_DOMAIN` 时打印。

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
EASYNET_PROFILE=strict EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
EASYNET_PROFILE=balanced ./scripts/deploy.sh
EASYNET_PROFILE=compat EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
```

策略说明：

- `strict`：只部署 `xray-reality`
- `balanced`：部署 `xray-reality` + `hysteria2`
- `compat`：部署当前全部兼容模块

订阅承载：

- 配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 会额外部署独立订阅承载层，不改变协议组合
- Edge Gateway 默认独占公网 `443/tcp`，首次部署时生成稳定随机订阅前缀，并使用 Nginx 在 `https://域名/s/<随机值>/sub`、`https://域名/s/<随机值>/clash` 发布订阅
- 随机订阅前缀会持久化保存，重启、重部署、证书续期和重新生成订阅都不会改变；可运行 `./scripts/show_subscription.sh` 重新显示链接和二维码
- 如怀疑订阅链接泄露，可运行 `./scripts/rotate_subscription.sh` 主动轮换订阅入口；如需给多设备迁移留出时间，可使用 `./scripts/rotate_subscription.sh --grace` 暂时保留旧入口
- 需要走 `443/tcp` 的 HTTP/WebSocket 协议应作为 Edge backend 监听本机回环地址，避免协议模块直接抢占公网 443
- `V2Ray` 与 `Trojan-Go` 在 Edge 启用时会自动切到 backend 模式，由 Edge 统一处理公网 `443/tcp`
- 如同时配置 `EASYNET_DOMAIN` 与 `EASYNET_SUBSCRIPTION_DOMAIN`，两者都需要解析到当前服务器，Edge 证书会同时覆盖这两个域名
- 如需单独部署协议并由协议自身直占 `443/tcp`，可设置 `EASYNET_EDGE_ENABLED=false` 临时关闭 Edge
- 如确需调整 Edge 端口，可使用高级变量 `EASYNET_EDGE_HTTPS_PORT`
- 当前订阅输出只保留 URI 与 Clash 两类入口，不再生成 `/sub_full`、`/clash_full` 及其二维码

交互部署编号：

- `0`：全部部署
- `1`：`xray-reality`
- `2`：`hysteria2`
- `3`：`trojan-go`
- `4`：`v2ray`
- `5`：`shadowsocks`
- `6`：`wireguard`
- `7`：退出

## 卸载部署

新架构下卸载也按模块边界执行：顶层入口只负责选择和编排，每个协议通过自己的 `scripts/protocols/<module>/uninstall.sh` 清理私有配置、服务文件和 metadata，公共层根据 metadata 更新定时重启任务和防火墙规则。

交互卸载：

```bash
./scripts/uninstall.sh
```

自动化卸载全部协议与 EasyNet Nginx 暴露层：

```bash
EASYNET_UNINSTALL_CHOICE=0 ./scripts/uninstall.sh
```

按单个模块卸载：

```bash
EASYNET_UNINSTALL_MODULE=xray-reality ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=hysteria2 ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=trojan-go ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=v2ray ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=shadowsocks ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=wireguard ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=nginx-exposure ./scripts/uninstall.sh
```

卸载编号：

- `0`：卸载全部协议与 EasyNet Nginx 暴露层
- `1`：`xray-reality`
- `2`：`hysteria2`
- `3`：`trojan-go`
- `4`：`v2ray`
- `5`：`shadowsocks`
- `6`：`wireguard`
- `7`：仅清理 EasyNet Nginx 暴露层与订阅文件
- `8`：退出

默认行为：

- 删除 EasyNet 生成的配置、systemd unit、metadata、订阅文件和协议私有证书目录
- 停止并禁用 metadata 中声明的 systemd 服务
- 移除仅由被卸载模块使用、且不是基础端口的 UFW 规则
- 重建订阅文件并刷新 EasyNet 管理的定时重启任务
- 不默认卸载 apt 包；确认依赖只被 EasyNet 使用时，可设置 `EASYNET_UNINSTALL_PURGE_PACKAGES=true`
- 如需保留配置用于迁移或排障，可设置 `EASYNET_UNINSTALL_KEEP_CONFIG=true`

## Cloudflare 关键说明

- 首次签发证书时必须使用 `DNS Only`，不要开橙云
- 证书签发完成后，可将 Trojan-Go / V2Ray / 订阅链接切到橙云
- `Xray+Reality`、`Shadowsocks`、`WireGuard` 不能依赖 Cloudflare 橙云代理协议本身
- `Hysteria2` 使用 UDP/443，不能走 Cloudflare 橙云代理；域名需要 DNS Only，并确认服务器安全组和 UFW 都放行 UDP/443
- Cloudflare SSL 模式建议使用 `Full` 或 `Full (strict)`
- 订阅链接推荐由 Edge Gateway 提供；旧版 Nginx/订阅承载状态仍可兼容读取

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

- Shadowrocket / v2rayN / v2rayNG：以部署输出或 `./scripts/show_subscription.sh` 显示的 URI 订阅为准
- Clash Verge Rev / Mihomo：以部署输出或 `./scripts/show_subscription.sh` 显示的 Clash 订阅为准

### 其他检查

```bash
sysctl net.ipv4.tcp_congestion_control
```

## 需要时再看

- 客户端导入与平台差异：[客户端说明](./clients.md)
- 出现故障时：[故障排查指南](./troubleshooting-guide.md)
