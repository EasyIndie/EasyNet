# Cloudflare CDN 配置指南

## 重要说明（与 EasyNet 当前实现强相关）

EasyNet 当前实现包含多种协议，但并非都能被 Cloudflare 橙云代理。

### 可以走 Cloudflare 橙云（Proxied）

- Trojan-Go：脚本使用 WebSocket + TLS（443，随机路径），属于标准 HTTPS/WebSocket 形态
- V2Ray：通过 Nginx 将 WebSocket 反代到本机 127.0.0.1:4443，对外仍是 HTTPS/WebSocket
- 订阅链接：`/sub` 与 `/sub_full` 由 Trojan-Go 回落到本机 Nginx 返回

### 不应指望 Cloudflare 橙云隐藏源站 IP

- Xray Reality：TCP 形态，不是标准 HTTPS
- Shadowsocks：非 HTTP(S) 协议
- WireGuard：UDP 协议

### 证书申请阶段必须 DNS Only（灰云）

脚本使用 acme.sh standalone 申请证书，需要公网直连服务器 80 端口完成校验。首次部署阶段请先设置 DNS Only，签发完成后再按需切换橙云。

## 为什么使用 Cloudflare

- 免费 CDN 加速
- 隐藏真实服务器 IP
- 免费 SSL 证书
- DDoS 防护
- 全球边缘节点

## 注册 Cloudflare 账号

1. 访问 https://dash.cloudflare.com/sign-up
2. 输入邮箱和密码注册
3. 验证邮箱地址

## 添加域名

1. 登录 Cloudflare 控制台
2. 点击「Add Site」
3. 输入你的域名（例如 example.com）
4. 选择免费套餐（Free Plan）
5. 点击「Continue」

## 修改 DNS 服务器

Cloudflare 会检测你当前的 DNS 记录，然后提供两个新的 DNS 服务器地址。

### 修改域名 DNS

1. 登录你的域名注册商网站（如 GoDaddy、Namecheap 等）
2. 找到域名管理页面
3. 修改 DNS 服务器（Nameservers）为 Cloudflare 提供的地址
   - 例如：`roan.ns.cloudflare.com` 和 `dawn.ns.cloudflare.com`
4. 保存更改

DNS 更改可能需要最多 24 小时生效。

## 配置 DNS 记录

### 添加 A 记录

1. 在 Cloudflare 控制台进入「DNS」页面
2. 点击「Add record」
3. 选择「A」类型
4. Name 填写：`@`（代表根域名）或 `www`
5. IPv4 address 填写你的 VPS 服务器 IP
6. Proxy status：
   - 首次部署与证书签发阶段：请选择「DNS only」（灰色云朵）
   - 仅在使用 Trojan/V2Ray/订阅链接时再切换为「Proxied」（橙色云朵）
7. 点击「Save」

如果你想使用子域名（如 proxy.example.com）：
- Name 填写：`proxy`
- 其他配置同上

### 添加 CNAME 记录（可选）

如果你想把 www 重定向到根域名：
1. Type: CNAME
2. Name: www
3. Target: example.com
4. Proxy: Proxied

## 配置 SSL/TLS

### SSL/TLS 加密模式

1. 进入「SSL/TLS」→「Overview」页面
2. 选择加密模式为「Full」或「Full (strict)」

推荐使用「Full」模式，更加稳定。

### 始终使用 HTTPS

1. 进入「SSL/TLS」→「Edge Certificates」
2. 启用「Always Use HTTPS」

### 最小 TLS 版本

1. 在同一页面，设置「Minimum TLS Version」为「TLS 1.2」

## 配置速度优化

### 自动压缩

1. 进入「Speed」→「Optimization」
2. 启用「Auto Minify」的 JavaScript、CSS、HTML
3. 启用「Brotli」压缩

### Rocket Loader（可选）

1. 在同一页面，启用「Rocket Loader」
2. 注意：可能会影响某些网站功能

## 配置防火墙规则（可选）

### 允许的国家/地区

1. 进入「Security」→「WAF」→「Firewall rules」
2. 创建新规则：
   - Field: Country
   - Operator: is in
   - Value: CN（或者你想要允许的国家）
   - Action: Allow

### 阻止恶意请求

1. 进入「Security」→「Bots」
2. 启用「Bot Fight Mode」

## 验证配置

### 检查 DNS 解析

在本地终端运行：
```bash
nslookup your-domain.com
```

应该返回 Cloudflare 的 IP 地址，而不是你真实的服务器 IP。

### 检查 SSL 证书

访问 https://your-domain.com，确认：
- 浏览器显示安全锁图标
- 证书由 Cloudflare 签发

## 注意事项

### 端口限制

Cloudflare 只代理以下端口：
- HTTP: 80, 8080, 8880, 2052, 2082, 2086, 2095
- HTTPS: 443, 2053, 2083, 2087, 2096, 8443

我们使用 443 端口，这个是支持的（Trojan/V2Ray/订阅访问）。
即便 8443 在列表中，Xray Reality 也不是标准 HTTPS 流量，Cloudflare 橙云无法代理该协议本身。

### WebSocket 支持

Cloudflare 默认支持 WebSocket，无需额外配置。

### 真实 IP 获取

在 Nginx 或其他服务中，可以通过 `CF-Connecting-IP` 头获取真实客户端 IP。

### 缓存问题

如果修改了服务器内容但没有生效：
1. 进入「Caching」→「Configuration」
2. 点击「Purge Everything」

## 故障排查

### 502 Bad Gateway

- 检查服务器是否正常运行
- 确认防火墙允许 Cloudflare IP
- 检查 SSL 证书是否有效

### 无法访问网站

- 确认 DNS 已生效（等待最多 24 小时）
- 检查 Cloudflare 代理状态是否为「Proxied」
- 查看 Cloudflare 「Analytics」页面了解更多信息

### 速度慢

- 尝试切换 Cloudflare 数据中心
- 检查服务器与 Cloudflare 之间的连接速度
- 启用 Cloudflare 的优化功能
