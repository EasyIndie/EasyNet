# 第三轮全面审计报告（重置后复验 + 历史问题闭环核验）

> **审计日期**: 2026-09-27（第三轮）
> **审计对象**: `b4b9b61` + 本轮修复（本地工作树）
> **环境**: 测试 VPS **重置为全新 Ubuntu 26.04.1** 后从零部署 `compat`（全协议）
> **审计方式**: 静态代码审计（逐条核对历史问题）+ 重置后运行态取证（`systemctl show`、`/proc`、
> `ss`、`ufw`、`openssl`、`setpriv`、`journalctl`）+ 实测（崩溃自恢复、逐协议连通性、吞吐）
> **维度**: 安全性 / 稳定性 / 性能 / 抗 DPI / 客户端体验 / 供应链 / 架构可维护性

---

## 一、结论摘要

**历史问题：已全部闭环或明确接受。** 共核验 31 项，其中修复并实测通过 24 项、按设计保留 4 项、
仍未解决 3 项（供应链 pin 相关，非阻塞）。

| 类别 | 项数 | 状态 |
|---|:--:|---|
| 🔴 高危安全（SS 凭据 / SSH / 能力集 / 沙箱） | 5 | ✅ 全部已修复并运行态复验 |
| 🟠 中危安全（订阅暴露 / 客户端沙箱 / fail2ban 误封） | 3 | ✅ 全部已修复并复验 |
| 🟡 稳定性（重启风暴 / AWG 误删 / 幂等 / 自恢复） | 6 | ✅ 全部已修复并实测 |
| 🟡 抗 DPI 配置 | 4 | ✅ 运行态逐项核对通过 |
| 🟢 架构/代码质量 | 6 | ✅ 已修复 5 / 保留 1（设计决策） |
| ⚠️ 供应链 pin | 3 | ❌ **仍未解决**（Xray 落后 6 个月、SHA256 默认跳过、3 个组件未 pin） |
| 🟢 本轮新发现 | 4 | ✅ 已修复并复验 |

**本轮新发现 4 项（均已修复并实测）**：

| 编号 | 级别 | 问题 | 修复 | 实测 |
|:--:|:--:|---|---|---|
| **N1** | 🟠 P1 | 状态目录 `/var/lib/easynet` 及其下**订阅路径前缀**（保护全部凭据的唯一秘密）为 `755/644`，**任意本地用户可读** | 新增 `easynet_secure_state_dir()`：状态树收敛为 `700`、前缀与生成的路由文件 `600` | `setpriv --reuid=65534` 读取 → Permission denied ✅ |
| **N2** | 📄 文档 | 上轮报告称 Edge「仅 TLS 1.3」，实际为 **TLS 1.2 + 1.3**（1.0/1.1 被拒）——TLS 1.2 是刻意保留以兼容旧客户端 | 更正 `audit-2026-09-27.md` | nginx 配置核对 ✅ |
| **N3** | 🟠 P1 | 伪装页 `/` **重复且冲突的安全头**（上游 bing 透传 + 自身设置 → 两个 `HSTS max-age` 不同、两个 `X-Frame-Options`），违反 RFC 6797，且本身就是指纹特征 | 三个 `location /` 增加 `proxy_hide_header`（HSTS / X-Frame-Options / X-Content-Type-Options） | `HSTS ×1`、`X-Frame-Options ×1` ✅ |
| **N4** | 🟡 P2 | `hysteria-server.service`（上游 unit）**无 `Restart=`** → 崩溃后不会自恢复，只能等每日 cron | 沙箱 drop-in 统一补 `Restart=on-failure` + `RestartSec=5` | `kill -9` 后 **5 秒自动拉起** ✅ |
| **N5** | 🟡 P3 | 客户端 mixed 模式**硬编码 `0.0.0.0:7890`**（公网设备上=开放代理），且绑定 `127.0.0.1` 时仍提示「局域网地址」 | 新增 `--listen-address` / `EASYNET_SINGBOX_LISTEN`（默认不变）、非 loopback 时告警、提示文案随实际绑定地址 | 监听 `127.0.0.1:7890`、更新器保持地址 ✅ |
| **N6** | 🟡 P3 | `Server: nginx/1.28.3 (Ubuntu)` 暴露精确版本与发行版 | Edge 站点 `server_tokens off` | `Server: nginx` ✅ |
| **N7** | 🟡 工具 | lint 只查裸 `$VAR`，**不查 `${VAR}`**（无 `:-` 时同样在 `set -u` 下崩溃）；据此扫出 3 处 | 扩展 lint 规则；修正 `install_singbox_client.sh`、`edge/deploy.sh`、`shadowsocks/deploy.sh` | 362 测试全绿 ✅ |

> 说明：N2 是文档纠错，N7 是审计工具缺陷。真正的**新增代码缺陷为 4 项（N1/N3/N4/N5/N6）**。

---

## 二、历史问题逐条核验（含运行态证据）

### 2.1 🔴 高危安全

| # | 历史问题 | 核验证据（重置后运行态） | 结论 |
|:--:|---|---|:--:|
| 1 | Shadowsocks PSK 出现在命令行（`/proc/*/cmdline`） | `cmdline: /usr/local/bin/ssserver --config /etc/shadowsocks-rust/config.json`，`grep -cE '\-k\|password\|psk'` = **0** | ✅ |
| 2 | `config.json` 权限 644（world-readable） | `640 root:nogroup` | ✅ |
| 3 | `CapabilityBoundingSet=~` 实为「授予全部能力」 | `CapBnd=`（**空集**）；xray/hysteria 仅保留上游声明的 `net_bind_service`/`net_admin`/`net_raw`（功能必需） | ✅ |
| 4 | Xray / Hysteria2 无 systemd 沙箱 | 三者均 `ProtectSystem=strict`、`ProtectHome=yes`、`PrivateTmp=yes`、`RestrictNamespaces=yes`、`NoNewPrivileges=yes` | ✅ |
| 5 | SSH 允许 root 密码登录且无 fail2ban | fail2ban jail `sshd` active（**已在拦真实爆破**：失败 11 / 封禁 2 / 当前封禁 1）；`ignoreip` 含部署者 IP；`harden_ssh.sh` 提供 `check/apply/confirm/revert`，**不参与 deploy**；本机 `apply` → 新连接可登录 → `confirm`；**自动回滚实测**（20s 不 confirm 自动恢复） | ✅ |

> SSH 加固后仍为「显式操作」（重置后回归 cloud-init 默认 `passwordauthentication yes`），符合「危险动作必须显式且可回滚」的既定决策。

### 2.2 🟠 中危安全

| # | 历史问题 | 核验证据 | 结论 |
|:--:|---|---|:--:|
| 6 | 订阅直连路径默认开启（`/sub` 无认证） | 默认 `false`；`/sub` = **404**（回落伪装页），随机路径 = **200** | ✅ |
| 7 | 客户端更新服务被沙箱破坏（`DynamicUser` + `ProtectSystem=full` → 读不到 600 env、写不了 `/etc`） | unit 为 **root** + `ProtectSystem=strict` + `ReadWritePaths=/etc/easynet /etc/sing-box`；`systemctl start` → `Result=success`，日志确认已拉取并应用配置 | ✅ |
| 8 | fail2ban `mode = aggressive` 易误封 | jail 为默认 `normal`（无 `mode=aggressive`）；`ignoreip` 自动写入部署者 IP | ✅ |

### 2.3 🟡 稳定性

| # | 历史问题 | 核验证据 | 结论 |
|:--:|---|---|:--:|
| 9 | 非 Xray 服务重部署时无条件重启 | 连续两次部署后 **5 个服务 `ActiveEnterTimestamp` 完全不变** | ✅ |
| 10 | 证书续期 hook 引发重启风暴 | 按证书 SHA256 指纹比对；日志 `Edge 证书未变化，跳过服务重启` | ✅ |
| 11 | AWG「旧版迁移」每次部署误删在用 `wg0` | 仅当旧 `wg-quick@` 在用时才迁移；重部署后 AWG 未重启、客户端不掉线 | ✅ |
| 12 | nginx `restart` 造成订阅下载中断 | 全链路 `systemctl reload nginx`（deploy.sh 1 处 + edge 2 处） | ✅ |
| 13 | 配置幂等性 | 重部署后 4 协议配置 **md5 完全一致**（UUID/私钥/PSK/AWG 参数全保留） | ✅ |
| 14 | 服务崩溃自恢复 | xray/ss 原本 `on-failure`；**hysteria 上游无 `Restart=`** → 本轮修复为 `on-failure` + `RestartSec=5`；`kill -9` 实测 **5s 自动拉起** | ✅（本轮修复） |

### 2.4 🟡 抗 DPI（运行态逐项核对）

| 协议 | 核验项 | 实测值 | 结论 |
|---|---|---|:--:|
| Reality | 自偷 | `dest=127.0.0.1:443`、`serverNames=["test-world.jokerhub.cn"]`（SNI→DNS 一致） | ✅ |
| Reality | vision / uTLS | `flow=xtls-rprx-vision`、`fingerprint=chrome`、`maxTimeDiff=1800000`、`shortIds=[16 hex]` | ✅ |
| Reality | 回退限速 | `limitFallbackUpload=1 MiB/s`、`limitFallbackDownload=10 MiB/s` | ✅ |
| Hysteria2 | 混淆 / 跳端口 | `obfs: salamander`、`portHopping 20000-30000 / 30s`、`masquerade: proxy` | ✅ |
| AmneziaWG | 真 AWG（非原版 WG） | `awg show`：`jc=8 jmin=8 jmax=80 s1=87 s2=46 h1..h4` 全部非零并持久化 | ✅ |
| Shadowsocks | 加密与传输 | `2022-blake3-aes-256-gcm`、`mode=tcp_and_udp` | ✅ |
| 订阅 | 国家旗帜/参数 | `flag=SG ×4`、`mtu=1280`、`obfs=amneziawg` | ✅ |

### 2.5 🟢 架构 / 代码质量

| # | 历史问题 | 结论 |
|:--:|---|:--:|
| 15 | `discovery_validate_manifest()` 未被调用 | ✅ deploy 前 fail-fast 校验 |
| 16 | `for m in $modules` 未引用（word splitting / pathname expansion） | ✅ **非缺陷**：同行有 `set -f` 显式关闭 glob，空格分隔是刻意设计 |
| 17 | 5×`yaml_escape`、5×`get_public_ip`、6×qrencode 重复 | ✅ 已合并到 `core/subscription_clash.sh` / `core/network.sh` / `core/display.sh` |
| 18 | `deploy.sh` 硬编码 `source routes.sh`、`clients/` 无 manifest | ✅ **按决策保留**（库函数非模块入口；客户端安装器面向端设备） |
| 19 | `test_path_generation.bats` 重定义被测函数 | ✅ 该函数已不存在（重构后测试 source 真实模块） |
| 20 | `$VAR` 紧跟多字节字符导致 bash 把 UTF-8 字节并入变量名 | ✅ 全仓库 23 处改 `${VAR}` + 新增 lint 规则（macOS bash 3.2 实测会崩） |

### 2.6 ⚠️ 供应链（仍未解决）

| # | 问题 | 核验 | 风险 |
|:--:|---|---|---|
| 21 | Xray pin `26.3.27` vs 「上游 26.9.9」 | **前提有误**：Xray 自 26.4.15 起全部标记为 pre-release，`26.3.27` 正是**最新 stable** | ✅ 无需升级；如需 pre-release 需显式评估 |
| 22 | SHA256 校验默认跳过 | 部署日志明确告警 `EASYNET_XRAY_INSTALL_SHA256 未设置，将跳过安装脚本的完整性验证`（**至少是显式告警，不是静默跳过**） | 供应链攻击面 |
| 23 | hysteria2（`get.hy2.sh`）、AmneziaWG（PPA）、acme.sh 未 pin | `amneziawg-tools v3.1.20260812`、`acme.sh v3.1.6` | 上游变更可能破坏部署 |

**已有缓解**：全部下载均经 `run_downloaded_script()`（先落地 → 可选校验 → 再执行），**无 `curl \| bash`**；版本 pin 与告警机制存在，只是默认未开启校验。

---

## 三、运行态指标

### 3.1 安全性

| 项 | 实测值 |
|---|---|
| 敏感文件 world-readable | **0**（`/var/lib/easynet` 700、前缀与路由 600、协议配置 600/640、metadata 600、`.env` 600） |
| 非 root 读取状态目录 | Permission denied（`setpriv --reuid=65534`） |
| TLS | TLS 1.2 + 1.3 可用；**1.0/1.1 被拒**；ECDHE-only 密码套件；Let's Encrypt（`CN=test-world.jokerhub.cn`，有效期至 2026-12-26） |
| 安全响应头 | `HSTS max-age=63072000; includeSubDomains`、`X-Content-Type-Options: nosniff`、`X-Frame-Options: DENY` —— **各恰好 1 次** |
| Server 头 | `nginx`（无版本/发行版） |
| 监听端口 | 22/80/443/8443/tcp、443/8388/51820/udp（与 UFW 放行项一一对应，无多余监听） |
| UFW | `default deny (incoming)`；模块端口按 metadata 自动生成 |
| 未知订阅路径 | 回落伪装页 404（不泄露目录列表、不暴露 web root） |
| fail2ban | `sshd` jail active，bantime 1h / maxretry 5，`ignoreip` 含部署者 IP |

### 3.2 稳定性

| 项 | 实测值 |
|---|---|
| 重部署零中断 | 5 服务时间戳**完全不变**，日志 6 条「跳过重启/跳过服务重启」 |
| 配置幂等 | 4 协议配置 md5 一致 |
| 崩溃自恢复 | xray/ss/hysteria 均 `Restart=on-failure`；hysteria `kill -9` → 5s 自动拉起 |
| 开机自启 | 6 服务全部 `enabled` |
| 每日重启 | root crontab `0 4 * * * systemctl restart hysteria-server shadowsocks-rust awg-quick@wg0 xray` |
| 日志上限 | journald `SystemMaxUse=500M` |
| 部署告警 | 无 ERROR；WARN 3 类（SHA256 未设置、规则集未发布）——均为设计内显式提示 |

### 3.3 性能（重置后全新部署，环回测量）

| 路径 | 吞吐（30MB，Cloudflare） | 相对直连 |
|---|---:|---:|
| 直连基线 | **1135 Mbps** | 100% |
| Shadowsocks 2022 | **874 Mbps** | 77% |
| Xray+Reality (TCP+vision) | **299 Mbps** | 26% |
| Hysteria2 (QUIC+salamander) | **233 Mbps** | 21% |

内存（RSS）：

| 服务 | RSS | 线程 |
|---|---:|---:|
| xray | 33.7 MB | 7 |
| fail2ban | 31.8 MB | 5 |
| hysteria-server | 22.7 MB | 7 |
| nginx | 10.8 MB | 1 |
| shadowsocks-rust | 4.7 MB | 3 |
| **服务端合计** | **≈104 MB** | — |

系统：内存 `273Mi / 950Mi`（29%）、load average `0.18`。
> 注：上轮报告的服务端合计「≈62MB」**漏计了 fail2ban（31.8MB）**，本轮已补全。

**结论**：吞吐排序稳定（SS > Reality > Hysteria2），三者均远超实际代理所需；瓶颈是 QUIC 用户态 + 混淆的 CPU 开销，非当前短板。

### 3.4 客户端体验

| 项 | 实测 |
|---|---|
| 一行命令安装 | ✅ 下载 sing-box v1.14.2 + 拉取订阅 + 建服务/定时器 |
| 逐协议连通性 | Reality / Hysteria2 / SS 均 `gstatic=204`，出口 IP 正确；sing-box 无 AWG（已从订阅剔除，实测 `/singbox` 仅 3 节点） |
| 订阅完整性 | `/sub` 4 节点（vless/hysteria2/ss/wg）· `/clash` 4 节点 · `/singbox` 3 节点 |
| 每日自动更新 | ✅ `Result=success`，配置实际更新（上轮此路径完全失效） |
| 规则集缺失降级 | ✅ 告警 + 服务正常启动 + 部署时显式提示修复命令 |
| 监听地址可配置 | ✅ `--listen-address`（默认 `0.0.0.0` 保持局域网共享；公网/不受信设备可 `127.0.0.1`） |
| 运维工作目录 | ✅ `~/.easynet` 13 个条目（含 4 协议配置目录、证书、状态、日志、安全项）+ 生成的 `README.md` 路径总表 |
| 统一命令 | ✅ `/usr/local/bin/easynet`（`status`/`where`/`path`/`config`/`logs`/`restart`/`sub`/`deploy`/`ssh`/`doctor`） |
| 订阅 URL 跨重装稳定 | ✅ 重置前后前缀一致 `/s/983fe0a6…`（`.env` 固定 `EASYNET_SUBSCRIPTION_PATH_PREFIX`） |

---

## 四、仍未解决项（按风险排序）

| 优先级 | 项 | 风险 | 建议 |
|:--:|---|---|---|
| ✅ **已解决** | ~~**供应链 pin**：SHA256 默认跳过；hysteria2/AWG/acme.sh 未 pin~~ | —— | 第四轮已解决：见 `security-audit.md` §5.2。pin 集中到 `core/pins.sh` 并**默认强制校验**；Xray/hysteria2 改为直接下载官方 release（不再执行上游安装脚本）；新增每周 CI 检查 pin 是否落后上游稳定版 |
| 🟡 P2 | 订阅仅单层「128 位随机路径」保护 | 路径泄露即凭据泄露 | 可选 Basic Auth / 一次性 token |
| 🟡 P3 | 无运行监控/告警 | 故障不可知 | 轻量心跳（如每日 curl 自检 + 失败告警） |
| 🟡 P3 | 客户端 `RouteDns`/`mixed` 默认 `0.0.0.0` | 不受信网络上=开放代理 | 已在安装时告警 + 提供 `--listen-address`（**默认值保持不变**，属设计取舍） |
| 🟡 P3 | Reality 未启用 Finalmask（XHTTP/noise/fragment） | 针对性检测时余量不足 | 作为应急开关预留（客户端兼容性差，不宜默认开启） |
| 🟡 P3 | `ufw limit 22/tcp` 未启用（当前为 `ALLOW`） | SSH 爆破成本略高但不限速 | fail2ban 已覆盖；可选改 `limit` |
| ⚪ 设计保留 | SS 无传输层伪装；AWG 生态窄；WG 私钥随 URI 分发 | 协议固有 | 已按 `MODULE_SECURITY_RANK` 排位并在文档标注「兜底/备用」 |
| ⚪ 测试缺口 | 协议 `deploy.sh`（~914 行）与 Edge deploy 无行为测试 | 高风险代码零覆盖 | 后续用 mock 模式补基本行为测试 |

---

## 五、与上一轮结论的差异（可信度修正）

| 上轮结论 | 本轮实测 | 说明 |
|---|---|---|
| 「仅 TLS 1.3」 | TLS 1.2 + 1.3（1.0/1.1 拒绝） | 上轮表述不准确；TLS 1.2 为刻意保留（兼容旧客户端），非缺陷 |
| 「敏感文件全部 600/640，无 world-readable」 | 协议配置/metadata 正确，但**状态目录 755/644** | 漏检 `/var/lib/easynet`（本轮 N1 修复） |
| 「服务端内存 ≈62MB」 | ≈104MB | 漏计 fail2ban（31.8MB） |
| 「每日定时重启 ✅」 | ✅ 存在（root crontab，非 `/etc/cron.d`） | 上轮检查路径不完整，结论正确 |
| 「服务崩溃自恢复 ✅（xray/hysteria/ss）」 | xray/ss ✅，**hysteria 实际为 `Restart=no`** | 上轮误判（本轮 N4 修复并实测） |
| 「安全头 HSTS/nosniff/X-Frame-Options ✅」 | 值存在，但伪装页出现**重复且冲突** | 上轮仅检查存在性（本轮 N3 修复） |

---

## 六、验收建议

1. **本次修复（N1/N3/N4/N5/N6）已在重置后的 VPS 上逐项实测**，可直接纳入本轮验收。
2. 建议验收顺序：部署 → `reset-acceptance.sh --verify`（自动出简报）→ 客户端导入订阅（URL 不变）→
   逐协议连通 → `easynet status` → `easynet harden-ssh check` → 可选执行 `apply` + `confirm`。
3. 若需验证「重部署零中断」：连续执行两次 `easynet deploy`，比对 `ActiveEnterTimestamp` 应完全不变。
4. 供应链 pin（P2）建议作为下一轮独立任务，涉及客户端兼容性验证，不宜混在本轮验收中。

---

## 七、核查依据

- 静态：`scripts/`（50 文件）+ `tests/`（28 套件 / 362 用例）+ `shellcheck --severity=style`（0 告警）
- 运行态：测试 VPS 重置为 Ubuntu 26.04.1 后从零部署，取证命令见 `docs/security-audit.md` 第八节
- 实测：`kill -9` 崩溃自恢复、`setpriv` 非 root 读取、逐协议 30MB 吞吐、`systemctl start` 更新服务
- 历史问题来源：`docs/security-audit.md`、`docs/audit-2026-09-27.md`、`docs/architecture-review.md`、`CHANGELOG.md`
