# Windows 客户端配置指南

## Trojan-Go 客户端 (推荐)

### 1. 下载客户端

推荐使用 **NekoBox for Windows**：
- 下载地址：https://github.com/MatsuriDayo/nekoray/releases

### 2. 安装并配置

**方法一：使用订阅链接（推荐）**
1. 打开 NekoBox
2. 点击「订阅」或「配置」→「从 URL 导入」
3. 粘贴部署完成后终端输出的订阅链接：
   - 安全订阅：`https://your-domain.com/sub`（Xray/Trojan/V2Ray）
   - 完整订阅：`https://your-domain.com/sub_full`（额外包含 Shadowsocks/WireGuard）
4. 点击更新，节点会自动导入

**方法二：手动配置单节点**
1. 下载并解压 NekoBox
2. 运行 `nekoray.exe`
3. 点击「服务器」→「新建服务器」→「Trojan」
4. 填写以下信息：
   - 地址：你的域名
   - 端口：443
   - 密码：部署时生成的密码
   - 传输：WebSocket
   - 路径：部署时生成的随机路径 (例如：/trojan 或 /a1b2c3d4)
   - TLS：启用

或者直接使用 URL 导入：
- 点击「服务器」→「从剪贴板导入」
- 粘贴服务器链接即可

### 3. 启动代理

1. 在服务器列表中右键点击已添加的服务器
2. 选择「启动」
3. 系统代理模式选择「全局模式」或「PAC 模式」

## Shadowsocks 客户端

### 1. 下载客户端

推荐使用 **Shadowsocks-Windows**：
- 下载地址：https://github.com/shadowsocks/shadowsocks-windows/releases

### 2. 配置

1. 运行 Shadowsocks.exe
2. 点击「编辑服务器」
3. 填写信息：
   - 服务器 IP：你的服务器 IP
   - 服务器端口：8388
   - 密码：部署时生成的密码
   - 加密：chacha20-ietf-poly1305

### 3. 启动

1. 右键点击系统托盘图标
2. 选择「启用系统代理」
3. 选择「PAC 模式」或「全局模式」

## V2Ray 客户端

### 1. 下载客户端

推荐使用 **V2RayN**：
- 下载地址：https://github.com/2dust/v2rayN/releases

### 2. 配置

1. 运行 v2rayN.exe
2. 点击「服务器」→「添加 [VMess] 服务器」
3. 填写信息：
   - 地址：你的域名
   - 端口：443
   - 用户 ID (UUID)：部署时生成的 UUID
   - 额外 ID (AlterId)：0
   - 传输协议：ws
   - 伪装域名/Host：你的域名
   - 路径：部署时生成的随机路径 (例如：/a6d31173)
   - 底层传输安全：tls

或者更简单的方法：复制终端输出的 `vmess://` 链接，在 V2RayN 中按 `Ctrl+V` 导入即可。

### 3. 启动

1. 点击「系统代理」→「自动配置系统代理」
2. 选择「PAC 模式」或「全局模式」

## 验证连接

配置完成后，访问以下网站验证：
- https://www.google.com
- https://www.youtube.com
- https://www.cloudflare.com/cdn-cgi/trace

## 常见问题

### 连接失败

- 检查服务器是否正常运行
- 确认防火墙已开放端口
- 检查域名 DNS 解析是否正确

### 速度慢

- 尝试更换服务器节点
- 确认 BBR 已启用
- 检查本地网络连接
