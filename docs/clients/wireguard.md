# WireGuard 客户端配置指南

## WireGuard 简介

WireGuard 是一种现代、高性能的 VPN 协议，具有以下优点：
- 超轻量级，代码简洁
- 极高的性能和低延迟
- 跨平台支持
- 配置简单

## Windows 客户端

### 1. 下载客户端

访问 WireGuard 官网下载 Windows 版本：
- 下载地址：https://www.wireguard.com/install/
- 选择 Windows 安装包

### 2. 安装客户端

1. 运行下载的安装程序
2. 按照提示完成安装
3. 启动 WireGuard 应用

### 3. 导入配置

**方法一：通过配置文件导入**
1. 从服务器获取客户端配置文件（`client1.conf`）
2. 在 WireGuard 应用中点击「Add Tunnel」
3. 选择「Import from file...」
4. 选择你的配置文件

**方法二：通过二维码导入**
1. 在 WireGuard 应用中点击「Add Tunnel」
2. 选择「Scan from QR code...」
3. 扫描服务器上生成的二维码

### 4. 连接

1. 在隧道列表中找到你的配置
2. 点击「Activate」按钮
3. 状态显示「Active」表示连接成功

## macOS 客户端

### 1. 下载客户端

从 Mac App Store 下载 WireGuard：
- 搜索「WireGuard」
- 安装官方应用

或使用 Homebrew 安装：
```bash
brew install wireguard-tools
```

### 2. 导入配置

1. 打开 WireGuard 应用
2. 点击「Import tunnel(s) from file」
3. 选择你的配置文件
4. 或点击「Create from QR code」扫描二维码

### 3. 连接

1. 在隧道列表中点击「Activate」
2. 允许添加 VPN 配置
3. 状态变为绿色表示连接成功

## Linux 客户端

### 1. 安装客户端

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install wireguard wireguard-tools resolvconf
```

**CentOS/Fedora:**
```bash
sudo dnf install wireguard-tools
```

**Arch Linux:**
```bash
sudo pacman -S wireguard-tools
```

### 2. 导入配置

将服务器上的配置文件复制到 `/etc/wireguard/` 目录：
```bash
sudo cp client1.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
```

### 3. 连接和断开

**启动连接：**
```bash
sudo wg-quick up wg0
```

**断开连接：**
```bash
sudo wg-quick down wg0
```

**设置开机自启：**
```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

**查看连接状态：**
```bash
sudo wg show
```

## Android 客户端

### 1. 下载客户端

从 Google Play Store 下载：
- 搜索「WireGuard」
- 安装官方应用

或从 GitHub 下载 APK：
- 下载地址：https://github.com/WireGuard/wireguard-android/releases

### 2. 导入配置

1. 打开 WireGuard 应用
2. 点击右下角「+」按钮
3. 选择「Create from QR code」扫描二维码
4. 或选择「Import from file or archive」导入配置文件

### 3. 连接

1. 点击配置卡片旁边的开关
2. 授予 VPN 权限
3. 开关变为蓝色表示连接成功

## iOS 客户端

### 1. 下载客户端

从 App Store 下载：
- 搜索「WireGuard」
- 安装官方应用（免费）

### 2. 导入配置

1. 打开 WireGuard 应用
2. 点击右上角「+」
3. 选择「Create from QR code」扫描二维码
4. 或选择「Import from file」导入配置文件

### 3. 连接

1. 点击配置旁边的开关
2. 允许添加 VPN 配置
3. 开关变为绿色表示连接成功

## 验证连接

### 检查 IP 地址

访问以下网站确认你的 IP 已变为服务器 IP：
- https://www.whatismyip.com/
- https://ipleak.net/

### 测试连接

```bash
ping 10.0.0.1  # Ping 服务器内网 IP
ping 8.8.8.8    # Ping 外网
```

### 测速

使用 speedtest.net 或 fast.com 测试网速。

## 常见问题

### 连接失败

- 检查服务器 WireGuard 服务状态：`systemctl status wg-quick@wg0`
- 确认防火墙允许 UDP 51820 端口
- 检查配置文件中的公钥是否正确

### 速度慢

- WireGuard 通常比其他协议更快，如果慢可能是服务器本身带宽问题
- 尝试更换服务器位置
- 确认 BBR 已启用

### 频繁断开

- 检查客户端的 `PersistentKeepalive` 设置（建议 25 秒）
- 确认网络稳定
- 查看服务器日志：`journalctl -u wg-quick@wg0 -f`

### 无法访问内网资源

- 检查 `AllowedIPs` 设置
- 确保服务器端的路由配置正确
- 确认防火墙允许转发

## 安全建议

1. **妥善保管私钥**：私钥决定了访问权限
2. **定期更换密钥**：建议定期更新客户端密钥
3. **使用防火墙**：限制只有授权 IP 可以访问 WireGuard 端口
4. **监控连接**：定期查看服务器上的连接状态
