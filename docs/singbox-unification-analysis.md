# sing-box 统一方案可行性分析

> **归档日期**: 2026-09-26
> **结论**: 技术可行，统一内核是趋势之一；但**本轮决策为「维持现状」**，不收敛为 sing-box 方案。
> **核查依据**: sing-box v1.14.2（`testing` 分支 `docs/configuration/*`）、Xray-core v26.3.27、GitHub 数据（2026-09）。

## 一、背景

EasyNet 当前以 4 个独立协议模块（Xray+Reality、Hysteria2、Shadowsocks 2022、WireGuard）各自安装上游二进制实现。本文评估「是否可收敛为统一的 sing-box 服务端实现」，以及该方向是否符合当前趋势。

## 二、结论

- **技术上：可以收敛** —— 当前 4 种协议 sing-box 均可作为服务端（含 WireGuard）。
- **趋势上：统一内核是主流方向之一**，但服务端是 sing-box 与 Xray **双雄并存**，并非「必须 sing-box」。
- **决策：维持现状**（不收敛）—— sing-box 缺少 Xray 的 XHTTP/Finalmask 等前沿传输能力，与本项目「抗 DPI 优先」的定位冲突；且大爆炸迁移风险高、收益可延后。

## 三、能力对照（当前实现 vs sing-box 服务端）

| EasyNet 协议 | 当前实现 | sing-box 服务端 | 成熟度 / 备注 |
|---|---|---|---|
| Xray+Reality | Xray-core | ✅ `vless` inbound + `tls.reality` | 支持；但**无 XHTTP**、无 Finalmask |
| Hysteria2 | 官方 hysteria | ✅ `hysteria2` inbound（obfs salamander、masquerade） | 良好 |
| Shadowsocks 2022 | shadowsocks-rust | ✅ `shadowsocks` inbound | 良好 |
| WireGuard | 内核 `wg-quick` | ⚠️ `wireguard` **endpoint**（`listen_port`+`peers`，可当服务端） | 支持但较新、非内核态，成熟度待验证 |

sing-box 服务端额外自带：Trojan、VMess、TUIC、AnyTLS、ShadowTLS、Snell、Naive、OpenVPN/MASQUE(server) 等。

**sing-box 传输**：HTTP / WebSocket / QUIC / gRPC / HTTPUpgrade —— **无 XHTTP**。

## 四、统一的收益

- 一套二进制 / 一套配置语言 / 一套 systemd 服务，取代 4 套上游安装脚本与版本跟踪；
- 新增协议成本骤降（加一个 inbound 段即可）；
- 服务端与客户端同一内核（端设备客户端已用 sing-box）→ 配置模型统一、订阅/规则逻辑可复用；
- metadata/export/render 的差异收敛，维护面大幅缩小（契合项目「简洁、快迭代」目标）。

## 五、统一的代价与风险

- **丢失 Xray 独有能力**：XHTTP、Finalmask、部分 uTLS/ECH 前沿（与「抗 DPI 第一」定位直接冲突）；
- **配置 schema 破坏性变更较频繁**（sing-box 1.x 多次改字段）→ 维护成本转移到「跟 schema」；
- **WireGuard 服务端**在 sing-box 里较新且非内核态，不如 `wg-quick` 稳；
- **单点耦合**：一个配置错误可能影响全部协议（当前每协议独立进程，隔离更好）；
- **迁移风险**：对正在运行的部署是破坏性的。

## 六、趋势判断（2025–2026）

1. **客户端已基本统一**：sing-box / mihomo(Clash.Meta) 成为事实标准（EasyNet 客户端已跟进）。
2. **服务端「多协议内核」是趋势**：sing-box 单内核覆盖几乎所有主流协议；Xray-core 也在扩张（v26.3.27 新增 **Hysteria2 入站**、WireGuard、XHTTP/3、**Finalmask**、ECH）。
3. **协议/传输向 QUIC（Hysteria2/TUIC/MASQUE）与更强混淆（REALITY/Finalmask/ECH）演进**。
4. **社区规模**：Xray-core 41.8k★、sing-box 38.3k★、hysteria 22.6k★ —— 服务端领域双雄并存，并非 sing-box 一家独大。

> 统一内核是趋势，但「统一到 sing-box」是**一种**可选路线，不是唯一正确路线。

## 七、若未来推进：建议路线（本轮暂不执行）

充分利用现有 plugin 架构（manifest + deploy/export/render 已把协议抽象得很薄），把「统一」做成后端实现，而不是重写：

- **阶段 1（低风险）**：新增一个 **sing-box 后端模块**（可选部署方式），先支持 VLESS+Reality / Hysteria2 / SS2022；WireGuard 暂留 `wg-quick`。
- **阶段 2（验证后）**：在测试 VPS 对比稳定性/性能/客户端兼容；若通过，把 sing-box 设为默认推荐，Xray 作为「前沿传输（XHTTP/Finalmask）」可选模块保留。
- **不建议**：一次性把 4 协议全量重写为 sing-box（丢前沿能力、迁移风险高）。
- 另一种模型：**单 sing-box 服务承载全部协议**（一个配置、一个进程）——最简洁，但模块耦合、单点风险最高，改造量也最大。

## 八、核查依据

- sing-box v1.14.2（2026-09-24），`docs/configuration/{inbound,endpoint,outbound,shared}`（服务端 inbound 含 `vless`/`hysteria2`/`shadowsocks` 等；`wireguard` endpoint 含 `listen_port`+`peers`；传输无 XHTTP）。
- Xray-core v26.3.27 发行说明（Hysteria2 入站、XHTTP/3、Finalmask、ECH、WireGuard）。
- GitHub stars：Xray-core 41.8k、sing-box 38.3k、hysteria 22.6k、shadowsocks-rust 10.9k（2026-09）。
