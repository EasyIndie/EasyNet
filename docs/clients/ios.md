# iOS 客户端配置指南

## Shadowrocket (推荐)

### 1. 下载客户端

Shadowrocket 是 iOS 上最强大的代理客户端之一：
- 官网: https://www.shadowrocket.vip/
- 需要在 App Store 购买（约 $2.99）
- 搜索「Shadowrocket」下载

注意：Shadowrocket 在中国区 App Store 已下架，需要使用外区 Apple ID 下载。

### 2. 配置节点

**方法一：使用订阅链接（强烈推荐）**
这是最简单的配置方式：
1. 复制终端部署完成后输出的**节点订阅链接**：
   - 安全订阅：`https://your-domain.com/sub`（Xray/Trojan/V2Ray）
   - 完整订阅：`https://your-domain.com/sub_full`（额外包含 Shadowsocks/WireGuard）
2. 打开 Shadowrocket，点击右上角的「+」号。
3. 在「类型」中选择 **Subscribe (订阅)**。
4. 在「URL」中粘贴刚刚复制的链接。
5. 点击「完成」，此时软件会自动下载并导入你部署的所有协议节点。

**方法二：扫描二维码（单节点导入）**
1. 点击右上角「扫码」图标
2. 扫描终端生成的对应协议的二维码即可

**方法三：手动填写 Trojan-Go**
1. 打开 Shadowrocket
2. 点击右上角「+」
3. 选择「类型」→「Trojan」
4. 填写以下信息：
   - 地址：你的域名
   - 端口：443
   - 密码：部署时生成的密码
   - 传输：WebSocket
   - 路径：部署时生成的随机路径 (例如：/trojan 或 /a1b2c3d4)
   - TLS：开启

### 3. 启动代理

1. 在服务器列表中点击已添加的服务器
2. 点击首页顶部开关
3. 授予 VPN 权限
4. 选择「全局路由」或「配置」模式

## Quantumult X

### 1. 下载客户端

- 需要在 App Store 购买（约 $7.99）
- 使用外区 Apple ID 搜索「Quantumult X」下载

### 2. 配置

1. 打开 Quantumult X
2. 点击右下角「风车」图标
3. 点击「+」添加服务器
4. 选择协议类型并填写信息

### 3. 启动

1. 回到首页
2. 点击右上角开关
3. 授予 VPN 权限

## Stash

### 1. 下载客户端

Stash 是 Clash 的 iOS 优秀衍生版本，支持各类主流协议：
- 需要在 App Store 购买（约 $3.99）
- 使用外区 Apple ID 搜索「Stash」下载

### 2. 配置

1. 打开 Stash
2. 点击「配置」→「新建配置」或「从 URL 下载」
3. 输入订阅链接或手动配置

### 3. 启动

1. 点击「策略」选择节点
2. 返回首页点击「启动」开关
3. 授予 VPN 权限

## V2Box

### 1. 下载客户端

V2Box 支持 V2Ray/Shadowsocks/Trojan：
- 在 App Store 搜索「V2Box」下载（部分地区可能下架）

### 2. 配置

1. 打开 V2Box
2. 点击「+」添加服务器
3. 选择协议并填写配置信息

### 3. 启动

1. 选择服务器
2. 点击「连接」
3. 授予 VPN 权限

## 如何获取外区 Apple ID

### 方法一：自己注册

1. 访问 appleid.apple.com
2. 注册新账号，地区选择「美国」或「香港」
3. 付款方式选择「无」
4. 验证邮箱和手机号

### 方法二：购买账号

- 在淘宝等平台购买外区 Apple ID
- 注意选择信誉好的卖家
- 购买后及时修改密码和绑定信息

### 使用注意事项

1. 不要在 iCloud 登录外区 ID
2. 只在 App Store 登录
3. 下载完应用后立即退出
4. 定期更换密码

## 验证连接

配置完成后，访问以下网站验证：
- https://www.google.com
- https://www.youtube.com
- https://www.cloudflare.com/cdn-cgi/trace

## 常见问题

### 无法连接

- 检查服务器是否正常运行
- 确认配置信息正确
- 尝试更换网络

### 应用闪退

- 更新应用到最新版本
- 重启手机
- 卸载后重新安装

### 速度慢

- 尝试更换服务器节点
- 确认 BBR 已启用
- 检查本地网络质量

### 流量消耗大

- 开启「规则模式」而非「全局模式」
- 使用 PAC 或分流规则
- 关闭后台应用刷新
