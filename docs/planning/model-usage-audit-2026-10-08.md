# 模型使用审计（2026-10-08）

本次只读核对了模型路由说明及 G0-04.2t/w/z/aa/ab/ac/ad/ae 的结果记录。审计执行模型为 Luna low；本次 token 数据不可用。

## 可确认的记录

- 8 份结果均未提供逐模型 token 遥测；因此无法量化各模型的 token 成本、比较本批任务费用或推断 API 账单。
- 账户用量工具快照显示 Plus 账户 5 小时窗口已用 8%、周窗口已用 17%。这是账户整体快照，不是本任务消耗、单模型使用量或账单；不据此分摊费用，也不记录 account ID。
- 历史 goal token 统计不是逐模型结算，不能分摊给这些任务或推算费用。
- 记录中的 Luna dispatch/resume 曾遇到线程限制，随后采用可用 worker 或既有历史恢复。此事实不提供历史复用的 token 数或费用。
- 记录显示 Sol medium 用于编号规则等范围明确的机械工作；这类工作原属 D 档，可优先由 Luna low 处理。线程限制本身不构成提升模型档位的理由。
- 部分安全/IPC 任务经历 Sol high 设计或绑定审阅、再次核对和代码预审等多回合。未来应将边界设计冻结一次，并在最终 diff 做一次安全审查；同一局部修复留在同一 agent，避免重复长历史核对。
- 主 Agent 和 Sol high 审查合计发现三项实际 bug：Drop 通知先于底层资源释放；`from_std` 失败路径未清理 shutdown clone；取消 close future 后 handle 仍可借用。这些发现说明安全/所有权审查仍必要；相关修复已通过独立 Sol high 最终源码审查；8 项内存单元通过，真实 SSH 验收仍未执行。

## 路由与操作建议

- D：Luna low，用于导航、事实提取、格式/编号核验、状态和报告汇总。
- C：Luna medium，用于已冻结接口的小型实现。
- I：Sol medium，用于跨边界集成；安全边界问题及时进入 R。
- R：Sol high，用于信任、密钥、权限、资源生命周期和阶段 Gate；Astra 只用于复杂争议。
- 新 agent 默认 fresh fork 且不带历史（`fork_turns: none`），只传任务卡、已接受合同和必要局部事实。低档派发失败时，只尝试一次定向恢复；若低档仍不可用，转给现成低档 agent 做机械工作，或保留当前状态等待，不自动升到更贵模型。必要的 I/R 安全审查不降档。
- 一次新边界设计冻结加一次最终 diff 审查即可；修复与定向复核沿用同一 agent。机械账目和报告汇总无需额外强 review；不要仅为微小机械操作新增任务卡。
- `spawn` 可为新子 agent 指定模型；当前 `followup` 只延续既有 agent 的模型，不能切换主聊天模型；用户需在 UI 更改主模型。本次未改主聊天配置。

## 费用解释限制

订阅账户窗口用量、历史 goal token 数和 API token 计价是不同指标。当前没有本任务逐模型 token 遥测或可核验的单次费率数据，故无法给出费用金额、节省比例或各模型成本排序。官方模型选择指南建议按任务复杂度选型并对同一输入评测；推理指南说明较低推理强度通常消耗较少 token，但这不保证订阅费用下降或质量不变：[模型选择](https://developers.openai.com/api/docs/guides/model-selection)，[推理指南](https://developers.openai.com/api/docs/guides/reasoning)。
