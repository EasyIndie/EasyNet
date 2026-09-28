# 服务端演进方向与建议

> **归档日期**: 2026-09-29
> **定位**: 基于现状盘点 + 业内趋势的服务端演进路线图（建议性质，未立项）
> **关联**: issue #5（统一服务端）、`docs/unified-backend-analysis.md`（统一可行性）、
> `docs/unified-client-analysis.md`（统一客户端方案）

## TL;DR

1. EasyNet 当前抗 DPI 栈（Reality+xhttp + Hysteria2+salamander+端口跳跃）**仍处第一梯队**。
2. 隐患与紧迫性已重新校准：**Xray 稳定版停在 26.3.27（2026-03）**、新特性在 pre-release，但**核实后这些特性对 EasyNet 当前「仅 Reality 服务端」的用法几乎无直接收益**（详见下方「隐患 3」）；**官方 hysteria 的 Hysteria2 已落后**于 sing-box/Xray（缺 gecko/chrome-parrot/hop 随机）；**AmneziaWG 是小众细分**（1.9k★、无 release），长期存疑。
3. 建议路径：**近期低风险加固 → 中期 `xray-unified` 单内核 PoC → 长期盯 ECH / sing-box 补 XHTTP
   两个触发器**。不急着推翻现状，先把「跟不上上游新特性」这个最现实的隐患补上。

## 一、现状盘点

| 组件 | 现状 | 备注 |
|---|---|---|
| 协议 | Reality(xhttp) / Hysteria2(salamander+跳跃) / SS2022 / AmneziaWG | 插件架构，薄适配 |
| Xray | pin **26.3.27**（稳定，2026-03） | 见下方「隐患 1」 |
| Hysteria | pin **app/v2.12.3**（官方，2026-09-16） | 见下方「隐患 2」 |
| Shadowsocks | pin v1.25.0（官方） | compat 才开 |
| AmneziaWG | awg-quick（PPA 内核） | 见下方「隐患 3」 |
| Ops | 审计/监控告警/SSH 加固/客户端二进制镜像 | 已上线（0.0.16） |

## 二、业内趋势（2026 六个关键点）

1. **抗 DPI 主战场移到「握手指纹」层**：Reality（借真 TLS1.3 会话）、Chrome QUIC 握手指纹模仿
   （sing-box `chrome_parrot`、Xray `ChromeParrot`）、Finalmask（TCP/UDP 掩码框架）、ECH。
   从「藏载荷」进化到「连握手都像真的」。
2. **Hysteria2 成为 UDP/QUIC 事实标准**：sing-box / Xray / 官方三方都在收敛到它；但**官方
   hysteria 开始落后**——sing-box v1.14 加了官方没有的 `gecko` 混淆、`chrome_parrot`、hop 随机、
   Realm/NAT 穿透，Xray 也补了 `ChromeParrot`。
3. **服务端「单内核多协议」是趋势**，双雄各有硬缺口：sing-box 无 XHTTP/Finalmask；Xray 无 AmneziaWG。
4. **Xray 发布模式 = 稳定慢 + pre-release 快**：最新稳定 v26.3.27（2026-03），但 v26.6/26.7/26.9
   （pre-release）持续每月发版，Finalmask XMC/udpHop、Hysteria v2.12.2+ChromeParrot、ECH 增强都在里面。
5. **AmneziaWG 是小众细分**：1.9k★、无 GitHub release（走 PPA），维护者少，长期存疑。
6. **客户端已基本统一**：sing-box / mihomo / Shadowrocket 三分天下（服务端要跟着客户端兼容性走）。

## 三、强项与隐患

### 强项

- 插件架构把协议抽象得很薄，**换内核/加协议成本低**（manifest + deploy/export/render）。
- 抗 DPI 栈先进：Reality 走 xhttp 传输、Hysteria2 走 salamander + 端口跳跃。
- Ops 基建刚补齐（审计脚本、监控告警、SSH 加固、客户端二进制自愈镜像）。

### 隐患

1. **官方 hysteria 落后于 sing-box/Xray 的 Hysteria2**：无 gecko 混淆、无 hop 间隔随机化
   （`hop_interval_max`）、无 chrome_parrot。用户用 sing-box 客户端（chrome_parrot+salamander）
   连我们服务器时，客户端侧收益已拿到；但**服务端侧新能力（gecko、hop 随机）我们拿不到**。
2. **AmneziaWG 长期存疑**：小众（1.9k★、无 release）、维护者少。它是「统一到 Xray」的最大阻力，
   也是 4 协议里最可能被时代淘汰的。
3. **Xray 稳定版 6 个月未更新（已核实：对当前用法影响有限）**：EasyNet pin 26.3.27，Finalmask
   XMC/udpHop、Hysteria ChromeParrot、ECH 增强、WireGuard 修复都在 pre-release（v26.6/26.7/26.9）。
   但逐一核实后：这些特性**几乎都落在 EasyNet 不用的组件上**——我们只用 Xray 的 VLESS+Reality
   **服务端**（xhttp/tcp），而 Hysteria（官方）、WireGuard（awg-quick）、ECH（未启用）、Finalmask
   掩码（未启用）都不经过 Xray；触及我们代码路径的 XHTTP server 变更只是重构/小修（`xPaddingObfsMode`
   我们也没开）。→ 升级 pre-release 对当前部署几乎无直接收益，**记入 0.0.17 评估**。
4. **4 个上游二进制维护面大**：每加一个协议就多一套 pin/installer/升级/安全审计面。

## 四、演进方向

### 方向 A：近期低风险加固（hop 随机/上游告警立即做；Xray 升级推迟到 0.0.17）

1. **Xray 升级评估（0.0.17 再做，本轮不升）**：已核实 pre-release（v26.9.9 等）的 Finalmask
   XMC/udpHop、Hysteria ChromeParrot、ECH、WireGuard 修复**对当前「仅 Reality 服务端」用法
   几乎无直接收益**（详见「隐患 3」）。升级的实际触发条件：①出现针对 Reality/xhttp 服务端的
   稳定性/安全修复；②采用 Finalmask 掩码（fragment/noise）或 `xPaddingObfsMode`；③推进
   xray-unified。届时在测试 VPS 按现成 pin 流程（SHA256）验证后再升。
2. **Hysteria2 端口跳跃随机化**：hop 间隔由固定值改随机（对应 sing-box `hop_interval_max`），
   降低可预测性。
3. **上游健康度告警**：把 `check_upstream_pins.sh` 接入监控 cron——pin 落后上游最新稳定/发布
   超 N 天即告警，避免再次出现「6 个月没发现 Xray 落后」。
4. **salamander→gecko 评估**：gecko 目前是 sing-box 独有、官方 hysteria 没有；想用服务端 gecko
   只能换内核，挂到方向 B 一起评。

### 方向 B：中期 `xray-unified` 单内核收敛（建议 PoC）

- 单进程承载 **Reality+xhttp + Hysteria2 + SS2022**；AmneziaWG 继续由 awg-quick 外挂。
- 收益：3 个二进制 → 1；新协议 = 加一段 inbound；订阅渲染/导出差异收敛。
- 风险：Xray 的 Hysteria2 是重实现（v2.12.2，略落后官方 2.12.3，但已带 ChromeParrot）；
  Xray release 节奏需长期盯。
- 触发条件：测试 VPS 验证 Xray 的 Hysteria2 实现（v2.12.2）稳定且三方客户端兼容后，或 AWG 决定弃用后。
- 具体做法沿用现有插件架构，加一个 `xray-unified` 可选后端模块，测试 VPS 对比
  「官方 hysteria vs Xray hysteria」的稳定性/性能/三方客户端兼容。

### 方向 C：中期重估 AmneziaWG 去留

- 若确认 Hysteria2 已能覆盖 AWG 的「UDP 抗指纹」场景，可从 compat 移除 AWG → 协议 4→3，
  并**解锁「xray-unified 无外挂」**（这是统一的最大阻力）。
- 触发条件：AWG 上游停更/弃坑，或 Hysteria2 抗 DPI 能力经真机验证覆盖 AWG 场景。

### 方向 D：观察 sing-box 服务端统一（等它补 XHTTP）

- 一旦 sing-box 加入 XHTTP/Finalmask，它就能覆盖 Reality+xhttp+Hysteria2+SS2022，且
  **服务端=客户端同内核**（对统一客户端最友好）。
- 现状：无时间表，**不主动等**，设触发器定期复盘即可。

### 方向 E：长期随军备竞赛演进

- ECH 成熟后评估 Reality+ECH 叠加；
- 跟踪 Finalmask 新掩码（XMC/udpHop）与 Hysteria2 新混淆，择机替换 salamander；
- 保持「协议层薄适配」的架构，让这类演进变成「改一段渲染 + 一个 pin」。

## 五、推荐路线图

| 时间 | 动作 | 依赖 |
|---|---|---|
| **现在** | 方向 A：hop 随机 + 上游健康度告警（无需测试 VPS） | — |
| **0.0.17** | 方向 A：Xray 升级评估（pre-release 收益已核实，见隐患 3）+ 可选 Finalmask/`xPaddingObfsMode` 评估 | 测试 VPS 已释放，需临时重建 |
| **下个迭代** | 方向 B PoC（`xray-unified` 可选后端）+ 方向 C 监控 AWG 上游 | A 验证通过 |
| **长期复盘** | 方向 D/E 触发器：sing-box 是否加 XHTTP、ECH 是否成熟、AWG 是否弃坑 | 每季度 |

## 六、一句话结论

**别急着推翻现状，也暂时不用急着升 Xray**：最现实的两件事是「把 hop 随机 + 上游健康度告警做掉」
和「在测试 VPS 验证 xray-unified 单内核收敛」。Xray pre-release 升级已核实对当前用法几乎无直接
收益，记入 0.0.17 评估；AmneziaWG 去留与 sing-box 补 XHTTP 作为两个长期触发器盯着即可。
