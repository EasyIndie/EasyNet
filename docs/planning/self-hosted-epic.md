## Problem
EasyNet 当前提供成熟的单机 Bash 部署、协议插件、服务端 CLI 和订阅生成，但用户仍需手动管理 SSH、服务器库存、设备连接、成本以及恢复流程。目标是在保留现有能力的基础上，增加 Local-first 的个人网络基础设施生命周期管理。

## Vision
**You own your VPN.**
自己的服务器 / 自己的云账号 → 检测 → 部署 → 连接 → 运维 → 成本 → 备份 → 迁移与恢复。

## Product Principles
- Self-hosted first；BYOS / Existing Server / Custom SSH 是一级入口；BYOC 是增强能力。
- 不成为 VPN 服务提供商，不代售流量，不要求充值、平台套餐或强制账号。
- 基础设施、云凭据、密钥、配置、备份由用户掌握；凭据优先设备安全存储。
- 默认 Local-first control plane；已部署数据面不依赖 EasyNet 官网、中央 API、客户端在线或管理 Agent。
- Native Config Export / Escape Hatch；用户可脱离 EasyNet 使用兼容客户端。
- Provider-agnostic / Protocol-agnostic；SSH 是通用管理与最终恢复通道。
- 管理 Agent 可选，不处理 VPN 数据流；移除 Agent 不影响后端。
- 成本透明：已有服务器允许手工录入价格、周期、流量/超额成本或 Free / Already Owned；后续报价数据必须可更新。

## Repository Audit / Compatibility Gate
基于 2026-10-06 本地代码 `1d288dc747862486c930d5d21042b3fc4339e16f`、README/docs、部署/导出/测试/CI，以及 GitHub Issues/PR。
检索时无 open Issues / PR；#5 已 closed / not_planned，已阅读全部五条评论。
结论：**新增管理层可兼容；不进行无必要重写或强制内核迁移。**

可复用：manifest discovery、四个协议模块、metadata v1、Edge/TLS、URI/Clash/sing-box 输出、Linux sing-box 安装器、easynet 运维 CLI、pin/checksum/release 流程和 Bats/真实客户端校验。

缺口：远程可信 SSH、ServerTarget/多服务器本地库存、只读结构化 preflight、管理操作模型、统一 native export、完整加密备份恢复、桌面连接管理、ProviderAdapter 和成本模型。

必须处理的边界：
1. `scripts/protocols/wireguard/` 实际使用 AmneziaWG，不能当作已支持原生 WireGuard。
2. 当前 bootstrap 在 module preflight 前发生；严格预检开关不足以保证“先检测后修改”。新增独立只读 gate。
3. 当前回滚恢复 state 目录，不恢复全部运行配置、密钥/证书、units/安装状态；不是灾难恢复。
4. Hysteria2 export 当前是 metadata，不是完整原生客户端 YAML。
5. Rust/SwiftUI 是交接候选；仓库另有 Flutter+sing-box 客户端提案。语言/框架通过 ADR 评估，不直接实施。
6. 首条 slice 建议 Hysteria2：已有 pinned binary、密钥保留测试和服务管理，避免 AWG 内核/PPA及 Reality transport 的额外复杂度；仍需域名/TLS、UDP 和 native YAML 工作。
7. 首批支持 Existing Ubuntu VPS / systemd；家庭/NAT/NAS 和更广平台通过明确兼容性矩阵逐步扩展。

## Architecture
Client UI / CLI
→ Application Services (Server / Deploy / VPN / Cost / Backup)
→ Local State + Secure Credential Store
→ SSH / ProviderAdapter / ProtocolDriver / VPNEngine
→ 用户服务器上的现有 Bash 后端与独立 native runtimes。

Protocol 与 Runtime 分开建模；首先使用 Bash compatibility adapter。保留现有 CLI、模块、profiles、metadata v1 消费者和订阅格式。GUI 不直接绑定任意 shell 字符串。独立 CLI 的职责先评估，避免重复现有服务端 easynet。

## Scope
Existing Server 生命周期、可信 SSH、preflight、部署编排、原生配置、设备连接、监控/升级、手工及 Provider 成本、加密备份/恢复、后续 BYOC 与可选 Agent。

## Non-goals
自营 VPN/流量套餐/充值；强制账号或云控制面；全协议一次完成；十几个 Provider；企业多租户/RBAC；强制 Agent；自研协议；立即 Rust 重写或全栈 sing-box。

## Phases
- **Phase 1A — Existing VPS management slice**：ServerTarget/local state → trusted SSH → read-only preflight → explicit plan → Hysteria2 native deployment → native client export，先用 application-service CLI/集成 harness 验证。
- **Phase 1B — macOS MVP**：desktop/VPNEngine connect/disconnect、状态/流量/重启/升级、手工成本、加密备份及另一 VPS 恢复。GUI 在核心闭环后建设。
- **Phase 2 — BYOC**：ProviderAdapter、首个经过评估的 Provider、创建/销毁与云防火墙、真实 TCO 和定价/流量数据；限制 Provider 数量。
- **Phase 3 — Recovery and expansion**：更多协议/平台、第三方配置安全导入、迁移和可选 Agent、SSH 救援。Agent 不作为数据面依赖。

## ADRs to Evaluate
ADR-001 Local-first Control Plane；
ADR-002 Protocol / Runtime abstraction；
ADR-003 SSH vs Optional Agent；
ADR-004 Shared Core Language；
ADR-005 Local State；
ADR-006 Backup / Recovery Format。
以上为待评估建议，不能视为已接受或已实现的架构决定。

## Child Issues / Related Work
当前仅创建本总 Epic；以下是 **Phase 1 拆分草案，尚未创建 GitHub 子 Issue**：
| ID | Proposed issue | Dependencies |
|---|---|---|
| P1-A | Architecture contracts and ADR-001–006 evaluation | — |
| P1-B | ServerTarget / ExistingServer + versioned local inventory | A |
| P1-C | Trusted SSH transport + secure credential storage | A, B |
| P1-D | Read-only structured server preflight before bootstrap | A, C |
| P1-E | Bash-compatible ProtocolDriver + deployment plan | A, C, D |
| P1-F | Native Hysteria2 client export + offline Escape Hatch | A, E |
| P1-G | Existing Ubuntu VPS → SSH → Deploy → Export integration | B–F |
| P1-H | Encrypted backup + restore to a different VPS | B, E, F, G |
| P1-I | Remote status / traffic / restart / verified upgrade | B, C, E, G |
| P1-J | Manual existing-server costs + TCO summary | B; I for observed usage |
| P1-K | macOS MVP over application services + VPNEngine | G, H, I, J; framework/engine ADR |

**Protocol Runtime / sing-box evolution — related #5**：
[#5 转向sing-box生态](https://github.com/EasyIndie/EasyNet/issues/5) 保留既有关闭状态与调研结论，纳入 Runtime 方向的历史依据/后续评估关联。它不是本 Epic 已完成子任务，也不是 Phase 1 阻塞依赖。
不把 Provider/Deployment/Cost/Backup 强耦合到 sing-box；不以本 Epic 推翻既有“暂不迁移 sing-box 服务端”决定。出现新兼容性证据后再评估可选 runtime；保留 native Xray/Hysteria2/AWG。

## Definition of Done
- Existing Server：导入 → 验证 SSH/host key → 只读 preflight → 明确计划 → 部署 → 原生配置 → 连接。
- BYOC：连接自己的云账号 → 地区/套餐 → 真实成本 → 创建 → 部署 → 连接；销毁有明确目标和恢复准备。
- Operations：状态、流量、成本、脱敏日志、重启、验证升级、加密备份与恢复。
- Exit / Recovery：导出配置/密钥，移除可选 Agent，迁移到另一服务器；停止客户端/中央服务不影响已运行 VPN。
- SSH changed-key/timeout/sudo、preflight、幂等/中断恢复、client config 实二进制、state migration、secret redaction、backup tamper/restore 均有测试；显式测试 VPS 上完成连接与跨服务器恢复验收。
- 现有 CLI、四协议模块、订阅输出及 release 验证保持兼容；测试环境完整 compat 验收不被单协议 slice 替代。
- 长期 Epic 完成与 Phase 1A 技术闭环完成分别验收，不把 native export 当作完整 GUI/Connect MVP。

## Validation at Audit Time
本地 fast suite：444 tests，0 failures，5 skipped（排除 network/client 标签）；ShellCheck style 全部通过；git diff --check 通过。
未进行 root/VPS 部署、全量网络/真实客户端或跨机恢复验收；检查 CI 定义不等于确认最新远程 CI 成功。

## Planning Artifacts
本次本地工作树形成 `AGENTS.md`（通用入口，CLAUDE.md 为兼容引用）、`docs/planning/repository-audit-2026-10-06.md` 和 `docs/planning/phase-1-issue-plan.md`，包含证据、复用/缺口/成本矩阵及各提案验收标准。尚未提交/推送，因此这里不提供会失效的 main 文件链接。
