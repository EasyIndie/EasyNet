# G0 收敛依赖与验收环境审查提案

G0-06.2aq；2026-10-09；基线 `f0b887be2c3204499c28a35010d23324dd8f37cf`。
**root 已接受；B 去除 A 签名串行边、最终显式汇合已同步。其余资格须逐卡冻结与实证，本文件不授予运行权限。**
依据：`lifecycle-preparation.md` accepted preparation v1 的隔离与 actual UI-host 合同；
`runner-attribution-contract.md` v1 的冻结观测权限；`progress-review-2026-10-09.md`
已接受调度与诊断上限；cards.json 的 G0-06 候选依赖及 G0-06 parent gate。

## 结论与保持的门槛

G0 尚未完成。Go/SQLite 与 G0-07 的成功不覆盖客户端、VPNEngine、系统权限或分发。
候选 A 为 Flutter 路线，候选 B 为 SwiftUI/原生路线；本审查不选择框架或 engine。
SDK/CLI 启动、合成 probe、headless controller 测试均不等于真实 UI 生命周期通过。
代理模式与系统 VPN 必须分别声明；CLI 子进程与 embedded libbox 不互相提供资格。
全部 G0–G6、真实四协议客户端覆盖、后续系统 VPN/签名/分发门槛及最终 main 合并门槛保留。
候选可经明确 ADR 处置为不采用，但不得静默取消既定能力或用文档成功替代运行验收。

## 建议的依赖边：root 接受后再冻结卡片

以下 Q-A/Q-B/Q-NE 是建议的**资格条件名称**，尚无 ready 卡或可执行命令。

| 目标 | 现有依赖问题 | 建议前置与后继 |
|---|---|---|
| A engine G0-06.2a | ac/ae/ah/aj 为历史 blocked；要求它们逐一 verified 会锁死替代环境 | 已审 A 生命周期/回收合同 + Q-A；通过后再进入 .2b→.2c |
| B engine G0-06.2d | .2c 是 A 签名结果；未发现 B 生命周期必须依赖它的理由 | .1b 路线证据 + 已审公共比较案例 + B 自身冻结合同/Q-B；通过后 .2e→.2f |
| A/B 系统权限 .2b/.2e | 前序 engine 通过仅覆盖被测模式 | 各自实际生命周期 + 被测权限模式所需 Q-NE；不得借用另一候选权限结果 |
| A/B 签名 .2c/.2f | 单一候选签名不能隐含覆盖另一候选 | 各自权限结果 + 独立签名/分发目标与授权；按候选记录成功或资格阻塞 |
| 最终 ADR G0-06.3 | 当前只直接依赖 .2f，靠串行链隐含 A 结果 | 显式汇合 A 与 B 的 engine/权限/签名证据及 disposition；仍验证完整 G0-06 gate |

Q-A 必须以独立 successor 证明被替换 probe 原本保护的性质：owned root/合成 decoy、
外部读写/非许可网络拒绝、子进程继承、准确身份/组信号/回收、输出/时间/FD 上限。
同时冻结 SDK/bootstrap/模板/engine 配置来源和哈希、隔离环境、guardian 与清理规则。
ac/ae/ah/aj/al/an/ao/ap 等历史 blocked 保留原结果；ag 等部分成功保留其限定范围。
successor 明确列出覆盖与未覆盖性质，经独立审查、真实资格通过后才可替换调度边。
仅有替代路线建议或 source review 时，.2a 继续 locked；不把历史故障改为 verified。

Q-B 独立审查自身工具链、临时 owned 工程、engine 接口/模式、权限边界、构建副作用、
进程或 provider 所有权及清理。公共案例可共用；A 的 Flutter、sandbox 或 CLI 假设不得
直接复制给原生 provider。两候选顺序执行 ready 卡，不因解耦而同时开展多卡。
若某候选的 engine 本身需要 NE/entitlement/签名，则 Q-NE 提前成为该模式的生命周期前置；
不能为了无账号测试而把 provider 模式换为 mock 后宣称 VPN 通过。

## 环境与凭据边界

| 工作 | 无账号可做的可逆准备 | 实际通过所需条件；当前状态 |
|---|---|---|
| 最后一次 reader 工作包 | 完整有限阶段分类、fake 故障、source/hash 独立审查、精确 binding | 一次已授权 fresh runner guest；目前仅证明有限 workflow 能跑，GUI/NE 未资格化 |
| A/B engine 生命周期 | 对比合同、源码/配置/模板审查、owned fake/widget/controller 案例、环境资格清单 | 被审目标 macOS/芯片、真实可见窗口、所选 engine、可控身份/回收和隔离；未取得 |
| 代理模式 | 冻结数值 loopback nonce、无 TUN/系统代理/路由/DNS 写入的配置与负例 | 实际 UI→engine→SOCKS/HTTP nonce + 全故障矩阵；签名账号不是合同设计前置 |
| 系统 VPN/NE | entitlement/provider/同意/路由 DNS 生命周期设计、模式与支持矩阵 | 选定目标、真实系统同意、该路线有效 entitlement/签名/provisioning 资格；未确认 |
| 签名与分发 | package manifest、更新/回退/卸载、验证步骤和干净目标清单 | 所选渠道的实际团队/签名/分发授权及可用凭据、干净验收目标；未知 |
| 临时 macOS VM | 资源、GUI访问、隔离、生命周期、可销毁性、成本/许可资格评审 | 独立可用 VM 的授权和实际资源；没有安装/采购授权，也没有已通过资格 |

root 本轮只读快照：macOS 27.0 arm64、Xcode 27.0.0 developer path、约 35GiB 可用盘；
memory sysctl 被 sandbox 拒绝，旧 8GiB 为历史记录。这些信息不证明 VM 容量或签名资格。
Apple 账号/团队/凭据是否可用仍待用户回答；不读取个人 Keychain、profiles 或签名身份。
缺少所选 Apple 路线要求的授权与凭据，会阻塞其真实签名、entitlement/provisioning、
分发资格证明，以及依赖这些条件的实际 NE 验收；G0 完整 gate 不能据此标通过。
这不阻塞 B 的独立源码/合同准备，也不构成 B 必须等 A 签名的理由。
无需账号的代理 UI 路线仍须先证明实际隔离、构建及启动条件；unsigned launch 目前未知。
本审查不声称某种会员、证书或渠道已可用；选定具体路线时再定向核对官方要求。
真实 VPS/Provider 账号不是这些 owned 客户端准备的前置；到后续 gate 再核对目标/预算，
测试 VPS 使用 compat，生产 balanced，无测试验收前生产修改。

## 收敛顺序与停止规则

1. root 审查本提案；接受后冻结公共比较矩阵、A/B 独立前置与显式最终汇合边。
2. 把诊断余量用于**一个完整 reader-phase 工作包、一次 guest 观测**：先实现固定有限
   入口/枚举/候选/读取/解析/identity/report/hash 阶段分类及 fake 故障，再独立 source/hash
   审查。扩展报告字段需冻结 successor 合同，不能偷改原 v1 六字段或泄露原始记录。
3. 该工作包冻结 driver/reader 同版哈希、精确命令、有限输出、预算、cleanup 和授权后
   才可观测；只允许 v1 那一次合成 target/等待/单次查询，不增加路径、polling 或 grant。
   不为阶段拆分额外 guest，不再安排零散诊断卡。有效分类也不证明缺少某项权限。
4. 无可行动证据、unknown 或资格不能满足：保存 bounded 结果与历史 blocked，结束归因。
   转为独立临时 VM/其他合格目标的资格评审；不默认安装、下载、采购或放宽个人环境访问。
   有可行动证据：先审查确切修正和资格 successor；不能自动重试或重置观测余量。
5. 一张一张完成 Q-A/Q-B 准备和环境资格；优先选择已有明确条件的 ready 卡。
   可先准备 B；A 历史 sandbox 故障不是 B 实验结果。无合格目标时停在环境阻塞，继续
   无账号的合同/源码准备，不执行未绑定 SDK/GUI/NE 动作。
6. 各候选实际 UI 生命周期：Connect/Cancel/Stop/Restart，真实 nonce readiness，重复/
   并发、无效配置、端口冲突、hung/flood/timeout、窗口关闭、host crash、harness/guardian
   失败清理；记录状态/代次/身份、deadline/输出/exit/FD 和端口复用。泄漏即失败并停用。
7. 各候选完成权限/签名/分发实证或明确 ADR disposition，再接受 G0-06.3；未验证边界
   明示 unknown。因账号缺失无法验证的候选不可自行 accepted-not-applicable。
8. 汇合 G0-01–07 全部 gate 与证据，完整 G0 通过后再按既定门槛推进；此前只允许已接受
   的 G1 离线例外。G0 完成不授权真实生产操作、正式发布或合入 main。

新信任/权限边界、失败两次、资源或目标不明时停下交审；安全故障首次即升级。
guardian 自身被杀/重启恢复、embedded libbox、最低系统/芯片与后续平台资格仍单列待验。
本卡仅做文档检查；未执行 runtime、SDK、下载、VM、网络实验或个人状态读取。
