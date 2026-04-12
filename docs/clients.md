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
- URI 安全订阅：`https://your-domain.com/sub`
- URI 完整订阅：`https://your-domain.com/sub_full`
- Clash 安全订阅：`https://your-domain.com/clash`
- Clash 完整订阅：`https://your-domain.com/clash_full`

使用建议：
- `Clash Verge Rev` / `Mihomo` 使用 `clash`
- `Shadowrocket` / `v2rayN` / `v2rayNG` 使用 `sub`
- 需要 `WireGuard` 或 `Shadowsocks` 时使用对应的 `*_full`

## 各平台最短导入步骤

### Windows / macOS / Linux

- 客户端：Clash Verge Rev
- 地址：https://github.com/clash-verge-rev/clash-verge-rev/releases
- 订阅：`https://your-domain.com/clash`
- 步骤：打开客户端 -> 导入订阅 -> 更新配置 -> 启用系统代理或 TUN

### Android

- 客户端：Clash Meta for Android
- 地址：https://github.com/MetaCubeX/ClashMetaForAndroid/releases
- 订阅：`https://your-domain.com/clash`
- 步骤：配置 -> 新配置 -> URL 导入 -> 粘贴订阅 -> 更新 -> 启动

### iOS

- 客户端：Shadowrocket
- 订阅：`https://your-domain.com/sub`
- 步骤：右上角 `+` -> 类型选 `Subscribe` -> 粘贴订阅 -> 保存 -> 启动

## 验证连接

- 打开 https://www.google.com
- 打开 https://www.cloudflare.com/cdn-cgi/trace
- 查看出口 IP 是否变化

## 常见问题

### Clash Verge Rev 导入失败

- 你导入的是 `sub`，不是 `clash`

### 完整节点没有出现

- 你导入的是安全订阅，不是完整订阅：`sub_full` 或 `clash_full`
