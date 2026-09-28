# VPS 运行时安全审计 Runbook

> 配套脚本：`scripts/audit_runtime.sh`（只读取证，不修改系统）

## 何时运行

| 场景 | 说明 |
|---|---|
| **发版前验收** | release 前在测试 VPS 跑一遍，确认无 [失败] 项 |
| **变更后回归** | 改过 deploy/协议/Edge 后跑一遍，确认没有引入回归 |
| **定期巡检** | 建议并入监控 cron（`audit_runtime.sh` 退出码非零即告警） |
| **新 VPS 上架** | 部署完成后立即跑一遍建立基线 |

## 用法

```bash
sudo bash /opt/easynet/scripts/audit_runtime.sh
```

- 退出码 `0` = 体检通过；`1` = 存在 [失败] 项。
- 报告中的订阅路径前缀会脱敏为 `/s/....xxxx`。
- 全程只读：不改文件、不重启服务、不动防火墙。

## 检查项清单

| 类别 | 检查内容 |
|---|---|
| 系统概览 | 发行版/内核、公网 IP、内存、负载 |
| 服务状态 | xray / hysteria / shadowsocks / awg / nginx / fail2ban 是否 active |
| 二进制版本 | 与 `scripts/core/pins.sh` 的 pin 对照（便于发现漂移） |
| 敏感文件权限 | 状态树 700、前缀 600、协议配置 600/640（拒绝 world-readable） |
| 进程命令行 | `/proc/<pid>/cmdline` 无 `-k`/`password`/`psk` 密钥泄漏 |
| systemd 沙箱 | `ProtectSystem=strict`、`NoNewPrivileges=yes`、能力集精确 |
| 端口与防火墙 | 对外监听端口 ↔ UFW 规则一一对应（跳过临时/loopback 端口） |
| TLS | 1.0/1.1 拒绝、1.2/1.3 可用；安全头恰好一次；`Server` 无版本 |
| 订阅路径 | 直连 `/sub` 404、随机路径 200 |
| SSH | `PasswordAuthentication no`、`PermitRootLogin prohibit-password` |
| fail2ban | sshd jail 运行中 + 当前封禁数 |
| cron / journald | 每日重启 + 监控 cron 存在；journald 500M 上限 |
| Reality | 自偷模式（`dest=127.0.0.1:443` + SNI=本域名） |
| 端口跳跃 | hysteria `listen` 含范围 + nftables `redirect to` 已装 + salamander |
| 证书 | Edge 证书 7 天内不会过期 |

## 结果解读

- **通过**：该项符合预期。
- **警告**：非致命，但值得人工看一眼（例如「无监控 cron」在未配置推送渠道时属正常）。
- **失败**：需要处理，且会让退出码非零。

## 手工核对命令（脚本背后的取证依据）

```bash
# 敏感文件权限（应无 world-readable）
find /var/lib/easynet /etc/hysteria /etc/shadowsocks-rust /usr/local/etc/xray -maxdepth 2 -type f | xargs ls -l

# 密钥是否进 cmdline（应无输出）
for p in xray hysteria ssserver; do pid=$(pgrep -x $p | awk 'NR==1'); [ -n "$pid" ] && tr '\0' ' ' < /proc/$pid/cmdline; echo; done

# systemd 沙箱
systemctl show xray hysteria-server | grep -E 'ProtectSystem|NoNewPrivileges|CapabilityBoundingSet'

# 端口 ↔ 防火墙
ss -lntup | grep -vE '127\.|::1'
ufw status verbose

# TLS 版本（1.0/1.1 应 REFUSED）
for v in tls1 tls1_1 tls1_2 tls1_3; do echo | timeout 8 openssl s_client -connect <域名>:443 -$v 2>/dev/null | grep -q 'Protocol' && echo "$v OK"; done

# 订阅路径
curl -s -o /dev/null -w '%{http_code}\n' https://<域名>/sub   # 404
curl -s -o /dev/null -w '%{http_code}\n' "https://<域名><前缀>/sub"   # 200
```

## 注意

- 脚本假定运行在 **Ubuntu/Debian 的 EasyNet VPS** 上（用 GNU `stat -c`、`systemctl`、`nft`）。
- `set -o pipefail` 下**不要**用 `cmd | grep -q`（grep 提前退出会让上游进程收 SIGPIPE，
  整条管道判非零）；脚本里统一用「先捕获到变量、再 `grep <<< "$var"`」规避。
