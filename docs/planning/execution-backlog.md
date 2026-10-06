# EasyNet 分阶段可执行推进清单

研究日期：2026-10-06。代码基线：`1d288dc747862486c930d5d21042b3fc4339e16f`。
总目标关联：[Epic #13](https://github.com/EasyIndie/EasyNet/issues/13)。

本文是当前推进工作包的主清单；低成本执行粒度见 [小任务目录](atomic-task-catalog.md)，
168 个原条目已展开为 [220 张独立任务卡](task-cards/README.md)，每卡带模型档位与解锁条件。
任务卡与长期 feature 分支规则见 [执行规范](agent-execution-policy.md)。
产品愿景见 [演进计划](product-evolution-roadmap.md)，
能力映射见 [仓库审计](repository-audit-2026-10-06.md)。任务 ID 为文档标识，不是 GitHub
Issue 编号。所有工程任务尚未实施；不因列入清单而视为技术决策已接受。
当前只存在总 Epic，本轮未创建子 Issue、修改外部 Epic 或启动部署。

## 1. 当前状态与研究结论

仓库仍是 Bash 服务端部署工具，尚未成为远程基础设施管理产品。当前代码没有新增
controller、SSH transport、桌面工程、Provider SDK 或加密恢复实现。
通用 Agent 指引及规划文档在本地工作树中完成，尚未提交/推送，不能当作 main 已交付。
研究时（2026-10-06）的 GitHub 查询发现 open Issue 为 #13，无 open PR；#5 保留关闭状态与 Runtime 关联。

| 能力 | 当前可复用证据 | 需要补齐的具体工作 |
|---|---|---|
| 服务端生命周期 | `scripts/deploy.sh`、`scripts/install.sh`、`scripts/easynet` | 远程计划、操作身份、并发锁、断线后查询与恢复；区分升级版本、安装完成和健康验收 |
| 插件与运行时 | `core/discovery.sh`、`protocols/*/manifest.sh` 和 deploy/export/uninstall | protocol/runtime/capability 合同；不能把目录 wireguard 当作 native WireGuard |
| 预检 | `core/validate.sh` 检查 OS/tools/domain/manifest 默认端口 | 当前 `deploy.sh:407` 后先 bootstrap，再 module preflight；新只读 probe 必须先于安装器与系统改动 |
| 状态 | `core/metadata.sh:13` 写 JSON 后 chmod；另有独立 validate | 原子写、版本/权限/可信路径校验；本地库存、vault 引用、操作日志与远端事实分离 |
| 配置生成 | URI/QR、Clash、sing-box；Hysteria export 为 metadata | native client YAML；不能混淆客户端 profile 与服务端配置；字段按 pinned runtime 验证 |
| 日志 | `core/logging.sh` 只做格式化；Hysteria `show_config()` 输出完整 URI/QR | 远程自动化专用输出策略；普通日志不得带密码、URI、订阅路径或二维码内容 |
| 安装与升级 | release tar/checksum、install-only、保留 `.env` | `install_package()` 删除旧目录再移入 staging，不构成完整事务/可恢复切换；记录旧版本与失败恢复点 |
| 恢复 | `deploy.sh` 的 state tar backup/rollback | 实际配置/密钥/证书/单位文件及重建清单；不能用 hub symlink 或 state-only tar 代替恢复包 |
| 客户端 | Linux sing-box installer、`client_check.sh` | macOS 连接生命周期、平台集成、发布；pins 有 darwin amd64，尚无 darwin arm64 校验覆盖 |
| 测试与发布 | 34 Bats 文件、465 test 声明；Ubuntu 双版本 CI、真客户端发布 gate | controller/SSH/状态/故障恢复/macOS/provider 测试；声明数不是实际通过数 |
| 云与成本 | 暂无 ProviderAdapter/本地计费模型 | API action reconciliation、资源所有权、账单单位/币种、流量可信来源及失败清理 |

前一轮本地 fast suite 444 项、0 失败、5 跳过，ShellCheck 通过。本轮仅文档研究，
没有重复运行未变更的测试，也未确认远程最新 CI 成功或操作真实 VPS。

主要结论：以“保留 Bash 后端，新增本地应用服务与兼容适配器”推进。第一条闭环复用
Hysteria2；不同时迁移服务端内核、扩展多协议、选择多个 Provider 或实现 GUI。
控制器使用何种语言应以 SSH/vault/平台集成 PoC 和维护成本为依据。

## 2. 执行规则与任务格式

每行包含工作包、落点/交付物、前置任务和可验证完成条件。工作包可对应一个 Issue，
内部按小任务 commit 或向演进分支的局部 PR 拆分。仅最终全部完成后向 main 合并；
阶段验收不触发 main 合并。依赖全部验收后才启动
有副作用的下游任务。文档中的 `controller/`、`contracts/`、`apps/` 是候选落点，
G0 决策后再创建，不先建空壳目录或固定语言。

状态采用 `planned → ready → active → verified`；阻塞记录原因、负责人及解除证据。
当前各项为 planned。负责人按角色描述，不虚构人员指派；开发/审查/实机验收角色可由
同一维护者承担，但验收报告必须独立记录目标、版本、证据与失败条件。

难度 S/M/L 分别表示局部改动、跨模块能力、外部系统/平台集成；不代表日期承诺。
到 G1 实测后才估算排期，先记录实际耗时和返工原因。无需为后期功能提前冻结细节。

## 3. G0：工程基线与关键决策

目标：明确可兼容的实现路线并排除平台交付阻塞。负责人：架构/维护者；Apple PoC 由客户端角色负责。

| ID / 难度 | 任务与交付物 | 前置 | 完成条件 |
|---|---|---|---|
| G0-01 / S | 将 AGENTS、CLAUDE 兼容入口、planning 文档和 README 导航作为文档 PR 收敛；登记 #13 | — | 文档进入可审查分支；无 handoff 残留依赖；不混入运行标识；文档只进入长期演进分支；最终合并前不得标 main 已完成 |
| G0-02 / M | 制作能力矩阵和 fixture：Ubuntu 24.04/26.04、root/sudo、首部署/既有 EasyNet/外部服务、amd64；ARM64 单列待验 | 01 | 每种组合有 supported/unsupported/unknown 状态与测试方式；记录现有 compat/balanced 行为 |
| G0-03 / M | ADR-001/002/003：应用服务边界、Bash 兼容执行、SSH-only；定义 ServerTarget、ProtocolRuntime、Profile、Operation、错误码与事件格式 | 02 | 示例 JSON/合同覆盖两服务器、原生 runtime 与 unsupported 方法；CLI 与 GUI 使用同一应用服务 |
| G0-04 / L | ADR-004 控制器语言 PoC：先对 Rust、Go、平台原生方案做维护/库/打包比较，再取前两项实现同一 SSH+vault+结构化结果样例 | 03 | 用同一任务验证 key auth、取消、host key、安全存储与 macOS 打包；记录选择/放弃原因；不重写 Bash |
| G0-05 / M | ADR-005 本地 store 与 operation journal：JSON/SQLite 的事务、锁、迁移、vault 引用、远端 reconciliation | 03 | 断电写入、双进程写入、未知 schema、新旧版本读取策略明确；选定最小实现 |
| G0-06 / L | 提前做 macOS 隧道发布 PoC；比较现有 Flutter/sing-box 候选与 SwiftUI/原生候选，确定连接 engine 与分发路径；新增客户端 ADR | 03；可与 04/05 同期研究 | 在目标 macOS/芯片验证 engine 启停、隧道或代理模式、权限/签名/entitlement、分发约束；不能仅“运行了一个二进制”就宣称系统 VPN 可交付 |
| G0-07 / M | 新控制器工程最小 scaffolding/CI：选定语言、格式化、单测、contract fixtures、dependency pin、macOS 构建 | 04,05 | 不改现有 Bash release 流程；新工程构建/测试通过；执行路径与 server easynet 命名不冲突；feature push/PR 测试触发且不发布正式 release |

**Gate G0**：03–05 已接受且 06 有可行路线；07 可构建。Backup ADR 到 G2 冻结，不作为
SSH/预检开始前的大而全门槛。Provider/Agent/所有平台无需此时选型。

## 4. G1 / Phase 1A：Existing VPS 管理闭环

目标：本机导入一台既有 Ubuntu VPS，可信 SSH → 只读检测 → 审阅计划 → 部署 → 原生导出。
负责人：controller/服务端开发；fixture 自动测试由测试角色负责。

| ID / 难度 | 任务与具体落点 | 前置 | 可验证完成条件 |
|---|---|---|---|
| G1-01 / M | 实现 ServerTarget/ExistingServer 本地库存；controller model/store，credential 仅引用 | G0-07 | 两目标 CRUD/重命名/端口配置相互隔离；迁移、原子写、权限和损坏数据错误有测试 |
| G1-02 / M | CredentialStore + macOS vault；SSH key/agent 引用、取用、删除；inventory 导出不携带 token | G1-01 | 无交互 agent auth 可用；vault 锁定/缺失可处理；自动化错误不回显秘密 |
| G1-03 / L | SSH transport：host trust 独立 store、首用指纹展示、changed-key 拒绝、超时/cancel、退出码/stdout/stderr 限制 | G1-02 | 假 sshd 集成覆盖未知/已信任/变更主机 key、网络断开、错误 key、取消；禁止 StrictHostKeyChecking=no |
| G1-04 / M | 权限与上传通道：root/明确 sudo policy，安全临时目录、权限 600 `.env`，命令参数与 hostname 校验、路径 allowlist | G1-03 | 无 sudo、sudo 需密码、磁盘不足、危险参数、传输中断均可恢复；密码不出现在 argv；不启用宽泛任意命令 sudo |
| G1-05 / M | 新只读 preflight collector（候选 `scripts/preflight.sh`）；无 jq/apt 前提也能收集基础事实，controller 解析报告 | G1-04 | OS/systemd/资源/现有服务/listener/DNS/权限/防火墙事实带时间、来源、unknown；失败不调用 apt/写配置/改防火墙；敏感读权限失败不伪装成功 |
| G1-06 / M | 选定协议 compatibility evaluator：effective ports + TCP/UDP、域名/TLS、UDP 外部可达的验收策略、既有安装 ownership | G1-05 | 80/443 占用、UDP 未知、证书不匹配、外部 Nginx/Xray 均明确阻塞/提示；不以静态 manifest 默认端口替代实际监听 |
| G1-07 / M | Operation state machine、remote lock、operation ID 与事件日志；幂等请求、断线查询、cancel 请求与远端状态区别 | G1-01,03 | 同目标第二操作拒绝/排队；重连先查询，不能重复 bootstrap；CLI 退出不等于远端操作已取消；crash fixture 可恢复 |
| G1-08 / M | 脱敏及自动化输出模式：`logging.sh`/协议 show_config/`easynet deploy` 相关路径；进度日志与 secret profile 通道分开 | G1-04,G0-03 | URI/auth/obfs/订阅路径/QR/vault key 不进入普通日志或报告；保留交互式显式导出能力；测试恶意错误中嵌入 secret 的情况 |
| G1-09 / L | DeploymentPlan + BashDriver：复用 deploy/discovery/env_file；列出 apt upgrade、UFW、cron、Edge、TLS、service 操作及 ownership；计划失效检测 | G1-06,07,08 | 执行前重新检测关键事实；审批绑定目标/plan hash；既有非 EasyNet 文件不静默覆盖；旧 CLI 仍可用；不把 precheck 开关当独立 gate |
| G1-10 / M | release staging：锁定 tag/checksum、安装版本记录、env 保留、install-only 使用与恢复边界 | G1-09 | 下载错误/hash mismatch/中断安装均不伪报成功；安装与部署事件可区分；记录可恢复前一目录，避免先删旧安装再失败 |
| G1-11 / M | Hysteria2 driver：原生 install/configure/health/export/restart；复用 secret preservation 与 TLS Edge hook | G1-10 | 重部署 key 不轮换；参数变更才触发预期重启；服务 active 与客户端真正连接分开判断；port hop 云侧端口要求明确 |
| G1-12 / M | Native Hysteria2 client YAML + export bundle；复用 metadata/URI/Clash/sing-box，新增 protected profile exporter | G1-11 | auth/TLS/SNI/salamander/port-hop 与 pinned runtime 一致；无 insecure 默认；文件 600；无 manager/subscription 在线依赖 |
| G1-13 / M | Native 配置实运行验证与 macOS arm64 checksum/caching 覆盖；扩展 client_check/CI 而不冒充已有命令 | G1-12；macOS 路线 G0-06 | 对选定 runtime 检查其真实验证方式；无 check 子命令时使用隔离启动/握手 harness；坏字段失败；macOS arm64 不静默 skip 为通过 |
| G1-14 / L | Application-service CLI/harness 与 SSH→deploy→export 端到端；本地 SSH fixture + 专门验收 VPS | G1-01–13 | 首部署/重复部署/掉线恢复/旧安装读取/失败预检无修改；真实 UDP/TLS 连接及四模块 compat 回归；生成脱敏证据报告 |

**Gate G1**：不仅能生成 JSON，必须通过真实 profile 连接；关闭 controller 后服务器和独立
客户端继续运行。对不支持目标提前失败。自动化不能误覆盖无归属安装。验收主测试环境仍用
compat；single-protocol slice 用单独临时目标或隔离测试，不替换既定测试环境策略。

## 5. G2 / Phase 1B：恢复、运维、成本与 macOS MVP

目标：用户拥有可用的本地管理产品，并能在服务器丢失后恢复。负责人：controller、客户端、测试角色。

| ID / 难度 | 工作包与交付 | 前置 | 可验证完成条件 |
|---|---|---|---|
| G2-01 / M | ADR-006：备份版本/加密/恢复钥匙/文件 allowlist/manifest 与运行配置映射 | G1 Gate | 明确 `.env`、runtime keys/certs/profiles/rules、state/cost；排除任意路径与默认 provider raw token；恢复顺序与版本兼容明确 |
| G2-02 / L | Encrypted backup exporter + inspector；复用 FHS 实际文件，不打包 hub symlinks | 01 | 完整性、wrong-key、tamper、超大 payload、路径穿越/symlink 测试；备份期间状态一致；无明文残留/日志泄漏 |
| G2-03 / L | RestorePlan + 新目标恢复：校验→read-only preflight→原生重建→endpoint/cert 映射→health | 02,G1-09 | 空白另一 VPS 真实恢复成功；不能复用旧 host fingerprint；新域名重签证书/更新 profile；明确需重新连接的客户端 |
| G2-04 / M | 远程 status/log/restart：复用 easynet/monitor/audit；稳定 JSON report、超时与部分失败 | G1 Gate | stale/offline/permission denied 分开；tail 日志有大小限制/脱敏；运行状态与连通性区分 |
| G2-05 / M | Traffic collector：接口/进程或 runtime counter adapter，采样/重启 reset/时间窗口 | 04 | 明确“主机流量/协议流量/Provider 计费流量”来源差异；计数器重置不出现负数；未知不填 0 |
| G2-06 / L | Verified upgrade + failure recovery：上一版本记录、配置检查、候选切换、健康失败回退/人工恢复步骤 | 03,04,G1-10 | 同服务器 upgrade 保留 secrets/sub prefix；注入新版本不可启动故障，可回到已知版本和配置；不声称可自动撤销 apt 全局升级 |
| G2-07 / M | Cost model + 手工 ExistingServer TCO：price/currency/cycle/allowance/overage/free/owned/unknown | G1-01 | 单位/周期与额度边界测试；金额 decimal 或最小货币单位；多币种不直接求和；未知不显示免费；无 provider 定价硬编码 |
| G2-08 / M | VPNEngine application service：profile store、connect/disconnect/status、系统路由/DNS生命周期 | G0-06,G1-13 | 原生可用 engine 实现；sleep/wake、网络切换、重复 connect、异常终止可恢复；明确 proxy mode 和全设备 VPN 区别 |
| G2-09 / L | macOS GUI：Server import/trust/preflight/plan/deploy、profile、operations/cost/export/backup/restore | 03–08 | 所有 UI 调用应用服务；异常任务可查看/retry；列表不展示 secret；用户可完成完整 BYOS 流程；GUI 没有另一份部署逻辑 |
| G2-10 / L | macOS 发布与完整 MVP 验收：签名/分发包、update/rollback、最小系统/芯片矩阵、安装/卸载手册 | 09 | 干净用户环境安装、首次信任/权限、连接/断开、备份/恢复通过；卸载本地 manager 不误删除 VPS；旧 Bash release 保持可用 |

**Gate G2**：BYOS 从导入到连接、运维、导出、跨服务器恢复全部可用；手工成本可解释。
离线意味着不依赖中央控制服务，不意味着 controller 离线时仍可 SSH 管理远端。

## 6. G3 / Phase 2：最小 BYOC 与真实成本

目标：第一家云厂商完整生命周期，而非同时完成三家 SDK。负责人：Provider/controller 开发。

| ID / 难度 | 工作包与交付 | 前置 | 可验证完成条件 |
|---|---|---|---|
| G3-01 / M | Provider 选型 ADR：Hetzner/Vultr/DigitalOcean 候选的 API、可用地区、账户可测试性、账单来源、IPv4/流量、权限范围 | G2 Gate | 官方资料和实际可测试账号条件形成评分；选择一家；价格仅为带日期的数据，不作为固定产品常量 |
| G3-02 / M | ProviderAdapter contract + fake provider：pricing provenance、ServerTarget、resource ownership、异步 action/errors | 01,G0-03 | fake adapter 覆盖成功、限流、超时、认证失败、部分创建；上层不引用厂商字段 |
| G3-03 / M | 第一家 discovery/auth/pricing：本地 vault token、regions/plans/price/IPv4/allowance/overage | 02,G2-07 | least-needed scopes，token 缺失/过期处理；价格有币种、时间、税/附加项说明及过期状态；不可用套餐不能创建 |
| G3-04 / L | Create + reconcile + cloud firewall + SSH readiness/cloud-init；operation IDs/labels/资源账本 | 03,G1-07 | timeout 不盲目再次创建；查找已建立资源后继续；控制台人工确认 SSH 指纹或可信 provisioning 通道，不跳过信任；清理仅本操作拥有的资源 |
| G3-05 / M | Quote/DeploymentPlan UI：预计 TCO、需购买的资源、创建→preflight→deploy→connect | 04,G2-09 | 上层复用 SSH/BashDriver；用户看见 IP/backup/overage 成本；报价与新状态变化重新计划 |
| G3-06 / L | DestroyPlan/撤销与孤儿资源清理：选择目标、备份、billing 状态核对 | 04,G2-03 | 明确服务器 ID/Project；外部资源不可删；失败/延迟删除可查询；本地状态移除不等于云实例已销毁 |
| G3-07 / M | Provider usage adapter + forecast：billing cycle、缺失采样、额度/预测/过期价格、multi-node TCO | 03,G2-05 | 本机流量不能直接冒充账单；明确 forecast 为估计；稀疏数据不给伪精确数字；多币种有显式汇率来源或不合计 |
| G3-08 / L | BYOC 真实账号全周期验收与成本对账；必要时再选择第二家验证抽象 | 05–07 | create→deploy→connect→backup→restore→destroy；限流/取消/断网恢复不重复计费资源；检查资源清单及账单来源；第一家通过前不启动第二家 |

**Gate G3**：达到 Epic BYOC 核心目标；一家公司已足够验证产品能力。真实创建/删除是后续
具体执行任务，当前计划不触发扣费或销毁。

## 7. G4 / Phase 3：协议、迁移与可选 Agent

目标：已有成熟后端可被安全管理、退出和迁移。负责人：协议/服务端/controller。

| ID / 难度 | 工作包与交付 | 前置 | 可验证完成条件 |
|---|---|---|---|
| G4-01 / M | Xray/Reality + Shadowsocks Driver：复用 deploy/export/render；补 native profile/health/upgrade 合同 | G2 Gate,G1-09 | 实际 transport/client 能力匹配；不得静默把 XHTTP→TCP 降级称为等价；各模块实客户端连接和兼容回归通过 |
| G4-02 / L | AWG 管理适配及 native WG 决策：分离 runtime IDs，保留 AWG kernel/PPA 边界；原生 WG 为单独 driver 候选 | 01,G0-02 | AWG 原生 conf 实连接；不输给不兼容客户端；未实现 native WG 时明确 unsupported；新增 WG 需独立 PR/矩阵 |
| G4-03 / L | 既有安装 read-only scanner + opt-in adoption；EasyNet 自有安装优先，第三方按 runtime 分批 | G1-06,G2-03,01 | detect 不等于可接管；预备备份/ownership 明确；自定义 systemd/外部 nginx/未知格式不覆写；撤销接管仍能运行 |
| G4-04 / L | 迁移 workflow：新目标部署/恢复、临时双端、native profiles 更新、切换与旧目标退役计划 | G2-03,G3-06,01 | 新端真实连接后才退役旧端；保留原端回切；DNS/TTL/证书/凭据变化显式；不会复制旧 SSH 信任到新主机 |
| G4-05 / M | 扩展 ServerTarget 支持矩阵：Debian/ARM64/VM/家庭机器；NAT/公网无 UDP/无 systemd 等分类 | G1-05,02 | 每个宣称支持的组合有集成报告；不能仅“能 SSH”就判可部署；无法连接公网时给出限界/替代模式，NAS 后续逐型号验收 |
| G4-06 / L | Optional Agent ADR/PoC（仅证明 SSH 存在明确不足时实施）：mTLS、权限、credential rotation、API 版本、卸载 | G2 Gate,G0-03 | 对比 SSH-only 收益；Agent restart/uninstall不影响后端；API 未认证请求拒绝；仍有 SSH rescue；无需 Agent 是产品基线 |
| G4-07 / L | 可选管理 API/collector + SSH rescue 集成（06 接受才做） | 06,04 | 失联可通过 SSH 修复/撤回；数据面 service 不依赖 Agent unit；双通道同操作 ID 避免重复执行 |
| G4-08 / M | 连接 probe/fallback 与可用性解释；Smart Transport 单独候选 | 01,02,G2-08 | 区分 server unavailable 与 UDP blocked；用户可手动选择；自动切换有上限/backoff，避免反复抖动；不承诺所有网络可穿透 |

**Gate G4**：原有四模块在新管理层可用、适用 native export、已管理节点迁移与新目标恢复
通过；第三方接管和更广平台按声明支持的范围验收。Agent 可以通过“决定不实现且 SSH-only
满足需求”关闭能力评估；它不是强制总 Epic 依赖。
#5 继续是 runtime 研究关联，强制 sing-box 服务端迁移不在任何 gate 中。

## 8. G5：长期跨平台扩展

这部分是路线图扩展，不因列出而自动扩张 #13 的完成边界。每个平台单独估算和验收。

| ID / 难度 | 工作包 | 前置 | 完成条件 |
|---|---|---|---|
| G5-01 / M | 共享应用服务 API 稳定性/序列化/FFI 或 IPC 合同；OS credential/VPN adapter matrix | G2-10 | 公共逻辑与平台生命周期分离；protocol capability 不依赖 UI；两种平台适配 fixture |
| G5-02 / L | Windows client + Credential Manager/选定 vault adapter、隧道/服务权限、installer/update | 01 | 干净 Windows 目标 install/connect/disconnect/recovery；管理员与普通用户行为明确；不硬编码 macOS path |
| G5-03 / L | Linux client + Secret Service/可用安全 store、TUN 权限、发行包/桌面生命周期 | 01 | 选定发行版矩阵实测；缺安全存储不给明文降级；权限失败可解释；已有 Linux installer 保持兼容 |
| G5-04 / L | iOS PoC 与 client：NetworkExtension、vault、后台连接、签名/分发、local state 导入；远程管理能力单独评估 | 01,G0-06 | 真机权限/sleep/network switch/导出或导入通过；设备与桌面共享不要求中央账号；不假设桌面 SSH 子进程路线可直接复用 |
| G5-05 / M | 各平台 compatibility matrix / 原生导出 / 多设备可选加密同步设计 | 02–04 | 各平台同一服务器的声明能力可复现；同步只是可选服务，服务停止不破坏本地使用 |

## 9. G6：长期基础设施智能化

| ID / 难度 | 工作包 | 前置 | 完成条件 |
|---|---|---|---|
| G6-01 / M | Plan comparison / break-even / budget advisor：费用、traffic allowance、数据时效和可用性 | G3-07 | 用同币种/周期单位比较；未知项明示；不给基于 stale price 的自动购买结论 |
| G6-02 / M | 用户设备到各自节点的 latency/throughput benchmark，方法和样本窗口 | G4-08 | 比较可复现；测量开销可控制；不把本地 latency 当每个地区的普适网络质量 |
| G6-03 / L | 自动迁移/IP 替换/故障恢复策略：预算、计划、备份、回切、资源回收 | G4-04,G6-01 | 先 dry-run/通知后启用明确策略；注入 false alarm 不重复建机或删原端；成本上限可执行 |
| G6-04 / M | Assisted operations：解释诊断与生成可审阅操作计划 | G1-08,G2-04,03 | AI 输出不直接授权任意 root/cloud destroy；离线手工路径完整；agent/服务不可用不影响数据面 |

## 10. 测试、发布与完成证据

按任务改动范围运行测试，不为纯文档重复全套。工程任务验收统一记录：commit/tag、目标
组合、预期/实际结果、脱敏日志、失败注入结果、恢复步骤。证据只包含保留域名和替代 ID。

| 验证层 | 使用方式 | 不可替代的证明 |
|---|---|---|
| Bash fixture regression | Bats fast + ShellCheck，涉及下载/客户端时运行相关完整 suite | 原有 modules/CLI/metadata/订阅兼容；macOS BSD grep lint 盲区按 AGENTS 补查 |
| Controller unit/contract | 新语言单测、versioned fixtures、state crash tests | 任务模型、vault 引用、错误/序列化/存储迁移 |
| SSH integration | 隔离 SSH fixture，sudo/host keys/network faults | 拒绝错误 trust、命令边界、并发、断线后实际 remote state |
| Config validation | pinned 真 mihomo/sing-box/native runtime | 配置 accepted 不等于实际连通；无客户端二进制不标绿 |
| End-to-end VPS | explicit test VPS；compat 完整验收；第二目标恢复 | TLS/UDP、重复部署、升级恢复、跨服务器重建 |
| Client platform | 目标系统/芯片及真机/分发包 | 系统权限、生命周期、路由/DNS与权限恢复 |
| Provider | fake action faults + 首家实际账户隔离资源 | 资源 ownership、timeout reconciliation、删除及成本数据 |

发布保持两条清晰边界：server release 继续 tarball/checksum/tag + 原有 CI gate；controller/client
按其选定工程独立产物与版本。最终需要一张兼容矩阵说明 controller/client 支持哪些 server
release 与 metadata/profile schema。旧客户端不能理解新 schema 时明确阻止升级/给导出路径。

## 11. 近期具体执行队列

1. **第一批：G0-01→02→03**。先提交文档基线、支持矩阵与应用服务合同，形成可审查结果。
2. **第二批：G0-04/05/06，再 G0-07**。同题 PoC 评估 controller 与 vault，提前验证 macOS
   交付；接受 ADR 后才创建正式新工程。
3. **第三批：G1-01→02→03→04→05→06**。交付可用 SSH 和只读 preflight；此时不部署。
4. **第四批：G1-07/08→09→10→11→12→13→14**。先远端状态/脱敏，再允许执行变更，
   用一条真实闭环验证抽象；不同时实现所有协议。
5. **后续**：通过 G1 后进入 G2；G3、G4 各自依赖上游 gate。跨平台/智能化按成熟能力追加。

现有 Phase 1 P1-A–K 的映射：A→G0；B→G1-01/07；C→G1-02–04；D→G1-05/06；
E→G1-08–11；F→G1-12/13；G→G1-14；H→G2-01–03；I→G2-04–06；
J→G2-07；K→G0-06 + G2-08–10。它们是工作包与工程任务两种粒度，不创建重复 Issue。
未来开 Issue 只开最近一批有边界/依赖/验收明确的任务，并在 #13 回链。

## 12. 最终目标覆盖与 Epic 关闭条件

| 演进目标 | 完成证据 |
|---|---|
| BYOS 一等入口 | G1-14 + G2-10：导入、可信 SSH、检测、部署、连接、管理全流程 |
| 自己的云账号 BYOC | G3-08：至少一家 Provider 创建/部署/连接/销毁闭环 |
| Local-first / 不依赖中央服务 | G1/G2：无平台账号；停 controller/官网模拟不可用，data plane 和已导出 client 仍运行 |
| Native Escape Hatch | G1-12/13 + G4-01/02：声明支持 runtime 的 profile/key 与独立客户端连接 |
| 运维和升级 | G2-04–06：状态、流量、脱敏日志、重启、验证升级/恢复 |
| 透明成本 | G2-07 + G3-03/07：手工和 provider 价格，单位/过期/unknown/forecast 的边界 |
| 备份/迁移/灾难恢复 | G2-03 + G4-04：第二服务器恢复、endpoint 更新、回切、旧服务器退役 |
| Provider/Protocol 独立 | 合同与 adapter 测试；业务层不引用厂商 SDK 或 sing-box schema |
| Agent 可选 | SSH-only 全流程；若存在 Agent，G4-07 的卸载/修复验收 |
| 保持现有功能 | 各次 release compat 四协议与 metadata v1/CLI/订阅回归报告 |

上述核心覆盖完成、实际支持范围与文档一致且无未关闭的核心流程失败后，才关闭 #13。
根据用户最新分支约束，最终 main 合并还需 G5/G6 的已约定任务完成并验收。
候选能力需 accepted-not-applicable 的 ADR 结论；不得用阶段完成替代全部演进完成。
最终合并检查以执行规范为准；GitHub Epic 原文仍为历史范围，外部范围同步另行处理。

## 13. 外部依据与尚待验证事项

- [OpenSSH ssh_config](https://man.openbsd.org/ssh_config)：host-key policy、非交互、
  连接管理选项有官方定义；本计划据此要求独立信任/错误处理，但实际实现需验证用户系统版本。
- [Hysteria2 native client configuration](https://v2.hysteria.network/docs/advanced/Full-Client-Config/)
  与 [sing-box Hysteria2 outbound](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)：
  不同配置合同必须分别实现。官方最新页面可能领先于仓库 Hysteria 2.12.3/sing-box 1.14.2 pin；
  native renderer 按已锁定版本的实二进制/源码验证，不从最新页面推断旧版支持随机 hop 等字段。
- [Apple NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
  及 [Network Extensions entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)：
  隧道涉及平台能力与签名；这支持提前安排 PoC，不代表项目当前已具备发布资格。
- [Hetzner Cloud API](https://docs.hetzner.cloud/reference/cloud)：异步 action、限流、资源与定价接口
  是 ProviderAdapter 需要处理的类别。只用作接口研究样例，不表示首家已选 Hetzner。

正式选 engine/provider/encryption 前还要核查其锁定版本、依赖许可证与分发要求，形成
可复现 PoC/ADR；本文不替代这些决策。暂未验证实际云账号、Apple 签名/权限条件、真实 VPS
或原生 Hysteria CLI 是否有独立 config-check 命令，因此对应任务保留具体验证步骤。
