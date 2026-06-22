# EasyNet 客户端说明

## 推荐组合

| 平台 | 推荐客户端 | 说明 |
|------|------------|------|
| Windows / macOS | Clash Verge Rev / Mihomo | 适合日常使用，优先导入订阅 |
| Linux | Clash Verge Rev / Mihomo | 适合桌面 Linux 日常使用，优先导入订阅 |
| Android | Clash Meta for Android | 适合订阅导入和规则分流 |
| iOS | Shadowrocket | 适合订阅导入 |
| Raspberry Pi / 卡片机 | sing-box | 适合作为低资源无界面常驻客户端，直接使用 sing-box 配置 |

## 优先使用订阅导入

部署完成后终端会打印三组订阅链接（URI / Clash / sing-box）。Edge Gateway 使用首次部署时生成的稳定随机路径承载订阅。

忘记链接时，在项目目录运行 `./scripts/show_subscription.sh`；怀疑泄露时运行 `./scripts/rotate_subscription.sh`（`--grace` 可临时保留旧入口供多设备迁移）。

使用建议：
- `Clash Verge Rev` / `Mihomo` 使用 `clash` 端点
- `Shadowrocket` / `v2rayN` / `v2rayNG` 使用 `sub`
- `sing-box` 使用 `singbox`

## 各平台最短导入步骤

### Windows / macOS / Linux

- 客户端：[Clash Verge Rev / Mihomo](https://github.com/clash-verge-rev/clash-verge-rev/releases)
- 步骤：打开客户端 → 导入 Clash 订阅 → 更新配置 → 启用系统代理或 TUN

### Android

- 客户端：[Clash Meta for Android](https://github.com/MetaCubeX/ClashMetaForAndroid/releases)
- 步骤：配置 → 新配置 → URL 导入 → 粘贴 Clash 订阅 → 更新 → 启动

### iOS

- 客户端：Shadowrocket
- 步骤：右上角 `+` → 类型选 `Subscribe` → 粘贴 URI 订阅 → 保存 → 启动

### Raspberry Pi / 卡片机

树莓派、软路由、卡片机建议使用 `sing-box`（要求 1.13+）。

**安装：** 在服务端运行 `./scripts/show_subscription.sh`，复制输出中的”树莓派快速安装”两行命令，到树莓派上执行：

```bash
curl -fsSL “https://your-domain/s/<random>/singbox-client.sh” -o easynet-singbox-client.sh
sudo bash easynet-singbox-client.sh --config-url “https://your-domain/s/<random>/singbox”
```

默认是 `mixed` 模式（监听 `7890` 代理端口）。如需本机全局代理，安装时加 `--mode tun`：

模式说明：

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| `mixed` | 监听 `7890` HTTP/SOCKS 代理端口 | 其它设备手动配置代理到树莓派 |
| `tun` | 接管树莓派本机流量 | 树莓派自己全局走代理 |

常用命令：`start` / `stop` / `restart` / `status` / `doctor` / `update`

```bash
sudo bash easynet-singbox-client.sh <命令>
```

- `status` — 先打印当前模式，再显示 systemd 状态
- `doctor` — 自动诊断模式、入站配置、服务状态和代理连通性（探测地址 `https://www.gstatic.com/generate_204`，可通过 `EASYNET_SINGBOX_PROBE_URL` 覆盖）

切换模式（`tun` / `mixed`）：

```bash
sudo bash easynet-singbox-client.sh switch-mode tun
sudo bash easynet-singbox-client.sh switch-mode mixed
```

切换时自动按”停止 → 写入新配置 → 启动”顺序执行，失败时恢复原模式。
`tun` 模式只接管本机流量，不透明转发局域网设备。

## 验证连接

优先运行：

```bash
sudo bash easynet-singbox-client.sh doctor
```

如果结论为代理正常，再按需打开网页或访问出口 IP 查询网站确认出口位置。

## 协议客户端兼容性

| 协议特性 | 最低客户端要求 |
|----------|--------------|
| Shadowsocks 2022 (BLAKE3) | Clash Verge Rev ≥1.6, Shadowrocket ≥2.2.38, sing-box ≥1.8 |
| Xray XHTTP 传输 | Clash Verge Rev ≥1.7, sing-box ≥1.11 |
| Hysteria2 Port Hopping | 需客户端支持 `port_hopping` 参数 |
| WireGuard AmneziaWG | Clash Verge Rev (支持 jc/jmin/jmax), AmneziaWG 客户端 |

## 常见问题

### Clash Verge Rev 导入失败

- 你可能导入了 URI 订阅 `sub`，Clash/Mihomo 应使用 `clash`
- 检查协议兼容性：XHTTP 传输需 Clash Verge Rev ≥1.7

### sing-box 启动失败

- 先运行 `/usr/local/bin/sing-box check -c /etc/sing-box/config.json`
- 确认使用的是 `singbox` 配置链接
- Shadowsocks 2022 节点需 sing-box ≥1.8
- 如看到 `legacy inbound fields are deprecated`，先在服务端重新运行 `./scripts/generate_subscription.sh`，再在树莓派执行 `/usr/local/bin/easynet-singbox-update`

### mixed 模式无法连接 7890

- 先运行自动诊断：`sudo bash easynet-singbox-client.sh doctor`
- 如果当前是 `tun`，切回 mixed：`sudo bash easynet-singbox-client.sh switch-mode mixed`
- 如果诊断结论显示服务未运行或端口未监听，按输出中的服务状态和日志继续处理
- 修复后再测试：`curl -x socks5h://127.0.0.1:7890 https://www.google.com -I`

### tun 模式无法访问域名

- 先确认 mixed 模式可用：`curl -x socks5h://127.0.0.1:7890 https://www.google.com -I`
- 切换到 tun 并重新生成配置：`sudo bash easynet-singbox-client.sh switch-mode tun`
- 运行自动诊断：`sudo bash easynet-singbox-client.sh doctor`
- 如果诊断结论显示连通性失败，确认配置中存在 `tun-in`、`hijack-dns`、`dns.servers` 和 `route.default_domain_resolver`
- 如看到 `missing route.default_domain_resolver`，先在服务端重新运行 `./scripts/generate_subscription.sh` 并重新下载客户端脚本
- 再测试：`curl https://www.google.com -I`

### 完整节点没有出现

- 确认使用的是当前部署输出或 `./scripts/show_subscription.sh` 显示的订阅入口
- 确认服务器已成功运行 `./scripts/generate_subscription.sh`

### AmneziaWG 节点无法连接

- 服务器端为标准 WireGuard（无需改动），客户端需使用支持 jc/jmin/jmax 的 AmneziaWG 客户端
- 如客户端不支持 AmneziaWG，关闭 `EASYNET_WIREGUARD_OBFS` 重新部署以生成标准 WireGuard 配置

### Hysteria2 端口跳变后无法连接

- 确认客户端支持 port hopping 参数
- 确认云厂商安全组和服务器防火墙已放行跳变端口范围（如 20000-30000/udp）
