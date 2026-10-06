# 小任务目录：低成本模型执行粒度

本目录把 56 个工作包拆为 **168 个顺序小任务**；与
[工作包清单](execution-backlog.md) 配合使用。任务 ID 不是 Issue 编号。
模型执行方式和 feature 分支规则见 [执行规范](agent-execution-policy.md)。

168 个原条目已细化为 [220 张任务卡](task-cards/README.md)，多候选/页面/平台条目使用 a/b 子卡。
以任务卡状态为准；locked 卡的依赖/路径/行为验证冻结前不允许执行，不能自行选择架构。
每个任务卡最多一个行为、一个 fixture 场景组、一个有限验证命令集。

## 依赖与大小规则

同工作包 `.1 → .2 → .3`；`.1` 继承工作包全部依赖；`.3` 完成后才满足下游工作包依赖。
这是一条保守默认串行队列，不授权自动启动多 Agent。研究 PoC 涉及两个候选、UI 涉及多个
页面、平台适配涉及多个 OS/架构时必须继续拆为 `.2a/.2b` 等独立卡，每卡只做一个候选或
一个页面/平台组合。ADR 接受、信任/加密/销毁边界、Gate 实机验收由评审角色处理。
低成本模型可收集证据、写 fixture、按冻结接口实现单一模块，但不能自行批准这些决定。

修改目标 ≤3 个实现文件 + ≤2 个测试/文档文件，建议 diff ≤200 行；不以硬删测试或压缩代码
满足限制。超限先切卡。单卡核心上下文建议 ≤8k tokens；任务与局部代码通常 ≤4k 更好。
限制是调度目标，不是已验证模型准确率或费用承诺。是否 ready 以具体任务卡的边界完整性为准。

## 小任务列表

| ID | 上层工作包 | 单次工作内容 | 任务卡 |
|---|---|---|---|
| G0-01.1 | G0-01 | 核对 Agent 指引与 planning 导航并修复失效引用 [G0-01.1](task-cards/G0/G0-01.1.md) |
| G0-01.2 | G0-01 | 校对演进目标、分支和任务状态文案 [G0-01.2](task-cards/G0/G0-01.2.md) |
| G0-01.3 | G0-01 | 汇总文档检查结果并提交到演进分支 [G0-01.3](task-cards/G0/G0-01.3.md) |
| G0-02.1 | G0-02 | 从代码列出现有 OS、架构、权限与协议能力 [G0-02.1](task-cards/G0/G0-02.1.md) |
| G0-02.2 | G0-02 | 为每种支持组合登记 fixture 和验证入口 [G0-02.2](task-cards/G0/G0-02.2.md) |
| G0-02.3 | G0-02 | 审查 supported/unknown 边界并冻结首批支持矩阵 [G0-02.3](task-cards/G0/G0-02.3.md) |
| G0-03.1 | G0-03 | 编写 ServerTarget、Runtime、Profile 的示例合同 [G0-03.1a](task-cards/G0/G0-03.1a.md) / [G0-03.1b](task-cards/G0/G0-03.1b.md) / [G0-03.1c](task-cards/G0/G0-03.1c.md) |
| G0-03.2 | G0-03 | 编写 Operation、事件与错误码合同 [G0-03.2a](task-cards/G0/G0-03.2a.md) / [G0-03.2b](task-cards/G0/G0-03.2b.md) / [G0-03.2c](task-cards/G0/G0-03.2c.md) |
| G0-03.3 | G0-03 | 审查并接受 ADR-001、002、003 的边界决策 [G0-03.3a](task-cards/G0/G0-03.3a.md) / [G0-03.3b](task-cards/G0/G0-03.3b.md) / [G0-03.3c](task-cards/G0/G0-03.3c.md) |
| G0-04.1 | G0-04 | 按固定指标收集语言方案的官方证据 [G0-04.1a](task-cards/G0/G0-04.1a.md) / [G0-04.1b](task-cards/G0/G0-04.1b.md) / [G0-04.1c](task-cards/G0/G0-04.1c.md) |
| G0-04.2 | G0-04 | 分别实现候选 SSH、vault、结果序列化 PoC [G0-04.2a](task-cards/G0/G0-04.2a.md) / [G0-04.2b](task-cards/G0/G0-04.2b.md) / [G0-04.2c](task-cards/G0/G0-04.2c.md) / [G0-04.2d](task-cards/G0/G0-04.2d.md) / [G0-04.2e](task-cards/G0/G0-04.2e.md) / [G0-04.2f](task-cards/G0/G0-04.2f.md) |
| G0-04.3 | G0-04 | 比较相同验收结果并接受 ADR-004 [G0-04.3](task-cards/G0/G0-04.3.md) |
| G0-05.1 | G0-05 | 编写本地数据、secret 引用和迁移合同 [G0-05.1](task-cards/G0/G0-05.1.md) |
| G0-05.2 | G0-05 | 分别验证 JSON 与 SQLite 的崩溃和并发行为 [G0-05.2a](task-cards/G0/G0-05.2a.md) / [G0-05.2b](task-cards/G0/G0-05.2b.md) |
| G0-05.3 | G0-05 | 比较证据并接受 ADR-005 [G0-05.3](task-cards/G0/G0-05.3.md) |
| G0-06.1 | G0-06 | 列出 macOS engine、签名和分发候选约束 [G0-06.1a](task-cards/G0/G0-06.1a.md) / [G0-06.1b](task-cards/G0/G0-06.1b.md) |
| G0-06.2 | G0-06 | 分别验证连接生命周期及目标芯片的最小 PoC [G0-06.2a](task-cards/G0/G0-06.2a.md) / [G0-06.2b](task-cards/G0/G0-06.2b.md) / [G0-06.2c](task-cards/G0/G0-06.2c.md) / [G0-06.2d](task-cards/G0/G0-06.2d.md) / [G0-06.2e](task-cards/G0/G0-06.2e.md) / [G0-06.2f](task-cards/G0/G0-06.2f.md) |
| G0-06.3 | G0-06 | 接受客户端框架、engine 与分发 ADR [G0-06.3](task-cards/G0/G0-06.3.md) |
| G0-07.1 | G0-07 | 按选定语言建立最小可构建工程 [G0-07.1](task-cards/G0/G0-07.1.md) |
| G0-07.2 | G0-07 | 添加格式化、单测和合同 fixture 入口 [G0-07.2](task-cards/G0/G0-07.2.md) |
| G0-07.3 | G0-07 | 添加 controller CI 并验证旧 Bash CI 保持有效 [G0-07.3](task-cards/G0/G0-07.3.md) |
| G1-01.1 | G1-01 | 实现 ServerTarget 数据校验与序列化 [G1-01.1](task-cards/G1/G1-01.1.md) |
| G1-01.2 | G1-01 | 实现单目标持久化、原子写和权限 [G1-01.2](task-cards/G1/G1-01.2.md) |
| G1-01.3 | G1-01 | 实现库存 CRUD、schema migration 与两目标隔离测试 [G1-01.3a](task-cards/G1/G1-01.3a.md) / [G1-01.3b](task-cards/G1/G1-01.3b.md) / [G1-01.3c](task-cards/G1/G1-01.3c.md) |
| G1-02.1 | G1-02 | 实现 CredentialStore 合同及 fake adapter [G1-02.1](task-cards/G1/G1-02.1.md) |
| G1-02.2 | G1-02 | 实现 macOS vault 获取、写入、删除 adapter [G1-02.2](task-cards/G1/G1-02.2.md) |
| G1-02.3 | G1-02 | 接入 SSH key/agent 引用并验证 vault 错误与导出无秘密 [G1-02.3](task-cards/G1/G1-02.3.md) |
| G1-03.1 | G1-03 | 实现 host trust store 与指纹匹配 [G1-03.1](task-cards/G1/G1-03.1.md) |
| G1-03.2 | G1-03 | 实现受限命令执行、超时与输出上限 [G1-03.2](task-cards/G1/G1-03.2.md) |
| G1-03.3 | G1-03 | 实现取消和 SSH 故障 fixture 并审查信任边界 [G1-03.3](task-cards/G1/G1-03.3.md) |
| G1-04.1 | G1-04 | 实现 root/sudo 能力探测与错误分类 [G1-04.1](task-cards/G1/G1-04.1.md) |
| G1-04.2 | G1-04 | 实现受限参数及路径验证 [G1-04.2](task-cards/G1/G1-04.2.md) |
| G1-04.3 | G1-04 | 实现安全临时文件上传、权限设置和断线清理 [G1-04.3](task-cards/G1/G1-04.3.md) |
| G1-05.1 | G1-05 | 实现 OS、systemd、CPU、内存和磁盘事实采集 [G1-05.1a](task-cards/G1/G1-05.1a.md) / [G1-05.1b](task-cards/G1/G1-05.1b.md) / [G1-05.1c](task-cards/G1/G1-05.1c.md) |
| G1-05.2 | G1-05 | 实现监听、DNS、防火墙与已有服务事实采集 [G1-05.2a](task-cards/G1/G1-05.2a.md) / [G1-05.2b](task-cards/G1/G1-05.2b.md) / [G1-05.2c](task-cards/G1/G1-05.2c.md) / [G1-05.2d](task-cards/G1/G1-05.2d.md) |
| G1-05.3 | G1-05 | 实现报告解析并验证 unknown 和全程只读 [G1-05.3](task-cards/G1/G1-05.3.md) |
| G1-06.1 | G1-06 | 实现 effective port/transport 冲突规则 [G1-06.1](task-cards/G1/G1-06.1.md) |
| G1-06.2 | G1-06 | 实现 TLS、域名、ownership 与 UDP unknown 规则 [G1-06.2a](task-cards/G1/G1-06.2a.md) / [G1-06.2b](task-cards/G1/G1-06.2b.md) / [G1-06.2c](task-cards/G1/G1-06.2c.md) |
| G1-06.3 | G1-06 | 实现兼容性结果汇总及阻塞案例 fixture [G1-06.3](task-cards/G1/G1-06.3.md) |
| G1-07.1 | G1-07 | 实现 operation 状态与事件持久化 [G1-07.1](task-cards/G1/G1-07.1.md) |
| G1-07.2 | G1-07 | 实现目标锁与幂等 operation ID [G1-07.2](task-cards/G1/G1-07.2.md) |
| G1-07.3 | G1-07 | 实现重连 reconciliation 和取消状态测试并审查 [G1-07.3](task-cards/G1/G1-07.3.md) |
| G1-08.1 | G1-08 | 实现字段级 secret 脱敏与恶意错误案例 [G1-08.1](task-cards/G1/G1-08.1.md) |
| G1-08.2 | G1-08 | 增加协议自动化模式禁止 URI/QR 输出 [G1-08.2](task-cards/G1/G1-08.2.md) |
| G1-08.3 | G1-08 | 隔离受保护 profile 导出通道并验证 deploy 日志 [G1-08.3](task-cards/G1/G1-08.3.md) |
| G1-09.1 | G1-09 | 实现无副作用的 DeploymentPlan 构造 [G1-09.1](task-cards/G1/G1-09.1.md) |
| G1-09.2 | G1-09 | 实现计划 hash 与执行前事实复核 [G1-09.2](task-cards/G1/G1-09.2.md) |
| G1-09.3 | G1-09 | 接入 BashDriver 并审查 ownership 和审批绑定 [G1-09.3](task-cards/G1/G1-09.3.md) |
| G1-10.1 | G1-10 | 实现锁定 tag、下载与 checksum staging [G1-10.1](task-cards/G1/G1-10.1.md) |
| G1-10.2 | G1-10 | 实现旧安装保留和 env 复制 [G1-10.2](task-cards/G1/G1-10.2.md) |
| G1-10.3 | G1-10 | 注入切换失败并验证版本记录与恢复目录 [G1-10.3](task-cards/G1/G1-10.3.md) |
| G1-11.1 | G1-11 | 适配 Hysteria 安装与配置入口 [G1-11.1](task-cards/G1/G1-11.1.md) |
| G1-11.2 | G1-11 | 适配启动、重启和结构化健康结果 [G1-11.2](task-cards/G1/G1-11.2.md) |
| G1-11.3 | G1-11 | 验证 secret 保留、TLS hook 和 port hopping 生命周期 [G1-11.3](task-cards/G1/G1-11.3.md) |
| G1-12.1 | G1-12 | 实现 native Hysteria client YAML renderer [G1-12.1](task-cards/G1/G1-12.1.md) |
| G1-12.2 | G1-12 | 生成受保护 bundle 与恢复说明 [G1-12.2](task-cards/G1/G1-12.2.md) |
| G1-12.3 | G1-12 | 验证 URI/Clash/sing-box 对照及离线导出边界 [G1-12.3](task-cards/G1/G1-12.3.md) |
| G1-13.1 | G1-13 | 核实 pinned native runtime 的真实配置验证方式 [G1-13.1](task-cards/G1/G1-13.1.md) |
| G1-13.2 | G1-13 | 补齐 darwin arm64 pin、缓存与完整性验证 [G1-13.2a](task-cards/G1/G1-13.2a.md) / [G1-13.2b](task-cards/G1/G1-13.2b.md) |
| G1-13.3 | G1-13 | 接入相关 CI 并验证坏字段失败和不可静默跳过 [G1-13.3](task-cards/G1/G1-13.3.md) |
| G1-14.1 | G1-14 | 组合应用服务为最小 CLI 闭环 [G1-14.1](task-cards/G1/G1-14.1.md) |
| G1-14.2 | G1-14 | 执行隔离 SSH 端到端故障 fixture [G1-14.2](task-cards/G1/G1-14.2.md) |
| G1-14.3 | G1-14 | 执行已授权验收 VPS 连接与 compat 回归并审查 Gate G1 [G1-14.3](task-cards/G1/G1-14.3.md) |
| G2-01.1 | G2-01 | 列出备份 manifest 与实际文件 allowlist [G2-01.1](task-cards/G2/G2-01.1.md) |
| G2-01.2 | G2-01 | 编写格式版本、加密及恢复钥匙候选比较 [G2-01.2](task-cards/G2/G2-01.2.md) |
| G2-01.3 | G2-01 | 审查恢复顺序与 credential 处理并接受 ADR-006 [G2-01.3](task-cards/G2/G2-01.3.md) |
| G2-02.1 | G2-02 | 实现一致性快照与 manifest exporter [G2-02.1](task-cards/G2/G2-02.1.md) |
| G2-02.2 | G2-02 | 接入选定加密实现及 backup inspector [G2-02.2](task-cards/G2/G2-02.2.md) |
| G2-02.3 | G2-02 | 实现 tamper、路径穿越、symlink 和错误钥匙测试并审查 [G2-02.3](task-cards/G2/G2-02.3.md) |
| G2-03.1 | G2-03 | 实现 RestorePlan 和新目标映射 [G2-03.1](task-cards/G2/G2-03.1.md) |
| G2-03.2 | G2-03 | 实现预检后原生重建与 cert/profile 更新 [G2-03.2](task-cards/G2/G2-03.2.md) |
| G2-03.3 | G2-03 | 在第二 VPS 恢复并验证 host trust 与独立连接 [G2-03.3](task-cards/G2/G2-03.3.md) |
| G2-04.1 | G2-04 | 实现结构化 status collector [G2-04.1](task-cards/G2/G2-04.1.md) |
| G2-04.2 | G2-04 | 实现受限日志读取和脱敏 [G2-04.2](task-cards/G2/G2-04.2.md) |
| G2-04.3 | G2-04 | 接入 restart 并验证 stale/offline/部分失败 [G2-04.3](task-cards/G2/G2-04.3.md) |
| G2-05.1 | G2-05 | 实现单一来源流量采样 [G2-05.1](task-cards/G2/G2-05.1.md) |
| G2-05.2 | G2-05 | 实现计数器重置、时间窗口与缺失采样处理 [G2-05.2](task-cards/G2/G2-05.2.md) |
| G2-05.3 | G2-05 | 标注来源差异并验证不冒充 provider 账单 [G2-05.3](task-cards/G2/G2-05.3.md) |
| G2-06.1 | G2-06 | 实现候选升级版本与旧配置快照计划 [G2-06.1](task-cards/G2/G2-06.1.md) |
| G2-06.2 | G2-06 | 实现候选切换及健康结果 [G2-06.2](task-cards/G2/G2-06.2.md) |
| G2-06.3 | G2-06 | 注入升级失败并验收回退及人工恢复边界 [G2-06.3](task-cards/G2/G2-06.3.md) |
| G2-07.1 | G2-07 | 实现币种、金额、周期和额度数据校验 [G2-07.1](task-cards/G2/G2-07.1.md) |
| G2-07.2 | G2-07 | 实现手工 TCO 与流量超额计算 [G2-07.2](task-cards/G2/G2-07.2.md) |
| G2-07.3 | G2-07 | 验证 unknown/free/owned、多币种和边界展示 [G2-07.3](task-cards/G2/G2-07.3.md) |
| G2-08.1 | G2-08 | 实现 VPNEngine 合同、profile store 与 fake engine [G2-08.1](task-cards/G2/G2-08.1.md) |
| G2-08.2 | G2-08 | 接入选定 engine 的 connect/disconnect/status [G2-08.2](task-cards/G2/G2-08.2.md) |
| G2-08.3 | G2-08 | 验证路由/DNS、休眠和网络切换恢复 [G2-08.3](task-cards/G2/G2-08.3.md) |
| G2-09.1 | G2-09 | 实现 server import/trust/preflight/plan 界面 [G2-09.1a](task-cards/G2/G2-09.1a.md) / [G2-09.1b](task-cards/G2/G2-09.1b.md) / [G2-09.1c](task-cards/G2/G2-09.1c.md) / [G2-09.1d](task-cards/G2/G2-09.1d.md) |
| G2-09.2 | G2-09 | 实现 profile/connect/operations 界面 [G2-09.2a](task-cards/G2/G2-09.2a.md) / [G2-09.2b](task-cards/G2/G2-09.2b.md) / [G2-09.2c](task-cards/G2/G2-09.2c.md) |
| G2-09.3 | G2-09 | 实现 cost/export/backup/restore 界面与流程测试 [G2-09.3a](task-cards/G2/G2-09.3a.md) / [G2-09.3b](task-cards/G2/G2-09.3b.md) / [G2-09.3c](task-cards/G2/G2-09.3c.md) / [G2-09.3d](task-cards/G2/G2-09.3d.md) |
| G2-10.1 | G2-10 | 建立签名分发包与安装卸载流程 [G2-10.1](task-cards/G2/G2-10.1.md) |
| G2-10.2 | G2-10 | 建立更新回退与干净用户环境测试 [G2-10.2](task-cards/G2/G2-10.2.md) |
| G2-10.3 | G2-10 | 验收 macOS MVP 并记录 Gate G2 证据 [G2-10.3](task-cards/G2/G2-10.3.md) |
| G3-01.1 | G3-01 | 按统一表格研究三家 provider API 与定价字段 [G3-01.1a](task-cards/G3/G3-01.1a.md) / [G3-01.1b](task-cards/G3/G3-01.1b.md) / [G3-01.1c](task-cards/G3/G3-01.1c.md) |
| G3-01.2 | G3-01 | 核实测试账号、资源权限与地域可用性 [G3-01.2](task-cards/G3/G3-01.2.md) |
| G3-01.3 | G3-01 | 比较证据并接受首家 Provider ADR [G3-01.3](task-cards/G3/G3-01.3.md) |
| G3-02.1 | G3-02 | 实现 ProviderAdapter 请求结果合同 [G3-02.1](task-cards/G3/G3-02.1.md) |
| G3-02.2 | G3-02 | 实现 fake discovery/pricing/resource action [G3-02.2](task-cards/G3/G3-02.2.md) |
| G3-02.3 | G3-02 | 实现认证、限流、timeout 和部分创建 fixture [G3-02.3](task-cards/G3/G3-02.3.md) |
| G3-03.1 | G3-03 | 实现 provider vault token 认证 [G3-03.1](task-cards/G3/G3-03.1.md) |
| G3-03.2 | G3-03 | 实现 regions/plans/pricing discovery [G3-03.2a](task-cards/G3/G3-03.2a.md) / [G3-03.2b](task-cards/G3/G3-03.2b.md) / [G3-03.2c](task-cards/G3/G3-03.2c.md) |
| G3-03.3 | G3-03 | 验证价格时间、币种、附加项及不可用套餐 [G3-03.3](task-cards/G3/G3-03.3.md) |
| G3-04.1 | G3-04 | 实现资源 ownership label 与创建记录 [G3-04.1](task-cards/G3/G3-04.1.md) |
| G3-04.2 | G3-04 | 实现异步 action reconciliation 和 firewall/SSH readiness [G3-04.2a](task-cards/G3/G3-04.2a.md) / [G3-04.2b](task-cards/G3/G3-04.2b.md) / [G3-04.2c](task-cards/G3/G3-04.2c.md) |
| G3-04.3 | G3-04 | 验证 timeout 不重复创建及可信 host 身份交接 [G3-04.3](task-cards/G3/G3-04.3.md) |
| G3-05.1 | G3-05 | 实现 quote 与费用明细展示 [G3-05.1](task-cards/G3/G3-05.1.md) |
| G3-05.2 | G3-05 | 组合 cloud create→SSH preflight→driver 流程 [G3-05.2](task-cards/G3/G3-05.2.md) |
| G3-05.3 | G3-05 | 验证状态变化触发重计划并端到端连接 [G3-05.3](task-cards/G3/G3-05.3.md) |
| G3-06.1 | G3-06 | 实现 DestroyPlan 与资源所有权检查 [G3-06.1](task-cards/G3/G3-06.1.md) |
| G3-06.2 | G3-06 | 实现删除 action 查询及孤儿资源清单 [G3-06.2](task-cards/G3/G3-06.2.md) |
| G3-06.3 | G3-06 | 执行授权测试资源销毁并核对云端和本地状态 [G3-06.3](task-cards/G3/G3-06.3.md) |
| G3-07.1 | G3-07 | 实现 provider usage 与计费周期映射 [G3-07.1](task-cards/G3/G3-07.1.md) |
| G3-07.2 | G3-07 | 实现预测、过期价格和缺失采样逻辑 [G3-07.2](task-cards/G3/G3-07.2.md) |
| G3-07.3 | G3-07 | 验证多节点成本及 forecast/bill 来源区别 [G3-07.3](task-cards/G3/G3-07.3.md) |
| G3-08.1 | G3-08 | 执行 fake provider 全周期故障回归 [G3-08.1](task-cards/G3/G3-08.1.md) |
| G3-08.2 | G3-08 | 执行首家授权账号完整生命周期 [G3-08.2](task-cards/G3/G3-08.2.md) |
| G3-08.3 | G3-08 | 核对资源账本与费用来源并验收 Gate G3 [G3-08.3](task-cards/G3/G3-08.3.md) |
| G4-01.1 | G4-01 | 适配 Xray driver 与 native profile [G4-01.1](task-cards/G4/G4-01.1.md) |
| G4-01.2 | G4-01 | 适配 Shadowsocks driver 与 native profile [G4-01.2](task-cards/G4/G4-01.2.md) |
| G4-01.3 | G4-01 | 验证真实客户端 transport 能力与升级回归 [G4-01.3](task-cards/G4/G4-01.3.md) |
| G4-02.1 | G4-02 | 适配 AWG runtime ID 与原生 conf [G4-02.1](task-cards/G4/G4-02.1.md) |
| G4-02.2 | G4-02 | 验证 AWG kernel/PPA 生命周期边界 [G4-02.2](task-cards/G4/G4-02.2.md) |
| G4-02.3 | G4-02 | 评估并单独决定原生 WG driver 支持范围 [G4-02.3](task-cards/G4/G4-02.3.md) |
| G4-03.1 | G4-03 | 实现 EasyNet 既有安装只读扫描 [G4-03.1](task-cards/G4/G4-03.1.md) |
| G4-03.2 | G4-03 | 实现一个已支持第三方 runtime 的 adoption plan [G4-03.2](task-cards/G4/G4-03.2.md) |
| G4-03.3 | G4-03 | 验证备份、ownership、撤销接管及未知格式拒绝 [G4-03.3](task-cards/G4/G4-03.3.md) |
| G4-04.1 | G4-04 | 实现迁移新目标与双端校验计划 [G4-04.1](task-cards/G4/G4-04.1.md) |
| G4-04.2 | G4-04 | 实现 endpoint/profile 更新和回切流程 [G4-04.2](task-cards/G4/G4-04.2.md) |
| G4-04.3 | G4-04 | 验收新端连通后退役旧端及断线恢复 [G4-04.3](task-cards/G4/G4-04.3.md) |
| G4-05.1 | G4-05 | 增加 Debian/ARM64 的能力 fixture 与报告 [G4-05.1](task-cards/G4/G4-05.1.md) |
| G4-05.2 | G4-05 | 增加家庭/VM/NAT/systemd 分类规则 [G4-05.2](task-cards/G4/G4-05.2.md) |
| G4-05.3 | G4-05 | 验收新增支持组合并明确 NAS 未验范围 [G4-05.3](task-cards/G4/G4-05.3.md) |
| G4-06.1 | G4-06 | 收集 SSH 管理不足与 Agent 候选收益证据 [G4-06.1](task-cards/G4/G4-06.1.md) |
| G4-06.2 | G4-06 | 验证 authenticated API 与独立 service PoC [G4-06.2](task-cards/G4/G4-06.2.md) |
| G4-06.3 | G4-06 | 决定实现或不实现 Agent 并写接受的 ADR [G4-06.3](task-cards/G4/G4-06.3.md) |
| G4-07.1 | G4-07 | 若 ADR 接受则实现最小管理 API/collector [G4-07.1](task-cards/G4/G4-07.1.md) |
| G4-07.2 | G4-07 | 若 ADR 接受则实现 SSH rescue 与同 operation ID [G4-07.2](task-cards/G4/G4-07.2.md) |
| G4-07.3 | G4-07 | 验证 Agent 卸载失联不影响数据面或登记 approved-not-applicable [G4-07.3](task-cards/G4/G4-07.3.md) |
| G4-08.1 | G4-08 | 实现协议连接 probe 和故障分类 [G4-08.1](task-cards/G4/G4-08.1.md) |
| G4-08.2 | G4-08 | 实现手动 fallback 与能力展示 [G4-08.2](task-cards/G4/G4-08.2.md) |
| G4-08.3 | G4-08 | 按 ADR 验证自动切换上限/backoff 或登记延期边界 [G4-08.3](task-cards/G4/G4-08.3.md) |
| G5-01.1 | G5-01 | 冻结平台无关应用服务 API/序列化合同 [G5-01.1](task-cards/G5/G5-01.1.md) |
| G5-01.2 | G5-01 | 实现第二平台 credential/VPN fake adapter [G5-01.2](task-cards/G5/G5-01.2.md) |
| G5-01.3 | G5-01 | 验证 FFI/IPC 错误与 capability matrix [G5-01.3](task-cards/G5/G5-01.3.md) |
| G5-02.1 | G5-02 | 实现 Windows vault 与 controller 适配 [G5-02.1a](task-cards/G5/G5-02.1a.md) / [G5-02.1b](task-cards/G5/G5-02.1b.md) |
| G5-02.2 | G5-02 | 实现 Windows VPN 权限与 lifecycle 适配 [G5-02.2a](task-cards/G5/G5-02.2a.md) / [G5-02.2b](task-cards/G5/G5-02.2b.md) |
| G5-02.3 | G5-02 | 验证 installer/update 和干净环境连接恢复 [G5-02.3](task-cards/G5/G5-02.3.md) |
| G5-03.1 | G5-03 | 实现 Linux 安全存储与 controller 适配 [G5-03.1a](task-cards/G5/G5-03.1a.md) / [G5-03.1b](task-cards/G5/G5-03.1b.md) |
| G5-03.2 | G5-03 | 实现 Linux TUN 权限与 lifecycle 适配 [G5-03.2](task-cards/G5/G5-03.2.md) |
| G5-03.3 | G5-03 | 验证发行包与既有 Linux installer 兼容 [G5-03.3](task-cards/G5/G5-03.3.md) |
| G5-04.1 | G5-04 | 验证 iOS 签名/隧道权限与真机 engine PoC [G5-04.1](task-cards/G5/G5-04.1.md) |
| G5-04.2 | G5-04 | 实现 iOS vault/profile/本地状态适配 [G5-04.2a](task-cards/G5/G5-04.2a.md) / [G5-04.2b](task-cards/G5/G5-04.2b.md) / [G5-04.2c](task-cards/G5/G5-04.2c.md) |
| G5-04.3 | G5-04 | 验证后台休眠网络切换并决策远程管理范围 [G5-04.3](task-cards/G5/G5-04.3.md) |
| G5-05.1 | G5-05 | 逐平台建立 native profile 与 compatibility 报告 [G5-05.1a](task-cards/G5/G5-05.1a.md) / [G5-05.1b](task-cards/G5/G5-05.1b.md) / [G5-05.1c](task-cards/G5/G5-05.1c.md) / [G5-05.1d](task-cards/G5/G5-05.1d.md) |
| G5-05.2 | G5-05 | 设计可选加密同步与冲突合同 [G5-05.2](task-cards/G5/G5-05.2.md) |
| G5-05.3 | G5-05 | 验证无同步服务仍可本地连接与恢复 [G5-05.3](task-cards/G5/G5-05.3.md) |
| G6-01.1 | G6-01 | 实现同币种套餐与额度比较 [G6-01.1](task-cards/G6/G6-01.1.md) |
| G6-01.2 | G6-01 | 实现 break-even 和预算规则 [G6-01.2](task-cards/G6/G6-01.2.md) |
| G6-01.3 | G6-01 | 验证 stale/unknown 数据与推荐可解释性 [G6-01.3](task-cards/G6/G6-01.3.md) |
| G6-02.1 | G6-02 | 实现设备到自有节点的测量采样 [G6-02.1](task-cards/G6/G6-02.1.md) |
| G6-02.2 | G6-02 | 实现采样窗口与资源开销上限 [G6-02.2](task-cards/G6/G6-02.2.md) |
| G6-02.3 | G6-02 | 验证可复现 benchmark 报告与比较边界 [G6-02.3](task-cards/G6/G6-02.3.md) |
| G6-03.1 | G6-03 | 实现只读自动恢复策略与预算计划 [G6-03.1](task-cards/G6/G6-03.1.md) |
| G6-03.2 | G6-03 | 实现用户启用后可执行的恢复/回切流程 [G6-03.2](task-cards/G6/G6-03.2.md) |
| G6-03.3 | G6-03 | 注入误报验证不重复建机、不误删原端并审查 [G6-03.3](task-cards/G6/G6-03.3.md) |
| G6-04.1 | G6-04 | 实现诊断事实到可审阅计划的合同 [G6-04.1](task-cards/G6/G6-04.1.md) |
| G6-04.2 | G6-04 | 接入辅助解释并限制工具执行边界 [G6-04.2](task-cards/G6/G6-04.2.md) |
| G6-04.3 | G6-04 | 验证任意 root/destroy 不被自动授权及手工离线路径 [G6-04.3](task-cards/G6/G6-04.3.md) |
