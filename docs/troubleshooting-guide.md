# EasyNet 故障排查指南

## 先按这个顺序查

遇到"部署失败"或"客户端连不上"时，按顺序执行以下检查：

1. **服务状态**：`systemctl status <服务名> --no-pager`
2. **日志**：`journalctl -u <服务名> -n 50 --no-pager -l`
3. **端口监听**：`ss -ltnup`
4. **防火墙**：`ufw status verbose`
5. **订阅**：重新导入最新订阅，避免混用旧配置
6. **链路可达性**：服务都正常但客户端连不上时，先排除「VPS 公网 IP 被 GFW/运营商拦截」——见下文《服务器 IP 被 GFW/运营商拦截》

服务名（按安全等级降序）：`xray` → `hysteria-server.service` → `shadowsocks-rust-server` → `awg-quick@wg0`

## 服务器 IP 被 GFW/运营商拦截（服务正常但客户端连不上）

> ⚠️ VPS 提供商创建实例时分配的公网 IP **可能已被 GFW 或运营商拉黑**。这是环境问题，不是 EasyNet 配置问题；IP 级封锁下任何协议都建不起 TCP/UDP 握手，重装 EasyNet 无效。

### 现象

- VPS 上 `nginx` / `xray` / `hysteria-server.service` 都是 `active`，服务器本机 `curl` 订阅正常；
- 客户端（手机/电脑）打不开订阅链接，也连不上任何节点（超时）；
- 用第三方多地探测（如 check-host.net）却返回 200；
- 关掉客户端代理后在浏览器直接打开 `https://<域名>/sub` 也超时。

### 典型原因

- 提供商分配的 IP 被 GFW/运营商列入黑名单，**回程（服务器→大陆）丢包**；
- 表现为：客户端 SYN 到达服务器、服务器回了 SYN-ACK，但客户端收不到，于是反复重传 SYN，TCP 三次握手永远完不成。

### 自动化诊断

在 VPS 上运行：

```bash
bash scripts/diagnose_reachability.sh
```

脚本会自动检查本机服务/监听端口，并通过 check-host.net 从多地探测公网可达性。

若要**确诊回程丢包**，先在客户端拿到公网 IP（浏览器搜索“我的 IP”或在服务器 `who` 里看 SSH 来源），然后：

```bash
EASYNET_DIAG_CLIENT_IP=<客户端公网IP> bash scripts/diagnose_reachability.sh
# 脚本会开一个抓包窗口（默认 60s）：请在窗口内从客户端尝试连接 TCP 443/8443 或打开订阅链接
```

可用环境变量：`EASYNET_DOMAIN`（全局 HTTP 探测）、`EASYNET_DIAG_CAPTURE_SECONDS`（抓包窗口，默认 60）、`EASYNET_DIAG_SKIP_GLOBAL=1`（跳过外部探测）。

### 判定与处理

| 抓包结果 | 结论 | 处理 |
|---------|------|------|
| 捕获到客户端 ACK | 链路可达 | 握手完成，转查协议/客户端配置 |
| 有客户端 SYN + 服务器 SYN-ACK、无 ACK 且 SYN 反复重传 | **回程被拦（GFW/运营商）** | 更换公网 IP 或更换机房/线路 |
| 只有客户端 SYN、无 SYN-ACK | 服务器未回应 | 查服务监听与服务器/云防火墙（非墙问题） |
| 完全没有 SYN | 客户端未发起或去程被拦 | 查客户端是否真在连接、本地网络限制 |

处理建议：

- **更换 VPS 公网 IP**：多数提供商支持更换/重建实例拿到新 IP；创建后先用 `nc -vz <新IP> 22` 从客户端直连验证；
- **更换地区/线路**：对国内运营商友好的线路通常比同地区换 IP 更稳；
- 拿到可用 IP 后重新部署（`EASYNET_DOMAIN=<域名> bash install.sh`），并更新订阅；
- 域名 A 记录变更后 TTL 通常 300s，客户端如仍解析旧 IP，切换飞行模式/重开 App 或刷新本机 DNS 缓存（macOS：`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`）。

## 通用问题

### 客户端订阅更新超时

现象：
- 手机/电脑上更新订阅提示超时，但服务器上本机访问订阅正常

处理：
- 先确认客户端**没有用代理去更新订阅**（Shadowrocket：先断开 VPN，或把“全局路由”设为直连，再更新；否则会“用坏节点拉订阅”形成死循环）
- 用浏览器直接打开 `https://<域名>/sub`：若同样超时，大概率是 IP 被墙，见《服务器 IP 被 GFW/运营商拦截》
- 若域名刚换过 IP，刷新客户端 DNS（切飞行模式/重开 App）；macOS 可执行 `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`

### Edge 证书申请失败

现象：
- `acme.sh` 提示 80 端口被占用或证书签发失败

处理：
- 确认域名 A 记录已经解析到当前服务器
- 确认云安全组和服务器防火墙放行 `80/tcp`
- 停掉占用 80 端口的服务后重新部署

### Edge 证书续期后协议异常

现象：
- Edge 证书刚续期，Hysteria2 开始异常

处理：
- 手动执行续期 hook：`./scripts/exposure/edge/cert_renew_hook.sh`
- 检查证书到期时间：`openssl x509 -in /etc/ssl/easynet-edge/fullchain.crt -noout -enddate`
- 检查证书权限：`ls -l /etc/ssl/easynet-edge`
- 查看日志：`journalctl -u hysteria-server.service -n 100 --no-pager -l`

### 订阅没出现或扫码后只有一个节点

原因：
- 扫到了单节点二维码，而不是订阅二维码
- Edge Gateway 还没有成功写入订阅入口状态

处理：
- 使用 `./scripts/show_subscription.sh` 重新显示订阅链接和二维码
- 检查 `/var/lib/easynet/exposure/edge/subscription_path_prefix.txt`
- Clash Verge Rev 使用 `clash` 订阅，Shadowrocket / v2rayN / v2rayNG 使用 `sub` 订阅
- Raspberry Pi / 卡片机上的 sing-box 使用 `singbox` 配置

## 协议问题

### Xray+Reality 连不上

现象：
- 客户端超时或 Reality 握手失败

处理：
- 检查 `systemctl status xray --no-pager`
- 检查 `journalctl -u xray -n 50 --no-pager -l`
- 确认客户端 `SNI`、`PublicKey`、`ShortID`、`UUID` 与部署输出一致
- 确认服务器和云安全组放行 Reality 端口，默认 `8443/tcp`

### Hysteria2 服务启动失败

现象：
- `hysteria-server.service` 为 `failed`
- 日志出现 `failed to read server config` 或 `permission denied`

处理：
- 检查配置权限：`ls -l /etc/hysteria/config.yaml /etc/hysteria/easynet.env`
- 检查服务用户：`systemctl cat hysteria-server.service | grep '^User='`
- 重新执行最新部署脚本，让脚本按 systemd 用户修正配置和证书权限
- 查看完整日志：`journalctl -u hysteria-server.service -n 100 --no-pager -l`

### Hysteria2 能连接但无法代理流量

现象：
- 客户端显示已连接，但网页打不开或无流量

处理：
- 确认 Hysteria2 正在监听：`ss -lunp | grep ':443'`
- 确认云安全组和服务器防火墙放行 `443/udp`
- 确认客户端导入的是最新订阅或部署输出中的 Hysteria2 节点
- 检查 Edge 证书文件 `/etc/ssl/easynet-edge/fullchain.crt` 与 `/etc/ssl/easynet-edge/private.key`
- 测试服务器出口：`curl -4 https://www.gstatic.com/generate_204 -I`
- 查看日志：`journalctl -u hysteria-server.service -n 100 --no-pager -l`

### Shadowsocks 连不上

现象：
- 服务运行中，但客户端超时

处理：
- 确认客户端支持 Shadowsocks 2022 Edition 加密（`2022-blake3-aes-256-gcm`）
- 旧客户端（如老版本 Shadowrocket）可能不支持 2022 cipher，需更新客户端版本
- 确认服务监听在 `0.0.0.0`
- 确认服务器和云安全组放行 Shadowsocks 端口，默认 `8388/tcp` 和 `8388/udp`
- 查看日志：`journalctl -u shadowsocks-rust-server -n 50 --no-pager -l`

### WireGuard/AmneziaWG 无握手

现象：
- `awg show` 看不到 `latest handshake`

处理：
- 确认 UDP 端口已放行，默认 `51820/udp`
- 确认服务端已重载最新配置：`systemctl restart awg-quick@wg0`
- 检查客户端导入的是最新 `client1.conf`（含 AmneziaWG 参数）

### WireGuard 有握手但不能上网

现象：
- `wg show` 有握手，但外网不通

处理：
- 检查转发：`sysctl net.ipv4.ip_forward`
- 检查 NAT 规则：`iptables -t nat -S`
- 检查主网卡名称和 `AllowedIPs`

### AmneziaWG 客户端不支持 / 参数不匹配

现象：
- 服务端为 AmneziaWG，但客户端用标准 WireGuard 或未携带混淆参数，一直无握手

处理：
- 服务端已固定使用 AmneziaWG（`/etc/amnezia/amneziawg/wg0.conf`），**不再提供纯 WireGuard**
- 客户端需支持 AmneziaWG（Clash Verge Rev (mihomo ≥1.19) / Shadowrocket）；**sing-box 暂不支持 AmneziaWG**
- 确认 Jc/Jmin/Jmax/S1/S2/H1-H4 与服务端一致（订阅会自动携带；手动配置需与服务端 `wg0.conf` 对齐）
- Clash Verge Rev / Mihomo 通过订阅导入会自动写入 `amnezia-wg-option`

### Hysteria2 启用 Port Hopping 后连接失败

现象：
- 启用端口跳变后客户端无法连接

处理：
- 确认云安全组和服务器防火墙已放行整个跳变端口范围（如 `20000:30000/udp`）
- 查看 Hysteria2 日志：`journalctl -u hysteria-server.service -n 100 --no-pager -l`
- 确认客户端配置中包含 `port_hopping` 参数（通过订阅导入自动包含）
- 如客户端不支持 Port Hopping，关闭 `EASYNET_HYSTERIA2_PORT_HOPPING` 重新部署
- 跳变到某个端口后断流：99% 是**云厂商安全组**没放行整个 UDP 范围（本机 `ufw status` 应能看到该范围，
  `nft list ruleset | grep redirect` 应能看到 `udp dport <范围> redirect to :<基础端口>`）

### Xray XHTTP 模式下连接异常

现象：
- `EASYNET_REALITY_TRANSPORT=xhttp` 部署后客户端无法连接

处理：
- 确认客户端支持 XHTTP/HTTP3 传输（需 Clash Verge Rev ≥1.7 或 sing-box ≥1.11）
- 查看 Xray 日志：`journalctl -u xray -n 100 --no-pager -l`
- 检查 Xray 配置中 xhttpSettings：`jq '.inbounds[0].streamSettings.xhttpSettings' /usr/local/etc/xray/config.json`
- 如客户端版本不兼容，切回 TCP：取消设置 `EASYNET_REALITY_TRANSPORT` 重新部署

## 快速判断是否是客户端问题

- 换一个客户端重新导入订阅（如 Clash Verge Rev 不行可换 Mihomo）
- 优先用订阅导入，不要手动抄参数
- Reality 手动导入时重点检查 `SNI`、`PublicKey`、`ShortID`；XHTTP 模式还需检查 `type=xhttp`
- Hysteria2 手动导入时重点检查 `password`、`obfs-password`、`SNI`；Port Hopping 时检查端口范围
- WireGuard 独立使用时优先导入 `client1.conf`；AmneziaWG 模式注意 `jc`/`jmin`/`jmax` 参数

## 还不行时

至少收集下面这些信息再排查：

```bash
systemctl status xray --no-pager
systemctl status hysteria-server.service --no-pager
systemctl status shadowsocks-rust-server --no-pager
systemctl status awg-quick@wg0 --no-pager
journalctl -u hysteria-server.service -n 100 --no-pager -l
journalctl -u xray -n 50 --no-pager -l
journalctl -u shadowsocks-rust-server -n 50 --no-pager -l
ss -ltnup
wg show
ufw status verbose
jq '.inbounds[0].streamSettings.network' /usr/local/etc/xray/config.json
```
