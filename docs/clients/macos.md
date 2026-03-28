# macOS 客户端配置指南

## Trojan-Go 客户端 (推荐)

### 1. 下载客户端

推荐使用 **NekoBox for macOS**：
- 下载地址：https://github.com/MatsuriDayo/nekoray/releases
- 选择 `nekoray-macos-universal.zip`

### 2. 安装并配置

1. 下载并解压
2. 将 NekoBox 拖拽到 Applications 文件夹
3. 打开 NekoBox（如遇安全警告，在系统设置中允许打开）
4. 点击「服务器」→「新建服务器」→「Trojan」
5. 填写以下信息：
   - 地址：你的域名
   - 端口：443
   - 密码：部署时生成的密码
   - 传输：WebSocket
   - 路径：部署时生成的随机路径 (例如：/trojan 或 /a1b2c3d4)
   - TLS：启用

或者直接使用 URL 导入：
- 点击「服务器」→「从剪贴板导入」
- 粘贴服务器链接

### 3. 启动代理

1. 在服务器列表中右键点击已添加的服务器
2. 选择「启动」
3. 系统代理模式选择「全局模式」或「PAC 模式」

## Shadowsocks 客户端

### 1. 下载客户端

推荐使用 **ShadowsocksX-NG**：
- 下载地址：https://github.com/shadowsocks/ShadowsocksX-NG/releases

### 2. 配置

1. 打开 ShadowsocksX-NG
2. 点击菜单栏图标 →「服务器」→「服务器设置」
3. 点击「+」添加服务器
4. 填写信息：
   - 地址：你的服务器 IP
   - 端口：8388
   - 密码：部署时生成的密码
   - 加密方式：chacha20-ietf-poly1305

### 3. 启动

1. 点击菜单栏图标
2. 选择「打开 Shadowsocks」
3. 选择「PAC 模式」或「全局模式」

## Clash Verge Rev (通用客户端)

### 1. 下载客户端

推荐使用 **Clash Verge Rev**（支持多协议，持续更新）：
- 下载地址：https://github.com/clash-verge-rev/clash-verge-rev/releases
- 根据你的 Mac 芯片选择 `aarch64` (M1/M2/M3) 或 `x64` (Intel) 版本。

### 2. 导入节点订阅（推荐）

现在 EasyNet 支持自动生成订阅链接，导入极其简单：

1. 下载并安装 Clash Verge Rev
2. 打开应用
3. 点击左侧「订阅」或「配置」→「导入」
4. 将部署完成后终端输出的 **节点订阅链接** 粘贴进去：
   - 安全订阅：`https://your-domain.com/sub`（Xray/Trojan/V2Ray）
   - 完整订阅：`https://your-domain.com/sub_full`（额外包含 Shadowsocks/WireGuard）
5. 点击「下载」或「更新」，节点将一次性导入。

### 3. 启动

1. 在「配置」中选中刚刚添加的配置
2. 在「设置」中开启「系统代理」
3. 选择合适的代理模式（规则/全局）

## 验证连接

配置完成后，访问以下网站验证：
- https://www.google.com
- https://www.youtube.com
- https://www.cloudflare.com/cdn-cgi/trace

## 常见问题

### 应用无法打开

macOS 可能会阻止第三方应用打开，解决方法：
1. 打开「系统设置」→「隐私与安全性」
2. 找到被阻止的应用，点击「仍要打开」

### 无法连接

- 检查服务器是否正常运行
- 确认防火墙已开放端口
- 检查域名 DNS 解析

### 代理不生效

- 确认系统代理已启用
- 尝试重启客户端
- 检查是否有其他代理软件冲突
