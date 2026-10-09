# EasyNet 进度复核与推进顺序调整提案

复核日期：2026-10-09；工程基准 HEAD 19d4018。状态：**用户已确认；ADR-004 与入口依赖已修订，逐卡冻结后实施**。
本轮只读取仓库/台账/证据并进行一次有界独立架构复核；未执行新实验或推进产品代码。

## 当前结果与完成边界

已完成通用 AGENTS 结构、Repository Audit/Gap Analysis、handoff 沉淀清理、Epic #13 与 #5 Runtime 关联、演进分支/路线/卡片/模型执行规则。
G0-01–05 限定范围完成；Go 共同应用服务与 SQLite 普通库存已接受。SSH、scoped vault、strict result、JSON/SQLite 故障 PoC 是实现依据，不是生产版本。
客户端框架、VPNEngine、系统权限、签名/分发和 production vault 未选定/未获得资格；Flutter 只是候选。
工程仍未有正式 controller/app scaffold、可用 BYOS 管理闭环、GUI、BYOC 或恢复产品。G1–G6 尚未实施。
所有演进仍在 codex/feature/self-hosted-byos-byoc；main 未合入。完整 G0–G6 验收后才提出唯一最终合并。

| 阶段 | 卡数 | verified | blocked | locked | 当前实质 |
|---|---:|---:|---:|---:|---|
| G0 基线/选型 | 96 | 78 | 8 | 10 | service/store 已选；client 与正式 scaffold 未完成 |
| G1 BYOS 核心 | 52 | 0 | 0 | 52 | 库存、凭据、SSH、预检、计划、部署/导出闭环待做 |
| G2 macOS MVP/恢复 | 38 | 0 | 0 | 38 | 备份恢复、运维、成本、VPNEngine、GUI、发布待做 |
| G3 BYOC | 30 | 0 | 0 | 30 | Provider 选型、资源生命周期、账单待做 |
| G4 扩展 | 24 | 0 | 0 | 24 | 原四协议管理、接管迁移、环境矩阵、Agent 候选待做 |
| G5 跨平台 | 23 | 0 | 0 | 23 | Windows/Linux/iOS、兼容与同步候选待做 |
| G6 基础设施智能化 | 12 | 0 | 0 | 12 | 比较/测量、预算、自动恢复、辅助运维待做 |
| 合计 | 275 | 78 | 8 | 189 | 卡数完成率不是产品完成率 |

78 张 verified 主要属于基线、合同、选型与 PoC；不能据 78/275 宣称产品约完成 28%。

## 当前阻塞与推进成本

自有 sandbox-exec EOF 探针在本机/runner 中出现 SIGABRT；这不是 Flutter 或 Go 应用启动的失败。
an 未取得崩溃归因；ao 新增有界 driver_step，定位到 report；ap 修复助手仍读 an 绑定造成的必然 pre-scan hash 拒绝。
ap 的 record8+driver7 模拟测试通过，修复后的单次 runner [37929861941](https://github.com/EasyIndie/EasyNet/actions/runs/37929861941) 仍 report/unknown。
尚无法区分读取入口、候选选择、解析拒绝、report 谓词或清理前 hash；不推断缺少何种 sandbox 权限。
8 个 blocked 是历史试验/修复链证据，不是 8 个独立产品功能都要重做。应保留历史状态，新的成功资格显式关联 successor acceptance，不逐张“补绿”。
G0-07.1 目前依赖 G0-06.3；客户端路线未接受使正式 Go 骨架和所有 G1 卡均 locked。ADR-004 还明确规定 G0 验收前不进入 G1。
选取 ac/ae/ah/aj/al/am/an/ao/ap 九个窗口，累计非缓存输入 3,022,395、输出 251,597；窗口包含协调、发布尾部、Q&A 和中断恢复，不是纯实验量、受控配对或账单。
这支持停止零散诊断/管理卡增殖，但不能证明主会话或子代理的通用成本胜负。

## 已接受调整：逐卡冻结后实施

1. **core/client 调度解耦**：G0-07.1 只为 GUI/engine-independent Go service skeleton 移除 G0-06.3 前置，保留 G0-04.3、G0-05.3；G0-07.2/3 继续单测/合同 fixture/非发布 CI。
2. **限定提前范围**：在整体 G0 未通过时，只允许冻结 successor contract 后的 ServerTarget 纯模型、owned SQLite inventory、fake adapter 源码与离线测试。不是直接复制 PoC schema/driver，也不是放行全部 G1。
3. **保持验收**：完整 G0 client gate、G1-13 与 G1 最终闭环、G2 VPN/签名/发布保持；提前离线成功不授权真实 SSH、VPS 部署、VPN 或生产操作。不改变 GUI/engine 选型、不删 G0–G6 范围。
4. **一次收敛诊断**：最多安排一个完整 reader-phase 观测工作包：固定有限分类、入口/候选/解析故障模拟、独立 source/hash 审查、一次 guest 观测、结果/用量一起提交。若仍无可行动证据，停止继续追加诊断；转为评估独立临时 macOS VM 的资格/可用性。VM 不代替 sandbox、签名或平台验收，也不默认安装或采购。
5. **任务粒度**：一次一张 ready 卡；源码/模拟测试/有限 runtime/报告/用量放在同一目标内，不为每个检查另开卡。保留输入路径、合同、错误例和定向命令；以一项可验收行为为粒度，不以行数/文件数切碎。
6. **模型与数据**：短机械活由主会话完成；较完整冻结文档 Luna low、小型纯模型 Luna medium、存储并发/凭据/SSH/危险操作 Sol medium；架构/安全必要独立 Sol high，Astra 仅未解决复杂争议。记录主会话+子代理+R+返工+自动审批；未来至少三组匹配成功样本才宣称某路线更省，避免为计量重复实施产品。
7. **文档事实同步**：backlog 中旧的卡数、未推送、语言/store 待选等已更新；模型档位卡数按现台账校对。后续安排单一机器状态源生成摘要，减少手工副本漂移。

独立 Sol high 架构复核：以上顺序调整有条件可行。用户已明确选择按调整方案推进；ADR-004、roadmap/backlog 与入口卡依赖已同步修订。实现卡仍须冻结 binding 和独立核查，不能批量标 ready。

## 确认后的近期执行顺序

| 顺序 | 任务 | 可审查产物/验收 | 模型/约束 |
|---|---|---|---|
| 1 | 接受执行顺序修订 | ADR-004 与执行 gate 文案/依赖同步、保留完整 client/final gates；计划校验通过 | root +独立 R；不直接将 locked 改 ready |
| 2 | G0-07.1→.2→.3 | Go skeleton、合同 fixture、定向测试、feature CI；Bash release gate 保留 | C Luna medium /CI I Sol medium；先冻结精确路径与命令 |
| 3 | G1-01.1 | ServerTarget successor contract 与校验/序列化；未知字段/损坏值明确拒绝 | C Luna medium；纯离线 |
| 4 | G1-01.2→.3a/.3b/.3c | SQLite production adapter 选型/冻结；事务、权限、CRUD、迁移、两目标隔离测试 | I Sol medium +边界 R；owned fixture，不含真实凭据 |
| 5 | client 诊断收敛/环境决策 | 完整有界 reader 观测；最多一次 guest，无有效证据即停止并评估 VM | root/I +R；不盲猜 grant，不采购资源 |
| 6 | G0-06 候选对比→.3 | engine 生命周期、系统权限、签名分发证据与明确候选 disposition，接受客户端 ADR | I/R；先审查候选 B 对 A 的串行依赖是否必要，不先移除 |
| 7 | G1 凭据/SSH/预检/操作状态 | production vault、trust enrollment、上限/cancel/reconciliation、无副作用 collector、脱敏计划 | 完整 G0/其适用门槛后解锁；SSH/vault 不当廉价机械任务 |
| 8 | G1 部署/导出/实环境闭环 | staging/回退、Hysteria2 native profile、真实 compat 测试 VPS 首次/重复部署/掉线恢复/连接 | 保留 G1-13、G1-14 gate；目标/凭据/资格到场后执行 |

上表 core 与 client 为两条工作线，调度仍串行一次一张卡，并非同时开多个子代理。
步骤 4 如缺生产 SQLite driver/迁移合同，只准备并审查合同，不能用 lab adapter 直接完成。

## 后续阶段保持原范围

G1 真闭环后：G2 加密备份与新目标恢复→状态/日志/流量/升级回退/手工成本→engine/GUI→macOS 签名安装更新/卸载与完整 MVP。
G2 后：G3 第一家 Provider 评估/adapter、auth/报价、创建 reconciliation/防火墙、销毁 ownership、账单来源与真实全周期。
G4：Xray/Shadowsocks/AWG 管理适配、原生 WG 明确 ADR、旧安装 opt-in 接管、迁移与目标矩阵、可选 Agent 和 fallback。
G5：共享 API 稳定后 Windows/Linux/iOS adapter、真机/系统生命周期/包/更新与兼容矩阵，可选同步另作 ADR。
G6：费用/额度比较、测量、预算约束恢复、可审阅辅助运维；先手工可恢复再评估自动化。
最后统一验收：原 Bash/metadata v1/四协议回归、失败恢复、退出/数据面独立、秘密扫描、跨平台与成本证据、文档/最终差异审查；全部约定 G0–G6 完成后才提出合入 main。

## 尚未具备的外部条件

GitHub runner 已验证能执行限定 guest workflow，尚未证明满足 GUI/NE/签名/全客户端验收。
本地 M1/8GiB、约39.7GiB 可用盘与约1.8GiB 已用 swap 为前次资源快照，未本轮刷新；重型 SDK/GUI VM 路线需重新评估。
真实测试 VPS、云 Provider 可测账号与预算、Apple 签名/分发及 iOS 真机/其他平台目标等，需要到对应 gate 核对，不臆造已具备，也不提前收集凭据。

## 本次核对

已检查任务状态/phase/dependencies、accepted ADR 和实际 runner/evidence、用量窗口；任务计划结构校验通过。
未重跑未变化的 Bats、平台或 crash 试验；没有新 native/runtime/云操作。提案不是接受证明或解锁权限。

## 用户确认后的落地更新

34e5fe7 正式修订 ADR-004/入口依赖并通过独立 R 审查。a1a3648 完成 G0-07.1 的纯标准库 Go development CLI 离线构建；f53127e 完成 G0-07.2 的格式化检查、版本 fixture 和单测，含 formatter 失败负例。G0-07.3 正在接入非发布 CI。此前表格是复核基线；当前状态以 cards.json 与逐卡结果为准。

新 controller 仅提供 --version，不提供 BYOS/BYOC 操作闭环；客户端与完整 G0–G6 gates 未完成。G1 本地库存仍须独立生产合同审查，不能直接复制 PoC。

G0-07.3 已通过 controller CI 和修复 jq1.8 binding 优先级兼容后两套 Ubuntu Bash/实客户端矩阵（37947832749，release skipped）。G0-07 三卡验收；当前 81 verified、8 blocked、186 locked。客户端门槛仍未通过，完整 G0 未完成；下一入口 G1-01.1 仍须冻结并审查正式本地模型合同。

## 用户确认 G0 优先后的收敛

aq 独立审查已接受（695ffd5）：B 去除等待A签名的串行边但自身资格仍locked，最终ADR显式汇合A/B六卡。ar 最后有界reader工作包源码/17fakes/独立source-runtime-evidence审查通过；source028b737 run37953433995 为directory-guard/unknown，native qualification blocked，诊断预算0。该标记仅是最后进入的步骤（后续clockcheck也可能保留），不能推断具体目录属性/权限/SIGABRT原因，不再新增归因观测。

当前 fresh hardware：8GiB RAM、8逻辑CPU、swap约2.3GiB已用、35GiB可用盘；无VM安装/启动或个人凭据读取。as 正在审查独立环境资格，Apple账号和实际测试目标可用性待用户说明；G0尚未完成。

as 独立环境资格计划已审并接受；278卡中83 verified、9 blocked、186 locked。没有已资格化UI/NE/签名目标，当前硬件快照不能保证VM余量，签名/独立目标可用性待用户回复。接下来可准备B独立source-only合同；不以文档通过冒充GUI/NE/签名或完整G0。

at source preparation accepted: 279 cards, 84 verified /9 blocked /186 locked. User confirms Apple account availability but only current development Mac and GitHub runner; independent VM/Mac not confirmed. Exact native source paths/API/build shape proposed, real UI/NE/signing unqualified. Next freeze one bounded runner GUI admission contract; no further crash attribution.

2026-10-10: au conditional window contract accepted at7009166; 281cards85verified/9blocked/186locked/1ready(av source package). Own-window queued events/rendered-region evidence required; exact feature-source push avoids defaultbranch changes. Current source stage has no runtime grant; toolchain provenance and Cocoa/toolchild/cleanup review remain prerequisites. Full seven client qualification/ADR cards remain locked.

2026-10-10 av checkpoint:281cards85verified/10blocked/186locked. Source900lines independently reviewed, two I repairs; local fullfake6then7 bothexit1 at normalchildcleanup-unproven. No Swift/compiler/GUI/guest, no push. R identifies existingreport loses separate proof predicates; next boundedfailure-envelope contract must distinguish expectedoverflow/timeout from unsafecleanup and precede any newexecution. PaidAppleDeveloper membership confirmed; no credential/Keychain access or qualifiedNE/signing inferred.

2026-10-10 av continuation: checkpoint ab75129 fixes independent bounded cleanup and live sentinel ownership under same-R accepted consolidated contract; exact local9fixturesPASS, stablehashes/emptyroot. Earlier group-KILLpermission failures preserved; installedkernel cause unproved. Counts remain281/85verified/10blocked/186locked because av native identity/GUI qualification stillopen. Next readonlymetadata sourceprep is samecard, no vendorCLI/compiler/GUI/guest execution; workflowdisabled. Whole continuation through19:57:40Z measured559,130noncachedinput/81,518output/cache96.63%, no matchedmain-only costwinner; repeatedreviewfragmentation recognized and consolidated workpackages adopted.

2026-10-10 av metadata checkpoint: same-R SOURCE/effects accepted1557lines after consolidated reader/deadline/refusal and monitor fixes; exactlocal11fixturesPASS/stablehashes/emptyroot/no nativeguest. Conditional identity observation requires reviewed strict binding and activationhash/sourcecommit, workflowstillfalse. Counts281/85verified/10blocked/186locked unchanged. Metadata continuation19:57:40–20:56:10Z measured321,831noncachedinput/121,931output/cache98.16%; highcache, no paired costwinner, material coordination/repair overhead. Mechanical workmain, complete bounded I packages+necessaryR only.

2026-10-10 identity observation: sourcecheckpoint6408dd2 and ONE reviewedpublication9df7792 pushedfeature, standardTests37991083115SUCCESS. Identity37991083138 finitely refused at image/python identity predicate; exactfailedsubpredicateunknown despite matching reportedimage20260907.0337.1. Attemptconsumed, no metadata/nativeGUI qualification/no rerun. Workflow restoredfalse, activebindingarchived. G0 remains85verified/10blocked/186locked (281total); nativequalification/A-Bsixgates/finalADR/signing stillopen. Independent environment qualification and Xcode development-signing configuration required; no newdiagnosticcards/guest or production action authorized.
