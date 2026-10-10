# G0 hosted macOS CI 与组织签名路线

2026-10-10 用户补充后的方案；root 接受独立 R 路线审查，不授予实验运行或凭据使用。
当前开发机是个人自用设备，没有可反复重置的全新 VM。GitHub hosted runner
作为主要实验资源；不再把本机实验账户、独立设备或本机 Xcode 登录当作 CI 准备前置。
用户确认 Actions 可以取得组织凭据；具体 Apple 材料、仓库可见范围与有效性待核对。
历史 ar/av 的失败、预算耗尽和禁用 workflow 保留，不直接重启旧脚本。

## 已核实能力与限制

- [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
  说明 macOS job 使用新 VM；`macos-15`、`macos-26` 是 arm64，
  `macos-15-intel` 是 Intel。不得把同名 OS 标签误写成固定 CPU 架构。
- [官方镜像说明](https://github.com/actions/runner-images/blob/main/README.md)
  说明镜像软件通常每周更新。OS 标签不能固定任意 patch、image build 或工具目录。
  每次记录实际 OS/build/arch/image、Xcode/SDK、工具来源/版本/身份；资格不符即明确拒绝。
  工具版本可以按冻结合同选择/取得，不为迁就一条历史 Homebrew 路径放宽身份验证。
- hosted VM 的整体销毁可保护个人开发机，但不证明测试子进程、端口、文件与权限生命周期正确。
  仍需 owned 工程、合成数据、时间/输出限制、进程回收及独立效果审查。
  新合同须逐项保留 owned-root/decoy、测试进程外部读写/网络拒绝、子进程继承、
  身份/组/权限及回收证明；依赖取得与 artifact 上传的允许网络另行冻结，不授予测试进程外网访问。
- arm64 runner 不支持 nested virtualization，也没有 static UDID。若开发 provisioning
  确需固定设备身份，独立评估 Intel 路线；不能据此推定任一 profile 已可用。
- GUI 会话、系统同意、Network Extension 激活、真实路由/DNS/流量都必须实际证明。
  构建或公证通过不能代替这些结果，也不预先宣称 hosted runner 无法完成它们。

## 有界顺序：先基线，再兼容性，最后凭据

| 工作包 | 输入与交付 | 执行/评审 | 验收与停止点 |
|---|---|---|---|
| 1. 无密钥环境合同 | 固定 `macos-15` arm64 基线；明确 Xcode/SDK/工具来源、真实入口身份、有限环境报告及 owned effects | 主会话机械准备；冻结小采集器 C Luna medium；合同 R Sol high | source/hash/effects 审查后一次基线观测；分项拒绝，不能继续执行 GUI 或改用发现路径 |
| 2. A/B 真引擎与 GUI | 各候选完整工程/依赖 pins、代理模式 loopback nonce、Connect/Cancel/Stop/Restart 和回收矩阵 | I Sol medium，一个候选整包；R 关键边界一次完整审查 | 实际 UI→engine 数据面与失败矩阵；无 GUI/效果资格就 blocked，不以 headless 替代 |
| 3. 兼容矩阵 | 基线成功后，同一已审测试分别用于 `macos-26` arm64、`macos-15-intel` x64 | C 机械适配；跨架构问题 I；root 合并有限结果 | 每格一次初始验收、最多一次基于明确故障的修复；无自动轮换 OS 找到绿色结果 |
| 4. Apple 签名与公证 | 明确渠道、secret 名称映射、Developer ID/P12、认证材料、临时 keychain、entitlements/profile、产物清单 | I Sol medium；R 权限/密钥/分发整包 | 先不带凭据的 contract/fake，再限定可信 feature commit 的实际签名、公证和验证；证据不等于正式发布 |
| 5. 真实系统 VPN 与分发验收 | 候选 provider 打包路线、系统同意、entitlement、路由/DNS/断连恢复、干净安装/更新/卸载 | I/R；独立冻结真实效果与测试目标 | hosted runner 能做多少以实证为准；系统同意/GUI 不可达时保留具体缺口，之后再确定必要人工目标 |

这是分阶段工作包，不是已解锁任务卡。正式调度前绑定精确实现/测试路径、命令、
来源/哈希、每格预算和授权；一次一张 ready 卡。不是三格并行的无界诊断 matrix。
不复用 ar/av 的 exhausted 额度；新的环境资格合同接受前不启动任何新 guest。
新合同验证 hosted 目标及冻结测试的资格，不新增 crash 读取、probe/grant 或对 ar/av 的失败归因；
av 已观测的 image identity 拒绝及其未知原因保持原记录，不能仅改标签/路径继续旧 probe。
不新增全部子 Issue。原 A/B 六项 gate、最终 ADR 与 G0–G6/main 门槛保持。

## 凭据与产物合同

[GitHub 官方签名指引](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
支持在 runner 导入 secrets 中的证书/profile 并使用临时 keychain；按 job 清理。
[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
的 Developer ID 签名、公证与 [Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)
是分别核验的条件。

- GitHub 发布 token 不是 Apple 签名身份；公证认证凭据也不能替代签名证书及私钥。
- 当前 CLI 组织 secret 元数据读取返回 403，仓库级 secret 列表为空；这不证明 Actions
  无法继承组织 secret。只核对名称/用途/可见范围，不下载、输出或提交 secret 值。
- secret 名称、证书类型/profile/capability 与可见范围确认后，才冻结签名 workflow。
  不向 fork/untrusted PR、日志、cache 或 artifacts 暴露材料；签名 job 与无密钥实验分开。
  实际凭据 job 绑定已审 feature SHA、依赖与 action pins，并验证待签 artifact digest；
  不在持有凭据的 job 中运行未审 candidate engine/GUI 或任意输入脚本。
- 临时 keychain/profile 使用 job-owned 路径和清理；证据仅保留验证状态与 artifact digest，
  不保留证书内容、原始 profile、公证认证材料或个人 Keychain 信息。
- 演进产物标记 feature SHA；先采用受限测试 artifacts。正式 Release/semver tag/main
  合并仍遵从最终 gate，用户关于凭据能力的说明不等于立即发布未验收软件。

## 下一步

此路线已独立审查接受；[基线合同草案](hosted-baseline-contract.md)允许有界静态源码准备，尚未冻结 runtime binding。并行等待组织 secret 名称/用途映射，
不阻塞无密钥合同准备。当前个人开发机不承接可破坏系统状态的实验，也不安装 VM。
