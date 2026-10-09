# EasyNet 产品演进计划

更新：2026-10-09。总跟踪：[Epic #13](https://github.com/EasyIndie/EasyNet/issues/13)。
本文将初始产品方案与仓库审计结果整合为长期演进计划；不代表未来功能已经实现。
初始交接资料已完成吸收并清理，后续以本目录、ADR 和关联 Issue 维护计划。
具体工程推进以 [分阶段可执行清单](execution-backlog.md) 的任务与验收 gate 为准。

## 产品定位与原则

EasyNet 向 Local-first、Self-hosted、BYOS/BYOC 的个人网络基础设施管理平台演进。
用户使用自己的服务器和云账号完成检测、部署、连接、运维、成本管理、备份、迁移与恢复。
核心价值是 **You own your VPN**，长期积累在生命周期管理能力，而非绑定某个代理协议。

- Existing Server / Custom SSH 是一级入口，Cloud Provider 是可替换增强能力。
- 服务器、云账号、IP 使用权、凭据、配置和备份由用户掌握。
- 不经营共享 VPN 服务、出售节点/流量、要求用户充值或购买平台套餐。
- 默认不要求账号或中央控制面；已部署数据面在官网、项目 API、客户端或管理 Agent
  不可用时继续运行。安装、升级和获取订阅仍可能使用外部网络。
- 提供原生配置、密钥和恢复说明，用户能脱离 EasyNet 使用第三方客户端。
- 管理 Agent 可选，不承载 VPN 数据流；移除后后端保持运行，SSH 是最终恢复通道。
- 成本透明；核心能力与配置格式保持开放。可选高级 GUI、同步、团队能力和支持服务
  是未来商业化候选，不改变数据面独立和用户退出能力，也不构成本轮商业决策。

## 架构边界

Client UI / CLI → Application Services → Local State / Credential Store
→ SSH / ProviderAdapter / ProtocolDriver / VPNEngine → 用户服务器独立运行的后端。

保留现有 Bash 服务端部署、easynet CLI、协议插件、metadata v1、Edge/TLS 与订阅格式。
新增管理层通过适配器复用现有逻辑；GUI 调用应用服务，不直接拼接 shell 命令。
ServerTarget 区分 ExistingServer 和 CloudServer，部署层不依赖来源。
协议、运行时和客户端能力分别建模，允许 Xray、Hysteria2、AmneziaWG、sing-box 等异构组合。

目标接口方向：ProviderAdapter 负责认证、地区/套餐/价格、服务器创建/查询/重启/销毁、
云防火墙及流量/账单；ProtocolDriver 负责安装、配置、生命周期、升级、客户端配置和健康检查；
VPNEngine 负责导入、连接、断开、状态、延迟和流量。未支持的方法应明确返回能力限制。
多客户端创建/撤销和已有第三方配置安全接管需后续单独实现。

## 分阶段路线与验收

| 阶段 | 交付范围 | 进入/退出条件 |
|---|---|---|
| Phase 1A：已有服务器管理闭环 | ServerTarget、本地库存、可信 SSH、独立只读预检、部署计划、Bash ProtocolDriver、Hysteria2 原生客户端导出及集成 harness | 先评估 ADR；Existing Ubuntu VPS 首次部署/重复部署/中断恢复与原生连接通过；预检失败不修改系统 |
| Phase 1B：macOS MVP | 连接管理、状态/流量/日志/重启/升级、手工成本、加密备份及跨 VPS 恢复、桌面交互 | 在核心闭环后选择 GUI/engine；平台权限与打包、客户端停止后的数据面独立和另一目标恢复通过 |
| Phase 2：BYOC | ProviderAdapter、首个经评估 Provider、地区/套餐、真实成本、创建/销毁、云防火墙、流量预测 | 限定 Provider 数量；账号凭据留在用户设备，资源与账单可追踪；失败创建/部分成功能清理和恢复 |
| Phase 3：恢复与能力扩展 | 更多协议、已有安装安全导入、迁移、可选 Agent；网络探测、协议 fallback / Smart Transport 候选 | 保留已有 runtime 能力；接管默认不覆盖；移除 Agent 和 SSH 救援不影响数据面 |
| 后续跨平台 | iOS、Windows、Linux 等客户端；共享应用服务与适用核心能力 | 按平台验证 VPN 权限、凭据存储、连接生命周期及打包；不预设共享核心语言 |
| 后续基础设施智能化 | Provider/套餐比较、延迟测量、成本优化、预算模式、IP 替换、自动迁移/故障恢复、辅助运维 | 成本与监控数据可信；先具备可测试、可恢复的手工操作路径，再评估自动化 |

G5/G6 中的具体任务纳入本地最终演进验收；可选候选由 ADR 明确实施或不适用。
所有阶段工作在 `codex/feature/self-hosted-byos-byoc`，全部约定演进完成后才合入 main；
GitHub Epic 范围尚未同步此次本地执行约束，不提前创建子 Issue。具体 Phase 1 顺序、依赖和
验收见 [Issue 拆分方案](phase-1-issue-plan.md)。首条闭环选择 Hysteria2，不以初始
方案的 WireGuard/Hysteria2 双协议建议作为必须同时实现的要求。

## 能力演进要求

**Preflight**：在 bootstrap 前采集 OS/版本、内核/架构、CPU/RAM/磁盘、systemd、
权限、监听端口、DNS、防火墙、已有服务及选定协议需要的 TLS/UDP/TUN 等事实。
区分已观察、未知和不支持；不能把本机 UDP socket 可用当作公网可达。
Existing Ubuntu VPS 是首批验收范围；Debian、ARM64、家庭/NAT、树莓派、VM、
独立服务器和符合条件的 NAS 逐步扩展，不承诺任意 Linux 主机均可部署。

**安全与交付**：设备安全存储保存 Provider Token、SSH Key 等凭据；库存只保存引用。
SSH 优先 key/agent，验证 host fingerprint，明确 root/sudo 和 recovery key；
专用管理账户及 SSH 加固是受控操作。未来 Agent API 需强身份认证（如 mTLS/device key）。
组件固定版本、校验完整性、明确来源、评估回滚；现有 AWG apt/PPA 例外仍需如实标注。
BYOC 可评估 cloud-init bootstrap，BYOS 保留 SSH 路径，两者共享 preflight/deployment。

**导出与恢复**：按实际能力提供 Hysteria2 YAML、Xray JSON、WireGuard/AWG `.conf`、
Mihomo YAML、sing-box JSON、URI/QR、密钥及完整备份。区分服务端配置和客户端 profile。
备份目标是版本化控制面状态与重建所需文件，包括部署清单、配置/密钥/证书、profiles、
rules、服务器/Provider 元数据和成本；不默认要求整盘快照。
加密格式（如 age）需 ADR；恢复钥匙由用户掌握。先本地导出，iCloud/WebDAV/S3/NAS/
其他云盘作为可选存储候选。支持离线恢复说明及新 IP/域名/证书映射，不能把当前 state tar
回滚称为完整备份或灾难恢复。

**成本**：TCO = Compute + Public IP + Storage + Traffic Overage + Backup + Domain
+ Optional Services + Software License（如适用）。记录币种、计费周期、流量额度与超额单价；
允许未知、手工价格和 Free / Already Owned。家庭服务器可先记录基础设施已拥有，电费是
可选扩展。Provider 价格带来源与更新时间，不能硬编码讨论时的报价为长期事实。
未来提供多节点月/年汇总、使用预测、超额费用和套餐 break-even 比较；已有软件免费不等于
基础设施总成本为零。

## 待决策与当前约束

ADR-001–006 覆盖 Local-first、Protocol Runtime、SSH/Agent、Shared Core Language、
Local State 和 Backup Format；建议及证据见 [仓库审计](repository-audit-2026-10-06.md)。
Rust Shared Core、SwiftUI/NetworkExtension、Flutter+sing-box 都是候选，不能由产品图直接
推导为已接受实现。Apple 系统隧道集成和跨语言共享通过 PoC 评估。
Hetzner、Vultr、DigitalOcean 是第一批 Provider 候选，后续厂商只作为扩展方向，尚未选定。

[#5](https://github.com/EasyIndie/EasyNet/issues/5) 属于 Protocol Runtime / sing-box
演进关联，保留 closed / not_planned 及原有结论；不意味着启动服务端统一迁移。
`wireguard` 目录当前是 AmneziaWG；原生 WireGuard 需要独立能力评估。
现有 bootstrap 顺序和 state-only rollback 的限制由新管理层解决，避免无必要重写。
继续遵守 compat 测试 / balanced 生产约定、真实运行标识不入库、真实客户端配置校验及
手动分流规则构建等项目规则。

MVP 不做中央 SaaS、团队 RBAC、多用户计费、大量 Provider/协议、强制 Agent、
自研 VPN 协议或 AI 自动运维。总 Epic 完成要求涵盖 BYOS、BYOC、运维、退出和恢复；
Phase 1A 成功仅表示技术闭环完成，不能代表完整产品交付。

## 2026-10-09 已接受的调度修订

用户确认、独立架构复核后，GUI-independent Go skeleton/合同 fixture/CI 先按已接受 Go/SQLite 方向推进。
完整 G0 未完成前，仅提前 G1-01.* 本地模型/owned inventory/离线测试和 G1-02.1 fake adapter；
先冻结 successor contract，不直接复制 lab schema/driver。真实 vault/SSH/部署/VPN/签名与完整 client/最终验收 gate 保留。
客户端 reader-phase 诊断最多一个完整工作包、一次 guest 观测；无可行动证据即停止追加诊断，另行评估临时 VM。
全 G0–G6 范围和单次最终 main 合并约束保持。精确依赖和资格以 ADR-004、卡片/binding 为准。
