# Hosted observer synthetic fixture — proposed target

2026-10-10；工作包1，source/effects由R接受、root接受静态冻结；runtime仍待审。
两次本机 fixture 均5/7 passing，normal child group unknown，具体原因未知；local预算0。
不再本机复验，不复活ar/av，不把本目标作为旧失败归因或OS轮换实验。

## 目标与效果

在fresh `macos-15`运行已审observer固定合成矩阵，验证自然退出与异常清理修订。
仅synthetic fixture，不运行五个真实metadata CLI、engine/GUI/NE、签名或凭据。
不证明任意后代、外部拒绝或vendor toolchain身份。

- 输入仅冻结的 `poc/client-framework/hosted-ci/observe.py`、`tests/client_framework/test_hosted_baseline.py`；
  source commit与两份SHA在源码收敛后填写，目前无runtime binding。
- 固定 `/usr/bin/python3 -I -B tests/client_framework/test_hosted_baseline.py`；
  clean `PATH=/usr/bin:/bin LANG=C LC_ALL=C`，无provider输入、备用解释器、安装。
- 私有Python合成case及其已知组后代；无socket/network/工程/原始文件/系统设置/个人Keychain。
- 自身SIGTERM只交付测试进程且恢复handler；mock PID不发真实系统调用。
- import只访问冻结源码，-B禁止repo bytecode；vendor Python/loader按fresh VM信任。
- 发布有限JSON counts/status，不发布traceback/原始流/路径/PID/环境。
- suite预期30秒；job外层timeout2分钟。内层case捕获/收尾有界；硬停/报告缺失为unknown，
  不声称子进程清理或VM销毁已证明。

## 工作流与预算

在 `.github/workflows/client-hosted-baseline.yml` 加默认disabled synthetic job；metadata仍disabled。
checkout固定 `3d3c42e5aac5ba805825da76410c181273ba90b1`，persist-credentials false，ref固定source commit。
contents read，无secrets/upload/cache/matrix/自动重试；本repo/feature精确一次激活消息触发。
先校验observer/test hashes；workflow/最终activation SHA单独审核。
source checkpoint → activation commit → R精确runtime binding → push → 一次初始合成验收 → 禁用并记录结果。
预算proposed：独立synthetic-only guest一次，无自动额外运行；不重置本机或旧预算。
root接受R前不执行；持续G0授权不替代源码/效果冻结。

## 成功与停止

exit0、严格有限JSON summary、全部合成case通过才fixture-pass。
report/exit矛盾、非零、超限、cleanup unknown/支持缺失均失败，不扫描/追加诊断。
即使通过只可准备metadata binding；A/B六项资格与最终ADR仍未通过。
真实metadata观测预算独立未使用，仍需自身source/effects/runtime接受。
