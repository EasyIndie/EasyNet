# 第四轮审计：供应链 pin 一等公民化 + 端口跳跃真修复 + 卸载路径收尾

范围：在「发版前最后确认」这一轮里，对**历史全部 31 项问题**重新以「代码 + 运行态实测」核验，
并针对本轮新发现做修复。全过程在测试 VPS（`test-world.jokerhub.cn` / 66.42.52.243）验证。

---

## 一、本轮真缺陷（全部已修复并实测）

| 编号 | 级别 | 问题 | 修复 | 实测证据 |
|---|---|---|---|---|
| **N8** | 🟠 P1 | `set -o pipefail` 下 `producer \| head -1` 触发 SIGPIPE(141)，`set -e` 直接**中止部署**（全仓库 12 处 / 7 文件） | 改为 `awk 'NR==1'` / `find -print -quit` / 单遍 awk；新增 lint 规则防回归 | `xray version \| head -1` 实测 `exit=141`；修复后部署 0 ERROR |
| **N9** | 🟠 P1 | `install_hysteria2` 在二进制已最新时提前 `return`，**跳过服务账号/运行时目录/systemd unit 创建** | 运行时准备改为无条件执行（下载逻辑拆到 `install_hysteria2_binary`） | 删除 `hysteria` 用户 + `/var/lib/hysteria` 后重部署：账号重建（uid 999）、目录 700、服务 active |
| **N10** | 🔴 P1 | **Hysteria2 端口跳跃从未生效**：服务端配置写了客户端专有的 `portHopping:` 块（服务端静默忽略），而订阅却向客户端宣告 `porthopping=20000-30000` → 会跳变的客户端被送到无人监听的端口 | 服务端改为 `listen: :<基础端口>,<范围>`（hysteria 内建范围支持：监听基础端口 + 自动建立/回收 nftables 重定向）；沙箱补 `AF_NETLINK`；订阅按各客户端方言输出跳变字段 | 服务端连 **443/20000/23456/25000/29999 全部 204**；`hop_interval=5s` 跳变客户端 35 秒内 **7/7 成功**；`nft list ruleset` 可见 `udp dport 20000-30000 redirect to :443` 且停止服务后自动清理 |
| **N11** | 🟠 P2 | 卸载遗留**开放端口**：元数据把范围存成 `20000-30000`（连字符），UFW 规范是 `20000:30000`（冒号），`ufw delete allow 20000-30000/udp` → `ERROR: Bad port` 被 `\|\| true` 吞掉 → 卸载后仍对外开放该 UDP 范围 | 抽出 `firewall_normalize_rule()` 作为唯一归一化入口，apply/uninstall 共用 | 卸载日志出现 `已移除 UFW 规则: 20000:30000/udp`；卸载后 UFW 仅剩 base（22/80/443） |
| **N12** | 🟠 P2 | 卸载遗留 systemd 加固 drop-in（`<unit>.d/easynet-hardening.conf`）与上游旧模板单元（`xray@.service`、`hysteria-server@.service`、`10-donot_touch_single_conf.conf`） | 新增 `uninstall_remove_hardening_dropin()`；各协议卸载清理自家 legacy 单元/drop-in | 卸载后 `*.service.d/` 与 `@.service` 残留 = 0 |
| **N13** | 🟠 P2 | `scripts/uninstall.sh`（编排器）调用了 `core/uninstall.sh` 里的函数却**没有 source 它** → `command not found`（exit 127）→ `set -e` **中断整个收尾流程**（cron 未刷新、`~/.easynet` 索引未更新） | 补 source；新增两条静态守卫测试（source 存在 + 每个被调用的 `uninstall_*` 都有定义） | 卸载退出码 0，输出 `卸载流程完成`，hub 断链 = 0 |
| **N14** | 🟡 P3 | `~/.easynet` 索引保留**指向已删除路径的断链**；状态目录残留空目录；证书指纹状态文件残留 | hub 增加 `easynet_hub_prune()`（只清理 hub 自建链接，**绝不穿透目录软链**，故不会误删 `/etc/systemd/system` 内真实文件）；`uninstall_prune_empty_state_dirs()`；edge 卸载清理规则集与证书指纹 | 卸载后 hub 断链 = 0；`/var/lib/easynet` 仅剩 `country_code`（刻意的缓存）；三个新测试覆盖 |
| **N15** | 🟡 P3 | 供应链：SHA256 默认跳过、hysteria2 用 `get.hy2.sh` 取 latest、Xray 从 `main` 分支取 `install-release.sh`、acme.sh 未 pin | 见下节 | 四个组件均「pin 版本 + 默认强制 SHA256」 |
| **N16** | 🟡 P3 | lint 只用 `grep -P` 检查「`$VAR` 紧跟多字节字符」，而 **BSD grep 无 `-P`** → 本地 macOS 静默通过（CI 才发现） | 改用可移植的 `LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]'`；用「回退验证」确认能稳定检出 | 该规则随后又抓出本轮新代码的 3 处（含 2 处 CJK 紧跟） |

> 另纠正上一轮的一个**前提错误**：Xray「落后上游 6 个月」不成立 —— Xray 自 `26.4.15` 起所有
> release 均为 pre-release，`26.3.27` 正是**最新 stable**（`releases/latest` 返回 26.3.27）。

---

## 二、供应链 pin 一等公民化

新增 `scripts/core/pins.sh`：版本 + **每架构 SHA256**，默认强制校验。

| 组件 | pin | 校验哈希来源 | 安装方式 |
|---|---|---|---|
| Xray-core | `26.3.27` | 官方 `.zip.dgst` 的 `SHA2-256=` | 直接下载官方 release zip（**不再执行** `install-release.sh`） |
| hysteria2 | `2.12.3` | release 内 `hashes.txt` | 直接下载官方 release 二进制（**不再执行** `get.hy2.sh`） |
| shadowsocks-rust | `1.25.0` | 官方 `.sha256` | 官方 release tarball |
| acme.sh | `3.1.6` | `get.acme.sh` 脚本哈希 | `get.acme.sh`（校验脚本自身） |

- 覆盖版本但未给 SHA256 → **拒绝部署**（`EASYNET_ALLOW_UNPINNED=1` 可强制跳过，不建议）。
- 自写 `xray.service` / `hysteria-server.service`（不再依赖会变动的上游安装脚本），并自动创建
  `hysteria` 系统账号与 `/var/lib/hysteria`。
- `scripts/check_upstream_pins.sh` + `.github/workflows/pins.yml`（每周一）检查 pin 是否落后
  **上游稳定版**；实测四组件均「✅ 最新」。
- **实际安装走的是官方直接下载路径**（强制删除二进制后重装）：Xray 26.3.27 / Hysteria2 v2.12.3 /
  ss 1.25.0 三者均「SHA256 校验通过」，0 ERROR。
- 替换二进制后**强制重启**（`*_BINARY_CHANGED`），否则运行的仍是旧镜像。

**残留（明确记录）**：AmneziaWG 走 PPA，由 apt 的 GPG 包签名校验（比自管哈希更标准），未做版本 pin；
acme.sh 安装后可能随其自身 cron 自升级（上游行为，pin 仅覆盖初始安装）。

---

## 三、历史 31 项核验结果

| 分类 | 数量 | 说明 |
|---|:--:|---|
| 本轮修复并实测 | 9 项 | N8–N16 |
| 核验仍有效（无需改动） | 25 项 | 全部以代码 + 运行态复核，含 TLS、安全头、权限、沙箱、幂等、订阅隔离等 |
| 按设计保留 | 4 项 | 见 `audit-round3.md` §2.5 的 16/18 号（`set -f` 下的空格分隔、`clients/` 无 manifest 等） |
| 供应链 | ✅ 已解决 | 见上节（含 1 个前提纠错） |

**运行态复核（第四轮实测，全部通过）**：

- 服务：6 个服务 `active` + `enabled`；`easynet status` 正常。
- TLS：1.0/1.1 拒绝、1.2/1.3 可用（1.2 为刻意保留的兼容）。
- HTTP 头：`Server: nginx`（无版本）；HSTS / X-Frame-Options / X-Content-Type-Options **各恰好 1 次**。
- 权限：敏感文件对**无关普通用户不可读**（SS PSK 与 Xray 私钥为 `640 root:nogroup`，服务以
  `nobody:nogroup` 运行；`wg0.conf` 为 `600 root:root`；状态目录 700）。
- SS 凭据：`cmdline` 仅 `ssserver --config …`，无 `-k/--password/psk`；`CapabilityBoundingSet=` 空集。
- 沙箱：`ProtectSystem=strict` + `Restart=on-failure`（hysteria 补齐）+ `RestartSec=5s`。
- 订阅：随机路径 200、直连 `/sub` 404、未知路径 404；`flag=SG`；sing-box 节点 3 个（**无 AmneziaWG**）。
- 端口：对外监听 22/80/443(tcp)、443(udp)、8388、8443、51820、20000-30000 与 UFW 一一对应，无多余开放。
- fail2ban：`sshd` jail 生效（在拦真实爆破）。
- 三协议连通（经 sing-box 客户端）：Reality / Hysteria2 / SS 均 `204`，出口 IP 正确。

---

## 四、发版前验收路径（模拟用户流程实测）

在测试 VPS 上完整走了一遍「重置后验收」的等价流程：

1. **全量卸载**（`EASYNET_UNINSTALL_MODULE=0`）→ 退出码 0，仅剩 base 防火墙规则，无残留 unit/drop-in/断链。
2. **release 安装器安装**：用 `git archive HEAD` 生成 tarball + `sha256`，本地 HTTP 充当 release 源，
   `EASYNET_VERSION=<tag> EASYNET_RELEASE_BASE_URL=… bash easynet-install.sh` →
   `easynet.tar.gz: OK`（SHA256 校验通过）、**保留已有 `.env`**、原子替换（无 staging 残留）、
   安装内容与本地 HEAD 一致（`pins.sh` sha256 相同）。
3. **全新部署**：0 ERROR；6 服务 active；三协议连通；订阅路径前缀与重置前**完全一致**（客户端无需重新导入）。
4. 二次部署：**0 下载 0 重启**（5 个服务 `ActiveEnterTimestamp` 完全不变）。

---

## 五、测试与 CI

- bats：362 → **386**（新增端口跳跃、卸载清理、hub 剪枝、pin 校验等用例）。
- `shellcheck --severity=style`：0 告警。
- CI：两套 Ubuntu + 两套集成测试全绿（含新增的 pin 周检工作流）。
