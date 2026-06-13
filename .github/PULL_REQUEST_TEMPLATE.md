## 变更描述

<!-- 描述变更内容和原因。如有关联 Issue 请注明。 -->

Fixes #(issue)

## 变更类型

- [ ] 缺陷修复
- [ ] 新功能
- [ ] 文档更新
- [ ] 重构 / 代码整理
- [ ] CI / 工具链

## 测试方式

- [ ] 所有已有测试通过（`bash tests/run_all_tests.bash`）
- [ ] 语法检查通过（所有修改过的脚本均通过 `bash -n`）
- [ ] 为变更添加或更新了测试
- [ ] 缺陷修复包含回归测试证明修复有效

## 检查清单

- [ ] 代码遵循项目的编码规范
- [ ] 已按需更新文档
- [ ] 已关联 Issue（`Fixes #123`）

### 仅新增协议时

- [ ] 包含 `deploy.sh`、`export.sh`、`uninstall.sh`
- [ ] 包含 `render_clash.sh` 和/或 `render_singbox.jq`（可选，推荐）
- [ ] 按需更新 docs/deployment.md 和 docs/clients.md
