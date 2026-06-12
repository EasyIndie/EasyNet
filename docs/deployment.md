# EasyNet 部署说明

## 适用场景

这份文档只保留部署 EasyNet 所需的最核心信息，适合首次搭建和后续快速复用。

## 部署前准备

- VPS：1 核、1GB 内存、20GB SSD 起步 👉 **[可选VPS提供商列表](./vps-providers.md)**
- 系统：Ubuntu 22.04+ 或 Debian 11+
- 位置：优先香港、日本、新加坡
- 域名：Hysteria2 和订阅链接需要域名
- 端口：确保 `80/tcp`、`443/tcp` 可入站访问；按协议额外开放 `8443/tcp`、`443/udp`、`8388/tcp/udp`、`51820/udp`

## 协议选择

| 协议           | 推荐度 | 适用场景                      |
| ------------ | --- | ------------------------- |
| Xray+Reality | 高   | 抗封锁优先，允许使用支持 Reality 的客户端 |
| Hysteria2    | 高   | UDP/QUIC 场景，适合与 Reality 组成双主力方案 |
| Shadowsocks  | 低   | 仅在特定客户端或测试场景使用            |
| WireGuard    | 低   | 适合中转、低延迟、独立 VPN 场景        |

结论：

- 日常优先：`Xray+Reality`，需要 UDP/QUIC 补充时加 `Hysteria2`
- 订阅承载与协议部署解耦；配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 后会自动启用 Edge Gateway 并打印订阅链接和二维码
- 特定用途：`Shadowsocks` / `WireGuard`

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
- 部署编号 `1` 到 `4` 按安全性和抗 DPI 能力从高到低排序

说明：各协议模块部署后会导出标准 metadata，订阅生成器只读取 metadata。部署入口统一走 `scripts/protocols/*` 与 `scripts/exposure/edge`。订阅链接只在存在 Edge Gateway 域名，或显式设置 `EASYNET_SUBSCRIPTION_DOMAIN` 时打印。

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
EASYNET_MODULE=hysteria2 EASYNET_DOMAIN=proxy.example.com ./scripts/deploy.sh
EASYNET_MODULE=shadowsocks ./scripts/deploy.sh
EASYNET_MODULE=wireguard ./scripts/deploy.sh
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
- `compat`：部署当前全部模块

订阅承载：

- 配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 会自动部署 Edge Gateway，不改变协议组合
- Edge Gateway 默认独占公网 `443/tcp`，首次部署时生成稳定随机订阅前缀，并使用 Nginx 在 `https://域名/s/<随机值>/sub`、`https://域名/s/<随机值>/clash`、`https://域名/s/<随机值>/singbox` 发布订阅
- 随机订阅前缀会持久化保存，重启、重部署、证书续期和重新生成订阅都不会改变；可运行 `./scripts/show_subscription.sh` 重新显示链接和二维码
- 如怀疑订阅链接泄露，可运行 `./scripts/rotate_subscription.sh` 主动轮换订阅入口；如需给多设备迁移留出时间，可使用 `./scripts/rotate_subscription.sh --grace` 暂时保留旧入口
- `Hysteria2` 使用 Edge 统一证书，自身监听 `443/udp` 承载 QUIC 流量
- 如同时配置 `EASYNET_DOMAIN` 与 `EASYNET_SUBSCRIPTION_DOMAIN`，两者都需要解析到当前服务器，Edge 证书会同时覆盖这两个域名
- 如确需调整 Edge 端口，可使用高级变量 `EASYNET_EDGE_HTTPS_PORT`
- Edge Gateway 根路径默认反向代理到 Bing 以消除指纹，可通过 `EASYNET_EDGE_MASQUERADE_URL` 自定义
- 当前订阅输出保留 URI、Clash/Mihomo 与 sing-box 三类入口
- 订阅文件中的节点顺序按安全性和抗 DPI 能力从高到低输出：`Xray+Reality`、`Hysteria2`、`Shadowsocks`、`WireGuard`

环境变量：

- `.env` 只加载 `EASYNET_*` 变量，非 EasyNet 变量会被忽略
- 远程安装脚本和发布包支持可选 SHA256 校验，变量见 `.env.example`

交互部署编号：

- `0`：全部部署
- `1`：`xray-reality`
- `2`：`hysteria2`
- `3`：`shadowsocks`
- `4`：`wireguard`
- `5`：退出

## 卸载部署

新架构下卸载也按模块边界执行：顶层入口只负责选择和编排，每个协议通过自己的 `scripts/protocols/<module>/uninstall.sh` 清理私有配置、服务文件和 metadata，公共层根据 metadata 更新定时重启任务和防火墙规则。

交互卸载：

```bash
./scripts/uninstall.sh
```

自动化卸载全部协议与 Edge Gateway：

```bash
EASYNET_UNINSTALL_CHOICE=0 ./scripts/uninstall.sh
```

按单个模块卸载：

```bash
EASYNET_UNINSTALL_MODULE=xray-reality ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=hysteria2 ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=shadowsocks ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=wireguard ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=edge-exposure ./scripts/uninstall.sh
```

卸载编号：

- `0`：卸载全部协议与 Edge Gateway
- `1`：`xray-reality`
- `2`：`hysteria2`
- `3`：`shadowsocks`
- `4`：`wireguard`
- `5`：仅清理 Edge Gateway 与订阅文件
- `6`：退出

默认行为：

- 删除 EasyNet 生成的配置、systemd unit、metadata、订阅文件和协议私有证书目录
- 停止并禁用 metadata 中声明的 systemd 服务
- 移除仅由被卸载模块使用、且不是基础端口的 UFW 规则
- 重建订阅文件并刷新 EasyNet 管理的定时重启任务
- 不默认卸载 apt 包；确认依赖只被 EasyNet 使用时，可设置 `EASYNET_UNINSTALL_PURGE_PACKAGES=true`
- 如需保留配置用于迁移或排障，可设置 `EASYNET_UNINSTALL_KEEP_CONFIG=true`

## 验证部署

### 服务状态

```bash
systemctl status xray
systemctl status hysteria-server.service
systemctl status shadowsocks-libev-server
systemctl status wg-quick@wg0
```

### 订阅链接

- Shadowrocket / v2rayN / v2rayNG：以部署输出或 `./scripts/show_subscription.sh` 显示的 URI 订阅为准
- Clash Verge Rev / Mihomo：以部署输出或 `./scripts/show_subscription.sh` 显示的 Clash 订阅为准
- Raspberry Pi / 卡片机 / 无界面 Linux：以部署输出或 `./scripts/show_subscription.sh` 显示的 sing-box 配置为准，推荐 `sing-box 1.13+`

### 其他检查

```bash
sysctl net.ipv4.tcp_congestion_control
./scripts/smoke_test.sh
```

`smoke_test.sh` 会读取 metadata，快速检查服务状态、关键端口、防火墙规则和当前订阅入口，适合真实 VPS 部署后做第一轮回归验证。

### 长期运行检查

Edge TLS 证书由 `acme.sh` 自动续期。续期完成后会调用 `scripts/exposure/edge/cert_renew_hook.sh`，自动修复 Edge 证书权限并重启 `nginx` 和 `hysteria-server.service`。

日志方面，部署脚本会限制 journald 使用量，并为 Nginx 写入 EasyNet 管理的 logrotate 配置。可定期检查：

```bash
journalctl --disk-usage
du -sh /var/log/nginx
~/.acme.sh/acme.sh --list
openssl x509 -in /etc/ssl/easynet-edge/fullchain.crt -noout -enddate
```

## 需要时再看

- 客户端导入与平台差异：[客户端说明](./clients.md)
- 出现故障时：[故障排查指南](./troubleshooting-guide.md)
