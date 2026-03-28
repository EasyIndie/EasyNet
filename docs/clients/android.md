# Android 客户端配置指南

## Trojan-Go 客户端 (推荐)

### 1. 下载客户端

推荐使用 **NekoBox for Android**：
- 下载地址：https://github.com/MatsuriDayo/NekoBoxForAndroid/releases
- 选择 `NekoBox-*-android-universal-release.apk`

### 2. 安装并配置

1. 下载并安装 APK（需允许安装未知来源应用）
2. 打开 NekoBox
3. 点击右上角「+」→「手动输入」→「Trojan」
4. 填写以下信息：
   - 服务器：你的域名
   - 端口：443
   - 密码：部署时生成的密码
   - 传输：WebSocket
   - 路径：部署时生成的随机路径 (例如：/trojan 或 /a1b2c3d4)
   - TLS：启用

或者直接扫描二维码：
- 点击右上角「+」→「扫描二维码」
- 扫描配置二维码即可

### 3. 启动代理

1. 在服务器列表中点击已添加的服务器
2. 点击右下角「启动」按钮
3. 授予 VPN 权限
4. 在系统通知栏可看到连接状态

## Shadowsocks 客户端

### 1. 下载客户端

推荐使用 **Shadowsocks for Android**：
- 下载地址：https://github.com/shadowsocks/shadowsocks-android/releases

### 2. 配置

1. 打开 Shadowsocks
2. 点击左上角「+」→「手动设置」
3. 填写信息：
   - 服务器：你的服务器 IP
   - 远程端口：8388
   - 密码：部署时生成的密码
   - 加密方式：chacha20-ietf-poly1305

### 3. 启动

1. 点击服务器卡片
2. 点击右下角「纸飞机」图标
3. 授予 VPN 权限

## Clash Meta for Android (通用客户端)

### 1. 下载客户端

推荐使用 **Clash Meta for Android**：
- 下载地址：https://github.com/MetaCubeX/ClashMetaForAndroid/releases

### 2. 配置节点（推荐使用订阅）

1. 下载并安装
2. 打开应用
3. 点击「配置」→「新配置」→「URL 导入」
4. 在 URL 栏中，粘贴终端部署完成后输出的 **节点订阅链接**：
   - 安全订阅：`https://your-domain.com/sub`（Xray/Trojan/V2Ray）
   - 完整订阅：`https://your-domain.com/sub_full`（额外包含 Shadowsocks/WireGuard）
5. 命名并保存，点击更新。节点会自动下载并分组。

### 3. 启动

1. 点击「代理」选择节点
2. 点击首页开关启动
3. 授予 VPN 权限

## V2Ray 客户端

### 1. 下载客户端

推荐使用 **V2RayNG**：
- 下载地址：https://github.com/2dust/v2rayNG/releases

### 2. 配置

1. 打开 V2RayNG
2. 点击右上角「+」→「手动输入」→「VMess」
3. 填写信息：
   - 地址：你的域名
   - 端口：443
   - 用户 ID (UUID)：部署时生成的 UUID
   - 额外 ID (AlterId)：0
   - 传输协议：ws
   - 伪装域名/Host：你的域名
   - 路径：部署时生成的随机路径 (例如：/a6d31173)
   - 底层传输安全：tls

或者更简单的方法：复制终端输出的 `vmess://` 链接，在 V2RayNG 中选择从剪贴板导入即可。

### 3. 启动

1. 点击右下角「V」图标
2. 授予 VPN 权限

## 验证连接

配置完成后，访问以下网站验证：
- https://www.google.com
- https://www.youtube.com
- https://www.cloudflare.com/cdn-cgi/trace

## 常见问题

### 无法安装 APK

1. 打开「设置」→「安全」
2. 启用「未知来源」或「安装未知应用」
3. 重新安装 APK

### 连接断开

- 检查服务器是否正常运行
- 尝试切换网络（WiFi/移动数据）
- 关闭电池优化

### 速度慢

- 尝试更换服务器节点
- 确认 BBR 已启用
- 检查本地网络质量
