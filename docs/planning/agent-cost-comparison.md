# 主会话与子代理的用量比较

日期：2026-10-08（Asia/Shanghai）。这是执行成本校准，不改变产品 G0–G6 范围。

## 当前结论与实际基线

**没有证据证明“每卡新开子代理”比主会话执行更省，也没有证据证明全部留在主会话更省。**
当前采取有选择的分工：短小、连续、已有上下文的机械工作在主会话完成；需要独立实现、
不同模型档位或独立安全审查时使用有界子代理。不能把派发本身当作节省费用的证明。

此前报告称逐模型 token 不可得，只检查了 task-result 和账户工具；本次发现本地 rollout
中的 `token_count`，现已修正。旧报告保留当时结论，不回填猜测。仍没有订阅账单明细，
历史任务的精确协调/评审归属也未预先记录，因此不能从这些计数推出费用或反事实省钱比例。

从本项目主线程树读取，合并同一线程的延续文件，累计计数取增量，去除重复快照。
截止 **2026-10-08 09:19:07 +08:00**，共 63 个文件、62 个线程，去除 149 个重复快照；
没有发现计数重置或缺失调用。包含这次用量调查截止时已记录的开销。
可复算数据见 [JSON 基线](metrics/agent-usage-baseline-2026-10-08.json)。

| 执行来源 | 用量增量记录数 | 输入 token | 其中缓存读取 | 非缓存输入 | 输出 token | 缓存输入占比 |
|---|---:|---:|---:|---:|---:|---:|
| 主会话 Sol | 1,122 | 132,870,362 | 130,270,080 | 2,600,282 | 504,224 | 98.04% |
| 子代理 Luna | 286 | 23,131,806 | 22,181,888 | 949,918 | 136,124 | 95.89% |
| 子代理 Sol | 834 | 63,826,076 | 61,058,560 | 2,767,516 | 347,838 | 95.66% |
| 自动审批审查 | 227 | 15,744,171 | 14,295,296 | 1,448,875 | 21,121 | 90.80% |

输入总数包含反复发送并命中缓存的历史，不是 2.36 亿个独有内容 token，也不是账单金额。
`reasoning_output_tokens` 已包含在输出内，不重复相加。表中“记录数”是去重后的用量
增量记录数，不宣称覆盖没有产生用量事件的失败请求，也不等于用户轮次数。
自动审批不是自主派发的实现/评审 worker，单独列出；其是否计入订阅收费未获确认。

主会话平均每记录输入 118,423 token，子代理合计平均约 77,641 token。
46 个带显式 agent_path 的 worker 线程首条观测输入为 30,607–34,994 token，
中位数 31,116.5；这些输入还含运行时指引和工具定义。所谓 4k/6k 的核心上下文目标
不代表真实请求只有这么多 token，也不是硬预算。首条观测不保证就是线程实际首条请求。

数据证明此批子代理的缓存占比并不低，但任务难度、角色、模型和推理档位不同，
不能拿主会话总量和所有子代理总量直接比较单任务效率，也不能把它们理解成两次相同实现。
Luna 的 local_state_model 线程实际有 5,279,902 输入 / 144,030 非缓存输入 /
32,944 输出；Sol 的后续定向修复为 447,641 / 28,313 / 3,199。
两者是不同工作范围，前者还必须加上主会话和评审开销，不能据此称 Sol 省了某个比例。

## 缓存为何不能只看百分比

官方 API 文档说明缓存复用要求前缀完全匹配，并且模型、service tier 和工具等设置兼容；
同一个聊天名称本身不是缓存保证。API 的诊断或费率也不能直接套用为本订阅产品的账单：
[缓存诊断](https://developers.openai.com/api/docs/guides/prompt-caching/diagnostics)。
日志报告的 cache_write_input_tokens 全部为 0；未验证 Codex 对 API 缓存写入的完整映射，
所以这表示本地报告为 0，不证明实际服务端没有缓存写入或费用。

同样质量下需比较输入量、缓存读取/写入、输出和重试的整组指标。缓存高但上下文非常长，
仍可能比一个短上下文代理昂贵；缓存低但反复读取/返工，也可能更昂贵。只在有可核验且
适用于实际调用的费率时，按模型分别计算普通输入、缓存读取、缓存写入及输出费用，
再求和；推理输出不另加一次。没有费率时保留 token 向量，费用字段填 null。
[官方缓存用量与费用计算](https://developers.openai.com/api/docs/guides/prompt-caching)。

## 之后如何获得可比较的数据

从下一张实际执行卡开始，task-result 关联 [记录模板](metrics/task-usage-template.json)：

1. 在准备/派发前记录 UTC 起点，记录 task ID、输入 commit、验收标准、策略 main 或
   delegated、实际模型/推理档位、子代理数量及是否继承历史。
2. 执行到最终验收/提交之后记录终点，按时间窗口提取整个线程树；包括主会话准备、
   派发、读取结果、实现、独立评审、修复及自动审批。测量操作也记为开销，不只报 worker。
3. 若有用户插入的无关问题或其他工作，单列窗口；不能偷偷把这些费用计入某一策略。
   用量按事件完成时间归属，跨界调用或日志缺失时标记 attribution=approximate/incomplete，
   不拿来作精确比较。进程/测试耗时单独记录，不用线程首尾时间冒充任务总耗时。
4. 记录首次通过、失败/修复轮次、审查缺陷及最终验收；不为节省用量而省略必要审查。
   暂未终验的任务不算便宜的成功样本。计数未能取到的字段用 null，不能填 0。

首轮利用 **至少 3 对实际同类小卡**，交替 main/delegated 顺序，预先登记共同验收尺度和
估计范围。比较机械适配/fixture 等低风险工作；JSON 与 SQLite 的实验工作量不同，
不能作为同难度的一对。每次只执行一张 ready 卡，输入与路径仍须冻结。
主会话执行样本记录当前真实设置，不声称它已切换成卡片指定的子代理模型。

这属于匹配任务的观察比较，不能消除任务差异；若两臂模型不同，它比较实际路由政策，
不能把差异全归因于子代理架构。需要更强因果结论时才选一个代表性离线任务在同一
输入快照、同一模型/推理设置、同一验收下运行两臂；隔离输出、不让后运行者读先前答案，
并交替顺序。完整主历史与短子代理输入本身是策略的一部分，不人为抹掉。
当前未追加这种双份实现，以免为测量扩大费用；未来确有必要时限定一次代表性实验。

判断规则：质量达到同一门槛，报告每对的所有用量、返工和耗时，优先看达到验收的总成本。
至少 3 对是启动校准的最低样本数，不是统计显著性的证明。若结果方向不一致或模型、
工作量不同导致解释不清，则继续标为 inconclusive；不从单个最便宜案例选路由。
没有适用费率时，只有各主要 token 指标稳定占优且无质量退化，才能下 token 效率结论；
指标有取舍则报告条件化结果，不能断言省钱。更复杂安全任务保留独立评审。

## 采集命令与限制

```bash
python3 tools/agent_usage_audit.py \
  --sessions-dir "$CODEX_HOME/sessions" \
  --project "$PWD" --root-thread '<本主会话 ID>' \
  --since '2026-10-08T01:00:00Z' --until '2026-10-08T02:00:00Z' \
  > /tmp/easynet-task-usage.json
```

CODEX_HOME 未设置时传实际 Codex 数据目录，工具不猜会话 ID。时间为带时区的 ISO 格式，
窗口左闭右开。同一主会话延续日志会合并；按父线程递归筛选本项目，不导出消息、工具
正文、账户信息或原始线程 ID。输出仅含模型、计数、散列线程标签和时间。
未找到主会话、缺少字段、计数重置/缺口或中间 JSON 损坏会失败，不偷偷补零。
仅忽略仍在写入的末尾不完整行。模型是日志配置字段，不声称得到服务端真实结算型号。
不修改 Codex 配置、安装遥测服务或读取凭据；没有持久在线采集进程，每卡结束调用一次。
本地日志 schema 不是稳定公开接口，升级后必须重新验证映射。

本次采集器 9 项合成测试通过，涵盖延续日志去重、历史 carry-in、模型切换、时间窗口、
缺失/非法字段、重置/缺口、自动审批分类与私有正文不导出。执行本项目日志采集成功。

## Actual related fact-card observations (2026-10-08)

| Observation | Configured execution | Uncached input | Output (reasoning included) | Input cache read | Usage events |
|---|---|---:|---:|---:|---:|
| [G0-06.1a](metrics/G0-06.1a-usage.json) Flutter facts | Luna medium + main Sol medium fact review | 156938 | 23442 | 96.64% | 46 |
| [G0-06.1b](metrics/G0-06.1b-usage.json) native facts | Main Sol medium, no subagent | 31332 | 8773 | 97.88% | 10 |

Totals include automatic approval separately in the underlying reports. Manual
parts: delegated arm133589 uncached/22947 output; main arm19593/8452. The
delegated worker alone was93575/12748 and its main coordination40014/10199.
Cache was high in both, not a generally low-hit subagent context. These are local
usage events and counters, not HTTP request counts, invoice or subscription units.

This is **related unpaired evidence**, not a controlled matched pair: Flutter
needed more new sources/platform facts and a fact-report repair; native facts
reused same-day NE/libbox/protocol sources and used a different actual model.
Windows/minimum-OS/bridge scopes also differ. Both windows contain prior metric
publication tails and exclude publication after their own collection cutoffs.
Do not turn the difference into a causal savings percentage or dollar conclusion.
The planned three matched pairs have not been satisfied by this observation.

Operational recommendation remains selective: keep short mechanical checks and
small frozen fact edits in main; use bounded Luna for an independently substantial
document/fact package, Sol medium for implementation and Sol high for required
architecture/security review. Avoid broad fan-out or a new agent for each tiny
lookup; include root/review/repair overhead when assessing future matched samples.
Complex SQLite evidence required review despite overhead; quality gates stay.

## G0-06.2aa 工具链事实卡观察

全链路非缓存输入232,614、输出25,751、缓存95.93%；主会话90,445/15,382，
Luna92,989/9,545，自动审批49,180/824（前两数为非缓存输入/输出）。
见 [窗口与限制](metrics/G0-06.2aa.json) 和 [用量](metrics/G0-06.2aa-usage.json)。
包含前卡发布尾部、准备和官方 manifest 补核，归属近似；没有对照臂或费用结论。
这个小事实卡的主会话协调输入已接近 worker 输入，进一步支持限制细碎派发，
将同一候选的来源核对放入有界工作包；安全执行设计仍保持独立 R 审查。

## G0-06.2ac 失败 fixture 卡用量

本卡源码审查通过但两次 runtime 未通过，状态blocked，不能算低成本成功样本。
全链路非缓存输入273,030、输出47,555、缓存97.06%；自动审批113,908/1,199，
主会话68,077/21,698，实现Sol medium52,614/18,527，审查Sol high38,431/6,131。
见 [窗口与失败限制](metrics/G0-06.2ac.json) 和 [原始脱敏计数](metrics/G0-06.2ac-usage.json)。
包含前卡发布尾部/准备/独立审查/两轮修复/两次运行/证据提交；无配对臂、账单费率或省钱结论。
自动审批输入开销也较大，不能只统计实现worker；两次失败后转新的有界诊断卡，不无限返工。

## Corrective isolation implementation observation — G0-06.2ae

Whole chain99 events:257442 uncached input/37072 output/cache96.81%;
[raw aggregate](metrics/G0-06.2ae-usage.json), [scope manifest](metrics/G0-06.2ae.json).
Main91463/20008, I Sol medium44568/12305, R Sol high37509/3828,
automatic approval83902/931. Output includes reasoning; no billing fee is inferred.
The same I/R agents were reused only for this card's two focused repairs; no Astra.
Independent review caught3 source blockers.6 fake tests passed; actual ordinary
qualification failed twice, now at zero-output SIGABRT after bounded reaping.
This is a blocked sample, not an efficient successful delivery. Main coordination
exceeded I+R combined in uncached input and output, so isolated worker totals
would materially understate total task consumption. Root compaction/re-reading,
source/hash binding, native safety approval and evidence publication are included.
Prior metric publication tail is included; this publication lies after cutoff.
No matched main-only same task exists; no causal savings percentage or cost winner.
Keep short mechanical work in main, bound source-review packets and avoid fresh
workers for individual log reads; required independent safety review remains.

2026-10-09 update: [aj full-chain](metrics/G0-06.2aj.json) records 779107 uncached input /40120 output, cache90.39%; main410447/22454, I73713/12520, R224029/4365, auto70918/781. This includes interruption/resumption and is blocked native startup, not successful delivery. Its lower cache ratio and high main coordination show that delegated execution does not guarantee token savings; these observations cannot isolate the effect of delegation from task difficulty, repair and interruption. Same-card root fake/native execution avoided an additional administrative execution card.
[ak source decision](metrics/G0-06.2ak.json): 115692 uncached input /9411 output, cache94.26%, one R and no repair; no runtime acceptance. No matched main-only comparator or billable prices exist, so there is still no cost winner. Operational choice remains main for short mechanical actions, bounded cheap workers for substantial frozen low-risk cards, and independent Sol review for architecture/security. Stop permission-guess loops; next native work needs a concrete dedicated environment.

[al runner/resource observation](metrics/G0-06.2al.json): 409923 uncached input /16642 output, cache92.93%; main341393/13392, R19378/1581, auto49152/1669. No I worker for this short mechanical transport. One native runner attempt failed at B; source review passed without repair. This window includes Q&A research, local hardware assessment, transport retry and broad initial reads/log output, so it is not a matched implementation efficiency sample. Main context dominates; minimize repeated start-doc/catalog/full-log reads and group mechanical checks. Independent R consumed less than5% of uncached input here, but neither that share nor comparison to aj proves delegation savings.

## 2026-10-09 attribution full-chain audit and routing decision

[an counters](metrics/G0-06.2an-usage.json), [window and limits](metrics/G0-06.2an.json): uncached input 710,970, output 43,931, cache 93.89%. Main uncached input 285,787 (40.2% of total), output 17,026. Two fresh I/R workers reused for same-card repairs; no Astra or fan-out.

- gpt-6.1-sol high: uncached input 207,452; output 5,086; cache 81.50%.
- gpt-6.1-sol medium: uncached input 158,806; output 20,454; cache 91.50%.

The single remote observation failed with all unknown; this is not a successful delivery sample. Required R caught genuine faults, but that quality benefit does not establish cheaper execution. Cache reuse is measured, and worker cache reuse can be lower than main; fresh context is not automatically cheap. API cache guidance supports measuring actual cached counts, not applying an assumed discount to these Codex subscription counters: [official diagnostics](https://developers.openai.com/api/docs/guides/prompt-caching/diagnostics).

**Decision now:** this workflow has not demonstrated lower total consumption than main-only. Default short frozen edits, log classification, state updates and aggregation to main. Delegate substantial bounded implementation or document packages only; retain independent review for architecture/security. Stop adding separate administrative cards for source/fake/run/metrics of the same objective; keep those as acceptance steps on one card. Freeze one concise input package, inspect only changed sections on repair, publish evidence and usage together, and avoid repeating full catalogs or unchanged test suites. No speculative third repair or repeated native diagnostic.

At least three matched accepted samples are still required before declaring either route cheaper. Compare uncached input, cached input, output, review/repair, root coordination and acceptance together; do not use total input or worker-only counters as a bill. No paid duplicate implementation experiment was launched solely to fabricate a winner. Current practical choice is selective delegation, with ordinary execution in main; this is a workflow decision under uncertainty, not a causal savings claim.

[ao main mechanical + required review](metrics/G0-06.2ao.json): uncached input 137,818, output 18,432, cache 94.89%. No implementation worker; one R reused within the same card for contract, diff, runtime binding and evidence. Source/fakes passed first time, one native attempt failed at report. Scope is substantially smaller than an and includes the previous publication tail, so the difference is not a savings estimate. This applies selective delegation now rather than continuing tiny I/R dispatches; a matched main-only winner remains unestablished.

[ap binding-repair audit](metrics/G0-06.2ap.json): uncached input 136,891, output 15,228, cache 96.23%; main mechanical fix with one required R, no I/Astra. The previous ao review and path-insensitive fakes missed a driver/reader version conflict; ap corrected it with a path-aware regression. Independent review improves confidence but does not guarantee correctness. Native unknown remains, so neither passed fakes nor lower worker count establishes efficient successful delivery or savings versus main-only. Keep one scoped execution card encompassing source, regression, binding review and once-only evidence; avoid a worker for mechanical binding replacements.

[G0-07.1 mixed checkpoint/scaffold window](metrics/G0-07.1.json): 358,240 uncached input / 32,440 output, cache 94.62%. Includes root progress/resequencing/toolchain recovery, one necessary R and one bounded Luna C; offline scaffold accepted. Cutoff excludes next card. This is not pure scaffold labor or matched main-only delivery; no cost winner. Keep mechanical acceptance in root and meaningful frozen C packages in Luna, avoid tiny delegations.

[G0-07.2 offline check delivery](metrics/G0-07.2.json): 64,660 uncached input / 8,267 output, cache 95.75%. One Luna medium worker, one same-card source repair, root actual acceptance; previous metric publication included. Useful accepted sample, still no matched main-only counterpart or causal cheaper route.

[G0-07.3 CI delivery](metrics/G0-07.3.json): 256,151 uncached input / 21,386 output, cache 96.69%; one I worker + necessary R reused for two same-card repairs, root mechanical source/runtime. New controller CI passed; inherited contract jq1.8 precedence faults found by real Bash matrix, fixed then accepted dual-jq local+runner regression. Costs include complete repair/coordination and automatic approval; no matched main-only sample, no causal savings conclusion.
