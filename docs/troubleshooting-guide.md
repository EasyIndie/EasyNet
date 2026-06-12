# EasyNet 故障排查指南

## 先按这个顺序查

遇到"部署失败"或"客户端连不上"时，优先执行这 5 步：

1. 查服务状态：`systemctl status <服务名> --no-pager`
2. 查日志：`journalctl -u <服务名> -n 50 --no-pager -l`
3. 查端口监听：`ss -ltnup`
4. 查防火墙：`ufw status verbose`
5. 重新导入最新订阅，避免混用旧单节点配置

服务名按安全性和抗 DPI 能力从高到低：

- `xray`
- `hysteria-server.service`
- `shadowsocks-libev-server`
- `wg-quick@wg0`

## 通用问题

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
- 确认服务监听在 `0.0.0.0`
- 确认服务器和云安全组放行 Shadowsocks 端口，默认 `8388/tcp` 和 `8388/udp`
- 查看日志：`journalctl -u shadowsocks-libev-server -n 50 --no-pager -l`

### WireGuard 无握手

现象：
- `wg show` 看不到 `latest handshake`

处理：
- 确认 UDP 端口已放行，默认 `51820/udp`
- 确认服务端已重载最新配置：`systemctl restart wg-quick@wg0`
- 检查客户端导入的是最新 `client1.conf`

### WireGuard 有握手但不能上网

现象：
- `wg show` 有握手，但外网不通

处理：
- 检查转发：`sysctl net.ipv4.ip_forward`
- 检查 NAT 规则：`iptables -t nat -S`
- 检查主网卡名称和 `AllowedIPs`

## 快速判断是否是客户端问题

- 换一个客户端重新导入订阅
- 优先用订阅导入，不要手动抄参数
- Reality 手动导入时重点检查 `SNI`、`PublicKey`、`ShortID`
- Hysteria2 手动导入时重点检查 `password`、`obfs-password`、`SNI`
- WireGuard 独立使用时优先导入 `client1.conf`

## 还不行时

至少收集下面这些信息再排查：

```bash
systemctl status xray --no-pager
systemctl status hysteria-server.service --no-pager
systemctl status wg-quick@wg0 --no-pager
journalctl -u hysteria-server.service -n 100 --no-pager -l
journalctl -u xray -n 50 --no-pager -l
ss -ltnup
wg show
ufw status verbose
```
