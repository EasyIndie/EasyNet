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

2026-10-10 用户环境补充：当前设备为个人自用、无可重置全新 VM；hosted CI 作为环境资格主线，组织凭据可用于签名/公证路线准备。新路线先无密钥基线与实际 A/B 引擎/GUI，再有界 OS/架构兼容矩阵，独立签名/公证/NE验收；本机账户/Xcode登录不再是CI准备前置。旧ar/av失败与预算不重置、不自动复跑；新合同须review/frozen后执行。CLI组织密钥元数据403、仓库列表空不证明组织继承不可用，现待secret名称/用途映射（不索取值）。任务计数与最终 G0–G6/main门槛不变。

Hosted CI 路线与基线静态源码合同已由独立R接受用于准备；五个工作包仍planned，runtime binding/CLI effects/helper资格未冻结。下一步先复用精确已审helper做小固定用途适配，不新建大型bootstrap；缺复用条件先给最小方案与预算，不直接runner试跑。执行者root机械文档+fresh R Solhigh，未运行源码/guest/签名或读取secret值；本轮用量见metrics/hosted-ci-route-preparation.json，非配对对照。

2026-10-10 凭据补充：仓库继承接口与组织设置页均确认 7 个组织 Actions Secrets，
均为 Public repositories 范围。用户确认除 Network Extension provisioning profile 外，
所列签名、公证认证与团队材料均具备；profile 明确缺失，材料有效性与 API 私钥编码处理仍待验证。
详情见 [凭据盘点](poc/client-framework/apple-credential-inventory-2026-10-10.md)。
组织总列表 CLI 403 不再作为材料未知或仓库继承不可用的依据。
用户再次要求推进 G0 完成：先落实无密钥基线的静态准备/复用评估，
按既定合同审查后才执行；不重置旧预算，不将 profile 缺失改为资格通过。

G0 hosted observer 已实施：官方 vendor metadata 观测与不可信候选隔离拆分经独立R接受，
完整候选门槛保持。两次本机初版合成测试5/7，失败原因unknown；local预算0。
自然退出语义修订后，固定source f051f82、activation 2d4806b 的唯一hosted合成验收
[38014394083](https://github.com/EasyIndie/EasyNet/actions/runs/38014394083)全部8tests PASS，
metadata job skipped。synthetic已恢复disabled，guest预算0；这不覆盖engine/GUI/NE/签名，
任务计数与完整G0门槛不变。下一步仅冻结真实metadata观测绑定。

唯一真实metadata观测 [38014757342](https://github.com/EasyIndie/EasyNet/actions/runs/38014757342)
PASS：macOS15.7.9/build24G830 arm64、Xcode16.4/build16F6、SDK15.5；五项均自然child reap/drain/FD闭合。
完整有限记录见 task-results/G0/hosted-metadata-record.json；synthetic skipped，入口恢复disabled，预算0。
这只取得文本版本，不授予toolchain身份/engine/GUI/NE/签名资格。下一工作是冻结候选B的源码/构建与Q-B合同，
不再盲目诊断个人机或旧identity tuple；完整G0依旧未完成。

关闭提交 b64d08c 的 [Tests 38015240881](https://github.com/EasyIndie/EasyNet/actions/runs/38015240881)
全部五个验证 job PASS，release skipped；baseline workflow skipped，两个入口 disabled。
独立 R 准备的 [Q-B compile-only 合同](poc/client-framework/native-build-contract.md)由 root 接受为
静态源码准备：三个实现文件和两个支持文件，真实 SwiftUI 骨架 + 固定直接 swiftc 构建，
无 engine/GUI 执行、无 Apple 凭据。编译工具的 fresh-vendor 信任只限 reviewed inert source；
完整候选隔离/真实 UI/生命周期与 NE 门槛保留。源码已派发 I Sol medium；后续实运行仍须审查精确源码和绑定。

Q-B 源码集中修复后，唯一 local 合成验收 17tests/3failures/0errors（2.477s）：
三个异常组清理用例返回 cleanup，具体失败谓词/原因 unknown；该用例内后续断言未覆盖。
有限记录 native-build-local-observation.json，local 预算0；不运行归因/重试。
独立 R 接受新 fresh hosted 目标方向：同一个 job 必须17tests无失败/错误/跳过且fixture清理通过，
才允许 compile-only；任何拒绝停止，整格仅一次。有限 test 输出与受信 bootstrap 已静态准备，
job仍disabled/checkout placeholder/binding absent，未执行编译器或生成应用。
root 又一次将后续请求以不启动 idle turn 的 send_message 发给完成的 R，造成无效等待；
已改用 followup_task。此为调度错误，必须计入用量，不作为多代理节省证据。

唯一 hosted Q-B qualification [38017582161](https://github.com/EasyIndie/EasyNet/actions/runs/38017582161)
synthetic17/3fail/0errors/0skips、fixture cleanup unknown，gate拒绝，compiler未运行。
与local计数相同不证明失败case或原因相同。标准 [Tests38017582571](https://github.com/EasyIndie/EasyNet/actions/runs/38017582571)
PASS。入口关闭、inline binding清空、runtime binding consumed，guest/local预算0。
R指出可静态确认的独立缺陷：异常组信号失败会跳过直接child wait/reap；root已准备拆分收尾与mock回归，
18-case successor未执行，不是hosted失败归因或资格通过。下一运行必须审materially corrected source/
精确binding与目标，不能沿用消耗的17-case授权。Q-B编译/.2d继续blocked，完整G0未完成。
01:58–02:38:41Z工作包用量330,680非缓存input/65,115output，cache97.68%；含主会话协调、I/R与自动审批，
后续关闭工作未计入。见 metrics/native-build.json；无配对main-only验收样本/账单，不能证明多代理更省。

2026-10-10 用户继续授权后，独立 R 冻结有界 capture successor：TERM后EOF先wait、只在
明确持有身份且超时后KILL；逻辑 swiftc argv0 与canonical散列路径分离；有限失败字段。
Darwin identity/absent只可在已审无fork溢出/独立owner的负例条件下验证“明确拒绝”，
不是positive group/engine/GUI containment通过；真实编译若发生该拒绝仍失败关闭。
跳过reap mock 1/1先通过；集中两文件修复后，唯一新命名local18目标全部18/18 PASS，
0fail/errors/skips，fixture cleanup passed，137bytes输出；记录 native-capture-successor-local-record.json。
该目标额度已消耗，旧17/ar/av额度保持0；下一步仅冻结新source SHA后的hosted18→compile绑定。

唯一 successor hosted [38030751354](https://github.com/EasyIndie/EasyNet/actions/runs/38030751354)
18/18PASS，0fail/errors/skips，fixture cleanup passed；标准 Tests38030751360PASS。
compile preparation 在固定command4（xcrun SDK版本查询）timeout，exit-15，0bytes；
直接child已reap/drain/FDclose，generated cleanup removed，compiler/sdk/artifact null。
5s metadata预算仅留1s工作、4s收尾；为何该查询未在1s完成未知，不认定编译器编译失败。
有限记录 native-capture-successor-hosted-records.json；入口禁用，successor guest/local均0，
旧native-build binding仍consumed0；无应用/engine/GUI/NE执行，G0仍未完成。
03:24:19.581–06:25:14Z本包545,458非缓存input/37,357output，cache94.80%，
含root/I/R及自动审批，关闭工作未计入；metrics/native-capture-successor.json。
未有配对main-only样本/账单，不能断言多代理更省；机械动作留root，限制重复微粒度评审。

固定 metadata 期限修订为14s（10swork+4scleanup），compile120/whole180不变；
源码6c587437，activation5469afd0经精确集中R复核；无重复local测试。
唯一新目标 [38031125723](https://github.com/EasyIndie/EasyNet/actions/runs/38031125723)
synthetic18/18PASS；查询0–8及实际SwiftUI编译command9全部exit0/reap/drain/FDclose。
Swift6.1.2、SDK15.5；随后artifact validator拒绝，具体谓词unknown，artifact=null，cleanupremoved。
有限记录 native-metadata-deadline-hosted-records.json；常规Tests38031125733PASS，
新入口关闭/额度consumed0。应用未启动，GUI/engine/NE未执行，完整构建与G0资格仍未通过。
费用统计扩展到06:31:56Z，覆盖两次hosted及期限修正；更新metrics/native-capture-successor.json。
无相同任务单会话对照，不能用缓存或不同结果工作包宣称多代理费用优势。

2026-10-10 新artifact-predicate工作包：C/Luna medium按冻结小函数方案实现，
R静态拦截了section打包/命令计数/方法名/期望编号错误；同C修正后遗漏的三个pack参数
由root按明确R指示机械补齐。未执行错误版本，扩大testcap至445保留覆盖，不能用此返工宣称省钱。
唯一pureartifact方法1/1PASS（0.227s、198bytes），固定字段保持所有validator条件；
新增sectioned/zerofill及VM/file边界合成覆盖。源码41acd18、activation04a1244经集中R绑定审查。
唯一 [hosted38032893036](https://github.com/EasyIndie/EasyNet/actions/runs/38032893036)
18/18PASS；查询/实际compile全部exit0，artifact明确拒绝于build-fields联合谓词，
具体platform/minos/sdk/tool-count字段仍unknown；cleanupremoved，app/GUI/engine/NE未执行。
有限记录artifact-predicate-hosted-records.json；常规Tests38032893069PASS。
入口false/inline空，artifact新grantconsumed0，所有旧预算0，G0和完整构建资格仍未通过。
06:46:00（起点按分钟取整）–07:02:50Z用量251,677非缓存input/42,147output，cache97.37%，
包含root/C/R/自动审批；截止后格式审查与关闭另计。metrics/artifact-predicate.json。
无配对main-only/I实现样本或账单，不能认定节省；Luna限冻结字段适配，
复杂二进制fixture交I或由R冻结完整字节结构，减少低档模型反复构造。

针对build-fields，R核对Apple Mach-O定义/公开ld写入实现，未证明校验格式有误；
真实失败field仍unknown。root按冻结机械方案新增artifact_build_mismatches四固定bool，
保留所有require；合法n0/n1及platform/minimum/sdk/length单项拒绝合成覆盖通过，
唯一local-artifact-build-map-v1 1/1PASS（~0.215s、198bytes），额度consumed0。
源码/测试/合同591/455/212，精确hash经R审；未再运行hosted/compiler/full18。
费用更新到07:09:51Z，完整用量metrics/artifact-predicate.json；后续关闭不在截止内。
下一真实字段资格需另行冻结reviewedtarget，不能恢复旧预算；G0/GUI/engine/NE/签名仍保留。

四bool字段观测的独立一次性grant经精确R审：源码292af6fa、activation36e484f9；
新目标 [38033726243](https://github.com/EasyIndie/EasyNet/actions/runs/38033726243)
hosted18/18PASS，实际compileexit0；明确sdk:true，其余platform/minimum/length:false。
只证明SDK标记不等于合同15.5.0，真实标记值和产生原因未知，不能猜patch/SDK0或其他版本。
cleanupremoved，入口禁用/inline空，新archiveconsumed0；标准Tests38033726249PASS。
有限记录artifact-build-map-hosted-records.json；未启动app/GUI/engine/NE，构建及G0资格未通过。
费用统计扩展到07:17:21Z；截止后SDK来源审查/关闭另计，metrics/artifact-predicate.json。
下一步只针对SDK版本产生链静态审查，不能强制标记15.5以制造通过或盲目重编译。

2026-10-10 SDK语义证据工作包：root按冻结范围直接实现，独立R审查；
保持原SDK15.5.0校验/四项mismatch/argv，新增有限major/minor/patch诊断。
唯一local-sdk-semantic-v1 1/1PASS，0.233s，所有新旧local额度0；无本机编译。
源阶段观察窗10:13:00–10:23:38Z（起点取整，关闭与hosted准备另计），
metrics/sdk-semantic-source-usage.json：root Sol medium与R Sol high，
未缓存输入261396、输出13674、总输入缓存命中92.89%。包含主会话首次
169191输入/24320缓存的上下文恢复成本；不能仅把主会话编码成本与worker比较。
该任务与此前Luna二进制fixture工作不同，未形成配对实验，不能宣称哪条路更省。
下一步是精确冻结一次hosted18→conditional compile，读取SDK语义实际值；
GUI/engine/NE/签名/最终G0均仍未验收。

SDK语义一次hosted观测已结束：sourceffcb6cf、activationcf22191，
[38044984525](https://github.com/EasyIndie/EasyNet/actions/runs/38044984525)
full18PASS、compileexit0；SDK标记实际15.0.0，仅sdk mismatch。
artifact仍null/cleanupremoved；未启动app/GUI/engine/NE，不能通过Q-B构建资格。
有限结果sdk-semantic-hosted-records.json；新archiveconsumed0，入口禁用且inline空。
标准Tests38044984594PASS。实际数字不能单独证明链接器原因；
下一步审查已验证版本化SDK路径的保留方案，禁止强制标记或降低原15.5.0校验。
全链路用量记录sdk-semantic-total-usage.json截止10:29:51Z，关闭/后继准备另计；
主会话与独立R，无实现worker；仍无同任务配对，不能认定单会话更省。

已验证版本化SDK路径差异：sourcec321567、activationc164fb3，
[38045574643](https://github.com/EasyIndie/EasyNet/actions/runs/38045574643)
full18PASS、compileexit0，明确argvSDK为MacOSX15.5.sdk但artifact仍15.0.0，
仅sdk mismatch；路径拼写差异未解决，不据此确认原因、不降低15.5.0校验。
定向local-sdk-logical-path-v1 1/1PASS（0.229s/201bytes）；local/guest均consumed0，
入口禁用/inline空；有限结果sdk-logical-path-hosted-records.json。
标准Tests38045574663PASS；GUI/engine/NE/签名/最终ADR和完整G0未通过。
下一张仅官方Swift6.1.2 producer源码事实收集，Luna medium，限定查询/文件预算；
不继续盲目编译，可能的print-jobs需另外冻结有界合同后才能执行。

SDK参数计划阶段：source3f0f0bd/activationdb46def，
[38048229650](https://github.com/EasyIndie/EasyNet/actions/runs/38048229650)
full19PASS，命令0–9全部exit0/reap/drain/FDclose；计划命令stdout2692/stderr0，
但解析拒绝plan-format，driver_jobsnull、artifactnull/predicatenotrun，cleanupremoved。
未启动app/GUI/engine/NE，未执行后续编译；SDK原因与构建资格未解决。
新local-sdk-driver-jobs-v1 1/1PASS（0.253s/188bytes）；全新旧预算consumed0，
入口禁用/inline空，有限记录sdk-driver-jobs-hosted-records.json；标准Tests38048229588PASS。
源码修正涵盖授权类型、残缺wrapper、目录完整性失败不可被重取快照覆盖；
mocked正常计划/篡改失败fixture纯自有目录/无工具，原18方法不变+1方法。
官方tag Options证实独立target-sdk-version语法与现有宽target前缀冲突，
尚缺tag frontend生成来源，不能将该静态冲突认定为真实失败参数；没有新runtime grant。
成本记录更新至11:26:11Z：sdk-progression-usage.json，整体缓存97.28%，
包括root/C/I/R/自动审批、草案预算回退、修正与中断；不是配对A/B或账单。

2026-10-10 SDK frontend 静态修复（主会话机械实现、同卡独立R整包审查）：
只让 frontend 精确消费独立 -target-sdk-version 参数，保留所有未知前缀/包装形式拒绝、
现有输出语义与SDK equality。原18测试 AST不变，仍19方法；新正反例在同一方法内。
唯一 local-sdk-frontend-metadata-v1 1/1PASS（0.394s/194bytes），无失败/错误/跳过，
fixture cleanup passed；local/guest额度0。未执行compiler、full19或新的hosted。
审查与有限结果分别为 sdk-frontend-review.md / sdk-frontend-local-record.json。
该静态缺陷与真实 plan-format 失败 token 的因果联系仍未证实。

下一步顺序调整仅针对缺失证据，不改变 G0 范围或放宽验收：

| 顺序 | 可执行交付与解锁条件 | 执行模型 |
|---|---|---|
| 1 | SDK producer 合同依据：定向取回 tagged Darwin linker source，追踪SDK路径/版本来源；区分输入SDK身份与Mach-O声明。先静态事实与合同审查，禁止继续无证据print-jobs guest | C Luna medium有界事实，R Sol high关键取舍 |
| 2 | 依据接受的SDK语义决定准确构建合同及必要测试；只有具体修正/全包source审查后才评估新运行资格。输入hash或SDK版本查询不能单独解释产物标记 | 短冻结修正root；复杂解析I Sol medium |
| 3 | 候选B实际GUI/engine完整工作包：真实窗口→Connect/Cancel/Stop/Restart→loopback nonce及故障/回收矩阵；前置构建、目标身份与效果保护均须通过。A独立前置仍保留 | I Sol medium完整包、R一次边界审查 |
| 4 | 独立签名/公证准备：组织名称映射、API密钥编码、Developer ID资格、临时Keychain清理、可信SHA/产物摘要；材料只在接受的job中使用，缺NE profile单列 | I Sol medium、R凭据/权限审查 |
| 5 | 各候选权限/系统VPN与签名真实验收→G0-06.3最终ADR处置→汇合G0-01–07。NE profile、系统同意及真实路由/DNS验证不可由代理模式或公证替代 | I/R；需要人工系统同意时单独说明 |

目前不能把测试声明数、准备卡通过率或编译exit0换算为G0完成百分比。
后续模型策略继续以全链路数据为依据：主会话处理短冻结修正，C只读事实，
I完成有界实现，R集中审查关键边界；不为纯台账再生成子代理，不反复新建同卡实现者。

Frontend三项SDK元数据完整源码修复已独立审查；唯一local-sdk-metadata-set-v1
1/1PASS（0.401s/189bytes）、零失败/错误/跳过、cleanup passed，额度consumed0。
源码690/589/245行，原18方法不变；未重跑full19/compiler/guest。
进一步定向读取tagged Jobs目录后发现最初链接器文件实际存在：加号编码为%2B的
Contents请求成功，早先404不能证明文件缺失。tagged链接实现传递 --sysroot
而非先前参考main分支的-isysroot；现parser缺这一SDK语义分类，是下一张明确源码修正卡。
该事实不证明真实plan-format失败token或SDK15.0原因；不恢复旧运行额度。

--sysroot共享SDK类别覆盖修复已exact整包R审查，唯一local-sdk-sysroot-v1
1/1PASS（0.392s/184bytes）、零失败/错误/跳过，cleanup passed，binding consumed0。
原18方法不变；源码690/596/245行。当前三个定向puremock结果不代表新源码full19或
hosted已通过。SDKparser源码工作包到此收敛，不继续逐参数guest；后继只按完整SDK
元数据/链接产物合同包推进。所有workflow禁用/inline空，无新compile/app/GUI/engine/NE。
成本统计窗口更新到11:51:06Z，含上述事实定位、三次主会话修复与独立审查；
截止后本段收尾/提交另计。仍未形成配对对照，不宣称主会话或多代理费用胜出。
G0最终剩余仍为：准确构建资格、候选A/B真实UI/engine、各自权限/签名、NE profile
与系统同意/路由DNS实证、客户端ADR与G0汇合；当前完整G0没有通过。
