# EasyNet 客户端说明

## 推荐组合

| 平台 | 推荐客户端 | 说明 |
|------|------------|------|
| Windows / macOS | Clash Verge Rev | 适合日常使用，优先导入订阅 |
| Linux | Clash Verge Rev | 适合桌面 Linux 日常使用，优先导入订阅 |
| Android | Clash Meta for Android | 适合订阅导入和规则分流 |
| iOS | Shadowrocket | 适合订阅导入 |

## 优先使用订阅导入

部署完成后，终端会打印两组订阅链接：
- URI 订阅：以部署输出为准
- Clash 订阅：以部署输出为准

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

## 验证连接

- 打开 https://www.google.com
- 打开 https://www.cloudflare.com/cdn-cgi/trace
- 查看出口 IP 是否变化

## 常见问题

### Clash Verge Rev 导入失败

- 你导入的是 `sub`，不是 `clash`

### 完整节点没有出现

- 确认使用的是当前部署输出或 `./scripts/show_subscription.sh` 显示的订阅入口
