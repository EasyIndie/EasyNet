# EasyNet 故障排查指南

## 先按这个顺序查

遇到“部署失败”或“客户端连不上”时，优先执行这 5 步：

1. 查服务状态：`systemctl status <服务名>`
2. 查日志：`journalctl -u <服务名> -n 50 --no-pager`
3. 查端口监听：`netstat -tlnp` 或 `netstat -ulnp`
4. 查防火墙：`ufw status`
5. 查协议是否导入正确：订阅、单节点、WireGuard 配置文件不要混用

常见服务名：
- `xray`
- `hysteria-server.service`
- `trojan-go`
- `v2ray`
- `shadowsocks-libev-server`
- `wg-quick@wg0`

## 最常见问题

### Edge 证书申请失败

现象：
- `acme.sh` 提示 80 端口被占用

处理：
- 先停掉占用 80 端口的服务
- 确认域名 A 记录已经解析到当前服务器
- 确认云厂商安全组和服务器防火墙放行 `80/tcp`

### Trojan-Go 或 V2Ray 能连通但打不开网页

现象：
- 连通性测试通过，但网页打不开

处理：
- 检查域名、SNI、WebSocket 路径是否为订阅或部署输出值
- 检查 Edge Gateway 路由状态目录 `/var/lib/easynet/exposure/edge/routes`
- 查看 `journalctl -u trojan-go -n 50`

### Hysteria2 服务正常但无法代理流量

现象：
- `hysteria-server.service` 已启动，但客户端无法通过 Hysteria2 上网

处理：
- 确认云厂商安全组和服务器防火墙放行 `443/udp`
- 确认客户端导入的是最新订阅或部署输出中的 Hysteria2 节点
- 检查 Edge 证书文件 `/etc/ssl/easynet-edge/fullchain.crt` 与 `/etc/ssl/easynet-edge/private.key` 是否存在
- 查看 `journalctl -u hysteria-server.service -n 50`

### Shadowsocks 连不上

现象：
- 服务运行中，但客户端超时

处理：
- 确认服务监听在 `0.0.0.0`，不要只绑定 `127.0.0.1`
- 停用系统默认 `shadowsocks-libev` 服务，避免端口冲突

### WireGuard 无握手

现象：
- `wg show` 看不到 `latest handshake`

处理：
- 确认 UDP 端口已放行
- 确认服务端已重载最新配置
- 检查客户端导入的是否为最新 `client1.conf`

### WireGuard 有握手但不能上网

现象：
- `wg show` 有握手，但外网不通

处理：
- 检查转发与 NAT 规则
- 检查主网卡名称是否正确
- 检查 `AllowedIPs` 与服务器路由设置

### 扫码后只有一个节点或订阅没出现

原因：
- 扫到了单节点二维码，而不是订阅二维码

处理：
- 批量导入使用订阅二维码或订阅链接
- 单独调试才使用 `trojan://`、`vmess://`、`vless://`、`wg://`

### Clash Verge Rev 无法导入订阅

原因：
- 导入了 URI 订阅 `sub`，而不是 Clash/Mihomo 订阅 `clash`

处理：
- Clash Verge Rev 使用部署输出或 `./scripts/show_subscription.sh` 显示的 Clash/Mihomo 订阅

## 快速判断是否是客户端问题

- 换一个客户端再次导入
- 优先用订阅导入，不要手动抄参数
- WireGuard 独立使用时优先导入 `client1.conf`
- Reality 手动导入时重点检查 `SNI`、`PublicKey`、`ShortID`

## 还不行时

至少收集下面这些信息再排查：

```bash
systemctl status trojan-go
journalctl -u trojan-go -n 50 --no-pager
systemctl status wg-quick@wg0
wg show
ufw status
```
