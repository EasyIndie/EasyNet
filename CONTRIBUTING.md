# 贡献指南

感谢你考虑为 EasyNet 做贡献！本项目开源，欢迎各种形式的参与——
问题报告、功能建议、文档改进、代码提交。

参与前请阅读我们的[行为准则](CODE_OF_CONDUCT.md)。

---

## 目录

- [如何提交问题](#如何提交问题)
- [缺陷修复流程](#缺陷修复流程)
- [功能开发流程](#功能开发流程)
- [开发环境搭建](#开发环境搭建)
- [运行测试](#运行测试)
- [编写测试](#编写测试)
- [代码规范](#代码规范)
- [Pull Request 流程](#pull-request-流程)
- [代码审查检查清单](#代码审查检查清单)
- [发布流程](#发布流程)

---

## 如何提交问题

任何人都可以提 Issue。创建时请选择合适的模板：

- **问题报告** — 功能表现与预期不符。请附上你的运行环境、EasyNet 版本、复现步骤和相关日志。
- **功能建议** — 新协议、部署选项或改进。描述你想解决的问题和你的方案。
- **疑问** — 对项目使用有疑问时，用普通 Issue 并打上 `question` 标签。

### 提交之后

维护者会在 **48 小时** 内分类处理。可能会打上标签（`bug`、`enhancement`、`question` 等）或要求补充信息。
如果 Issue 缺乏关键信息且 **14 天** 内没有回应，可能会被关闭。

---

## 缺陷修复流程

1. **报告** — 使用模板提交问题报告
2. **分类** — 维护者确认缺陷并评定严重程度（严重=立即修复，一般=下个补丁版本）
3. **认领** — 在 Issue 下回复「我来处理」以避免重复劳动
4. **分支** — 基于 `main` 创建分支：`git checkout -b fix/简短描述`
5. **修复与测试** — 实现修复并添加覆盖该缺陷的回归测试
6. **PR** — 提交 Pull Request，描述中**必须**包含 `Fixes #123` 关联 Issue
7. **审查** — 维护者审查修复
8. **合并** — 修复合入 `main`，随下一个补丁版本发布

### 缺陷修复 PR 要求

- PR 标题格式：`fix: 简短描述`（例如：`fix: sing-box 客户端 DNS 解析器`）
- 必须关联 Issue：PR 描述中写 `Fixes #123`
- 必须包含回归测试，证明缺陷已修复且不会复现
- 所有已有测试必须通过

---

## 功能开发流程

1. **建议** — 先提交功能建议 Issue 讨论方案，待维护者打上 `enhancement` 标签后再开始编码
2. **分支** — 基于 `main` 创建分支：`git checkout -b feature/简短描述`
3. **实现** — 编写代码、测试和文档（新增协议需包含下方列出的 6 个脚本文件）
4. **PR** — 提交 Pull Request 并关联功能建议 Issue
5. **审查与合并** — 维护者审查后合入 `main`，随下一个次版本发布

### 新增协议的 PR 必须包含

```
scripts/protocols/<名称>/
├── manifest.sh              # 模块声明（MANIFEST_VERSION、MODULE_ 系列变量）
├── deploy.sh                # 部署脚本
├── export.sh                # 配置导出为 metadata
├── uninstall.sh             # 卸载脚本
├── render_clash.sh          # Clash YAML 输出（推荐）
├── render_singbox.jq        # sing-box JSON 输出（推荐）
tests/test_<名称>_*.bats     # 对应的测试文件
docs/                        # 按需更新 deployment.md、clients.md 等
```

新增或修改协议后，可运行文档生成器同步协议支持表：

```bash
bash docs/generate-protocol-table.sh --update
```

非协议变更（订阅系统、Edge Gateway、CI、文档等）按变更范围自行判断需要包含的内容。

---

## 开发环境搭建

EasyNet 是纯 Bash 项目，无需编译。

### 前置依赖

```bash
# 安装测试依赖
# Debian / Ubuntu：
sudo apt-get install -y jq ripgrep

# macOS：
brew install jq ripgrep
```

### 克隆

```bash
git clone https://github.com/EasyIndie/EasyNet.git
cd EasyNet
```

### 跨平台开发环境配置

项目包含 `.gitattributes` 和 `.editorconfig`，提交代码时自动将换行符统一为 **LF**。
不同平台需额外注意以下几点：

#### Windows (WSL)

WSL 的 drvfs（`/mnt/c/` 跨文件系统）可能无法正确追踪可执行权限，
导致 `git status` 中出现大量非预期的 mode 变更（`100755 → 100644`）。

**推荐做法**：在 WSL 的 `/etc/wsl.conf` 中添加 `metadata` 选项：

```ini
[automount]
options = "metadata,umask=22,fmask=11"
```

保存后重启 WSL（`wsl --shutdown` 再重新打开），
重新克隆仓库即可正确保留可执行权限。
这是解决 Windows 下 `.sh` 文件 mode 问题的最彻底方案。

如果无法配置 `wsl.conf`，则需避免使用 `git add -A` / `git add .`，
改用显式指定文件路径的方式提交，例如：

```bash
git add scripts/protocols/xray-reality/deploy.sh
git add --chmod=+x scripts/protocols/xray-reality/deploy.sh  # 修复可执行位
```

#### macOS

macOS 原生支持 Unix 权限，通常无需额外配置。
如果遇到换行符问题，确认 `git config core.autocrlf` 为 `input`：

```bash
git config core.autocrlf input
```

#### Linux

无需额外配置。`.gitattributes` 会自动处理换行符一致性。
CI 中会检查所有 `.sh` 文件的 git mode 是否为 `100755`。

---

## 运行测试

```bash
# 运行完整测试套件（23 个 bats 测试文件、262 个测试用例 + shell 语法检查）
bash tests/run_all_tests.bash

# 运行单个测试文件（开发时更快）
bats tests/test_env_vars.bats

# TAP 格式输出（CI 中使用）
bats --formatter tap tests/

# 检查所有脚本语法（与 CI 一致）
find scripts tests -type f \( -name "*.sh" -o -name "*.bash" \) \
  | sort | while IFS= read -r file; do bash -n "$file"; done
```

---

## 编写测试

EasyNet 使用 [bats-core](https://github.com/bats-core/bats-core) 作为测试框架。
测试文件放在 `tests/` 目录下，以 `.bats` 为扩展名。

### 测试框架 API

```bash
# test_helper.bash 提供辅助函数
load test_helper

@test "测试描述" {
    result=$(some_function)
    [ "$result" = "期望值" ]

    # 或使用辅助断言
    assert_equals "期望值" "$result" "测试描述"
    assert_not_empty "$result" "测试描述"
}
```

bats 核心断言模式：
- `[ "$a" = "$b" ]` — 字符串相等
- `[[ "$a" == pattern ]]` — 模式匹配
- `run command` — 捕获 `$status` 和 `$output`
- 更多用法参见 `bats --help`

### 约定

- 测试文件以 `test_<主题>.bats` 命名，放在 `tests/` 目录下。
- 由 `run_all_tests.bash` 自动发现（通过 bats 运行所有 `.bats` 文件），无需注册。
- 每个测试文件必须能独立运行（`bats tests/test_foo.bats`）。
- 测试可依赖 `jq` 和 `ripgrep` 已安装。

---

## 代码规范

### Shell 风格

- 使用 `#!/bin/bash` 作为 shebang
- 条件判断优先用 `[[ ]]` 而非 `[ ]`
- 变量展开加引号：`"$var"` 而非 `$var`
- 函数作用域变量使用 `local`
- 遵循 `scripts/core/` 中已有函数的命名和参数模式

### 日志

使用共享日志库，避免直接 `echo`：

```bash
source "$(dirname "$0")/../core/logging.sh"

log_info "正在处理 $profile 的订阅"
log_warn "证书续期跳过"
log_error "域名解析失败：$domain"
```

### 语法检查

所有 Shell 脚本必须通过 `bash -n`：

```bash
bash -n scripts/my-script.sh
```

### 避免硬编码

不要在代码中硬编码密码、路径或域名。应使用 metadata 系统
（`metadata.sh`）和环境变量。

---

## Pull Request 流程

1. **基于 `main` 创建分支**，并保持分支更新。
2. **PR 聚焦** — 每个 PR 只做一个功能或修复。
3. **编写或更新测试**。
4. **运行完整测试套件**并确认通过。
5. **更新文档**（如果变更影响使用方式）。
6. **关联 Issue** — 在描述中使用 `Fixes #123` 或 `Refs #456`。
7. **等待 CI** — 测试工作流会在 PR 上自动运行。
8. **处理审查反馈** — 修改后推送到同一分支，CI 自动重新运行。

---

## 代码审查检查清单

审查者会检查以下项目。提交前可自行预检：

- [ ] 遵循已有项目结构和模式
- [ ] 所有 Shell 文件通过 `bash -n`（语法检查）
- [ ] 核心逻辑有对应的测试覆盖
- [ ] 完整测试套件通过（`bash tests/run_all_tests.bash`）
- [ ] 无硬编码的密钥、路径或域名
- [ ] 使用共享日志函数（`log_info` / `log_error`）而非裸 `echo`
- [ ] 文档按需更新（`docs/`、README）
- [ ] 缺陷修复包含回归测试
- [ ] PR 描述关联了 Issue（`Fixes #123`）

---

## 发布流程

发布遵循[语义化版本](https://semver.org/)：

| 版本号位 | 适用场景 | 示例 |
|---------|----------|------|
| PATCH   | 缺陷修复、小调整 | 0.3.0 → 0.3.1 |
| MINOR   | 新功能（向后兼容） | 0.2.0 → 0.3.0 |
| MAJOR   | 不兼容的重大变更 | 1.0.0 → 2.0.0 |

### 维护者发布检查清单

```bash
# 1. 确认 main 分支就绪（所有测试通过、变更已合并）
# 2. 更新 CHANGELOG.md（按 Added / Fixed / Changed 分类）
# 3. 提交
git add CHANGELOG.md
git commit -m "Release X.Y.Z"
# 4. 推送
git push origin main
# 5. 打标签（严格的 semver 格式，无 v 前缀）
git tag X.Y.Z
git push origin X.Y.Z
# 6. GitHub Actions 自动创建 Release
```

[测试与发布工作流](.github/workflows/tests.yml) 会：
1. 运行全量测试 + ShellCheck
2. 从 CHANGELOG.md 提取发布说明
3. 创建 GitHub Release

---

## 有疑问？

如果你对贡献有疑问，欢迎发起 Discussion 或打上 `question` 标签的 Issue。
