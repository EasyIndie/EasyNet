# Hosted baseline — bounded static preparation

Latest checkpoint: v2 implementation exists; initial local synthetic run failed (5/7 passing),
group cleanup unknown for normal child despite child reap/drain/FD closure. Runtime/guest remains unfrozen.
The v1 static-only state below is historical, not the current source checkpoint.

2026-10-10；工作包 1；状态 **planned / implementation blocked**，不是 ready binding。
仅静态读取及本报告写入；未运行源码/import/fixture/真实 CLI/guest，未安装、下载、读取凭据、提交或推送。
feature 分支已核对；现有两份凭据/路线文档改动未触碰；ar/av 预算 0，旧文件保留。
依据 [源码合同](../../poc/client-framework/hosted-baseline-contract.md) 与 [独立 R](hosted-ci-route-review.md)。

## 复用结论与精确身份

**没有可直接绑定、同时满足本合同全部保护的已审 helper。** 已审源码不是通用执行资格。
以下 SHA-256 来自当前文件的静态字节读取；没有运行文件或声明其 hosted 支持。

| 文件 | SHA-256 |
|---|---|
| `poc/client-framework/window-admission/driver.py` | `1aa1936a22aa36e5f9c0c7cd94b0c16d8f8f44e5105e79a61ca027c0b1f696fc` |
| `poc/client-framework/lab/isolate.py` | `3bc47c022eb6bf10004372cc4021e0d692720e81b318d5dd0cffb54b18d2522c` |
| `tests/client_framework/test_window_admission_driver.py` | `22cb979302bb45ff517b6d6e925ec18cec148f8d6927a8851b0b519cffc21f60` |
| `docs/planning/poc/client-framework/hosted-baseline-contract.md` | `76827dbf046d362d598db532378200ffa18649476265dee71445ba3c8628e8ea` |
| `docs/planning/poc/client-framework/runner-window-qualification-contract.md` | `06d93d10346eaff2de978298471849957d1d2da21bfa3de40dba0d25f8d546b1` |

driver 的 `clean_environment`/`close_except`/`reap_before`/`CleanupAttempts`/`guardian`/`bounded`
位于 353–670；对应 R 的 exact1557 source 接受及本地 11-fixture 资格见 [av 审查](G0-06.2av-review.md)。
可作为设计参考：保留 sentinel 组身份、直接子进程所有权、流式上限、取消/EOF、独立收尾及有限 proof。
不能直接 import 作为基线 helper：全文件 859 行、绑定窗口/旧 identity 来源与 metadata 阶段，
`LIMIT=16384`、`bounded()` 返回成功 stdout 或抛拒绝，未提供五命令逐项 4 KiB observation 接口。
其严格子环境不接受 provider 标签，组身份仅覆盖不逃逸的后代；没有外部读写/网络拒绝机制。
旧本地合成 qualification 不覆盖 fresh hosted kernel、官方 CLI、启动器/Python 或 Xcode/SDK 效果。
runner-window 合同明确 Q-A/Q-B、完整 guardian 与工具后代/写入效果仍未资格化。

isolate 的 `_environment():90` 转发 HOME/CODEX_HOME；`_execute():106` 为 2 s/8 KiB 的旧合成探针。
`_probe_guards():342` 与 `run_probe():364` 固定旧 fixture root/profile hash/合成 argv，不接受五个新 CLI。
其旧 sandbox 启动 abort 后读写/网络/继承资格未完成，见 [隔离决策](../../poc/client-framework/isolation-path-decision.md)。
更换 profile、环境、命令、时限或调用其私有 `_execute` 均是新安全设计，不能冒充既有复用。

## 尚未覆盖的必要保护

- owned job-temp 0700 根/decoy 的 canonical、owner、mode、inode、无链接/manifest 校验与固定清理。
- 外部读写和网络拒绝、子进程继承；精确 OS loader/Xcode/SDK 只读例外与隐式写入清单。
- 实际 launcher/入口/developer/SDK/downstream 身份及组/权限不变；固定文本版本不证明这些。
- 单命令 10 s/捕获 4 KiB、总 90 s 含最终 5 s；流式溢出即停止、取消后后代/FD drain/reap 的 hosted 证据。
- 官方 CLI 是否 fork/exec、daemon/setpgid/setsid、服务请求或写入仍未知；组 absent 不证明任意后代已回收。

## 完整最小固定用途方案（估算，待 R 决策；未授权新增文件）

保留当前合同的全部保护时，需要一个独立五命令 launcher，不能塞入 150 行 shell 或复用旧 bootstrap。
拟议额外路径 `poc/client-framework/hosted-ci/observe.py` 约 320 行：
固定 argv/环境/阶段及入口身份 45；owned root/decoy/manifest 55；流式 capture/deadline 55；
保留组 leader 的 fork/exec/取消/独立 TERM/KILL/reap/drain/FD 110；逐命令有限 report/拒绝 55。
不开放任意 argv、shell 文本、扫描、下载、安装、备用解释器、profile import 或配置扩展接口。
拟议 `poc/client-framework/hosted-ci/observe.sb` 约 45 行，只允许冻结的 loader/工具只读路径和 owned 写入，
默认拒绝外部读写/网络，继承相同拒绝；组/身份变化的禁止规则与必要系统服务须逐项审查，不能猜语法。
解释器绝对入口、启动方式、vendor 来源和固定 API 须另冻结；不得沿用 av 的失败 tuple 或个人机 pin。
五 CLI 精确解析分别限定 OS version/build、arm64、Xcode version/build、SDK version；每项有限错误独立保留。
报告含实际 provider 标签和 child/reap/output/FD proof；未知为 refused/unknown，≤4096 bytes，无原始路径/PID/流。
只有已审子进程闭包不逃逸且拒绝策略有效，才能以 held group 生命周期作为后代回收方案；否则停止。

原三个目标文件的拟议估算：`baseline.sh` 70 行（固定 adapter/hash/有限输出）；
`test_hosted_baseline.bats` 110 行（合成 schema/缺字段/错误差异/超时/溢出/取消/收尾失败）；
`client-hosted-baseline.yml` 55 行（literal false、repo+feature、完整 checkout SHA、github.sha、
persist-credentials false、contents read、5 min、无 secrets/缓存上传/下载、执行前 reviewed hash）。
完整固定用途安全 fixture 尚需额外约 120 行，覆盖 owned/decoy 拒绝、网络监听阴性、继承、身份/权限与生命周期故障；
Bats 合成输出不能代替这些实际策略证明。合计估算 720 行；需新增 helper/profile/test 路径和预算审查。
这是完整范围估算而非已实现精确行数；不得压缩、嵌入巨型解释器代码或用标志假造保护以守住旧预算。

## 合同边界决策与停止点

固定官方 CLI 观测与 untrusted candidate isolation 是两种资格问题；当前合同明确对前者也要求拒绝保护，
但尚未给出这些 CLI 的最小读取/服务/写入闭包，存在范围耦合。仅供独立 R 审议是否拆分；本卡不降低保护。
若 R 接受单独 trusted observer 合同，须明确逐项保留/替换的要求及新信任根，不能称已有 Q-A/Q-B 通过。
若保留当前全部要求，则须先接受上述独立固定用途 helper/profile/fixture 范围及工具效果合同，再允许源码准备。
涉及信任/权限设计变更，依执行规范停止；没有创建三个源码入口，没有改合同/旧 helper/旧 workflow 或标 ready。
下一步仅独立 R 对复用否定、合同拆分问题、额外固定用途预算与效果闭包作 disposition；未授予执行。
静态核查：准确路径/行号/hash 与既有 source 接受对齐；仅报告 whitespace 检查，不作行为资格声明。

## v2 successor 静态实现包（2026-10-10；root 已接受方向）

仅 v2 替换工作包1的信任与保护边界；上述 v1 复用否定仍有效，未使用旧 helper。
root 接受 observe.py 最小预算增量 220→255，仅用于 schema/provider/cleanup 一致性及最终取消处理。
四文件静态源码已创建，合计 443 行；尚未审源码、未导入/执行/语法编译/fixture/CLI/guest。
- `poc/client-framework/hosted-ci/baseline.sh`：18行，SHA `88fbb75df90cc7e93a906150b01cf23d4222b6aa45e618ba27ffcc674e9e9191`。
- `poc/client-framework/hosted-ci/observe.py`：250行，SHA `46481914336f0e1d8d426f950d185c443ac1e7342440278c89bac8ad7f9c03f5`。
- `.github/workflows/client-hosted-baseline.yml`：38行，SHA `7a666129e6712d37f285538d847ea87eedd928f0dc22eb12fad3e793e134ead2`。
- `tests/client_framework/test_hosted_baseline.py`：137行，SHA `bbee7b007d9ee3863f0b7a987d4dbf45097c24f76d78127a7072333cb71649e5`。
固定五CLI，子环境仅 PATH/LANG/LC_ALL；provider仅有限报告数据，无临时工程/原始日志。
逐命令9s操作+至多1s独立收尾，总90s内保留最后5s；捕获合计4096bytes，溢出即终止。
WNOWAIT观察不reap；持有直接leader至组TERM/KILL完成，随后有界wait/drain/selector/pipe close。
仅报告已知组信号尝试，不报告group absent或任意后代reap；失败独立保留有限错误及unknown状态。
waitid/WNOWAIT/入口/vendor支持仍未实测，不支持拒绝，不扫描备用API/解释器或恢复旧tuple。
测试源码覆盖parser/缺字段/schema/provider/cleanup拒绝及真实合成超时、溢出、取消、已知组后代/FD继承、cleanenv。
新增测试也需 exact hash 审查及私有fixture授权；不授予真实metadata或官方CLI资格。
workflow literal false，feature/source hash均明确 NOT_FROZEN；执行前固定hash校验；未上传/缓存/secrets使用。
root须冻结可执行commit绑定与全部执行hash后另审激活；占位不构成可执行runtime binding。
候选external-denial/decoy/identity/权限/真实后代门槛仍归Q-A/Q-B/NE，不被此metadata观察取代。
仅静态行数/hash/whitespace检查；未提交推送；等待同R一次完整 source/effects/fixture disposition。

## 两次本地失败后的 source-only 自然退出修订

root提供的两次结果均5PASS/2FAIL；保留失败和local预算0，不作归因或重试。
仅修改observer/test；自然双EOF后短片段wait，reap成功记group=not-requested，不再signal；取消竞态拒绝但不signal。
自然wait超时保留leader先TERM/KILL再wait/drain/close；其他wait异常ownership unknown，禁止signal，仍独立drain/close。
report仅接受reaped的not-requested，observed还需完整drain/FD/严格解析；任意后代与vendor/VM声明保留。
测试正常/非零自然退出采用not-requested；异常路径signalled；新增waittimeout/取消竞态/unknown不signal断言。
测试入口仅输出有限JSON计数，unittest文本/traceback仅内部StringIO；异常为有限refused，无路径/原始日志发布。
observe.py：273/300行，SHA `79394936e61caa7b7afb186d42be4991cf85fd2cb04560809606c28d68c00b5f`。
测试：179/180行，SHA `c8cde5ce28136b2ad40c22406a798e88e7e05bf1928de87e06511685be6dc890`。
本轮未执行/import/编译/测试/CLI/guest，未改shell/workflow/旧ar-av，未提交推送；仅静态hash/行数/whitespace。
等待同R精确source/hash审查；独立hosted synthetic-only合同/job由root另准备，未激活、未授予metadata资格。
