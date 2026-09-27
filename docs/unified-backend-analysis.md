# 统一服务端方案可行性分析（sing-box / Xray-core）

> **归档日期**: 2026-09-26（2026-09-27 增补 Xray-core 路线）
> **结论**: 技术可行，统一内核是趋势之一；**本轮决策仍为「维持现状」**，但新增候选
> **Xray-core** —— 它保留 XHTTP/Finalmask，对「抗 DPI 优先」的 EasyNet 是比 sing-box
> 更强的统一候选。
> **核查依据**: sing-box v1.14.2、Xray-core v26.9.9（2026-09-08）配置文档与源码、
> GitHub 数据（2026-09）。

## 一、背景

EasyNet 当前以 4 个独立协议模块（Xray+Reality、Hysteria2、Shadowsocks 2022、
WireGuard/AmneziaWG）各自安装上游二进制。本文评估「是否可收敛为**一个统一内核**的服务端」，
以及 sing-box 与 Xray-core 两条路线的取舍。

## 二、结论

- **技术上：两条路线都可收敛** —— 4 种协议在内核层面都能找到服务端 inbound。
- **趋势上：统一内核是主流方向**，服务端是 sing-box 与 Xray **双雄并存**。
- **关键点：之前否定统一的理由只对 sing-box 成立**。sing-box 缺 XHTTP/Finalmask（与
  「抗 DPI 优先」冲突）；而 Xray-core 自带 XHTTP/Reality/Finalmask/ECH，并已补齐
  Hysteria2 与 Shadowsocks 2022 inbound。
- **共同硬伤：两者都不支持 AmneziaWG**（sing-box 拒绝 `jc/jmin/...`；Xray 无 AWG 实现，
  其文档还明确警告「WireGuard 不用于翻墙、特征明显易被封锁」）→ `awg-quick` 模块无论如何
  要独立保留。
- **决策：维持现状**（不收敛）；把「统一」定为**可选后端**方向，优先评估 Xray-core。

## 三、能力对照

| 维度 | 现状（4 个上游） | 统一到 **sing-box** | 统一到 **Xray-core** |
|---|---|---|---|
| VLESS+Reality | Xray-core | ✅ `vless` inbound + `tls.reality` | ✅ 原生（realitiy 发源地） |
| Hysteria2 | 官方 hysteria | ✅ `hysteria2` inbound（obfs salamander、masquerade） | ✅ `hysteria` inbound v2（auth + Finalmask `udp`/`quicParams.udpHop`） |
| Shadowsocks 2022 | shadowsocks-rust | ✅ `shadowsocks` inbound | ✅ `shadowsocks` inbound（`2022-blake3-*`） |
| AmneziaWG | `awg-quick`（内核） | ❌ 不支持 AWG 混淆 | ❌ 不支持 AWG 混淆 |
| WireGuard 原生 | 内核 `wg-quick` | ⚠️ `wireguard` **endpoint**（非内核态，较新） | ⚠️ **user-space** inbound（官方警告易被封锁） |
| XHTTP 传输 | ✅（Xray） | ❌ 无 | ✅ 有 |
| Finalmask 混淆 | ❌（内核有、当前未启用） | ❌ 无 | ✅ `streamSettings.finalmask`：`tcp`/`udp` 掩码 + `quicParams` |
| ECH / 后量子 | ✅（Xray） | 部分 | ✅ |
| 额外 inbound | — | Trojan/VMess/TUIC/AnyTLS/ShadowTLS/Snell/Naive/OpenVPN/MASQUE… | Trojan/VMess/SOCKS/HTTP/Dokodemo/TUN/Tunnel… |
| 进程数 | 4 + N | **1**（+ `awg` 1） | **1**（+ `awg` 1） |
| 与端设备同内核 | — | ✅（端设备客户端已用 sing-box） | ❌ |

### Xray-core Finalmask 可用的掩码类型（`transport/internet/finalmask/`）

`fragment`、`header/custom`、`mkcp/*`、`noise`、`realm`、**`salamander`**、`sudoku`、
`udphop`、`xdns`、`xicmp`、`xmc` —— 即 Hysteria2 也能用 Xray 侧的 UDP 混淆组合，
并可用 `quicParams.udpHop` 做端口跳变。

## 四、统一的收益

- 一套二进制 / 一套配置语言 / 一套 systemd 服务，取代 3~4 套上游安装脚本与版本跟踪；
- 新增协议成本骤降（加一个 inbound 段即可）；
- metadata/export/render 的差异收敛，维护面大幅缩小（契合「简洁、快迭代」）。

## 五、统一的代价与风险

- **AmneziaWG 无法收敛**：必须保留 `awg-quick` 独立模块（抗 UDP 指纹的主力之一）；
- **失去「每协议独立进程」的隔离**：一个配置错误可能影响全部协议；
- **WireGuard inbound 更弱**：Xray user-space 版官方点名易被封锁，sing-box endpoint 也非内核态；
- **配置 schema 变更频繁**：sing-box 1.x 改字段、Xray 也持续演进，维护成本转移为「跟 schema」；
- **迁移是破坏性的**：对正在运行的部署需要重装与重新分发订阅。

## 六、趋势判断（2025–2026）

1. **客户端已基本统一**：sing-box / mihomo 是事实标准（EasyNet 客户端已跟进）。
2. **服务端「多协议单内核」是趋势**：Xray-core 已补齐 Hysteria2、WireGuard，并持续加
   XHTTP/3、Finalmask、Post-Quantum；sing-box 单内核覆盖最广 but 无 XHTTP/Finalmask。
3. **抗 DPI 的增量主要来自 Reality / XHTTP / Finalmask / ECH / QUIC 混淆** —— 这些都集中在
   Xray 侧，与项目定位一致。
4. **社区规模**：Xray-core 41.8k★、sing-box 38.3k★、hysteria 22.6k★ —— 双雄并存。

## 七、若推进：建议路线（本轮暂不执行）

充分利用现有 plugin 架构（manifest + deploy/export/render 已把协议抽象得很薄），
把「统一」做成**可选后端**，而不是重写：

- **阶段 1（低风险）**：新增一个可选后端模块（建议 `xray-unified`），用**单个进程**承载
  VLESS+Reality / Hysteria2 / Shadowsocks 2022；WireGuard 继续由 `awg-quick` 承担。
- **阶段 2（验证后）**：测试 VPS 对比稳定性、性能、客户端兼容（Shadowrocket / mihomo /
  sing-box 三方连接同一节点），再决定是否设为默认。
- **备选**：若更看重「与端设备同内核」，则做 `singbox-unified`，代价是放弃
  XHTTP/Finalmask（抗 DPI 上限下降）。
- **不建议**：一次性把 4 协议全量重写进单内核（AmneziaWG 仍要外挂，收益被摊薄、风险最高）。

## 八、核查依据

- sing-box v1.14.2（2026-09-24）：`docs/configuration/{inbound,endpoint,outbound,shared}`；
  服务端 inbound 含 `vless`/`hysteria2`/`shadowsocks` 等；`wireguard` endpoint；传输无 XHTTP。
- Xray-core v26.9.9（2026-09-08）：`infra/conf/hysteria.go`（`version`/`users`/`clients`）、
  `infra/conf/wireguard.go`（`secretKey`/`peers`/`mtu`/`isClient`）、`infra/conf/shadowsocks.go`
  （`2022-blake3-*`）、`transport/internet/finalmask/*`（salamander/sudoku/realm/noise/…）、
  `infra/conf/transport_finalmask.go`；文档 `docs/config/{inbounds,transports}/`。
- GitHub stars：Xray-core 41.8k、sing-box 38.3k、hysteria 22.6k、shadowsocks-rust 10.9k（2026-09）。
