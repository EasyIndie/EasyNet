# 任务卡与模型分配索引

已将 168 条原任务进一步拆为 **270 张独立卡**，覆盖 56 个工作包。
新增 G0-06.2aa 只拆出官方工具链事实准备，原生命周期与平台验收范围保留。
每卡单独文件，可只把本卡和相关合同交给执行模型，无需读整个目录。
已完成卡的状态见下表与对应 task-result；其余已具备目标/案例/依赖/模型评估，
但标为 locked：尚未实施前置项；未来工程语言/路径/行为命令须冻结后才能执行。
不把未来命令或编译环境假装成今天已经存在。

模型档位及成本校准见 [模型路由](../model-routing.md)。机器可读台账：[cards.json](cards.json)。
只修改 JSON 或只修改 Markdown 均会造成漂移，验证器会检查一致性；状态转换同时更新两者。
结构校验：`python3 docs/planning/validate_task_cards.py`。
解锁用 [binding 模板](../task-binding-template.json)；细则见 [执行规范](../agent-execution-policy.md)。

| 档位 | 默认模型类型/示例 | 卡数 |
|---|---|---:|
| D | Luna low | 5 |
| C | Luna medium | 84 |
| I | GPT-6.1 Sol medium | 141 |
| R | GPT-6.1 Sol high；冲突难解时 Astra high | 39 |

## G0

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G0-01.1](G0/G0-01.1.md) | Luna low | verified | 核对 Agent 指引与 planning 导航并修复失效引用 |
| [G0-01.2](G0/G0-01.2.md) | Luna low | verified | 校对演进目标、分支和任务状态文案 |
| [G0-01.3](G0/G0-01.3.md) | Luna low | verified | 汇总文档检查结果并提交到演进分支 |
| [G0-02.1](G0/G0-02.1.md) | Luna low | verified | 从代码列出现有 OS、架构、权限与协议能力 |
| [G0-02.2](G0/G0-02.2.md) | Luna medium | verified | 为每种支持组合登记 fixture 和验证入口 |
| [G0-02.3](G0/G0-02.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 审查 supported/unknown 边界并冻结首批支持矩阵 |
| [G0-03.1a](G0/G0-03.1a.md) | GPT-6.1 Sol medium | verified | ServerTarget 合同与两目标示例 |
| [G0-03.1b](G0/G0-03.1b.md) | GPT-6.1 Sol medium | verified | ProtocolRuntime 合同与 native/AWG 能力示例 |
| [G0-03.1c](G0/G0-03.1c.md) | GPT-6.1 Sol medium | verified | Profile 合同与 secret 引用示例 |
| [G0-03.2a](G0/G0-03.2a.md) | GPT-6.1 Sol medium | verified | Operation 状态与转移表 |
| [G0-03.2b](G0/G0-03.2b.md) | GPT-6.1 Sol medium | verified | 事件 schema 与序列样例 |
| [G0-03.2c](G0/G0-03.2c.md) | GPT-6.1 Sol medium | verified | 错误码与失败结果样例 |
| [G0-03.3a](G0/G0-03.3a.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 评审 ADR-001 Local-first |
| [G0-03.3b](G0/G0-03.3b.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 评审 ADR-002 Protocol Runtime |
| [G0-03.3c](G0/G0-03.3c.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 评审 ADR-003 SSH-only/Agent optional |
| [G0-04.1a](G0/G0-04.1a.md) | Luna medium | verified | Rust 候选证据表 |
| [G0-04.1b](G0/G0-04.1b.md) | Luna medium | verified | Go 候选证据表 |
| [G0-04.1c](G0/G0-04.1c.md) | Luna medium | verified | 平台原生候选证据表 |
| [G0-04.2g](G0/G0-04.2g.md) | GPT-6.1 Sol medium | verified | Go SSH 隔离 fixture 与模块 |
| [G0-04.2j](G0/G0-04.2j.md) | GPT-6.1 Sol medium | verified | Go SSH fixture 拒绝与清理验证 |
| [G0-04.2h](G0/G0-04.2h.md) | GPT-6.1 Sol medium | verified | Go SSH key auth 与 host trust |
| [G0-04.2k](G0/G0-04.2k.md) | GPT-6.1 Sol medium | verified | Go SSH handshake auth deadline 验证 |
| [G0-04.2l](G0/G0-04.2l.md) | GPT-6.1 Sol medium | verified | Go SSH combined output 上限验证 |
| [G0-04.2m](G0/G0-04.2m.md) | GPT-6.1 Sol medium | verified | Go SSH bounded Run 与未知结果 |
| [G0-04.2i](G0/G0-04.2i.md) | GPT-6.1 Sol medium | verified | Go SSH deadline output cancel 故障 |
| [G0-04.2a](G0/G0-04.2a.md) | GPT-6.1 Sol medium | verified | 候选 A SSH PoC |
| [G0-04.2n](G0/G0-04.2n.md) | GPT-6.1 Sol medium | verified | Go native vault 创建隔离助手（仅编译） |
| [G0-04.2o](G0/G0-04.2o.md) | GPT-6.1 Sol medium | verified | Go native vault 显式作用域 CRUD（仅编译） |
| [G0-04.2p](G0/G0-04.2p.md) | GPT-6.1 Sol medium | verified | Go native vault 隔离进程与锁定实测 |
| [G0-04.2q](G0/G0-04.2q.md) | GPT-6.1 Sol medium | verified | Go vault 限界结果助手（仅编译） |
| [G0-04.2r](G0/G0-04.2r.md) | GPT-6.1 Sol medium | verified | Go vault 无创建 preflight 故障定位 |
| [G0-04.2s](G0/G0-04.2s.md) | GPT-6.1 Sol medium | verified | Go vault 无创建沙箱外对照 |
| [G0-04.2t](G0/G0-04.2t.md) | Luna medium | verified | 候选 A 严格脱敏结果编码 |
| [G0-04.2u](G0/G0-04.2u.md) | GPT-6.1 Sol medium | verified | 候选 B 隔离依赖与编译门槛 |
| [G0-04.2v](G0/G0-04.2v.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 候选 B SSH 传输与 fixture 桥接合同 |
| [G0-04.2w](G0/G0-04.2w.md) | Luna medium | verified | 候选 B Go 侧有界凭据帧编码 |
| [G0-04.2x](G0/G0-04.2x.md) | GPT-6.1 Sol medium | verified | 候选 B Rust 凭据帧解码与密钥校验 |
| [G0-04.2y](G0/G0-04.2y.md) | GPT-6.1 Sol medium | verified | 候选 B Rust 所属 IPC 控制状态机 |
| [G0-04.2z](G0/G0-04.2z.md) | GPT-6.1 Sol medium | verified | 小卡编号支持两字母后缀 |
| [G0-04.2aa](G0/G0-04.2aa.md) | GPT-6.1 Sol medium | verified | 候选 B 继承 IPC descriptor 与 bridge 启动门槛 |
| [G0-04.2ab](G0/G0-04.2ab.md) | GPT-6.1 Sol medium | verified | Go 父进程有界 bridge 输出解析 |
| [G0-04.2ac](G0/G0-04.2ac.md) | GPT-6.1 Sol medium | verified | Go 父进程所属 bridge 启动与回收 |
| [G0-04.2ad](G0/G0-04.2ad.md) | GPT-6.1 Sol medium | verified | Go–Rust 真实 IPC bootstrap 验收 |
| [G0-04.2ae](G0/G0-04.2ae.md) | GPT-6.1 Sol medium | verified | Go fixture 所属临时凭据导出 API |
| [G0-04.2af](G0/G0-04.2af.md) | GPT-6.1 Sol medium | verified | Rust SSH transport 所属与 retained join helper |
| [G0-04.2ag](G0/G0-04.2ag.md) | GPT-6.1 Sol medium | verified | Rust transport bridge 集成（编译门槛） |
| [G0-04.2ah](G0/G0-04.2ah.md) | GPT-6.1 Sol medium | verified | Rust SSH transport 真实 loopback 故障门槛 |
| [G0-04.2ai](G0/G0-04.2ai.md) | GPT-6.1 Sol medium | verified | Rust 签名认证 bridge 集成（编译门槛） |
| [G0-04.2aj](G0/G0-04.2aj.md) | GPT-6.1 Sol medium | verified | Rust 签名认证真实故障门槛 |
| [G0-04.2b](G0/G0-04.2b.md) | Luna low | verified | 候选 A vault PoC |
| [G0-04.2c](G0/G0-04.2c.md) | GPT-6.1 Sol medium | verified | 候选 A result/打包 PoC |
| [G0-04.2ak](G0/G0-04.2ak.md) | GPT-6.1 Sol medium | verified | Rust 固定命令状态机与桥接编译 |
| [G0-04.2al](G0/G0-04.2al.md) | GPT-6.1 Sol medium | verified | Rust 命令执行真实故障验收 |
| [G0-04.2am](G0/G0-04.2am.md) | GPT-6.1 Sol medium | verified | Go 命令故障 fixture 准备 |
| [G0-04.2an](G0/G0-04.2an.md) | GPT-6.1 Sol medium | verified | Rust 派发与完成证据故障验收 |
| [G0-04.2ao](G0/G0-04.2ao.md) | GPT-6.1 Sol medium | verified | Rust 完整命令退出契约收敛 |
| [G0-04.2d](G0/G0-04.2d.md) | GPT-6.1 Sol medium | verified | 候选 B SSH PoC |
| [G0-04.2ap](G0/G0-04.2ap.md) | Luna medium | verified | Rust vault 原生 C ABI 与构建事实 |
| [G0-04.2aq](G0/G0-04.2aq.md) | Luna medium | verified | Rust vault 数据 ABI 与原生符号链接探针 |
| [G0-04.2ar](G0/G0-04.2ar.md) | GPT-6.1 Sol medium | verified | Rust scoped vault helper 编译与所有权适配 |
| [G0-04.2e](G0/G0-04.2e.md) | GPT-6.1 Sol medium | verified | 候选 B vault PoC |
| [G0-04.2f](G0/G0-04.2f.md) | GPT-6.1 Sol medium | verified | 候选 B result/打包 PoC |
| [G0-04.3](G0/G0-04.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 比较相同验收结果并接受 ADR-004 |
| [G0-05.1](G0/G0-05.1.md) | GPT-6.1 Sol medium | verified | 编写本地数据、secret 引用和迁移合同 |
| [G0-05.1a](G0/G0-05.1a.md) | GPT-6.1 Sol medium | verified | 共同存储纯模型、严格解码与迁移规则 |
| [G0-05.2a](G0/G0-05.2a.md) | GPT-6.1 Sol medium | verified | JSON 崩溃与并发 PoC |
| [G0-05.2b](G0/G0-05.2b.md) | GPT-6.1 Sol medium | verified | SQLite 崩溃与并发 PoC |
| [G0-05.3](G0/G0-05.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 比较证据并接受 ADR-005 |
| [G0-06.1a](G0/G0-06.1a.md) | Luna medium | verified | Flutter/sing-box 路线证据表 |
| [G0-06.1b](G0/G0-06.1b.md) | Luna medium | verified | SwiftUI/原生路线证据表 |
| [G0-06.2aa](G0/G0-06.2aa.md) | Luna medium | verified | 候选 A 工具链校验与隔离事实 |
| [G0-06.2ab](G0/G0-06.2ab.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 候选 A 生命周期实验执行边界设计 |
| [G0-06.2ac](G0/G0-06.2ac.md) | GPT-6.1 Sol medium | blocked | 实现自有 fixture 隔离探针 |
| [G0-06.2ad](G0/G0-06.2ad.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 审查退出 leader 的进程组信号与回收语义 |
| [G0-06.2ae](G0/G0-06.2ae.md) | GPT-6.1 Sol medium | blocked | 实现已审回收合同和精确进程组对照 |
| [G0-06.2af](G0/G0-06.2af.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 审查隔离启动链的无输出 SIGABRT |
| [G0-06.2ag](G0/G0-06.2ag.md) | GPT-6.1 Sol medium | verified | 实现固定的启动基线和沙箱 EOF 对照 |
| [G0-06.2ah](G0/G0-06.2ah.md) | GPT-6.1 Sol medium | blocked | 执行已审固定启动诊断并记录真实边界 |
| [G0-06.2ai](G0/G0-06.2ai.md) | GPT-6.1 Sol high；冲突难解时 Astra high | verified | 审查沙箱启动中止的最小能力与隔离替代 |
| [G0-06.2aj](G0/G0-06.2aj.md) | GPT-6.1 Sol medium | blocked | 实现独立哈希的限定可执行映射诊断 |
| [G0-06.2ak](G0/G0-06.2ak.md) | GPT-6.1 Sol high | ready | 隔离启动失败后的归因停止条件与替代路径决策 |
| [G0-06.2a](G0/G0-06.2a.md) | GPT-6.1 Sol medium | locked | 候选 A engine 生命周期 PoC |
| [G0-06.2b](G0/G0-06.2b.md) | GPT-6.1 Sol medium | locked | 候选 A 系统权限 PoC |
| [G0-06.2c](G0/G0-06.2c.md) | GPT-6.1 Sol medium | locked | 候选 A 签名打包 PoC |
| [G0-06.2d](G0/G0-06.2d.md) | GPT-6.1 Sol medium | locked | 候选 B engine 生命周期 PoC |
| [G0-06.2e](G0/G0-06.2e.md) | GPT-6.1 Sol medium | locked | 候选 B 系统权限 PoC |
| [G0-06.2f](G0/G0-06.2f.md) | GPT-6.1 Sol medium | locked | 候选 B 签名打包 PoC |
| [G0-06.3](G0/G0-06.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 接受客户端框架、engine 与分发 ADR |
| [G0-07.1](G0/G0-07.1.md) | Luna medium | locked | 按选定语言建立最小可构建工程 |
| [G0-07.2](G0/G0-07.2.md) | Luna medium | locked | 添加格式化、单测和合同 fixture 入口 |
| [G0-07.3](G0/G0-07.3.md) | GPT-6.1 Sol medium | locked | 添加 controller CI 并验证旧 Bash CI 保持有效 |

## G1

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G1-01.1](G1/G1-01.1.md) | Luna medium | locked | 实现 ServerTarget 数据校验与序列化 |
| [G1-01.2](G1/G1-01.2.md) | GPT-6.1 Sol medium | locked | 实现单目标持久化、原子写和权限 |
| [G1-01.3a](G1/G1-01.3a.md) | GPT-6.1 Sol medium | locked | 库存 CRUD fixture |
| [G1-01.3b](G1/G1-01.3b.md) | GPT-6.1 Sol medium | locked | schema migration fixture |
| [G1-01.3c](G1/G1-01.3c.md) | GPT-6.1 Sol medium | locked | 两目标隔离 fixture |
| [G1-02.1](G1/G1-02.1.md) | Luna medium | locked | 实现 CredentialStore 合同及 fake adapter |
| [G1-02.2](G1/G1-02.2.md) | GPT-6.1 Sol medium | locked | 实现 macOS vault 获取、写入、删除 adapter |
| [G1-02.3](G1/G1-02.3.md) | GPT-6.1 Sol medium | locked | 接入 SSH key/agent 引用并验证 vault 错误与导出无秘密 |
| [G1-03.1](G1/G1-03.1.md) | GPT-6.1 Sol medium | locked | 实现 host trust store 与指纹匹配 |
| [G1-03.2](G1/G1-03.2.md) | GPT-6.1 Sol medium | locked | 实现受限命令执行、超时与输出上限 |
| [G1-03.3](G1/G1-03.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 实现取消和 SSH 故障 fixture 并审查信任边界 |
| [G1-04.1](G1/G1-04.1.md) | GPT-6.1 Sol medium | locked | 实现 root/sudo 能力探测与错误分类 |
| [G1-04.2](G1/G1-04.2.md) | GPT-6.1 Sol medium | locked | 实现受限参数及路径验证 |
| [G1-04.3](G1/G1-04.3.md) | GPT-6.1 Sol medium | locked | 实现安全临时文件上传、权限设置和断线清理 |
| [G1-05.1a](G1/G1-05.1a.md) | Luna medium | locked | OS/架构事实 collector |
| [G1-05.1b](G1/G1-05.1b.md) | Luna medium | locked | systemd 事实 collector |
| [G1-05.1c](G1/G1-05.1c.md) | Luna medium | locked | CPU/内存/磁盘事实 collector |
| [G1-05.2a](G1/G1-05.2a.md) | Luna medium | locked | 监听端口 collector |
| [G1-05.2b](G1/G1-05.2b.md) | Luna medium | locked | DNS 事实 collector |
| [G1-05.2c](G1/G1-05.2c.md) | Luna medium | locked | 防火墙事实 collector |
| [G1-05.2d](G1/G1-05.2d.md) | Luna medium | locked | 已有服务 collector |
| [G1-05.3](G1/G1-05.3.md) | GPT-6.1 Sol medium | locked | 实现报告解析并验证 unknown 和全程只读 |
| [G1-06.1](G1/G1-06.1.md) | Luna medium | locked | 实现 effective port/transport 冲突规则 |
| [G1-06.2a](G1/G1-06.2a.md) | GPT-6.1 Sol medium | locked | TLS/SNI/域名兼容规则 |
| [G1-06.2b](G1/G1-06.2b.md) | GPT-6.1 Sol medium | locked | 已有服务 ownership 规则 |
| [G1-06.2c](G1/G1-06.2c.md) | GPT-6.1 Sol medium | locked | 公网 UDP unknown 规则 |
| [G1-06.3](G1/G1-06.3.md) | Luna medium | locked | 实现兼容性结果汇总及阻塞案例 fixture |
| [G1-07.1](G1/G1-07.1.md) | GPT-6.1 Sol medium | locked | 实现 operation 状态与事件持久化 |
| [G1-07.2](G1/G1-07.2.md) | GPT-6.1 Sol medium | locked | 实现目标锁与幂等 operation ID |
| [G1-07.3](G1/G1-07.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 实现重连 reconciliation 和取消状态测试并审查 |
| [G1-08.1](G1/G1-08.1.md) | GPT-6.1 Sol medium | locked | 实现字段级 secret 脱敏与恶意错误案例 |
| [G1-08.2](G1/G1-08.2.md) | Luna medium | locked | 增加协议自动化模式禁止 URI/QR 输出 |
| [G1-08.3](G1/G1-08.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 隔离受保护 profile 导出通道并验证 deploy 日志 |
| [G1-09.1](G1/G1-09.1.md) | GPT-6.1 Sol medium | locked | 实现无副作用的 DeploymentPlan 构造 |
| [G1-09.2](G1/G1-09.2.md) | GPT-6.1 Sol medium | locked | 实现计划 hash 与执行前事实复核 |
| [G1-09.3](G1/G1-09.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 接入 BashDriver 并审查 ownership 和审批绑定 |
| [G1-10.1](G1/G1-10.1.md) | Luna medium | locked | 实现锁定 tag、下载与 checksum staging |
| [G1-10.2](G1/G1-10.2.md) | GPT-6.1 Sol medium | locked | 实现旧安装保留和 env 复制 |
| [G1-10.3](G1/G1-10.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 注入切换失败并验证版本记录与恢复目录 |
| [G1-11.1](G1/G1-11.1.md) | Luna medium | locked | 适配 Hysteria 安装与配置入口 |
| [G1-11.2](G1/G1-11.2.md) | Luna medium | locked | 适配启动、重启和结构化健康结果 |
| [G1-11.3](G1/G1-11.3.md) | GPT-6.1 Sol medium | locked | 验证 secret 保留、TLS hook 和 port hopping 生命周期 |
| [G1-12.1](G1/G1-12.1.md) | Luna medium | locked | 实现 native Hysteria client YAML renderer |
| [G1-12.2](G1/G1-12.2.md) | Luna medium | locked | 生成受保护 bundle 与恢复说明 |
| [G1-12.3](G1/G1-12.3.md) | GPT-6.1 Sol medium | locked | 验证 URI/Clash/sing-box 对照及离线导出边界 |
| [G1-13.1](G1/G1-13.1.md) | Luna medium | locked | 核实 pinned native runtime 的真实配置验证方式 |
| [G1-13.2a](G1/G1-13.2a.md) | Luna medium | locked | sing-box darwin arm64 pin/cache |
| [G1-13.2b](G1/G1-13.2b.md) | Luna medium | locked | mihomo darwin arm64 pin/cache |
| [G1-13.3](G1/G1-13.3.md) | GPT-6.1 Sol medium | locked | 接入相关 CI 并验证坏字段失败和不可静默跳过 |
| [G1-14.1](G1/G1-14.1.md) | GPT-6.1 Sol medium | locked | 组合应用服务为最小 CLI 闭环 |
| [G1-14.2](G1/G1-14.2.md) | GPT-6.1 Sol medium | locked | 执行隔离 SSH 端到端故障 fixture |
| [G1-14.3](G1/G1-14.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 执行已授权验收 VPS 连接与 compat 回归并审查 Gate G1 |

## G2

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G2-01.1](G2/G2-01.1.md) | Luna medium | locked | 列出备份 manifest 与实际文件 allowlist |
| [G2-01.2](G2/G2-01.2.md) | GPT-6.1 Sol medium | locked | 编写格式版本、加密及恢复钥匙候选比较 |
| [G2-01.3](G2/G2-01.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 审查恢复顺序与 credential 处理并接受 ADR-006 |
| [G2-02.1](G2/G2-02.1.md) | GPT-6.1 Sol medium | locked | 实现一致性快照与 manifest exporter |
| [G2-02.2](G2/G2-02.2.md) | GPT-6.1 Sol medium | locked | 接入选定加密实现及 backup inspector |
| [G2-02.3](G2/G2-02.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 实现 tamper、路径穿越、symlink 和错误钥匙测试并审查 |
| [G2-03.1](G2/G2-03.1.md) | GPT-6.1 Sol medium | locked | 实现 RestorePlan 和新目标映射 |
| [G2-03.2](G2/G2-03.2.md) | GPT-6.1 Sol medium | locked | 实现预检后原生重建与 cert/profile 更新 |
| [G2-03.3](G2/G2-03.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 在第二 VPS 恢复并验证 host trust 与独立连接 |
| [G2-04.1](G2/G2-04.1.md) | Luna medium | locked | 实现结构化 status collector |
| [G2-04.2](G2/G2-04.2.md) | Luna medium | locked | 实现受限日志读取和脱敏 |
| [G2-04.3](G2/G2-04.3.md) | GPT-6.1 Sol medium | locked | 接入 restart 并验证 stale/offline/部分失败 |
| [G2-05.1](G2/G2-05.1.md) | Luna medium | locked | 实现单一来源流量采样 |
| [G2-05.2](G2/G2-05.2.md) | Luna medium | locked | 实现计数器重置、时间窗口与缺失采样处理 |
| [G2-05.3](G2/G2-05.3.md) | Luna medium | locked | 标注来源差异并验证不冒充 provider 账单 |
| [G2-06.1](G2/G2-06.1.md) | GPT-6.1 Sol medium | locked | 实现候选升级版本与旧配置快照计划 |
| [G2-06.2](G2/G2-06.2.md) | GPT-6.1 Sol medium | locked | 实现候选切换及健康结果 |
| [G2-06.3](G2/G2-06.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 注入升级失败并验收回退及人工恢复边界 |
| [G2-07.1](G2/G2-07.1.md) | Luna medium | locked | 实现币种、金额、周期和额度数据校验 |
| [G2-07.2](G2/G2-07.2.md) | Luna medium | locked | 实现手工 TCO 与流量超额计算 |
| [G2-07.3](G2/G2-07.3.md) | Luna medium | locked | 验证 unknown/free/owned、多币种和边界展示 |
| [G2-08.1](G2/G2-08.1.md) | Luna medium | locked | 实现 VPNEngine 合同、profile store 与 fake engine |
| [G2-08.2](G2/G2-08.2.md) | GPT-6.1 Sol medium | locked | 接入选定 engine 的 connect/disconnect/status |
| [G2-08.3](G2/G2-08.3.md) | GPT-6.1 Sol medium | locked | 验证路由/DNS、休眠和网络切换恢复 |
| [G2-09.1a](G2/G2-09.1a.md) | Luna medium | locked | server import 页面 |
| [G2-09.1b](G2/G2-09.1b.md) | Luna medium | locked | host trust 页面 |
| [G2-09.1c](G2/G2-09.1c.md) | Luna medium | locked | preflight 页面 |
| [G2-09.1d](G2/G2-09.1d.md) | Luna medium | locked | deployment plan 页面 |
| [G2-09.2a](G2/G2-09.2a.md) | Luna medium | locked | profile 页面 |
| [G2-09.2b](G2/G2-09.2b.md) | Luna medium | locked | connect 页面 |
| [G2-09.2c](G2/G2-09.2c.md) | Luna medium | locked | operations 页面 |
| [G2-09.3a](G2/G2-09.3a.md) | Luna medium | locked | cost 页面 |
| [G2-09.3b](G2/G2-09.3b.md) | Luna medium | locked | native export 页面 |
| [G2-09.3c](G2/G2-09.3c.md) | Luna medium | locked | backup 页面 |
| [G2-09.3d](G2/G2-09.3d.md) | Luna medium | locked | restore 页面 |
| [G2-10.1](G2/G2-10.1.md) | GPT-6.1 Sol medium | locked | 建立签名分发包与安装卸载流程 |
| [G2-10.2](G2/G2-10.2.md) | GPT-6.1 Sol medium | locked | 建立更新回退与干净用户环境测试 |
| [G2-10.3](G2/G2-10.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验收 macOS MVP 并记录 Gate G2 证据 |

## G3

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G3-01.1a](G3/G3-01.1a.md) | Luna medium | locked | Hetzner API/价格证据表 |
| [G3-01.1b](G3/G3-01.1b.md) | Luna medium | locked | Vultr API/价格证据表 |
| [G3-01.1c](G3/G3-01.1c.md) | Luna medium | locked | DigitalOcean API/价格证据表 |
| [G3-01.2](G3/G3-01.2.md) | GPT-6.1 Sol medium | locked | 核实测试账号、资源权限与地域可用性 |
| [G3-01.3](G3/G3-01.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 比较证据并接受首家 Provider ADR |
| [G3-02.1](G3/G3-02.1.md) | GPT-6.1 Sol medium | locked | 实现 ProviderAdapter 请求结果合同 |
| [G3-02.2](G3/G3-02.2.md) | Luna medium | locked | 实现 fake discovery/pricing/resource action |
| [G3-02.3](G3/G3-02.3.md) | Luna medium | locked | 实现认证、限流、timeout 和部分创建 fixture |
| [G3-03.1](G3/G3-03.1.md) | GPT-6.1 Sol medium | locked | 实现 provider vault token 认证 |
| [G3-03.2a](G3/G3-03.2a.md) | Luna medium | locked | regions discovery |
| [G3-03.2b](G3/G3-03.2b.md) | Luna medium | locked | plans discovery |
| [G3-03.2c](G3/G3-03.2c.md) | Luna medium | locked | pricing discovery |
| [G3-03.3](G3/G3-03.3.md) | Luna medium | locked | 验证价格时间、币种、附加项及不可用套餐 |
| [G3-04.1](G3/G3-04.1.md) | GPT-6.1 Sol medium | locked | 实现资源 ownership label 与创建记录 |
| [G3-04.2a](G3/G3-04.2a.md) | GPT-6.1 Sol medium | locked | 异步 action reconciliation |
| [G3-04.2b](G3/G3-04.2b.md) | GPT-6.1 Sol medium | locked | cloud firewall adapter |
| [G3-04.2c](G3/G3-04.2c.md) | GPT-6.1 Sol medium | locked | SSH readiness adapter |
| [G3-04.3](G3/G3-04.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验证 timeout 不重复创建及可信 host 身份交接 |
| [G3-05.1](G3/G3-05.1.md) | Luna medium | locked | 实现 quote 与费用明细展示 |
| [G3-05.2](G3/G3-05.2.md) | GPT-6.1 Sol medium | locked | 组合 cloud create→SSH preflight→driver 流程 |
| [G3-05.3](G3/G3-05.3.md) | GPT-6.1 Sol medium | locked | 验证状态变化触发重计划并端到端连接 |
| [G3-06.1](G3/G3-06.1.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 实现 DestroyPlan 与资源所有权检查 |
| [G3-06.2](G3/G3-06.2.md) | GPT-6.1 Sol medium | locked | 实现删除 action 查询及孤儿资源清单 |
| [G3-06.3](G3/G3-06.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 执行授权测试资源销毁并核对云端和本地状态 |
| [G3-07.1](G3/G3-07.1.md) | Luna medium | locked | 实现 provider usage 与计费周期映射 |
| [G3-07.2](G3/G3-07.2.md) | Luna medium | locked | 实现预测、过期价格和缺失采样逻辑 |
| [G3-07.3](G3/G3-07.3.md) | GPT-6.1 Sol medium | locked | 验证多节点成本及 forecast/bill 来源区别 |
| [G3-08.1](G3/G3-08.1.md) | GPT-6.1 Sol medium | locked | 执行 fake provider 全周期故障回归 |
| [G3-08.2](G3/G3-08.2.md) | GPT-6.1 Sol medium | locked | 执行首家授权账号完整生命周期 |
| [G3-08.3](G3/G3-08.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 核对资源账本与费用来源并验收 Gate G3 |

## G4

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G4-01.1](G4/G4-01.1.md) | GPT-6.1 Sol medium | locked | 适配 Xray driver 与 native profile |
| [G4-01.2](G4/G4-01.2.md) | Luna medium | locked | 适配 Shadowsocks driver 与 native profile |
| [G4-01.3](G4/G4-01.3.md) | GPT-6.1 Sol medium | locked | 验证真实客户端 transport 能力与升级回归 |
| [G4-02.1](G4/G4-02.1.md) | GPT-6.1 Sol medium | locked | 适配 AWG runtime ID 与原生 conf |
| [G4-02.2](G4/G4-02.2.md) | GPT-6.1 Sol medium | locked | 验证 AWG kernel/PPA 生命周期边界 |
| [G4-02.3](G4/G4-02.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 评估并单独决定原生 WG driver 支持范围 |
| [G4-03.1](G4/G4-03.1.md) | Luna medium | locked | 实现 EasyNet 既有安装只读扫描 |
| [G4-03.2](G4/G4-03.2.md) | GPT-6.1 Sol medium | locked | 实现一个已支持第三方 runtime 的 adoption plan |
| [G4-03.3](G4/G4-03.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验证备份、ownership、撤销接管及未知格式拒绝 |
| [G4-04.1](G4/G4-04.1.md) | GPT-6.1 Sol medium | locked | 实现迁移新目标与双端校验计划 |
| [G4-04.2](G4/G4-04.2.md) | GPT-6.1 Sol medium | locked | 实现 endpoint/profile 更新和回切流程 |
| [G4-04.3](G4/G4-04.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验收新端连通后退役旧端及断线恢复 |
| [G4-05.1](G4/G4-05.1.md) | Luna medium | locked | 增加 Debian/ARM64 的能力 fixture 与报告 |
| [G4-05.2](G4/G4-05.2.md) | Luna medium | locked | 增加家庭/VM/NAT/systemd 分类规则 |
| [G4-05.3](G4/G4-05.3.md) | GPT-6.1 Sol medium | locked | 验收新增支持组合并明确 NAS 未验范围 |
| [G4-06.1](G4/G4-06.1.md) | Luna medium | locked | 收集 SSH 管理不足与 Agent 候选收益证据 |
| [G4-06.2](G4/G4-06.2.md) | GPT-6.1 Sol medium | locked | 验证 authenticated API 与独立 service PoC |
| [G4-06.3](G4/G4-06.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 决定实现或不实现 Agent 并写接受的 ADR |
| [G4-07.1](G4/G4-07.1.md) | GPT-6.1 Sol medium | locked | 若 ADR 接受则实现最小管理 API/collector |
| [G4-07.2](G4/G4-07.2.md) | GPT-6.1 Sol medium | locked | 若 ADR 接受则实现 SSH rescue 与同 operation ID |
| [G4-07.3](G4/G4-07.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验证 Agent 卸载失联不影响数据面或登记 approved-not-applicable |
| [G4-08.1](G4/G4-08.1.md) | Luna medium | locked | 实现协议连接 probe 和故障分类 |
| [G4-08.2](G4/G4-08.2.md) | Luna medium | locked | 实现手动 fallback 与能力展示 |
| [G4-08.3](G4/G4-08.3.md) | GPT-6.1 Sol medium | locked | 按 ADR 验证自动切换上限/backoff 或登记延期边界 |

## G5

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G5-01.1](G5/G5-01.1.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 冻结平台无关应用服务 API/序列化合同 |
| [G5-01.2](G5/G5-01.2.md) | Luna medium | locked | 实现第二平台 credential/VPN fake adapter |
| [G5-01.3](G5/G5-01.3.md) | GPT-6.1 Sol medium | locked | 验证 FFI/IPC 错误与 capability matrix |
| [G5-02.1a](G5/G5-02.1a.md) | GPT-6.1 Sol medium | locked | Windows vault adapter |
| [G5-02.1b](G5/G5-02.1b.md) | GPT-6.1 Sol medium | locked | Windows controller 适配 |
| [G5-02.2a](G5/G5-02.2a.md) | GPT-6.1 Sol medium | locked | Windows VPN 权限 adapter |
| [G5-02.2b](G5/G5-02.2b.md) | GPT-6.1 Sol medium | locked | Windows VPN lifecycle adapter |
| [G5-02.3](G5/G5-02.3.md) | GPT-6.1 Sol medium | locked | 验证 installer/update 和干净环境连接恢复 |
| [G5-03.1a](G5/G5-03.1a.md) | GPT-6.1 Sol medium | locked | Linux secure store adapter |
| [G5-03.1b](G5/G5-03.1b.md) | GPT-6.1 Sol medium | locked | Linux controller 适配 |
| [G5-03.2](G5/G5-03.2.md) | GPT-6.1 Sol medium | locked | 实现 Linux TUN 权限与 lifecycle 适配 |
| [G5-03.3](G5/G5-03.3.md) | GPT-6.1 Sol medium | locked | 验证发行包与既有 Linux installer 兼容 |
| [G5-04.1](G5/G5-04.1.md) | GPT-6.1 Sol medium | locked | 验证 iOS 签名/隧道权限与真机 engine PoC |
| [G5-04.2a](G5/G5-04.2a.md) | GPT-6.1 Sol medium | locked | iOS vault adapter |
| [G5-04.2b](G5/G5-04.2b.md) | GPT-6.1 Sol medium | locked | iOS profile adapter |
| [G5-04.2c](G5/G5-04.2c.md) | GPT-6.1 Sol medium | locked | iOS local state adapter |
| [G5-04.3](G5/G5-04.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验证后台休眠网络切换并决策远程管理范围 |
| [G5-05.1a](G5/G5-05.1a.md) | Luna medium | locked | macOS profile compatibility 报告 |
| [G5-05.1b](G5/G5-05.1b.md) | Luna medium | locked | Windows profile compatibility 报告 |
| [G5-05.1c](G5/G5-05.1c.md) | Luna medium | locked | Linux profile compatibility 报告 |
| [G5-05.1d](G5/G5-05.1d.md) | Luna medium | locked | iOS profile compatibility 报告 |
| [G5-05.2](G5/G5-05.2.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 设计可选加密同步与冲突合同 |
| [G5-05.3](G5/G5-05.3.md) | GPT-6.1 Sol medium | locked | 验证无同步服务仍可本地连接与恢复 |

## G6

| 卡 | 默认模型 | 状态 | 目标 |
|---|---|---|---|
| [G6-01.1](G6/G6-01.1.md) | Luna medium | locked | 实现同币种套餐与额度比较 |
| [G6-01.2](G6/G6-01.2.md) | Luna medium | locked | 实现 break-even 和预算规则 |
| [G6-01.3](G6/G6-01.3.md) | Luna medium | locked | 验证 stale/unknown 数据与推荐可解释性 |
| [G6-02.1](G6/G6-02.1.md) | Luna medium | locked | 实现设备到自有节点的测量采样 |
| [G6-02.2](G6/G6-02.2.md) | Luna medium | locked | 实现采样窗口与资源开销上限 |
| [G6-02.3](G6/G6-02.3.md) | Luna medium | locked | 验证可复现 benchmark 报告与比较边界 |
| [G6-03.1](G6/G6-03.1.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 实现只读自动恢复策略与预算计划 |
| [G6-03.2](G6/G6-03.2.md) | GPT-6.1 Sol medium | locked | 实现用户启用后可执行的恢复/回切流程 |
| [G6-03.3](G6/G6-03.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 注入误报验证不重复建机、不误删原端并审查 |
| [G6-04.1](G6/G6-04.1.md) | GPT-6.1 Sol medium | locked | 实现诊断事实到可审阅计划的合同 |
| [G6-04.2](G6/G6-04.2.md) | GPT-6.1 Sol medium | locked | 接入辅助解释并限制工具执行边界 |
| [G6-04.3](G6/G6-04.3.md) | GPT-6.1 Sol high；冲突难解时 Astra high | locked | 验证任意 root/destroy 不被自动授权及手工离线路径 |
