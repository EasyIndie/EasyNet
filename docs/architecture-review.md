# EasyNet 架构与代码质量评估报告

**评估日期：** 2026-06-18（本文档为快照审计，以下标记 ✅ 的条目已在后续提交中修复）
**评估范围：** 全部 Shell 脚本、测试、文档、CI/CD
**评估方法：** 静态分析 + 代码审查 + 测试运行

---

## 一、总体评分

| 维度 | 评分 | 说明 |
|------|------|------|
| **架构设计** | ⭐⭐⭐⭐ | 四层分离清晰，metadata 状态模式优秀，插件系统简洁 |
| **代码质量** | ⭐⭐⭐⭐ | ShellCheck 仅 2 个警告，引用规范，无遗留语法 |
| **测试覆盖** | ⭐⭐⭐ | 267 测试全通过，核心逻辑覆盖好，但部署脚本无测试 |
| **文档** | ⭐⭐⭐⭐ | README/CONTRIBUTING/CHANGELOG 完善，但缺架构文档 |
| **CI/CD** | ⭐⭐⭐⭐ | ShellCheck + bats + 集成测试 三层 CI |
| **安全性** | ⭐⭐⭐⭐ | 审计后已修复大部分问题，剩余 6 项低风险未处理 |

---

## 二、架构评估

### 2.1 四层分离架构

```
 deploy.sh / uninstall.sh         ← 编排层
 ┌─────────────────────────────┐
 │        core/                 │  ← 基础设施层 (19 文件)
 │  discovery metadata firewall│
 │  cron download env validate │
 │  subscription profiles ...  │
 └─────────────────────────────┘
 ┌─────────────────────────────┐
 │      protocols/              │  ← 协议层 (4 个)
 │  xray-reality / hysteria2   │
 │  shadowsocks / wireguard    │
 └─────────────────────────────┘
 ┌─────────────────────────────┐
 │      exposure/edge/          │  ← 暴露层
 │  Nginx + acme.sh + 订阅     │
 └─────────────────────────────┘
 ┌─────────────────────────────┐
 │      clients/                │  ← 客户端层
 │  sing-box 客户端安装器      │
 └─────────────────────────────┘
```

**评价：** 四层分离概念清晰，层级间依赖方向严格单向（编排 → 基础设施 → 协议/暴露/客户端）。`metadata.json` 作为持久化状态制品是架构中最佳设计。

### 2.2 插件系统

`manifest.sh + discovery.sh` 构成了一个简洁的文件系统驱动插件系统：

- 新增协议 = 新建目录 + 写 7 个变量 + 5 个脚本
- 自动出现在部署菜单、防火墙规则、订阅生成、卸载流程中
- 无需注册步骤，无中心数据库

**亮点：** `discovery_get_manifest_value()` 通过 `case` 白名单限制可读变量，拒绝未知变量。

**问题：** `discovery_validate_manifest()` 定义了但未被 `deploy.sh` 调用——有缺失字段的模块会在后续步骤中静默失败。

### 2.3 数据流质量

**优秀模式：** `metadata.json` 是"一次写入、多次消费"的中心状态制品：

```
export.sh 写入 →  firewall.sh (UFW 规则)
                  cron.sh (服务重启)
                  subscription*.sh (三种订阅格式)
                  cert_renew_hook.sh (证书后服务重启)
                  validate.sh (部署前预检)
                  smoke_test.sh (部署后验证)
```

**边界违反处：**
1. `deploy.sh` 硬编码 `source exposure/edge/routes.sh`——暴露模块应通过 `discovery.sh` 发现
2. `export.sh` 在协议 `deploy.sh` 内部调用，而非由编排器负责——耦合了编排与实现
3. `setup_firewall` 在部署循环前**调用了两次**，第一次调用时无元数据，属无效调用
4. `clients/` 没有 `manifest.sh`，无法被 `discovery.sh` 发现

---

## 三、代码质量

### 3.1 Shell 脚本规范

| 指标 | 结果 |
|------|------|
| Shebang 一致性 | ✅ 全部 `#!/bin/bash`（47 文件）|
| 变量引用 | ✅ **优秀**——几乎全部用双引号包裹 |
| `set -e` | ⚠️ 协议脚本只用 `set -e`，缺 `-u pipefail` |
| 函数命名 | ⚠️ 三种命名约定混用（`snake_case` / `easynet_` / 裸 `verb_noun`）|
| ShellCheck 警告 | ✅ **仅 2 个**——全部在文档生成器中，生产中脚本 0 警告 |
| 遗留语法 | ✅ 无反引号、无 `expr`、无 `$[]` |

### 3.2 重复代码

| 重复内容 | 出现次数 | 建议 |
|---------|---------|------|
| ~`yaml_escape()`~ | ~~**5 次**~~ | ✅ 已合并到 `core/subscription_clash.sh`，各协议 `render_clash.sh` source 复用 |
| ~`get_public_ip()`~ | ~~**5 次**~~ | ✅ 已合并到 `core/network.sh`，各协议脚本 source 调用 |
| ~`qrencode` + fallback 模式~ | ~~**6+ 次**~~ | ✅ 已提取为 `core/display.sh` 的 `show_qrcode()` |
| `random_secret()` / `generate_uuid()` / `generate_psk()` | 各 1-2 次 | 已集中到 `core/crypto.sh`，各协议直接调用 |

### 3.3 潜在 Bug

1. ~~**`discovery_uninstall_entrypoint()` 被定义两次**~~ ✅ 已修复——现在只有一个定义（`discovery.sh:244`）
2. **`for m in $modules`**（`profiles.sh:86`）——未引用的变量同时受 word splitting 和 pathname expansion 影响
3. **协议脚本无 `set -u`**——未定义变量引用静默展开为空字符串

---

## 四、测试评估

### 4.1 覆盖总结

```
23 个测试文件, 267 个测试, 0 失败
```

| 覆盖良好 | 覆盖缺失 |
|---------|---------|
| 模块解析（menu + profile + 直接引用） | **协议 deploy.sh（4个，共 914 行）** |
| 防火墙规则聚合 + 去重 | **Edge Gateway deploy（215 行）** |
| Metadata 导出（4 协议的 end-to-end） | **acme.sh 证书颁发 + 续期** |
| 订阅生成（Clash + URI + sing-box） | **客户端安装器行为测试** |
| 订阅轮转（旋转 + grace 迁移） | **validate.sh（203 行）预检** |
| 环境变量解析 | **render_clash.sh / render_singbox.jq 单元测试** |
| 卸载流程 | **失败模式（缺文件/网络超时/无效输入）** |
| 代码退化守卫（`rg -q` 模式） | **回滚/清理逻辑** |

### 4.2 测试质量问题

- `test_path_generation.bats` 在测试文件中**重新定义了 `generate_random_path()`**，测试的是自己的逻辑而非真实代码——真实函数坏了测试照样过
- ~~CONTRIBUTING.md 中记载的 `test_start`/`test_end` API 在迁移到 bats 后已不存在~~ ✅ **已修复**（已更新为 bats 原生 API）

---

## 五、改进建议（按优先级）

### P0 — 架构问题

| # | 建议 | 涉及文件 | 工作量 |
|---|------|---------|--------|
| ~1~ | ~~从 `deploy.sh main()` 中提取系统初始化到 `core/bootstrap.sh`~~ ✅ 已修复 | `deploy.sh` → `core/bootstrap.sh` | 小 |
| ~2~ | ~~合并 `get_public_ip()` 到 `core/network.sh`~~ ✅ 已修复 | `core/network.sh` | 小 |
| ~3~ | ~~移除部署循环前的冗余 `setup_firewall` 调用~~ ✅ 已修复 | `deploy.sh:366` | 极小 |
| ~4~ | ~~让 `export.sh` 调用由编排器负责~~ ✅ 已修复 | `deploy_module()` | 中 |

### P1 — 代码质量

| # | 建议 | 涉及文件 | 工作量 |
|---|------|---------|--------|
| ~5~ | ~~修复 `discovery_uninstall_entrypoint()` 重复定义~~ ✅ 已修复 | `core/discovery.sh:244` | 极小 |
| 6 | 协议脚本增加 `set -uo pipefail` | 协议 `deploy.sh`/`export.sh`/`uninstall.sh` | 小 |
| ~7~ | ~~合并 5 个 `yaml_escape()` 到 `subscription_clash.sh`~~ ✅ 已修复 | `core/subscription_clash.sh` | 小 |
| ~8~ | ~~添加 `core/display.sh`，统一 qrencode 输出~~ ✅ 已修复 | `core/display.sh` | 小 |

### P2 — 测试

| # | 建议 | 工作量 |
|---|------|--------|
| 9 | 为 `test_path_generation.bats` 改为 source 真实函数 | 极小 |
| 10 | ~~清洁 CONTRIBUTING.md 中过期 API 引用~~ ✅ 已修复 | 极小 |
| 11 | 为协议 deploy.sh 添加基本的行为测试（mock 模式下运行） | 中 |
| 12 | 添加 render_clash.sh / render_singbox.jq 单元测试 | 中 |

---

## 六、综合评价

**架构优势：** `metadata.json` 作为中心状态制品是最佳设计决策。插件系统简洁、测试友好、扩展成本低。SSH 端口自动检测防止防火墙锁定的设计务实。

**代码优势：** Shell 脚本质量在同类项目中属上乘——引用规范几乎完美、ShellCheck 零生产告警、无遗留语法。架构分离度良好。

**最大薄弱环节：** 914 行协议部署脚本 + 215 行 Edge 部署脚本零测试覆盖。这是风险最高的代码——包含包安装、配置模板、systemd 管理，一旦出错可导致生产服务中断。

**总体：** 在 Shell 脚本项目中，EasyNet 的架构和代码质量处于第一梯队。改进空间主要集中在提取基础设施层、消除重复代码、补上高风险的部署脚本测试。
