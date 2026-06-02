# EasyNet 客户端说明

## 推荐组合

| 平台 | 推荐客户端 | 说明 |
|------|------------|------|
| Windows / macOS | Clash Verge Rev | 适合日常使用，优先导入订阅 |
| Linux | Clash Verge Rev | 适合桌面 Linux 日常使用，优先导入订阅 |
| Android | Clash Meta for Android | 适合订阅导入和规则分流 |
| iOS | Shadowrocket | 适合订阅导入 |
| Raspberry Pi / 卡片机 | sing-box | 适合作为低资源无界面常驻客户端，直接使用 sing-box 配置 |

## 优先使用订阅导入

部署完成后，终端会打印三组订阅链接：
- URI 订阅：以部署输出为准
- Clash 订阅：以部署输出为准
- sing-box 配置：以部署输出为准

Edge Gateway 会使用首次部署时生成的稳定随机路径承载订阅。忘记链接时，可在服务器项目目录运行：

```bash
./scripts/show_subscription.sh
```

怀疑订阅链接泄露时，可主动轮换订阅入口：

```bash
./scripts/rotate_subscription.sh
```

多设备迁移时可临时保留旧入口：

```bash
./scripts/rotate_subscription.sh --grace
```

使用建议：
- `Clash Verge Rev` / `Mihomo` 使用 `clash`
- `Shadowrocket` / `v2rayN` / `v2rayNG` 使用 `sub`
- `sing-box` 使用 `singbox`

## 各平台最短导入步骤

### Windows / macOS / Linux

- 客户端：Clash Verge Rev
- 地址：https://github.com/clash-verge-rev/clash-verge-rev/releases
- 订阅：使用部署输出中的 Clash 订阅
- 步骤：打开客户端 -> 导入订阅 -> 更新配置 -> 启用系统代理或 TUN

### Android

- 客户端：Clash Meta for Android
- 地址：https://github.com/MetaCubeX/ClashMetaForAndroid/releases
- 订阅：使用部署输出中的 Clash 订阅
- 步骤：配置 -> 新配置 -> URL 导入 -> 粘贴订阅 -> 更新 -> 启动

### iOS

- 客户端：Shadowrocket
- 订阅：使用部署输出中的 URI 订阅
- 步骤：右上角 `+` -> 类型选 `Subscribe` -> 粘贴订阅 -> 保存 -> 启动

### Raspberry Pi / 卡片机

推荐优先使用 `sing-box`。它资源占用更低，适合树莓派、软路由、卡片机这类低资源设备长期无界面运行。

对比结论：

| 方案 | 资源占用 | 订阅导入 | 适配 EasyNet | 建议 |
|------|----------|----------|--------------|------|
| sing-box | 更低 | 可直接使用 sing-box 配置 | 直接使用 `/singbox` 配置 | 推荐 |
| Mihomo | 略高但树莓派 3/4/5 可接受 | 可直接使用 Clash 订阅 | 直接使用 `/clash` 订阅 | 需要 Clash 生态或规则面板时使用 |

原因：
- EasyNet 会生成完整 sing-box JSON 配置，不需要在客户端侧转换
- sing-box 配置只由统一 metadata 渲染，节点顺序与其它订阅保持一致
- 默认提供 `mixed` 本地入口，适合局域网设备通过 HTTP/SOCKS 代理使用

版本要求：
- 推荐使用 `sing-box 1.13+`
- EasyNet 生成的配置已按 `sing-box 1.13+` 新格式输出
- 如果使用更旧版本，建议先升级 sing-box，再导入 `/singbox` 配置

快速安装：

1. 在服务端运行 `./scripts/show_subscription.sh`
2. 复制输出中的“树莓派快速安装”两行命令
3. 在树莓派上执行

示例：

```bash
curl -fsSL "https://example.com/s/<random>/singbox-client.sh" -o easynet-singbox-client.sh
sudo bash easynet-singbox-client.sh --config-url "https://example.com/s/<random>/singbox"
```

默认是 `mixed` 模式，只开启 `7890` HTTP/SOCKS 代理端口。需要让树莓派本机流量自动走代理时，安装时指定 `tun` 模式：

```bash
sudo bash easynet-singbox-client.sh --config-url "https://example.com/s/<random>/singbox" --mode tun
```

安装脚本会自动完成：

- 识别 `arm64` / `armv7` / `armv6` / `amd64` 架构
- 下载或复用 sing-box
- 拉取并校验 `/singbox` 配置
- 按 `mixed` 或 `tun` 模式生成本机配置
- 创建 `easynet-singbox.service`
- 创建每日配置更新 timer
- 启动并设置开机自启
- 输出局域网代理地址

模式说明：

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| `mixed` | 只监听 `0.0.0.0:7890`，不接管本机路由 | 树莓派作为局域网 HTTP/SOCKS 代理 |
| `tun` | 创建 TUN 入站并启用 `auto_route`，接管树莓派本机流量 | 树莓派本机需要全局代理 |

常用检查：

```bash
systemctl status easynet-singbox --no-pager
systemctl status easynet-singbox-update.timer --no-pager
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

随时启动或停止：

```bash
sudo bash easynet-singbox-client.sh start
sudo bash easynet-singbox-client.sh stop
sudo bash easynet-singbox-client.sh restart
sudo bash easynet-singbox-client.sh status
sudo bash easynet-singbox-client.sh doctor
```

切换模式并立即生效：

```bash
sudo bash easynet-singbox-client.sh switch-mode tun
sudo bash easynet-singbox-client.sh switch-mode mixed
```

手动更新配置：

```bash
sudo bash easynet-singbox-client.sh update
```

默认 `mixed` 模式会监听 `7890` 端口。如果树莓派只作为局域网代理网关，可在客户端设备上配置 HTTP/SOCKS 代理指向树莓派的 `7890` 端口。`tun` 模式会接管树莓派本机流量，但不会自动把其它局域网设备透明转发到代理。

## 验证连接

- 打开 https://www.google.com
- 打开任意出口 IP 查询网站
- 查看出口 IP 是否变为服务器所在地

## 常见问题

### Clash Verge Rev 导入失败

- 你可能导入了 URI 订阅 `sub`，Clash/Mihomo 应使用 `clash`

### sing-box 启动失败

- 先运行 `/usr/local/bin/sing-box check -c /etc/sing-box/config.json`
- 确认使用的是 `singbox` 配置链接，不是 `sub` 或 `clash`
- 如看到 `legacy inbound fields are deprecated`，先在服务端重新运行 `./scripts/generate_subscription.sh`，再在树莓派执行 `/usr/local/bin/easynet-singbox-update`

### mixed 模式无法连接 7890

- 先确认当前确实是 `mixed` 模式：`sudo bash easynet-singbox-client.sh doctor`
- 如果当前是 `tun`，切回 mixed：`sudo bash easynet-singbox-client.sh switch-mode mixed`
- 确认服务已启动：`systemctl status easynet-singbox --no-pager`
- 确认端口已监听：`ss -lntup | grep ':7890'`
- 如果没有监听，查看日志：`journalctl -u easynet-singbox -n 80 --no-pager`
- 修复后再测试：`curl -x socks5h://127.0.0.1:7890 https://www.google.com -I`

### 完整节点没有出现

- 确认使用的是当前部署输出或 `./scripts/show_subscription.sh` 显示的订阅入口
- 确认服务器已成功运行 `./scripts/generate_subscription.sh`
