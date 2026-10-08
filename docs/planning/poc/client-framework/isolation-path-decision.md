# G0-06.2ak — 隔离路径决策（root 接受：后续验证建议）

R / GPT-6.1 Sol high；2026-10-09；仅源码决策，无运行或资源授权。

后续用户决定：先用 GitHub 托管 macOS runner 验证（G0-06.2al）；本卡 VM-only 推荐不再限制当前合成诊断。专用本地 VM 留作交互验收候选，runner 的 SDK/GUI/完整权限资格仍须分别证明。
输入：已接受的 [ai](sandbox-startup-decision.md)、[aj 实际报告](../../task-results/G0/G0-06.2aj.md)、
[lifecycle preparation v1](lifecycle-preparation.md)；binding 证据版本 `1c91024`，aj 源码 `1aba68e`。
本卡不新增官方来源；复用输入证据，不重复研究或推断已安装二进制的实现。

## 已知、否定与未知

aj 对每条实际命令立即前后校验六份审查文件及 pinned Python；冻结运行仅一次。
A direct cat EOF：rc0、空 stdout/stderr；B mapping sandbox cat EOF：rc−6/SIGABRT、空流。
两者 sole-Z/leader/helper Wait、reap、EOF/FD 收尾健康，无信号/超时/收尾错误。
driver 首次失败停止；C allowed-read、D denied-read 未运行，不能据此认定读边界有效。
`expected_match=true` 仅代表空流匹配；B 独立成功条件失败。
因此否定“ai 的限定 executable-mapping 增量足以使本次启动成功”假设。
失败不证明该操作不需要，也不证明映射拒绝、dyld、签名或其他 capability 是原因。
aborting image、阶段、拒绝操作及实际原因仍未知；上游源码不能填补观测缺口。
aj 保留 fixture；本卡不检查、不删除，后续清理仍需独立审查的精确 owned manifest 边界。

## 唯一推荐路径：专用可丢弃 macOS arm64 VM

结束当前个人主机的权限猜测/试运行链。选择隔离 VM 作为下一目标的准备前提；
不推荐本卡再做 public synthetic attribution：现有证据没有可区分原因的公开阶段标记，
也没有已审查、被授权且不读取个人 crash/system logs 的新增观测方案。
空流、SIGABRT 和健康 cleanup 不支持猜一个 permission、profile import 或 helper。

选择 VM 是本次安全设计建议，不声称 VM 已供应、可用或天然能通过现有 sandbox。
相对仅新建主机账号，VM 允许把 SDK/GUI 的写入与整机生命周期纳入专用实验目标；
它仍需实际证明隔离、工具兼容性、进程收尾及 GUI 运行，不能代替 sandbox 验收。
新建账号在本卡不作为并行替代方案，避免重新打开多个权限试验分支。

外部必须提供一台可重置的专用 macOS arm64 VM、明确系统版本、可交互前台 GUI，
以及受支持的执行/观察通道；用户确认目标所有权与限定实验授权。不要提供个人凭据。
供应者负责满足 Apple 平台许可与虚拟化条件；本卡未验证提供方或创建方式。
专用 guest 账号不得含个人资料、Keychain/云登录或凭据；禁用主机 home/目录共享、
共享凭据与剪贴板通道，确认 VM 到主机/生产目标的访问边界；保留干净可回退快照。
这是供应和审查前提，不能由本卡静态检查宣告成立，也不授权修改当前主机设置。
user/external requirement：供应并提供上述一个具体 VM 的执行入口，授权专用 guest 的合成预检；
取得目标与范围前不运行、不建 VM；SDK/下载/GUI 操作须各自后续绑定，不索取私有凭据。

## 新目标的解锁与停止条件

准备者先冻结目标身份/OS/架构、guest 隔离证据、owned root/manifest、执行通道和清理范围；
独立 R 审查后，另卡绑定精确工具路径、argv、版本/hash、每命令前后校验和一次运行预算。
HOME/CODEX_HOME 不重定义；工具/SDK 读取、owned 写入、网络下载、GUI 服务逐项审查。
不能把 VM 所有权当作 blanket grant，也不导入未经审查的系统 profile/扩展权限。
SDK/凭据操作之前，第一道 native gate 是新鲜 synthetic fixture 的启动、allowed/denied
读写、子进程继承拒绝、网络拒绝与生命周期；预检需要已审查的精确绑定，不直接复用旧失败运行。
仅记录 owned manifest/进程身份、返回码、限额流与 cleanup，不采集个人/系统原始日志或进程清单。
若启动 abort、权限拒绝含糊、身份/流/收尾异常或隔离证明缺失，立即停止并保留限定证据；
不自动增加 grants、不换 helper、不串联下一次试验。新归因需求须有新的具体证据及审查。
SDK 下载/解包/bootstrap 的来源、hash、网络端点与 transitive scripts 先另卡审查；
offline runtime、CLI proxy readiness、guardian 和真实可见 GUI 各自验收，不能由 VM 存在代替。
Flutter/engine pin 与 patch delta 延续 preparation 待审项；本卡不刷新或默许升级。

## 原任务与完整范围

root 对当前台账机械核对：除本卡外，无已确认 independently ready 的原任务。
G0-06.2a native gate 未通过；b→a、c→b、d→c、e→d、f→e、client ADR→f 仍 locked；
G0-07.1 虽已有 controller/state ADR，仍等待 client ADR，不能宣称可独立开工。
可独立推进的仅是经新 bounded card 冻结后的 VM 前提/SDK 来源及提取准备文档，尚非 ready。
本卡可在 root 接受后 source-only verified；依赖它的 native/SDK/GUI gate 保持 blocked/locked。
Candidate B/C、embedded libbox、NE/provider/TUN、授权/签名/分发、平台与四协议实客户端验收，
以及 G0–G6 全 scope 均保留；候选处置须显式 ADR，不以主机阻塞代替取消或 accepted-not-applicable。

验证：binding 的 plan validator 与 `git diff --check` 均 exit0；没有 runtime、fixture、SDK、权限或生产/main 操作。
