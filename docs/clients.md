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

最短部署思路：

1. 下载与系统架构匹配的 sing-box Linux 二进制，例如 `linux-arm64` 或 `linux-armv7`
2. 保存到 `/usr/local/bin/sing-box` 并赋予执行权限
3. 将 EasyNet 输出的 sing-box 配置链接保存为 `SINGBOX_URL`
4. 定时下载配置到 `/etc/sing-box/config.json`
5. 使用 systemd 常驻运行 sing-box

示例：

```bash
mkdir -p /etc/sing-box
install -m 0755 sing-box /usr/local/bin/sing-box
curl -L "$SINGBOX_URL" -o /etc/sing-box/config.json
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

将下面内容保存为 `/etc/systemd/system/sing-box.service`：

```ini
[Unit]
Description=sing-box Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启动服务：

```bash
systemctl daemon-reload
systemctl enable --now sing-box
```

配置更新示例：

```bash
curl -L "$SINGBOX_URL" -o /etc/sing-box/config.json
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
systemctl restart sing-box
```

默认配置会监听 `7890` mixed 端口。如果树莓派只作为局域网代理网关，可在客户端设备上配置 HTTP/SOCKS 代理指向树莓派的 `7890` 端口。需要透明代理或 TUN 时，再额外配置系统路由和防火墙规则。

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

### 完整节点没有出现

- 确认使用的是当前部署输出或 `./scripts/show_subscription.sh` 显示的订阅入口
- 确认服务器已成功运行 `./scripts/generate_subscription.sh`
