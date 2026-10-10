# Hosted baseline trusted observer contract v2 — successor proposal

2026-10-10；工作包1；独立R审查后 root 已接受 v2 拆分，**仅允许有界静态源码准备，runtime binding未冻结**。
不授权fixture/CLI/guest、安装、凭据或workflow激活。
依据[主路线](hosted-ci-qualification-route.md)与[静态准备](../../task-results/G0/hosted-baseline-preparation.md)。
v1把官方metadata观测与候选隔离资格耦合；本successor仅替换工作包1要求。
主路线的完整隔离证明仍适用engine/GUI/NE；v1 被此范围明确的 successor 替代，不恢复旧实验。

## 产品目标与信任边界

取得一次fresh `macos-15` arm64的OS/build/arch与默认Xcode/SDK文本，避免盲目准备不匹配的候选工程。
结果是 **metadata-observed**，不是image identity、developer/SDK/downstream身份或执行资格。
默认developer选择不作修改；真实developer路径/文件身份未观测，记 `not-qualified`。
真实toolchain/engine、GUI、NE、签名、公证、安装生命周期另有合同与实证；baseline不解锁其执行。

信任根是GitHub官方fresh VM镜像、受限checkout action与已审feature SHA的observer源码。
镜像内的绝对入口及正常loader/系统服务/后代属于可信observer闭包，不视为不可信candidate。
这是vendor信任取舍，不是证明它们不会外部读写、联网、fork/exec或逃逸进程组。
无Apple/SSH/应用secrets、个人资料或用户配置；checkout只读GitHub凭据与runner控制面仍存在。
`persist-credentials:false`，不向子进程转发credential/runner环境；不声称整台runner没有令牌。
不执行repo其他脚本、engine、GUI、用户输入或任意argv；不安装、下载、sudo、登录、改设置或响应系统提示。
固定命令可能读系统文件、调用服务或产生vendor cache；允许这些效果留在一次性VM内。
不设置外部拒绝sandbox，不称网络被阻断；metadata命令不显式请求网络。交互、错误或超限即拒绝，不修复环境。

## 固定文件与argv

root接受方向后才准备下列源码；本轮均未创建，随后须完整source/hash/effects审查。

| 文件 | 唯一职责与审查预算 |
|---|---|
| `poc/client-framework/hosted-ci/baseline.sh` | ≤40行；校验固定observer hash，以 `/usr/bin/python3 -I` 启动固定文件，无discovery/fallback |
| `poc/client-framework/hosted-ci/observe.py` | ≤300行；固定表、clean env、流式捕获、已知组/直接child收尾、有限JSON；非通用launcher |
| `.github/workflows/client-hosted-baseline.yml` | ≤70行；literal false，本repo/feature已审SHA，5min、`contents:read`，无上传/cache/secrets |
| `tests/client_framework/test_hosted_baseline.py` | ≤180行；私有合成parser/生命周期fixture，不授予真实工具资格 |

预算是完整固定用途估算；超出时报告具体缺口与实际行数，不压缩、内嵌巨型代码或扩写generic bootstrap。
root 接受实现者报告的最小 +35 行预算，用于完整有限 schema/provider/cleanup 一致性与最终取消处理；
该增量仍须同 R 完整源码审查，不授予运行。
root 接受测试最小 +10 行，用于 SIGCHLD 拒绝、实际 SIGTERM 及完整成功/最终取消 schema 用例。
两次本机失败后，R接受source-only自然退出语义修订；预算至300/180行仅用于
EOF后有界wait/取消/未知所有权及对应有限报告测试，不扩展通用helper。
Python入口按官方fresh镜像vendor信任处理，不沿用历史av tuple；不存在/需取得工具/需交互则拒绝，不扫描备用入口。
checkout采用已审 `3d3c42e5aac5ba805825da76410c181273ba90b1`，`ref: github.sha`、`persist-credentials:false`。
feature/source hash由root在实际源码审查后冻结，不填猜测值。禁止PR/fork、matrix、自动重试和签名job共用环境。
一次人工授权绑定一个feature commit；执行前校验全部执行文件hash。
严格依次执行以下命令，无参数覆盖、shell字符串、插件或额外discovery CLI：

1. `/usr/bin/sw_vers -productVersion`
2. `/usr/bin/sw_vers -buildVersion`
3. `/usr/bin/uname -m`
4. `/usr/bin/xcodebuild -version`
5. `/usr/bin/xcrun --sdk macosx --show-sdk-version`

子环境只含固定 `PATH=/usr/bin:/bin`、`LANG=C`、`LC_ALL=C`；不重设HOME，不继承ambient环境。
provider `ImageOS`/`ImageVersion`由workflow作为有限数据输入，严格ASCII/长度校验，不进入CLI子环境。
不传DEVELOPER_DIR、SDK覆盖、DYLD/PYTHON配置、令牌或个人路径；default resolution属于未资格化信息。
退出0且严格语法通过才记observed；OS major必须15、arch必须arm64；Xcode/SDK文本只记录，不推定兼容。
预定格式：OS/SDK有界点分十进制，OS build有界ASCII字母数字，Xcode恰为version/build两行；详细regex由源码审查冻结。
stderr非空、退出非零、缺字段、未知格式分别拒绝；不输出原始stderr，不猜原因、不安装/扫描备用工具。

## 有界收尾与有限报告

总限时90s，最后5s用于收尾；每命令10s；stdout/stderr合计≤4096bytes，增量读取，溢出立即停止。
报告≤4096bytes：固定schema/phase/command、observed/refused、错误枚举、有限版本/provider标签。
不输出环境、任意路径、PID、原始流；provider标签是自报信息，非精确镜像pin。
pipe捕获，不建工程/decoy、不写原始日志；若必须有临时文件，仅owned 0700 job-temp固定文件并独立清理。
每CLI单独 `start_new_session`，持有直接child；组信号须在leader被reap前完成，避免PGID/PID复用误杀。
正常双EOF后有界wait；自然reap后group记not-requested，不再向已释放PID/PGID发信号。
超时、取消、溢出及natural wait超时，仍在leader未reap前尝试组TERM/KILL，再wait/drain/close；失败不跳过其他尝试。
natural wait短TimeoutExpired片段检查取消；成功wait竞态取消仅拒绝、不补信号；其他wait异常ownership unknown拒绝并禁止信号。
EOF不代表child或descendants已退出；等待/清理状态单列，不以kill成功或group absent冒充任意后代证明。
直接child未reap、已知组收尾或FD/临时文件清理未知则refused/unknown并停止新命令，不无界wait。
报告始终含 `descendants=not-proven`、`external-effects=trusted-vendor-not-denied`、`vm-cleanup=provider-managed-unverified`。
这些声明不能写success；不使已完成metadata无效，也不允许声称整体隔离测试通过。
最终VM销毁是provider的个人主机/未来job隔离责任，observer不能实测或声称已验证；取消/硬停可能无完整报告。
本方案仅有界处理直接child/已知组并如实报告；逃逸进程、服务请求及任意后代由VM生命周期最终隔离。

## 验收与后续归属

1. root接受successor后仅授予有界源码草案；审完整workflow/action/feature/文件hash、固定argv、解析/清理语义。
2. exact source/hash接受后，root才冻结定向合成fixture命令/目标/预算；覆盖缺字段、stderr、非零、格式、超时、溢出、取消、reap/drain/close失败。
   生产入口不开放fixture argv；真实组继承case只证明已知组，不能证明逃逸拒绝或vendor后代闭包。
3. fixture通过后才冻结runtime binding/action/feature/执行文件hash与一次macos-15 guest；此前保持disabled/planned。
4. 一次初始观测；仅具体故障与已审修复可一次额外验收。无行动证据停止，不轮换OS归因；ar/av预算0。
5. metadata-observed后仅可准备兼容格/候选合同，不自动运行Q-A/Q-B/GUI/NE/签名；其他OS/架构分别冻结。

两次本机fixture失败保留，local预算0。独立[hosted合成目标](hosted-fixture-contract.md)仍proposal，
source/hash/runtime审查前不运行，其成功不能证明原失败原因。

owned工程/decoy、外部读写/网络拒绝、拒绝继承、候选身份/组/权限保护与实际后代回收证明，
**全部保留在工作包2的Q-A/Q-B engine/GUI及工作包5的NE/真实生命周期资格**，未删除或accepted-not-applicable。
签名凭据隔离/临时Keychain/profile清理仍属工作包4；本observer不触及缺失NE profile。
不得将vendor信任移植到candidate isolation，不复活ar/av、不改写未知失败、不宣称G0完成。
