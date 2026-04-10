# EasyNet 客户端说明

## 推荐组合

| 平台 | 推荐客户端 | 说明 |
|------|------------|------|
| Windows / macOS | Clash Verge Rev | 适合日常使用，优先导入订阅 |
| Android | Clash Meta for Android | 适合订阅导入和规则分流 |
| iOS | Shadowrocket | 适合订阅导入与手动补充 |
| Windows / Android | v2rayN / v2rayNG | 适合手动调试 Reality、VMess、Trojan 单节点 |

## 优先使用订阅导入

部署完成后，终端会打印两个订阅链接：
- 安全订阅：`https://your-domain.com/sub`
- 完整订阅：`https://your-domain.com/sub_full`

使用建议：
- 日常首选 `sub`
- 需要 `WireGuard` 或 `Shadowsocks` 时使用 `sub_full`

## 各平台最短导入步骤

### Windows / macOS

- 客户端：Clash Verge Rev
- 地址：https://github.com/clash-verge-rev/clash-verge-rev/releases
- 步骤：打开客户端 -> 导入订阅 -> 更新配置 -> 启用系统代理或 TUN

### Android

- 客户端：Clash Meta for Android
- 地址：https://github.com/MetaCubeX/ClashMetaForAndroid/releases
- 步骤：配置 -> 新配置 -> URL 导入 -> 粘贴订阅 -> 更新 -> 启动

### iOS

- 客户端：Shadowrocket
- 步骤：右上角 `+` -> 类型选 `Subscribe` -> 粘贴订阅 -> 保存 -> 启动

## WireGuard 单独使用

如果你只想把 WireGuard 当独立 VPN 使用，建议直接导入官方配置文件 `client1.conf`，不要走订阅。

### 官方客户端下载

- Windows / macOS / iOS：https://www.wireguard.com/install/
- Android：https://github.com/WireGuard/wireguard-android/releases

### 导入步骤

- Windows：`Add Tunnel` -> `Import from file...`
- macOS：`Import tunnel(s) from file`
- Android：右下角 `+` -> `Import from file or archive`
- iOS：右上角 `+` -> `Import from file`

## Xray+Reality 手动导入

只有在订阅导入不满足需求，或者要单独调试 Reality 时，才建议手动填写。

关键参数：
- 地址：服务器 IP
- 端口：`443`
- 协议：`VLESS`
- 加密：`none`
- 流控：`xtls-rprx-vision`
- 传输：`tcp`
- 安全：`reality`
- 指纹：`chrome`
- SNI / PublicKey / ShortID：使用部署输出值

推荐手动调试客户端：
- Windows：`v2rayN`
- Android：`v2rayNG`
- iOS：`Shadowrocket`

## 验证连接

- 打开 https://www.google.com
- 打开 https://www.cloudflare.com/cdn-cgi/trace
- 查看出口 IP 是否变化

## 常见问题

### 订阅导入后没有 WireGuard 节点

- 你导入的是 `sub`，不是 `sub_full`

### 扫码后只出现单个节点

- 扫到的是协议二维码，不是订阅二维码

### 客户端能连上但系统没有走代理

- 确认系统代理或 TUN 已启用

### iOS 无法下载 Shadowrocket

- 通常需要外区 Apple ID
