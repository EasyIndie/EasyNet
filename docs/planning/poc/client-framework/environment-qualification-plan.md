# G0 实验环境资格计划

G0-06.2as；2026-10-09；R 文档审查已由 root 接受；不授予运行、安装或采购权限。
输入：[fresh 环境事实](environment-facts-2026-10-09.json)、[已接受收敛决定](g0-closure-decision.md)、
[A preparation v1](lifecycle-preparation.md)、[ar 最后观测](../../task-results/G0/G0-06.2ar.md)。
feature 分支已核对；A=Flutter、B=SwiftUI/原生是待比较候选，本卡不选择框架或 engine。

## 当前结论

没有已经资格化的真实 UI/engine、NE 或签名验收目标；完整 G0 仍未通过。
ar 唯一剩余 guest 已消耗，directory-guard 为最后进入阶段，六项 crash 字段 unknown。
它不确定具体失败检查或原因；诊断预算为 0，不再读 crash、加 probe/grant 或重跑归因。
既有 runner 构建/检查成功只证明其列明行为，既不证明实际可见 UI/NE/签名，也不证明 GUI 不可能。
优先准备**已有且获授权的独立 macOS arm64 实验目标**；目标尚未提供时继续 A/B 源码合同准备。
这里的优先次序是实验资源建议，不改变平台支持、产品架构、候选 disposition 或完整 G0–G6。

## 资源事实与目标筛选

fresh CLI 事实：macOS 27.0 arm64、8 GiB RAM、8 logical CPU、swap 已用 2363.44 MiB、
可用盘约 35 GiB，Xcode developer path 存在。CPU 数与路径不证明工具链或实验负载资格。
swap 是该时点使用量，不能单独推定持续内存压力；8 GiB 总量也不是可分配 guest 内存。
tart/prlctl/qemu CLI 未在 PATH 解析到，不证明没有 GUI VM app、现有 VM 或其他管理入口。
当前本机并非已证不可用，但没有证明同时容纳 host、guest、SDK、engine 和构建的余量。
不以通用“guest 至少 N GiB”代替具体要求：[Apple restore-image 配置](https://developer.apple.com/documentation/virtualization/vzmacosconfigurationrequirements/minimumsupportedmemorysize)
给出所选镜像的 minimumSupportedMemorySize；低于该要求的配置不支持。
未来资格卡须核对镜像/OS/芯片、guest 配置要求、host 自留资源、完整存储预算与负载上限，
预算包括 restore image、guest disk、SDK/cache、构建、证据及清理余量；35 GiB 本身不保证容纳。
未取得这份预算前，本机 VM 保持资源未资格化，不下载/启动来试探，也不建议据此采购。

| 实验目标 | 可用条件与用途 | 资格缺口/停止条件 |
|---|---|---|
| 已有独立 Mac | 用户明确提供/授权；无个人数据的实验账户/卷；可见 GUI 与受控清理；先评估 A/B 代理 UI | 仍需冻结 OS/芯片、工具链、隔离/外网拒绝、guardian、实际资源；仅“有 Mac”不通过 |
| 已有或另行授权 VM | 明确所属 host、镜像/许可、GUI 操作入口、资源预算、无共享个人目录/凭据、回退/销毁边界 | 独立 guest 不自动替代 owned-root/decoy、外部读写/网络拒绝及子进程继承实证；不得直接删除现有 VM |
| 当前 8 GiB host 上新 VM | 只有具体镜像与完整预算证明 host/guest 余量，且另获安装/下载/启动授权后才可能成为目标 | 当前 RAM/swap/disk 快照不充分；达不到所选镜像要求、运行中触及冻结资源上限即停 |
| 临时 hosted macOS runner | 可继续承载已冻结离线构建/fixture；真实 GUI 必须另证可见窗口、可操作状态、观测及回收 | [GitHub 官方](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)：arm64 不支持 nested virtualization、无 static UDID；不在此 runner 再套 VM；NE/provisioning 需独立有效路线 |

以上 Apple/GitHub 事实沿用 fresh 输入所列官方来源，本卡未重新浏览；future 路线冻结时再核对具体版本/渠道。
GitHub 所述 same-host development provisioning 不是用户账号/profile 已有的证据；不推定签名可用或不可用。

## 下一步可具体准备的工作

1. root 接受本计划后，先冻结一张 B 独立 source-only preparation 卡：准确工程文件/模板与
   Xcode/SDK 版本、实际 engine 接口/模式、生成文件清单、构建副作用、进程/provider 所有权、
   隔离/guardian/清理和公共案例映射；CLI proxy 与 native provider 分开。此步不等 A 签名，
   不执行 Xcode/GUI/engine、不读个人 settings/Keychain/profile，也不把 mock 写为 NE 通过。
2. A source-only successor 准备保留已审 pin 与 fix-delta、下载/提取/模板/config/guardian 门槛；
   明确覆盖历史 probe 保护性质：owned root/decoy、外部读写/网络拒绝、继承、身份/组/回收、
   输出/时间/FD 上限。替代环境不得借机放松这些条件；history blocked 保留。
3. 获得目标可用性答复后，仅给一个具体目标冻结 qualification binding：目标 OS/芯片与模式、
   owned 工程/合成数据、来源/hash、资源/时间/输出限制、GUI 操作/证据、guardian、清理、
   精确命令及本次授权。先独立 source/security review，后运行一张 ready 卡；无目标则止于准备。
4. 每候选分别执行实际 UI→engine→loopback nonce readiness；覆盖 Connect/Cancel/Stop/Restart、
   重复/并发、配置/端口错误、hung/flood/timeout、窗口关闭、host crash、harness/guardian 清理。
   需记录代次/身份、UI 状态、deadline/exit/output/FD 和端口复用；headless 成功不能替代此 gate。

## 外部条件与最终停止点

| 资格 | 需用户/外部提供的条件 | 不依赖条件的准备与通过边界 |
|---|---|---|
| A/B 代理 UI 生命周期 | 一个可授权、实际可见 GUI、可隔离且可清理的具体目标；工具链/engine取得与构建授权 | 可先冻结源码/模板/config；账号不是合同准备前置；unsigned build/launch 仍须分别证明 |
| A/B 系统 VPN/NE | 各候选选定 provider 路线的有效 entitlement/签名/provisioning、目标与真实系统同意 | 可先审接口和路由/DNS/回退；需要 NE 的 engine 模式在生命周期前就须具备该资格 |
| A/B 签名与分发 | 选定渠道的团队/签名/分发授权及可用凭据，干净安装/更新/回退/卸载目标 | 先准备 package manifest/验证步骤；仅确认可用性，不索取密钥/证书内容或个人日志 |

Apple Developer 账号/团队和独立测试目标问题已待答，不重复请求、不猜已有资格。
缺条件就记录具体 blocked 与尚缺证据，继续独立准备；不自行把候选/平台 accepted-not-applicable。
出现隔离失效、个人数据接触、外部网络/系统状态越界、进程/端口泄漏立即停止并首次升级安全评审；
出现资源超限、目标身份不明或权限/签名条件不符也停；同一失败两次后交审，不开启新的归因预算。
A 历史前置仅在真实 successor 覆盖并独立接受后替换；最终 ADR 显式汇合两候选 engine/权限/签名。
完整 G0、四协议真实客户端、后续 G0–G6 与最终 main gate 保留；本计划检查不能代替任何运行验收。
