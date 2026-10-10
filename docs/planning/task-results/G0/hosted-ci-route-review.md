# G0 hosted CI route 独立 R 审查

2026-10-10；R `gpt-6.1-sol` high；文档审查，未运行源码/guest、安装、读取凭据或激活 workflow。

结论：接受路线用于冻结无密钥环境合同；五个工作包仍为 planned，不授予实验、签名或发布执行。
个人 Mac 的实验账户、本机 Xcode 登录和新 VM 不是 CI 准备前置；hosted fresh VM 可作个人主机隔离边界。
补充保留 owned-root/decoy、外部读写/网络拒绝、继承、身份/权限和回收证明；VM 销毁不替代它们。
补充新资格合同与旧 ar/av 归因的区别；原失败/未知、exhausted 预算及禁用 workflow 保持。
组织 secret 的 CLI 403/仓库空列表不证明 Actions 无组织凭据；只核对名称/用途/可见范围。
凭据 job 须绑定已审 feature SHA、依赖/action pins 与 artifact digest，不运行未审 engine/脚本。
GUI、NE、同意、签名/公证及真实安装生命周期分别实证；原 A/B gate、ADR、G0–G6/main 门槛保留。

范围：路线全文、资格计划的用户补充段、事实文件 `user_update_2026_10_10`；沿用 root 已核实官方事实，无新增研究。
验证：`git diff --check`；仅文档改动，不运行 Bats 或行为验收。root 接受本审查后可准备工作包 1 的精确合同。

## 同工作包：基线源码合同提案复核

`hosted-baseline-contract.md`：允许有界静态源码草案准备，仍为 planned proposal，不是冻结 runtime binding。
150 行 shell 应只做固定 argv/schema adapter，保护优先复用精确已审 helper；缺 helper 时先报最小固定用途方案与预算，不造通用 bootstrap。
已补必要保护：owned-root/decoy、外部读写/网络拒绝、继承/身份/权限；Xcode/SDK 例外、隐式写入及后代范围须单独冻结。
runtime blocker：尚无准确 helper/hash、流式输出截止、取消/后代回收及 FD drain 证明；固定 CLI 的身份/效果仍待源码审查。
旧 ar/av 归因与额度不恢复；本复核未执行脚本、fixture、真实 CLI、guest 或凭据操作。
