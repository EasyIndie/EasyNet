# Hosted baseline source contract v1 — proposal

工作包 1；仅待审源码合同，不授权 guest、工具执行、安装或 secrets 使用。
依据 [已审主路线](hosted-ci-qualification-route.md)。不修改或执行旧 ar/av 实验。

## 目标与文件

在 fresh `macos-15` arm64 job 收集一个可逐项审查的 OS/Xcode/SDK 身份候选，
不把运行入口的文本路径相同当作身份等价证据，也不以观测替代 GUI/engine 资格。
后续 source author 的准确路径：`poc/client-framework/hosted-ci/baseline.sh`、
`tests/client_framework/test_hosted_baseline.bats`、`.github/workflows/client-hosted-baseline.yml`。
它们当前未创建，工作包仍 planned；本文件不是已存在验证命令或 ready binding。
实现最多 150 行 shell、120 行 fixture、80 行 workflow，不新增通用 guardian/解释器引导器。
若安全实现不能满足此预算，停止并给完整 blocker，不压缩安全检查。
独立 R 允许按本提案准备这三个文件的静态源码草案；合同仍未冻结，源码编写不授予工具或 fixture 执行。
150 行 shell 只承载固定 argv/报告 adapter；生命周期与拒绝保护优先绑定精确已审 helper。
若无可复用 helper，先报告所缺保护、准确复用路径或最小固定用途实现方案及行数，不扩写通用 bootstrap。

## 信任与固定效果

- 候选信任根为 GitHub 官方 fresh macOS 镜像及 root 独立审查的 feature commit；
  checkout action 固定完整 SHA，`ref: github.sha`、`persist-credentials:false`。
  执行前校验 baseline shell 的已审 SHA；不得运行未审 checkout 脚本或 engine。
- 仅一个 repo+feature 限定、默认 disabled 的 job，`contents:read`、timeout 5 min；
  无 secrets、个人资料、SSH、下载、缓存上传、sudo、Keychain、系统设置或 GUI 操作。
- 固定候选 CLI：`/usr/bin/sw_vers -productVersion`、`/usr/bin/sw_vers -buildVersion`、
  `/usr/bin/uname -m`、`/usr/bin/xcodebuild -version`、
  `/usr/bin/xcrun --sdk macosx --show-sdk-version`；每条实际 argv、退出语义、
  Xcode/SDK 选择与隐式写入须在 source/effects 审查中单独接受。
  这些是待审命令，当前不在本机/runner 执行。若效果无法冻结，改为停止，不以安装/扫描替代。
- 文件与命令结果仅为候选观测；CLI 文本版本、runner 标签或父级 image 不能单独授予
  工具链执行资格。需区分 bootstrap 程序、实际入口、所选 developer/SDK 与 downstream 工具。
- 只转发固定 locale/PATH 及必要 provider 标签；不重设 HOME 或继承令牌环境给测试子进程。
- owned-root/decoy、测试进程外部读写/网络拒绝、子进程继承、身份/组/权限保护仍为必要条件。
  工具所需的只读 Xcode/SDK 例外、隐式写入和后代进程范围须逐项冻结；fresh VM 与可信镜像不能代替这些证明。

## 有限输出、所有权与测试

报告上限 4 KiB：schema、阶段、固定命令标签、success/refused、固定错误枚举、
有界 ASCII version/build/arch、实际 image 标签，以及实际 child/reap/output/FD 证明。
不输出原始环境、任意路径、PID、完整工具 stdout/stderr 或猜测失败原因。
绝不把 unknown 清理写为 success；每条命令保留自己的明确拒绝信息。
总限时 90 s 含最终 5 s 回收；单命令最多 10 s、私有捕获至多 4 KiB。
owned 0700 job-temp 工程，保留直接子进程所有权，等待完成前不复用 PID；
超时/取消/溢出独立尝试终止、reap、drain、各 FD/临时文件清理，未知即拒绝。
不以 job 的 eventual VM destruction 代替测试过程回收。
执行 binding 前须给出准确 helper/source hash 及流式溢出停止、取消后的后代回收/FD drain 证据；
命令效果、拒绝保护或回收机制未确定时保持 planned，不能以固定版本文本或合成 fixture 授予 runtime 资格。

fixture 仅使用合成命令/结果，覆盖格式、缺字段、不同错误、超时/溢出/取消与回收失败，
不调用上述真实 CLI、不替代 A/B engine 测试。源码及 exact hash 审查后才授予定向 fixture。
源码接受且私有 fixture通过后才冻结完整 runtime binding；基线最多一次初始 guest，
仅具体故障和已审修复允许一次额外验收，不跨版本归因试跑或恢复旧额度。
基线成功后才准备其他 OS/架构；secretless job 与未来签名 job 的合同保持独立。
