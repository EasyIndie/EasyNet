# G0 SDK frontend 后续审查

1. 本轮仅阅读指定事实报告、既有审查末尾和 hosted 必要字段；未追加源码研究或运行。
2. 接受最新事实报告的有界结论：tagged FrontendJobHelpers 已取回，所述片段生成 target/sdk，但未证明生成 target-sdk-version。[事实与来源](sdk-frontend-facts.md)
3. Options 声明与现有前缀冲突足以支持独立静态 parser 修复；不支持声称它导致此次失败，也不解锁新 runtime。
4. Hosted full19 PASS，命令 9 exit 0、stdout 2,692 字节；随后 plan-format，driver_jobs/artifact null，cleanup removed，候选与 GUI/engine/NE 未运行。
5. 当前闭环维持既有已消耗额度及禁用工作流；本轮不修改实现、额度或授予新运行。
6. 阻塞是缺少生成该选项的明确调用/赋值路径证据；实际失败 token、安装版行为和 SDK 编码原因均未观测。
7. 冻结仅 driver_jobs 内 exact -target-sdk-version 的单独消费分支：只对 frontend 类别、一次、一个非空非 flag/@ 操作数；值只瞬时跳过，不保留、不写 target/sdk/平台字段；保持未知前缀/包装形式、重复与缺参拒绝及全部边界。
8. 同一既有 test_driver_jobs_parser_and_grant 增加纯文件用例：与真实 -target/-sdk 并存及 quoted operand 保持语义；缺参/空参/重复/未知近似前缀/包装形式/非 frontend 拒绝。仍为 19 方法，无 helper/import/phase/输出字段；既有源码预算不变，contract 必要说明只替换原行。
9. root 可机械准备此源码修复供完整 diff/hash 审查；不执行测试或 runner。未知实际失败路径继续阻塞 guest，SDK artifact 15.5 equality 与全部最终验收门槛不变。

## 精确静态包与一次本地测试合同

R 一次审完三个完整 source diff：driver 的 exact 分支、同一方法的正/反例及 contract 原行替换符合冻结范围。无新 helper/import/phase/输出字段；原 18 方法 AST 不变，仍为 19。AST/预算/diff 检查通过，R 未执行候选或测试。

| 文件 | 行/字节 | SHA-256 |
|---|---:|---|
| native-lab/build.py | 689/34,196 | 13846d4f2fd8ad082df243df855735e872d3a56740221201a30a2e5840d4e7f8 |
| native-lab/Tests/test_build.py | 588/34,018 | d64d34cdaf0cd4d31b39191469859da8452468baa9fc2b04d1e53d2037de7621 |
| native-build-contract.md | 245/18,883 | 655af7ad7626bac72ee32708ea9f9b92abe99879ee740dcbbafe6badcdb199a2 |

接受一次全新 local-sdk-frontend-metadata-v1，local=1/guest=0，cwd=/Users/joker/Documents/EasyNet，10 秒/1,024 输出字节。
从已消耗 local-sdk-driver-jobs-v1.json（文件 SHA 5cd725bc96d56e693bb0e9621b1fb591c6664bd0e72d3d5b069291bf184cdaa2）仅替换 argv[4] 的 target 和三个 source hash。
argv 前缀 /usr/bin/python3 -I -B -c、run_name artifact_predicate_target、method test_driver_jobs_parser_and_grant 均不变；新 wrapper 为 1,966 UTF-8 字节，SHA 90a3f87c18aff6880ad792893a0d9e586077b2304beb7fac732c5ae824f8ca5a。
同一方法依旧限定 owned self.root，identity/capture/Popen mock，断言无真实 Popen/artifact；没有 compiler、candidate、network 或 guest。
root 冻结此 exact binding 后可仅执行一次；source hash 验证必须先于导入。要求 exit0/tests1/PASS/零失败错误跳过/cleanup passed/输出≤1KiB；dispatch 消耗，失败即停，不重试、不恢复旧额度。无 hosted/compile/全19 allowance。

## SDK 合同依据 disposition

现有 contract 第 22 行把 SDK15.5/target15.0 明确列为实验选择，第 162 行要求产物 SDK15.5。xcrun 查询只支持输入身份，不能单独推出 Mach-O producer 标记必须15.5；既有证据仍缺 SDK 元数据到该标记的生成依据。
后续优先限定 source-only 合同/SDK 元数据来源审查：固定 SDKSettings/version 生成链，区分编译输入与产物声明；不再先开 print-jobs guest。未取得事实前保持原校验，不放宽 equality，不强制 marker，也不宣称已知 mismatch 原因。

## 后续完整静态 schema 范围（覆盖前述单 version 提案）

已核 local-sdk-frontend-metadata-v1：exit0/1PASS/零失败错误跳过/cleanup passed，0.39362195899593644 秒、stdout194/stderr0 字节；wrapper 匹配，binding consumed/local0/guest0。未授 planned syntax binding，旧额度不恢复。
本轮只读本地已取回源码；DarwinToolchain.swift 为22,909字节，git blob79bce9cc2613216328b905e26836e54211d5eb01，机械 git-blob SHA 验证一致，无网络/候选运行。
[同 tag Darwin 源](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Toolchains/DarwinToolchain.swift#L281-L405) 将 SDKSettings.json 的 Version/CanonicalName 解码为 SDK info；sdkVersion 对普通 macOS 返回 version，对 Catalyst 有映射。
[同 tag frontend 调用](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Jobs/FrontendJobHelpers.swift#L522-L525) 调用 addPlatformSpecificCommonFrontendOptions；Darwin 实现追加 -target-sdk-version，条件支持时追加 -target-sdk-name，targetVariant 存在时追加 -target-variant-sdk-version。
这证明支持的生成语法与前缀拒绝冲突；不证明 installed Apple 实现、实际失败 token、SDKSettings 实值或产物 SDK 编码原因。此前“生成路径未获证”的静态阻塞由此解除，guest 额度仍零。
冻结一次 source-only 完整修复：driver_jobs 中 exact closed set {-target-sdk-version,-target-sdk-name,-target-variant-sdk-version}；仅 frontend，每选项每 job 最多一次，一个非空非 flag/@ 操作数，seen set 按 spelling 区分。
值仅瞬时消费，不保留或比较 SDK 版本，不改变 target/sdk/platform 分类；joined/未知近似前缀/包装/缺参/空参/重复/非frontend仍拒绝，已有长度/token/行/UTF8/reference边界不变。
同一 parser/mock 方法一次补齐三个选项的 direct/quoted/组合/与真实 target+sdk 共存正例及各项上述拒绝反例，检查 exact semantic shape/值不泄露；旧18 AST、19名称及 owned/no-Popen 范围不变。
target-variant triple 和 target-cpu 在 frontend helper 由 parsedOptions 显式输入生成；当前冻结 argv 未提供它们。它们不可当无关元数据跳过，保留拒绝，未来输入变更须另审。
只准原三 source paths：driver≤700/40,960、tests≤600/40,960、contract≤245/32,768；无 helper/import/phase/字段。先准备完整 diff/hash 包审查，超界先停止，不能压缩或删用例；本报告不授新本地/guest 运行。
SDKSettings 到 frontend 转发已证明，至实际 Mach-O producer 标记仍缺直接证据；继续优先合同/生成链 source-only 判断。保持产物SDK15.5 equality，不强制 marker，不盲开 print-jobs guest。

## 完整 metadata-set 包接受与一次本地冻结

R 一次审完三个完整 diff 和 planned binding；三选项 closed set/按 spelling 去重、瞬时消费及全部拒绝行为符合上文，参数化用例覆盖全部三项，不删原边界；mock/owned范围不变。AST/旧18AST/19名/预算/diff通过，未执行。
driver690/34,275B SHA f4309afd0679e52ad7124181735b015aa8fbae510370dafaba351dfbc3721959；tests589/34,132B SHA d2e3472f789ab9650ba35765ac064e771a756a3140b6dcb0f447e537fb527eb3；contract245/18,933B SHA28bb76c17fa525dc86faa0dcfae75f7625be6f19cc985b716fd6b0e97b92f2c4。
接受 exact planned local-sdk-metadata-set-v1.json，当前文件 SHA068d7c14f509dd4d6f51ce7933a1962db38cf0a5ac002ce3cb080b023eba5ed5。
已核 consumed metadata-v1 前件文件 SHA401a169ec98cd3954bce64bd5dddc7391a6441a2bac3c5b26631fa9c44de8c6b；新 argv[4] 仅替换 target+三个 source hash，其余不变。
wrapper1,961B SHA4055c16280243e5bf978a4272f080d54e71ed81be80ad28f108ada0a0400eeeb；cwd repo、/usr/bin/python3 -I -B -c、method test_driver_jobs_parser_and_grant、10s/1024B、local1/guest0。
root 可只将此 planned binding frozen 后执行一次 puremock 方法；hash验证先于导入，dispatch消费。要求 exit0/tests1/PASS/零失败错误跳过/cleanup passed/≤1KiB finite output；失败停止，无重试，记录闭合 consumed0。
此包不准 full19/guest/compiler/app，全部旧额度保持0；source/binding变化使本次许可失效。无新 print-jobs 试探：后续优先 SDK 元数据/链接 producer 完整合同 source-only 审查，保留未知实际 token/cause，不放宽 SDK15.5 equality 或强制 marker。
