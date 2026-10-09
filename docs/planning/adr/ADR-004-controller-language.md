# ADR-004：共同应用服务语言

状态：**accepted，root 审查接受，限演进分支共同服务层**；日期：2026-10-08；任务：G0-04.3。

## 决策范围

选择 **Go** 作为后续共同 Application Services / controller 的唯一语言基础。
这是对既有候选证据的工程取舍，不是生产实现、平台支持或 G0 完成声明。
本 ADR 已经 root 审查接受；仅可按下一张 ready 卡创建该层新代码；本卡不创建代码或依赖。
保留 [ADR-001](ADR-001-local-first.md)、[ADR-002](ADR-002-protocol-runtime.md) 与
[ADR-003](ADR-003-ssh-first.md) 的边界；不冻结未来 G1 API、GUI transport 或 vault backend。

现有 Bash、easynet CLI、metadata v1、协议消费者、Edge/TLS/订阅格式继续兼容。
四套现有部署能力及其 native runtime 保留；`wireguard` 目录仍指 AmneziaWG。
GUI 框架、VPNEngine/协议 runtime、可选管理 Agent 和原生 WireGuard 均需各自后续 gate。
此选择不删除已约定 G0–G6 能力，不提前授权 main 合并、正式 release 或生产操作。

## 同题比较：已接受证据与限制

比较对象是相同 SSH trust/auth/dispatch/unknown、scoped vault 与 ResultLab-v1 边界。
各候选测试组织、执行 flags 和 artifact 依赖不同；不以数量、耗时或文件大小排名。

| 边界 | Go 候选 A | Rust 候选 B | 共同结论 / 未验证边界 |
|---|---|---|---|
| SSH trust 与认证 | 未知 trust 在 dial 前拒绝，changed key 在 auth 前拒绝；实际 signed-key 成功、wrong key 拒绝 | typed trust 预拒绝、实际 KEX mismatch、signed-key 成功与 wrong key 拒绝 | loopback 合同通过；没有用户 enrollment/rotation 或真实 VPS 凭据生命周期资格 |
| deadline / cancel / output | context、独占 client close/join；合并 4096-byte cap，overflow 保持 unknown | retained future/Handle、OwnedStream 与 joined event；同样合并 cap 与 unknown | 本地停止不证明远端取消；保留 owner/ID、一次 exec、不 replay；durable receipt/reconciliation 未实现 |
| command completion | Start-success 信号区分 client ack；固定完整输出成功，post-ack 故障 unknown | 只将实际 ChannelMsg::Success 视为 ack；complete+joined 才 exit0，cancel/EOF exit2 | ack-loss/block 显示远端 pending 到 fixture.Close；不是生产 journal 或远端锁证明 |
| vault | scoped native helper 的 owned 临时 file-Keychain CRUD/locked-read/cleanup 通过 | 同一 native C backend 下 owned helper CRUD/locked-read/cleanup 通过 | 两者只证明同题临时 fixture；deprecated file-Keychain、非个人数据；production store/ACL/更新身份/恢复仍未知 |
| JSON/CLI | bounded stdin、六字段 canonical JSON、重复/escaped duplicate/unknown/null/trailing 拒绝；固定错误与 I/O 注入通过 | 同题 CLI 通过；typed borrowed record、显式 exact-number/UTF-8 校验及 I/O 注入通过 | lab record 是脱敏 ABI 样例，非生产 result schema 或认证回执；partial write 不保证原子送达 |
| host packaging | macOS arm64 Mach-O；链接 Security/CoreFoundation 等；adhoc，无 TeamIdentifier | macOS arm64 Mach-O；libiconv/libSystem；adhoc，无 TeamIdentifier | 未验证 Developer ID、notarization、installer/update、其他平台或声明最低工具链版本 |

主证据：[Go SSH](../poc/controller-language/go-ssh-results.md)、
[Go vault](../poc/controller-language/go-vault-results.md)、
[Go result/host](../poc/controller-language/go-result-results.md)、
[Rust SSH](../poc/controller-language/rust-ssh-results.md)、
[Rust vault](../poc/controller-language/rust-vault-results.md)、
[Rust result/host](../poc/controller-language/rust-result-results.md)。

Rust release build 成功时保留了具体 warning：`rust-objcopy` stripping failed
（SIGABRT；missing `@rpath/libLLVM.dylib`）；debug stripping 未获资格。
Go 使用 default build flags，Rust 为不同 release flags；上述事实不能推出公平的体积或构建速度优势。
Go 1.27.1 与 Rust 1.99.0 仅为执行 host 工具链；Rust 声明 1.89 MSRV 未验证，
Go 最低版本兼容政策也未获得本卡资格。native Swift/OpenSSH 资料未执行同题验收。

## 选择理由与代价

两种语言都具备本轮已接受的行为证据，安全结论不能只由语言或绿色测试推导。
选择 Go 的依据是当前同题实现的集成边界较少：accepted SSH 路径直接持有 client、
context 和 output writer，并完成 close/join、unknown 与 no-replay 检查；
其 vault 和 strict JSON CLI 也已有可复用证据，能够作为一个共同服务层的起点。
下一步仍需设计 production adapter，不能直接把 PoC 当作生产实现。

Rust 的 concrete 优势是 typed ownership/state、保留的 future/Handle 与严格数值解析。
不过本候选的已验证路径还维护 Go fixture parent、固定 event IPC、child containment、
phase-only 与 full-command exit semantics；IPC 不携带 raw output/ID，需由 parent/typed state
保持关联。其 event-write failure/forced cleanup-timeout 未做真实 child 注入。
这些是当前方案需继续审查的集成与维护成本，不是 Rust 必须使用 Go bridge，
也不是断言重新设计的 direct Rust service 必然更复杂；本卡不为该替代设计另建 PoC。

Go 的代价是 owner、cancel、deadline、error precedence 与 join 等保证主要靠显式控制流
及回归测试维持，不能借 Rust 的 typed state 推断 Go 编译器已经强制这些保证。
Go 原有 result CLI 的 native import/link closure 也不能当作纯 service 最小依赖闭包。
两者的 native vault 都需要平台 helper 和 production backend 决策；选择 Go 没有消除该成本。

维护成本判断限定为当前已有证据与接口数量：一个 service 语言可减少重复实现业务政策，
但并未证明开发工时、token、货币成本、性能或节省比例。配置为 Sol high；
本卡无可用实际 token/cost 统计，不依据模型价格或语言偏好作选择。

## 候选 disposition

| 候选 | 共同 service 的 disposition | 保留价值 / 再评估条件 |
|---|---|---|
| Go | accepted-selected | G1 先沿现有直接 SSH 和 result 合同准备 production adapter；仍需逐卡审查 |
| Rust | accepted-not-selected，候选证据保留 | 类型约束与解析设计可供合同/测试参考；若 Go 不能满足明确平台或安全 gate，再用同题证据审查替换成本 |
| Swift + system OpenSSH | documented-not-runtime-qualified；accepted-not-selected | [native evidence](../poc/controller-language/native-evidence.md) 为 macOS 对照；Security 与 `/usr/bin/ssh` 的平台耦合仍需分平台实现/验收 |

native candidate 未执行 strict JSON、可信 SSH 故障矩阵或 packaged-app 验收；
不以文档能力代替运行证明。上述 service disposition 不判定 SwiftUI/原生 GUI、
OS vault adapter 或其他 native 集成不可行；它们保持独立、未选定的后续任务。

## 进入生产前的 gates 与下一步

1. 2026-10-09 用户确认、独立架构复核接受 core/client 调度解耦：Go/SQLite 决策已接受后，
   G0-07 可先建立 GUI/engine-independent service skeleton、合同 fixture 与非发布 CI。
   完整 G0 仍要求客户端可行路线与工程验收；未通过完整 G0 时，提前范围只限
   G1-01.* 的 ServerTarget 纯模型/owned inventory/离线故障测试，以及 G1-02.1 的
   CredentialStore 合同/fake adapter，必须先冻结 successor production contract。
   G1-02.2 真实 vault 与 G2-07.1 成本入口增加 G0-06.3 gate，真实 SSH/部署/VPN/签名
   及 G1-13/最终 G1、G2 平台验收保持；离线成功不授予其资格。
   后续 Bash adapter 继续复用 Bash；本修订不选 GUI/engine、vault 或生产 SQLite driver，
   不删除 G0–G6 范围或提前合并 main。
2. 先审查 successor production contracts：trust enrollment/rotation、credential lifecycle、
   权限与输入约束；完整落实 ADR-003 的授权、回执、锁、durable ownership/reconciliation
   与重启恢复 gates。fixture unknown/no-replay 不得替代这些实现和验收。
3. 单独选择 production vault backend，验证无 UI locked-store 行为、sandbox/ACL、
   signing/update identity、export/backup/recovery 与所有目标平台凭据生命周期。
4. 固定支持平台与最低工具链政策，验证 dependency/license closure、production ABI、
   release artifact、Developer ID/notarization（适用时）、installer/update 和平台 lifecycle。
   GUI/framework、transport、VPNEngine 和 management Agent 保持各自 gate。
5. Existing Ubuntu VPS 首次部署、重复部署、中断恢复、read-only preflight 无写入、
   native client 与数据面独立性需真实验收；测试 VPS `compat`，生产 `balanced`，
   生产改动等待测试接受。metadata v1/current CLI/client rendering 兼容及 pinned
   real-client validation 不能由候选 loopback 结果代替。
6. [roadmap](../product-evolution-roadmap.md) 与
   [execution policy](../agent-execution-policy.md) 的完整 G0–G6/final gate 继续约束交付；
   未完成能力不能借语言选择静默省略。需要范围取舍时提交具体 review，不自授取消权限。

本卡只复用未变更候选的已接受运行事实；validator/diff 是文档计划检查，非 runtime 重验。
