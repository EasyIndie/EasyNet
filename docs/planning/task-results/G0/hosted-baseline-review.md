# Hosted baseline successor — 独立R disposition

2026-10-10；工作包1；静态合同/安全审查；未执行源码、fixture、CLI、guest或凭据操作。
分支已核对；只改合同与本记录，不触碰现有其他diff。

**接受trusted observer与untrusted candidate isolation的分离方向；root接受前仍是proposal。**
v1的5个官方metadata CLI不运行输入配置/candidate，却要求完整candidate sandbox/decoy/后代闭包，
使150行adapter变成约720行新安全子系统。I的复用否定合理，旧helper已审范围未包含全部保护。
不直接import旧driver/isolate、不造generic bootstrap，不为推进宣称环境已资格化。

可接受的缩小是更改观测任务的信任根与成功含义：信任官方fresh VM vendor命令及已审observer，
收集有界metadata，承认版本信息不等于executable identity；真实engine/GUI/NE要求保持完整。
vendor misbehavior与逃逸后代风险由一次性无应用密钥VM承担，此假设不能迁移至候选或凭据job。
checkout/runner控制面存在token；clean子环境及persist-credentials false限制转发/落盘，不证明无凭据。

## 逐项disposition

| v1要求 | successor处置与实际安全意义 |
|---|---|
| 官方镜像、审SHA/action pin、固定argv | 保留，阻止任意候选代码/动态输入扩张observer执行面 |
| 无secrets/个人资料、最小权限、disabled、无下载/sudo/GUI操作 | 保留，限制实验价值/效果；不宣称vendor无隐式服务/cache |
| owned工程/root/decoy/manifest | 改pipe/no raw log，无候选工程无需decoy；临时文件仍owned0700；工程/decoy证明移交Q-A/Q-B/NE |
| 外部读写/网络拒绝及继承 | observer明确vendor信任替换，绝不报告denied；Q-A/Q-B/NE全部保留，后续合同实证 |
| 入口/developer/SDK/downstream身份 | metadata记not-qualified，不猜文本/路径等价；实际资格移交candidate/toolchain合同 |
| 组/权限/身份不变与拒绝保护 | observer不声称验证，信任vendor；候选门槛完整保留，不继承metadata状态 |
| 流式输出/时间上限、直接child/FD收尾 | 保留，防止无限挂起/日志泄漏；清理unknown独立拒绝，不能吞失败 |
| 任意后代/逃逸/service清理证明 | observer明确not-proven；已知组有界收尾，VM最终隔离；候选完整证明延期至Q-A/Q-B/NE，非豁免 |
| VM销毁替代测试收尾 | 拒绝此表述；本进程必须尝试收尾，provider final cleanup未实测，硬停可能无报告 |
| A/B真engine/GUI、NE同意/真实流量 | 不改；baseline不授予运行资格，需独立frozen binding/证据 |
| 签名/临时Keychain/profile/公证/发布 | 不改；独立可信SHA凭据job，NE profile缺失继续记录 |
| 初始一次+定向修复一次、ar/av预算0 | 保留，不切OS/路径重跑，不声称G0完成 |

## 最小可执行后继

[v2合同](../../poc/client-framework/hosted-baseline-contract.md)给出3个实现+1个测试路径、5条literal argv、固定解释器入口。
固定observe.py预计≤220行；shell≤40、workflow≤70、test≤140；超限报告实际缺口，不压缩安全机制。
Python入口按官方fresh镜像vendor信任，不沿用历史tuple或新增巨大prebootstrap；无任意argv/安装/发现接口。
checkout沿用root提供的已审SHA；feature/source hash须实际source审查后冻结，本轮未核验任何新源码。
静态source审查→独立冻结私有synthetic fixture→runtime binding/hashes→一次fresh guest，顺序不倒置。
source审查重点：incremental cap/deadline、leader未reap前组信号、独立wait/drain/close与有限unknown。
当前尚无源码或行为证据，不能标ready/verified；本审查不授权任何运行。
root接受后需在主路线明确工作包1采用v2，消除旧baseline全部sandbox条款与新合同冲突。
若root不接受vendor信任，最小可行仍是I的独立helper/profile/拒绝fixture方案：先冻结工具读/服务/写/后代闭包与额外预算；闭包未知则blocked，不启动guest。

验证：仅文档diff/whitespace；无行为测试、安装、凭据读取、Git写入或旧预算恢复。

## 一次完整 source/effects 审查（2026-10-10，同工作包）

结论 **source blocked，仅同卡定向修复；当前不授予fixture/CLI/guest**。
静态字节核对4个SHA与preparation附表完全一致：
- baseline.sh `88fbb75df90cc7e93a906150b01cf23d4222b6aa45e618ba27ffcc674e9e9191`
- observe.py `46481914336f0e1d8d426f950d185c443ac1e7342440278c89bac8ad7f9c03f5`
- workflow `7a666129e6712d37f285538d847ea87eedd928f0dc22eb12fad3e793e134ead2`
- test `bbee7b007d9ee3863f0b7a987d4dbf45097c24f76d78127a7072333cb71649e5`
成立部分：5条固定argv/closed env；捕获存储≤4096、最终JSON≤4096且schema验证；有限unknown标签；
流式超限停止、9s捕获+1s收尾；当前不poll/reap，组TERM/KILL在wait前；独立wait/drain/selector/pipe close。
cleanup注入测试检查后续尝试未跳过；group/reap/drain/close失败是合成mock证据，非native故障实证。
workflow literal false+未冻结SHA/hash确实拒绝；checkout固定SHA、无cache/upload/secrets；bootstrap hash后才启动observer。

完整阻塞清单（不追加generic研究）：
1. `observe.py:95,119`依赖waitid/WNOWAIT；root核实[Python官方文档](https://docs.python.org/3/library/os.html#os.waitid)明确macOS支持自3.13才加入。
   固定vendor入口未证明≥3.13，当前设计不可作为macos-15可用baseline；unsupported虽安全拒绝，不能以guest发现此已知缺口。
   最小修复：移除waitid/WNOWAIT，持有leader且不poll/wait/reap；drain至双pipe EOF或deadline，再发组信号后wait。
   `finished`只表示捕获结束，EOF不冒充exit；cleanup后code==0且无stderr/清理失败才允许observed。
2. 为保持PID/PGID安全，启动前明确要求SIGCHLD默认，拒绝ignored/其他handler；否则leader可被自动reap而失去所有权。
   固定单线程observer无其他reaper，Popen对象持有到组信号完成；不引入sentinel或通用guardian。
3. 测试:73直接调用cancel setter，尚未验证实际SIGTERM交付；改为安装handler后真实signal，finally恢复原handler。
   移除waitid/WNOWAIT create=True mock；继承FD的descendant case在EOF设计下应timeout并完整收尾，不能继续期望none。
   加明确unsupported/SIGCHLD拒绝不spawn断言；完整五record成功schema及最终取消拒绝建议作为同次fixture核验，不能称mock为native通过。
以上一次完整列出；其余candidate拒绝/身份/任意后代证明不扩回observer。修复若超测试预算，报告实际最小增量，不压缩安全测试。
下一步：I同卡修observe/test并更新hash，再定向R核对上述三项；source接受后才给exact私有fixture命令/效果/预算。
未来runtime需source commit与activation commit分离，冻结checkout source SHA；当前github.sha自引用占位不构成激活方案。
本轮只静态读取/hash与文档whitespace检查，未导入/执行源码、测试、真实CLI、guest或凭据；ar/av预算0。

## 同卡定向修复 source acceptance

2026-10-10；root修复后三项静态核对通过，**接受精确源码仅用于本地私有合成fixture**，不授予真实CLI/guest。
observe SHA `f450f4f331837524c2f17ac9c721fcc225dad2dd139c8b0de4be620c8cc86092`；test SHA `507b11a222543490fd50ab81dd34e1185f7e62310d9f60adcc6eaabc2e8ef031`。
shell/workflow SHA仍为上一节已核对值；249/150行分别在root接受预算内。
已移除waitid/WNOWAIT；默认SIGCHLD检查在spawn前；双pipe EOF只终止捕获，TERM/KILL后才wait，未提前poll/reap。
真实SIGTERM测试恢复handler；FD继承case明确timeout且收尾；mock清理故障与SIGCHLD不spawn、五record成功/最终cancel schema测试齐备。
最终cancel测试证明schema容纳取消，不单独冒充完整main的信号时序实证；故障注入仍非native拒绝/任意后代证明。
root执行前重新核对上述两个SHA；cwd `/Users/joker/Documents/EasyNet`，精确命令：
`/usr/bin/python3 -I -B tests/client_framework/test_hosted_baseline.py -v`
效果：仅import已审observer与7个unittest；8类固定Python合成case、私有mock，无官方metadata CLI、网络/安装/凭据/guest。
真实合成child/同组后代最多sleep30s，但capture0.4s与最多1s收尾负责TERM/KILL/reap/drain/close；SIGTERM只发送测试进程自身。
目标：当前本地Darwin固定vendor Python；-B禁止repo bytecode写入；仅控制台有限测试结果，无工程/原始日志持久化。
预算：一次初始suite、总30s；超预算/清理异常停止并记录unknown；仅明确故障+已审修复可一次定向重验，不循环试跑。
预期7测试exit0且生命周期proof符合断言；失败不得授予runtime。R未运行源码或fixture；whitespace检查通过，workflow仍disabled，ar/av预算0。

## 最后一次定向fixture：执行边界复验

首次同SHA本地tool sandbox fixture：exit1，7tests中5PASS/2FAIL，0.153s；normal/environment直接child已reaped，group unknown。
lifecycle循环在首个normal断言停止，不能声称overflow/timeout/descendant矩阵已运行；cancellation及mock/parser/schema/SIGCHLD通过。
不推断group异常errno或历史原因；首次失败保留，不将未知收尾写success。失败用例未启动descendant case，当前无该case泄漏证据。
R接受**唯一剩余的一次执行边界定向复验**：source/test SHA仍为上节精确值，cwd/命令不变，目标改为本地Darwin工具sandbox外。
root可对 `/usr/bin/python3 -I -B tests/client_framework/test_hosted_baseline.py -v` 使用 `require_escalated` 正常自动审批；R接受不绕过审批结果。
理由：已审源码只生成固定合成child/同组后代；直接leader默认SIGCHLD且未reap前才组signal，mock不向PID123发真实信号；无任意输入或系统设置。
边界变化仅移除工具执行sandbox，不修改application测试保护、源码、group异常处理或unknown语义；不新增probe/logging/权限能力。
效果/30s预算同上；这是具体group信号失败的执行目标修正，不补发新initial额度或重跑ar/av，之后额度为0。
预期7tests exit0且各真实合成case实际通过；失败/超时即停止、保留unknown，不再切环境或增加诊断链。无真实CLI/guest/凭据授权。
R本轮仅记录disposition与whitespace检查，不执行fixture；若自动审批拒绝，报告拒绝及原因，不能将R接受表述为审批已通过。

## 两次失败后的语义 disposition（不授予重试）

唯一sandbox外复验仍exit1、5PASS/2FAIL、0.155s；wrapper假设未成立，不推断errno/历史归因。两份失败保留，local fixture预算0。
R接受**trusted observer正常完成语义**的source-only修订方向；现有源码/guest仍blocked，无新执行授权。
双pipe EOF仅表示捕获结束，可在余下单命令/总deadline内有界wait；自然wait返回后记child=reaped、group=not-requested，绝不再signal已释放PID/PGID。
正常exit0、无stderr、解析有效且drain/FD清理通过才observed；not-requested不是signalled/不存在后代证明，descendants仍not-proven、VM cleanup仍provider-managed-unverified。
依据v2明确vendor信任，正常返回后可能存在关闭FD的后代/服务，由一次性VM最终隔离；不将此语义迁移至candidate/GUI/NE或凭据job。
EOF前timeout/cancel/overflow/capture故障仍先对未reap leader的已知组TERM/KILL，再独立wait/drain/close。EOF后的natural wait超时亦走此路径。
natural wait可用短片段TimeoutExpired循环检查取消/剩余deadline；TimeoutExpired保留leader所有权，成功wait立即停止后续group signal。
取消与成功wait竞争时，以实际已reap为准，报告cancel且不得补发group signal；任意其他wait异常不能假定仍持有PID，记ownership/cleanup unknown并停止，不冒险signal。
最小源码改动仅capture正常/异常分支与有限group enum/schema；维持默认SIGCHLD、closed env、cap/time、独立收尾及五条固定argv，无新helper/发现接口。
测试相应分开自然wait0→not-requested、非零自然退出、EOF但仍活跃→waittimeout/取消、原timeout/overflow/继承FD异常收尾；mock不得误用正常EOF替代异常组信号路径。
修订只解决不必要的正常组signal要求，不把两次失败改成pass；新source/hash/test须完整定向审查，local预算不恢复。
独立资格途径：另冻fresh macos-15 **synthetic-only** job，固定checkout action+已审source commit+执行文件hash，默认disabled、无secrets/cache/upload/真实CLI。
job仅运行已审test（固定vendor `/usr/bin/python3 -I -B`），明确suite/job时限、输出上限、自然/异常路径证据及provider最终VM清理声明；与metadata job分开绑定。
root先产具体workflow/source/hash/fixture合同再R审查；可申请一次新hosted合成资格，不复跑旧ar/av，不执行metadata CLI，不凭source acceptance提前激活。
R本轮仅文档disposition/whitespace检查，无源码改动、fixture、guest、凭据或新诊断。

## 正常退出 successor / hosted synthetic source acceptance

2026-10-10；一次完整source/effects及后继合同静态审查；**接受静态冻结，不授予本机/guest运行或metadata执行**。
已核对observe SHA `79394936e61caa7b7afb186d42be4991cf85fd2cb04560809606c28d68c00b5f`（273行）、test `c8cde5ce28136b2ad40c22406a798e88e7e05bf1928de87e06511685be6dc890`（179行）。
workflow草案 SHA `47b25de9ec1524b2fb3354157cceb9d5854bac15620d088c1ec90fd3f76f63ff`（63行）；baseline仍 `88fbb75df90cc7e93a906150b01cf23d4222b6aa45e618ba27ffcc674e9e9191`。
自然EOF→短wait；成功reap后not-requested且无组信号；TimeoutExpired保留leader，异常held路径TERM/KILL后wait。
其他wait异常转ownership unknown并不signal；取消与成功reap竞争只记cancel；独立drain/selector/pipe close仍尝试，unknown拒绝。
默认SIGCHLD、closed env、stream/report cap、有限schema未放宽；good record仅允许自然reap/not-requested/全FD收尾成功。
测试8项覆盖自然/nonzero、异常timeout/overflow/继承FD、自身SIGTERM、unknown-no-signal及自然waittimeout；mock在异常分支检查收尾顺序。
测试JSON入口只输出有限counts/status；真实异常清理/全部case尚未在新source下实证，mock不是native隔离/后代证明。
未发现需新增helper的source blocker；接受[hosted fixture合同](../../poc/client-framework/hosted-fixture-contract.md)作为单次synthetic-only目标草案。

root可机械冻结的唯一范围：synthetic job的observer/test两hash填上述值；source checkpoint形成后将该job checkout.ref填完整source SHA。
observer/test内容不变；metadata literal false及其未冻结baseline/hash/feature占位全部保留，不顺手激活metadata。
workflow activation仅synthetic predicate加入本repo+feature+精确单次完整commit message，保持其余effects/timeout/source hashes/checkout pin。
先提交source checkpoint，再静态生成activation commit；记录完整source SHA、activation SHA、最终workflow SHA及消息，**R runtime接受前不push触发**。
activation SHA用外部binding冻结，不能在同一commit内猜自引用；push目标必须是已审activation commit，之后重复消息/手动rerun不获授权。
workflow直接vendor入口为固定 `/bin/bash --noprofile --norc`、`/usr/bin/env -i`、`/usr/bin/shasum -a 256`与 `/usr/bin/python3 -I -B`。
shasum/Python的vendor解释器、stdlib/loader/default resolution同属fresh镜像信任，不扫描/安装/改PATH；-I阻断repo import搜索，-B禁repo bytecode。
repo代码仅两已核hash的显式import；mock/provider-refused main不调用真实metadata COMMANDS。checkout网络/只读token属于workflow控制面，非fixture网络授权。
有限fixture命令固定 `/usr/bin/python3 -I -B tests/client_framework/test_hosted_baseline.py`，无-v/动态argv/provider输入；报告须exit0、tests=8、failures=0、errors=0、result=passed且有限JSON一致。
预算拟定hosted一次初始synthetic guest；suite预计≤30s、job硬停2min，超限/非零/缺报告即失败或unknown，无自动额外运行/OS轮换。
root冻结后R再审最终predicate/全部hash/commit绑定才能授运行；workflow平台控制面日志并非fixture JSON，成功不证明VM销毁或任意后代清理。
local预算0、两次失败及ar/av全部保留；通过后也仅可准备metadata runtime binding，不能完成Q-A/Q-B/GUI/NE/ADR或G0。
本轮仅静态读取/字节hash与whitespace检查，未修改observer/test/workflow、未运行源码/fixture/真实CLI/guest或读取凭据。

## 精确 hosted synthetic runtime acceptance

2026-10-10；R只读核对Git对象、最终workflow与binding，**接受并冻结一次synthetic-only runtime**，尚未运行。
source `f051f82a497a20d490f549f26523872079060652` 的observer/test字节SHA与上节一致；未凭工作目录相同推定commit相同。
activation `2d4806b6ba4232fa8cdd902be681b150bafa2425` 的parent恰为source；仅workflow两行predicate/ref变更。
最终workflow SHA `4743209ed50d29724b1da39d70999032d10b23d9cb018fa8bf210ffd09f54e92`；source checkout/action/两hash/closed env/命令均一致。
activation消息恰为 `Run one hosted synthetic fixture f051f82a497a20d490f549f26523872079060652`，predicate限定本repo/feature及此完整消息。
metadata job literal false/未冻结占位完整保留；权限contents read、无应用secrets/cache/upload/matrix/重试，现有release gate未改。
`hosted-synthetic-runtime.json` status改frozen；只授权root将此**指定activation SHA**正常push至指定feature ref，不force、不顺带后续commit。
该push可触发现有常规CI；仅本synthetic fresh macos-15 job获一次新guest预算，无手动rerun/重复消息/其他OS执行授权。
执行仅固定 `/usr/bin/python3 -I -B tests/client_framework/test_hosted_baseline.py`；hash校验后才能import，供应方vendor loader/stdlib沿用信任合同。
预期suite≤30s、job硬停2min；通过要求exit0及有限schema1/resultpassed/tests8/failures0/errors0一致；缺报告/超限/非零保留failed/unknown。
root记录实际run/job/commit结果并使synthetic恢复禁用；guest额度本次使用后0，未运行不得先记pass。
local预算始终0，两次本机失败/旧ar/av不改；不授予真实metadata CLI/engine/GUI/NE/签名/凭据或正式发布。
本轮只更改binding状态与本审查记录，未执行任何源码、fixture、guest或Git写操作；whitespace检查通过。

## Hosted synthetic evidence / metadata 静态冻结接受

2026-10-10；依据root已核验的run `38014394083` / job `114101346437`记录，接受唯一JSON schema1/passed/tests8/failures0/errors0及job success，metadata skipped。
这是新source的hosted synthetic-fixture-only通过，不归因两次local失败，不提升任意后代/外部拒绝/engine/GUI/NE/签名资格。
observation JSON保留local unknown、两次5/7与剩余0；synthetic predicate恢复literal false；binding改consumed，guest/local remaining均0。
静态核对metadata机械冻结：baseline仅expected placeholder→已审observer hash，shell SHA `81be011a5bf5801e976d8ed81d0665fd21cbcba44f4d5686abd17d3f5bc69c2c`；observer仍 `79394936e61caa7b7afb186d42be4991cf85fd2cb04560809606c28d68c00b5f`。
workflow仅冻结metadata shell/observer hash，metadata false与未冻结runtime占位仍保留；当前不运行真实CLI。
接受v2五条固定sw_vers/uname/xcodebuild/xcrun argv的trusted vendor效果scope；允许fresh VM系统读取/服务/cache，不称外部拒绝或精确toolchain identity。
沿用closed CLI env、provider有限数据、stream/report cap、90s总/每命令≤10s、natural not-requested及异常held-leader收尾；任何stderr/未知格式/非零/清理unknown拒绝。
root可创建metadata source checkpoint；随后activation仅改metadata predicate为repo/feature/精确一次message及checkout.ref固定source SHA，synthetic始终false。
最终source SHA、activation SHA、workflow SHA、两个执行hash、固定baseline命令/provider映射与预算须另建metadata binding再R runtime审；不能保留github.sha自引用假装冻结。
真实metadata初始guest预算尚未使用，拟一次macos-15观察；不复用synthetic/local/ar-av额度，不自动授第二次修复运行或其他OS。
本接受只授静态commit准备，不授push触发、CLI/guest/tests/凭据/系统变更；metadata成功也仅metadata-observed，不完成其余G0-06资格。
R本轮只读/evidence一致性/hash及binding/review修改，whitespace通过；未远程重跑/下载日志或执行任何源码。

## 精确 metadata runtime acceptance

2026-10-10；R接受并冻结metadata-only runtime；本轮只读Git对象，不执行源码/CLI/guest。
source `5ecacc5f601c7442fd6c40e1041db5bf341cb2f2` 的shell/observer字节SHA准确匹配81be011…/793949…；沿用已审v2效果与合成证据。
activation `5ee0478a14538400f40745bffdc4630e6c21b15e` 的parent恰为source，只改metadata predicate及checkout.ref两行。
最终workflow SHA `c2f538b641e30e5a56a2016ff3e91a3bd467775911bea712cd337ba6e01f0518`匹配binding；精确消息 `Run one hosted metadata baseline 5ecacc5f601c7442fd6c40e1041db5bf341cb2f2`、repo/feature固定。
checkout完整action SHA/persistfalse/source ref、两执行hash、baseline二次校验、closedenv与仅ImageOS/ImageVersion有限转发均成立。
五argv/固定entry与v2相符，无发现/安装/凭据/GUI操作；provider标签和默认工具链版本不作精确身份证明。
metadata binding改frozen，并将toolchain/descendants/external-effects/vm-cleanup四个既有未知边界常量纳入expected，避免观测被误标完整资格。
准许root**正常push指定activation SHA**至指定feature一次，不force、不顺带未审commit；现有标准CI可照常运行，release gate未改。
只授一个fresh macos-15 metadata guest；synthetic literal false/remaining0、local0保持，不手动rerun/重复消息/换OS或自动追加修复。
总90s含收尾、每CLI≤10s/捕获≤4096、report≤4096，job5min；要求exit0、schema1/metadata-observed/errornone、5条完整顺序observed与provider/cleanup/schema一致。
natural child reaped/not-requested，drain/fds true；任一非零/stderr/格式/清理unknown/缺报告/超限失败或unknown，不安装或改环境继续。
通过仅version-metadata-only，后代/外部拒绝/VM销毁及toolchain identity仍未证明，不授engine/GUI/NE/签名资格。
root记录实际run/job/有限报告，消耗metadata一次额度后恢复false、binding consumed+remaining0；结果与禁用同包关闭。
本轮仅binding/review修改及whitespace检查通过；无Git写操作、CLI/fixture/guest或凭据读取。

## Metadata evidence / 工作包关闭接受

2026-10-10；依据root核验的唯一run `38014757342` / job `114102459593` success，定向核对record/observation/binding一致，接受metadata-observed。
5个label顺序完整且均observed/errornone；每项child reaped/group not-requested/drain true/fds true，四个未知边界常量保持；无原始路径/PID/环境/流。
ImageOS macos15、ImageVersion 20260907.0337.1；OS15.7.9/build24G830/arm64/Xcode16.4 build16F6/SDK15.5，是默认工具的有限版本信息，非精确身份或资格。
source/activation对应5ecacc5…/5ee0478…；synthetic skipped；metadata observation剩余guest/local均0且明确仅version-metadata-only。
metadata binding改consumed及guest/local remaining0；synthetic已consumed，workflow两个predicate均literal false，关闭diff仅禁用metadata一行。
接受该无密钥hosted baseline工作包的限定范围关闭；无下一实验/修复/retry/OS矩阵/CLI/guest/凭据授权。
root可提交/push当前禁用关闭及证据/metrics；不重复激活消息、不复跑旧SHA，既有release gate不改。
两次local失败原因仍unknown；任意后代/外部拒绝/VM销毁及toolchain/Q-A/Q-B/GUI/NE/签名资格保持未证明，不宣称G0完成。
常规CI38014394023据root记录success；38014757324仍待root核对，本审查不把未核对的常规CI记pass。
R本轮仅静态evidence一致性与binding/review修改，whitespace通过；未执行源码、fixture、CLI、guest或Git写操作。
