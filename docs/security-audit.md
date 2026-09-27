# EasyNet 安全审计报告

> **最后更新**: 2026-09-27
> **审计范围**: 协议实现（Reality / Hysteria2 / Shadowsocks 2022 / AmneziaWG）、Edge Gateway、
> 防火墙、系统加固、订阅分发、供应链
> **审计方式**: 静态代码审计 + 测试 VPS 运行时取证 + 2025–2026 最新公开研究对照
> **漏洞报告**: 参见项目根目录 [SECURITY.md](../SECURITY.md)

---

## 一、结论摘要

**抗 DPI 判定（核心问题）：当前实现可以有效对抗已知的防火墙探测，但有 3 处已知短板。**

| 协议 | 抗 DPI 判定 | 说明 |
|---|:--:|---|
| **Xray+Reality（自偷 + vision）** | ✅ **强** | 可对抗 2026-09 公开的「SNI→DNS 一致性检查」（nDPI `NDPI_UNRESOLVED_HOSTNAME`） |
| **Hysteria2（salamander + 端口跳跃）** | ✅ **强** | 可对抗 QUIC/SI 过滤与 QUIC 指纹（中/俄均已部署 QUIC SNI 过滤） |
| **AmneziaWG** | ⚠️ **中** | 消除标准 WireGuard 的 UDP 指纹；但无统一分享格式、生态窄 |
| **Shadowsocks 2022** | ⚠️ **弱（仅作兜底）** | 协议本身无传输层伪装，被动 DPI 可识别；**不应作为主力** |

**服务安全判定：存在 2 个高危、3 个中危问题，均可修复（部分已在本轮修复）。**

| 严重性 | 问题 | 状态 |
|:--:|---|---|
| 🔴 P0 | **Shadowsocks PSK 双重泄露**：`-k` 出现在命令行（`/proc/*/cmdline` 任何本地用户可读）+ `config.json` 权限 644 | ✅ 本轮修复 |
| 🔴 P0 | **SSH 允许 root 密码登录且无 fail2ban** | ✅ 已解决：fail2ban（自动） + `scripts/security/harden_ssh.sh`（显式、带回滚看门狗） |
| 🟠 P1 | **订阅直连路径默认开启**（`/sub`、`/clash`、`/singbox` 无认证）→ 随机路径保护被绕过 | ✅ 已解决：默认仅随机路径 + 可用 `EASYNET_SUBSCRIPTION_PATH_PREFIX` 固定 |
| 🟠 P1 | `CapabilityBoundingSet=~` 实际语义是「授予全部能力」（应为空集） | ✅ 本轮修复 |
| 🟠 P1 | Xray / Hysteria2 服务缺少 systemd 沙箱（`ProtectSystem`/`ProtectHome`/`PrivateTmp`） | ✅ 本轮修复 |

---

## 二、行业动态对照（2025–2026）

审计以以下最新公开研究为判据：

| 时间 | 研究 / 事件 | 对 EasyNet 的影响 |
|---|---|---|
| 2026-09-25 | **REALITY 与 SNI→DNS 一致性检查**（net4people #668）：审查者记录 `(SNI, 目的IP)` 后解析 SNI，不一致即判定可疑 | 直接否定了「借同网段邻居站」的做法 → 必须**自偷**（自有域名 + 本机回退） |
| 2026-08-21 | **Geedge（TSG 防火墙）源码泄露分析**（USENIX Security '26，net4people #653） | 确认商用 DPI 具备完整 TLS/QUIC 解析、SNI 提取、流量分类与自动封禁能力；**协议伪装必须做到「与真实流量无法区分」** |
| 2026-08-25 | **QUIC SNI 过滤**（FOCI 2026，net4people #654）：俄罗斯 TSPU 最早 2023-07 部署，中国 2024-04 | Hysteria2 依赖 `obfs salamander` 抵御；未开混淆的 QUIC 代理会被 SNI 直接识别 |
| 2025-10 | **nDPI 实现 `NDPI_UNRESOLVED_HOSTNAME`**（ntop） | 把 SNI→DNS 检查产品化并「自动加入黑名单」，成本「有限」 |
| 2026 | 审查能力趋势：TLS-in-TLS 检测、流量熵/指纹分类、协议多样性启发式 | 强化了「Reality 自偷 + Hysteria2 混淆 + 避免裸露 SS」的方向 |

**结论**：审查已从「按协议端口/特征封」演进到「**按与真实流量的可区分性打分**」。
EasyNet 当前的 Reality 自偷与 Hysteria2 salamander 正是针对这一代检测，方向正确。

---

## 三、协议抗 DPI 逐项判定

### 3.1 Xray+Reality —— ✅ 强（当前最优）

运行取证（测试 VPS）：

```
network=tcp, security=reality, flow=xtls-rprx-vision
dest=127.0.0.1:443          ← 自偷：回退到本机 Edge
serverNames=["<自有域名>"]   ← SNI 解析到的就是本机 → 通过 SNI→DNS 一致性检查
fingerprint=chrome, maxTimeDiff=1800000ms, shortIds=[16 hex]
Xray 26.3.27（捆绑 uTLS v1.8.x，Chrome profile 含 X25519MLKEM768 后量子曲线）
```

| 检测向量 | 判定 | 依据 |
|---|:--:|---|
| SNI→DNS 一致性（#668） | ✅ 通过 | 自偷模式：SNI 属于自有域名且解析到本机 |
| 主动探测（probe 到端口） | ✅ 免疫 | REALITY 证书来自真实站点，无认证握手回落到真实站点 |
| TLS 指纹（uTLS/Chrome） | ✅ 良好 | `fp=chrome` + uTLS ≥v1.8.x，含 Padding / ECH-GREASE / ML-KEM |
| TLS-in-TLS 特征 | ✅ 良好 | `xtls-rprx-vision` 消除外层 TLS 记录长度特征 |
| 端口异常 | ⚠️ 注意 | 默认 8443 属常见替代端口；实测高端口更稳，但需客户端配合 |

遗留可选项（非缺陷）：未启用 **Finalmask**（Xray 26.3+ 的 `fragment`/`noise`/`sudoku`）。
在与 Reality 组合时收益有限，但可作为「已部署 Reality 被针对性检测」时的应急手段。

### 3.2 Hysteria2 —— ✅ 强

```
listen: :443 (UDP)   TLS 1.3 (Edge 证书)
obfs: salamander（随机密钥，每次部署生成并持久化）
portHopping: 20000-30000 / 30s
masquerade: proxy → https://www.bing.com/ (rewriteHost)
```

| 检测向量 | 判定 | 依据 |
|---|:--:|---|
| QUIC SNI 过滤（#654） | ✅ 缓解 | salamander 混淆使 QUIC 首包不再是明文 SNI 结构 |
| QUIC 版本/参数指纹 | ✅ 缓解 | 混淆后不暴露标准 quic-go 指纹 |
| UDP 端口固定被针对 | ✅ 缓解 | 端口跳跃把流量摊到 10001 个端口 |
| 主动探测 | ⚠️ 中 | masquerade 用 `proxy` 模式回源 bing；相比静态站点更像「真站点」，但仍是代理语义 |

### 3.3 AmneziaWG —— ⚠️ 中

```
awg-quick@wg0, MTU(客户端)=1280, Jc/Jmin/Jmax/S1/S2/H1-H4 随机并持久化
```

- ✅ 消除了标准 WireGuard 固定首包长度/类型的 UDP 指纹（AWG 的初衷）；
- ⚠️ 生态窄：sing-box 不支持；无统一分享 URI 标准（本项目用 Shadowrocket 格式 `obfs/obfsParam` + 独立参数双写）；
- ⚠️ 仍属「非标准协议」，审查者若对 UDP 做通用熵/行为分析，可区分于常见 UDP 服务；
- ⚠️ Xray 官方文档亦明确警告「WireGuard 不用于翻墙、特征明显易被封锁」。

**定位**：可用作**备用通道**，不应作为对高审查目标的唯一入口。

### 3.4 Shadowsocks 2022 —— ⚠️ 弱（兜底）

- ✅ 加密与重放防护强（`2022-blake3-aes-256-gcm`，含完整重放保护）；
- ❌ **无传输层伪装**：SS 的流量形态（高熵、固定长度特征、无证书）可被被动 DPI 分类；
- ❌ 仅靠随机端口（8388）无助于隐藏。

**定位**：兼容性兜底（几乎所有客户端都支持），**不应作为抗 DPI 主力**。
文档中已按 `MODULE_SECURITY_RANK=40` 排在第 3 位，与实际判定一致。

---

## 四、服务安全发现（本轮已修复项）

### 4.1 🔴 P0 — Shadowsocks PSK 双重泄露（已修复）

**问题**（运行时取证）：

```
$ tr '\0' ' ' < /proc/<ssserver-pid>/cmdline
ssserver -U --encrypt-method 2022-blake3-aes-256-gcm --server-addr 0.0.0.0:8388 -k <PSK明 文>
$ ls -l /etc/shadowsocks-rust/config.json
-rw-r--r-- 1 root root      ← 世界可读，内容含同一 PSK
```

任一本地用户即可读取 PSK（`/proc/<pid>/cmdline` 与 world-readable 配置各一份）。
且 `--config` 实际**未被使用**——此前注释所称「1.24.0 必须传 CLI 参数」经实测为误。

**修复**：
- 服务改为 `ssserver --config /etc/shadowsocks-rust/config.json`（实测 TCP+UDP 均正常监听）；
- 配置写入 `"mode": "tcp_and_udp"`，权限 `640 root:nogroup`（仅服务用户 `nobody` 可读）；
- 命令行不再出现任何密钥。

### 4.2 🟠 P1 — `CapabilityBoundingSet=~` 语义错误（已修复）

运行时取证显示 ssserver 的 `CapBnd=000001ffffffffff`（**全部能力**）：

```
CapabilityBoundingSet=~      ← systemd 语义：对空列表取反 = 授予全部
```

**修复**：改为 `CapabilityBoundingSet=`（空集，丢弃全部能力）。

### 4.3 🟠 P1 — 缺少 systemd 沙箱（已修复）

| 服务 | 修复前 | 修复后（加固项） |
|---|---|---|
| `xray` | 无 `ProtectSystem`/`ProtectHome`/`PrivateTmp` | 追加 `ProtectSystem=strict`(读) / `ProtectHome=yes` / `PrivateTmp=yes` / `ProtectKernelTunables=yes` 等 |
| `hysteria-server` | 同上 | 同上（保留 `CAP_NET_ADMIN`/`CAP_NET_BIND_SERVICE`） |
| `shadowsocks-rust-server` | `ProtectSystem=full` ✅，能力集错误 | 修正能力集 + `ProtectSystem=strict` |

采用 **systemd drop-in**（`/etc/systemd/system/<unit>.d/easynet-hardening.conf`），
不覆盖上游安装脚本生成的主 unit，升级友好。

---

## 五、稳定性与供应链

### 5.1 稳定性

| 项 | 状态 |
|---|:--:|
| 配置幂等渲染（内容不变则跳过重启） | ✅ |
| 各协议独立进程/服务（故障隔离） | ✅ |
| 服务 `Restart=on-failure` | ✅ |
| 每日定时重启（`cron.sh` 按 metadata 生成） | ✅ |
| journald 日志上限（500M） | ✅ |
| 部署失败回滚 | ⚠️ 部分（配置文件先写临时文件再替换） |
| 运行状态监控 / 告警 | ❌ 无（无外部心跳；建议后续加） |

### 5.2 供应链

| 组件 | 版本固定 | 完整性校验 |
|---|:--:|:--:|
| Xray-core | ✅ `EASYNET_XRAY_VERSION`（默认 26.3.27） | ⚠️ SHA256 可选、默认跳过 |
| shadowsocks-rust | ✅ `v1.24.0` | ⚠️ SHA256 可选、默认跳过 |
| hysteria2 | ❌ `get.hy2.sh` 取最新 | ⚠️ 可选 |
| AmneziaWG | ❌ `ppa:amnezia/ppa` | —— |
| acme.sh | ❌ `get.acme.sh` | ⚠️ 可选 |
| 无 `curl \| bash`（先落地→校验→执行） | ✅ | ✅ |

**建议**：把 SHA256 校验列为一等公民（提供 `scripts/security-pins.sh` 或 release 附
`checksums.txt`），并在 CI 中对默认版本 pin 做「是否落后于上游最新」的提醒。

---

## 六、待决策 / 未修复项（按风险）

| 优先级 | 问题 | 风险 | 建议 |
|:--:|---|---|---|
| ✅ 已解决 | **SSH：`PermitRootLogin yes` + `PasswordAuthentication yes`，无 fail2ban** | 暴力破解 → 服务器沦陷 | 自动：fail2ban（`mode=normal` + 部署者 IP 白名单）。显式：`bash scripts/security/harden_ssh.sh check\|apply\|confirm\|revert`——公钥存在性预检 + `sshd -t` 校验 + **10 分钟自动回滚**，实测无锁死。**不参与 `deploy.sh`** |
| ✅ 已解决 | **订阅直连路径默认开启** → 任何人访问 `https://<域名>/sub` 即可拿到全部凭据 | 凭据泄露 | 默认改为 `false`（仅随机路径）；`EASYNET_SUBSCRIPTION_PATH_PREFIX` 可固定路径，重装后客户端无感 |
| 🟡 P2 | 订阅仅单层「128 位随机路径」保护 | 路径泄露即凭据泄露 | 可选 Basic Auth / 一次性 token |
| 🟡 P2 | WireGuard 私钥写入客户端 URI | 分享链接=私钥 | 协议约定，保留但已在部署时告警 |
| 🟡 P3 | Xray 版本 pin 落后上游 6 个月（26.3.27 vs 26.9.9） | 缺后续修复 | 评审后跟进升级（保持 pin 策略） |
| 🟡 P3 | Reality 未启用 Finalmask | 应对针对性检测的余量不足 | 作为应急开关（`EASYNET_REALITY_FINALMASK`）预留 |
| 🟡 P3 | 无运行监控/告警 | 故障不可知 | 后续加轻量心跳 |

---

## 七、修复与验证清单（本轮）

| 修复 | 文件 | 验证 |
|---|---|---|
| SS 不再在命令行暴露 PSK；配置 640 | `scripts/protocols/shadowsocks/deploy.sh` | 单测 + 运行时 `/proc` 复核 |
| `CapabilityBoundingSet` 修正为空集 | `scripts/protocols/shadowsocks/deploy.sh` | 运行时 `CapBnd=0` |
| Xray/Hysteria2 沙箱 drop-in | `scripts/protocols/{xray-reality,hysteria2}/deploy.sh` | 服务 active + `systemctl show` |
| fail2ban（sshd jail） | `scripts/core/maintenance.sh` + `deploy.sh` | `fail2ban-client status sshd` |
| 本文档 | `docs/security-audit.md` | —— |

---

## 八、核查依据

- net4people/bbs #668（2026-09-25）REALITY 与 SNI→DNS 一致性检查；
  ntop nDPI `NDPI_UNRESOLVED_HOSTNAME`（2025-10）。
- net4people/bbs #653（2026-08-21）Geedge TSG 防火墙源码分析（USENIX Security '26）。
- net4people/bbs #654（2026-08-25）QUIC SNI 过滤时间线（FOCI 2026）。
- Xray-core v26.3.27 / v26.9.9 发行说明；uTLS v1.8.x（Chrome profile 含 `X25519MLKEM768`）。
- sing-box v1.14.2 / Xray-core v26.9.9 配置文档与源码（见 `docs/unified-backend-analysis.md`）。
- 测试 VPS 运行时取证（2026-09-27）：`systemctl show`、`/proc/<pid>/status`、`ss -lntup`、
  `ufw status verbose`、`sshd -T`、配置文件权限。


---

## 九、第二轮修复落实（2026-09-27）

| 项 | 实现 | 验证 |
|---|---|---|
| **P0 SSH 加固** | 新增 `scripts/security/harden_ssh.sh`（`check`/`apply`/`confirm`/`revert`/`status`），drop-in 命名为 `10-` 以排在 `50-cloud-init.conf` 之前（sshd「首个值生效」）；apply 前校验公钥存在性 + 当前会话为 publickey，apply 后 `sshd -t` 校验并武装 10 分钟自动回滚 | 体检→apply→新连接仍可登录→confirm；**自动回滚实测**（20s 延迟不 confirm 后自动恢复默认，全程可登录）；重复 apply 为 no-op |
| **P1 订阅直连路径默认关闭** | `EASYNET_SUBSCRIPTION_DIRECT_PATHS` 默认 `true` → `false`；新增 `EASYNET_SUBSCRIPTION_PATH_PREFIX` 校验（拒绝空白/?/#/&，过短告警） | `/sub` 不再返回节点（0 条），随机路径 200/4 节点 |
| **P2 重部署零中断** | hysteria2 / shadowsocks / awg-quick 增加「渲染→比对→不变则跳过重启」；xray 仅在沙箱变化或未运行时重启；nginx 全链路 `reload`；**证书续期 hook 增加指纹比对**（acme 每次部署都会跑 `--install-cert`，此前每次都重启全部服务）；AWG 的「旧版迁移」不再误删在用接口 | 连续两次部署后 **5 个服务 `ActiveEnterTimestamp` 完全不变** |
| **P3 规则集缺失提示** | `generate_subscription.sh` 检测 `rules/manifest.json` 缺失并给出修复命令 | 实测输出完整告警 |
