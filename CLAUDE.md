# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

EasyNet is a Bash-based server deployment tool that installs and manages proxy protocol servers (Xray+Reality, Hysteria2, Shadowsocks 2022, WireGuard) on Ubuntu/Debian VPS. It features a plugin-based protocol architecture, Nginx-based Edge Gateway for TLS termination and subscription distribution, and a sing-box client installer for end devices.

## Key Commands

| Command | Description |
|---------|-------------|
| `bats tests/*.bats` | Run all tests (真客户端校验在有二进制时才跑，CI 里强制) |
| `bats tests/test_protocol_metadata.bats` | Run a single test file |
| `bats --formatter tap tests/` | TAP output (used in CI) |
| `shellcheck --rcfile=.shellcheckrc --shell=bash --severity=style scripts/` | Lint all scripts |
| `bash scripts/deploy.sh` | Start deployment (must run as root on target VPS) |
| `EASYNET_DOMAIN=... bash scripts/acceptance_test.sh` | VPS acceptance harness (root, real VPS) |
| `bash scripts/diagnose_reachability.sh` | Diagnose public reachability / IP blocking |

CI runs both shellcheck and bats on push/PR to `main` (see `.github/workflows/tests.yml`). All tests use temp directories (`mktemp`) and are fully isolated — no real VPS needed.

One-command install (no `git clone`): releases publish `easynet-install.sh`, which downloads the release tarball, verifies SHA256, extracts to `/opt/easynet`, then runs `scripts/deploy.sh`.

## Architecture

```
scripts/
  install.sh                   ← Bootstrap installer (release tarball + SHA256 + deploy)
  deploy.sh / uninstall.sh     ← Main orchestrators
  generate_subscription.sh/
  show_subscription.sh/
  rotate_subscription.sh/
  generate_singbox_rules.sh    ← Build sing-box .srs rule sets
  smoke_test.sh                ← Post-deploy smoke check
  diagnose_reachability.sh     ← Public reachability / IP-block diagnosis
  acceptance_test.sh           ← VPS acceptance harness (verify deploy/uninstall)
  core/                         ← Shared infrastructure (19 files)
    discovery.sh                ←   Plugin system (manifest loading, validation)
    metadata.sh                 ←   metadata.json write/validate (chmod 600)
    firewall.sh                 ←   UFW rules from metadata
    bootstrap.sh                ←   System init (apt, BBR, firewall, cron)
    cron.sh                     ←   Daily service restart from metadata
    profiles.sh                 ←   Deployment profiles (strict/balanced/compat)
    download.sh                 ←   Download + SHA256 verify + execute
    crypto.sh                   ←   Key generation, arch detection
    network.sh                  ←   Public IP detection
    display.sh                  ←   QR code display
    validate.sh                 ←   Pre-flight checks
    env.sh / env_file.sh        ←   State directory paths, .env parsing
    hub.sh                      ←   ~/.easynet operational hub (symlink index)
    subscription*.sh            ←   Subscription generation
    logging.sh                  ←   Unified logging (log_info/log_error)
    maintenance.sh              ←   System maintenance utilities
    url.sh                      ←   URL encode/decode
    metadata.schema.json        ←   JSON schema for metadata contract
    uninstall.sh                ←   Safe path/firewall/service removal
  protocols/                    ← Plugin modules (4 protocols)
    hysteria2/                  ←   6 files each: manifest.sh, deploy.sh,
    xray-reality/               ←   export.sh, uninstall.sh, render_clash.sh,
    shadowsocks/                ←   render_singbox.jq
    wireguard/
  exposure/edge/                ← Edge Gateway (Nginx + acme.sh + subscriptions)
    manifest.sh, deploy.sh, export.sh, uninstall.sh, routes.sh, cert_renew_hook.sh
  clients/                      ← Client installer (standalone, runs on end device)
    install_singbox_client.sh   ←   Downloads sing-box binary, manages config
```

## Plugin Architecture

Protocol modules are discovered via filesystem: any `scripts/protocols/<name>/manifest.sh` is a plugin. The manifest declares variables:

```
MANIFEST_VERSION=1
MODULE_NAME="hysteria2"
MODULE_DISPLAY_NAME="Hysteria2"   # Human-readable label for menus
MODULE_PROTOCOL="hysteria2"       # Protocol identifier
MODULE_CLASH_TYPE="hysteria2"     # Clash/Mihomo type
MODULE_SINGBOX_TYPE="hysteria2"   # sing-box type
MODULE_SECURITY_RANK=20           # Lower = stronger anti-DPI
MODULE_DEFAULT_PORT=443
MODULE_EDGE_MODE="shared_tls"     # "shared_tls" | "backend" | "none"
MODULE_PROFILES="balanced compat" # Which deployment profiles include this
MODULE_SYSTEMD_SERVICES=("hysteria-server.service")
```

Variable access is whitelist-protected (`discovery_get_manifest_value` rejects unknown names). Adding a new protocol = creating a new `protocols/<name>/` directory with the 6 required scripts — no registration needed.

## Data Flow

1. **User intent** → `.env` file or env vars (`EASYNET_*` namespace)
2. **Module resolution** → `discovery.sh` scans manifests → `profiles.sh` or menu selects modules
3. **Deployment** → per module: `deploy.sh` installs + configures + starts service → `export.sh` writes `metadata.json`
4. **State consumption** → `metadata.json` at `/var/lib/easynet/modules/<name>/metadata.json` is consumed by:
   - `firewall.sh` (UFW rules)
   - `cron.sh` (daily service restart)
   - `subscription*.sh` (Clash/URI/sing-box generation)
   - `cert_renew_hook.sh` (post-renewal service restart)
   - `validate.sh` (pre-flight checks)
5. **Subscription files** → served via Edge Nginx at randomized paths

## Operational Hub (`~/.easynet`)

Every path EasyNet touches is spread across the FHS because upstream installers and systemd
units hard-code them. Physical relocation would break upstream upgrades and redeploy
idempotency, so instead `core/hub.sh` builds a **single working directory** of symlinks plus a
generated `README.md` index:

```
~/.easynet/{easynet,project,env,state,logs/,certs,web,nginx-site,acme,systemd,
            configs/<module> → MODULE_CONFIG_DIR (declared by each manifest),
            security/{harden-ssh,sshd-hardening.conf,fail2ban.conf}}
```

`ensure_easynet_hub()` runs at the end of every deploy/uninstall (pure `mkdir`/`ln` — deleting
the hub is always safe). `scripts/easynet` is the unified CLI (`status`, `where`, `path`,
`config`, `edit`, `logs`, `restart`, `sub`, `services`, `hub`, `ssh`, `doctor`, `env`,
`deploy`, `update`); `ensure_easynet_hub` also symlinks it to `/usr/local/bin/easynet`.
`easynet deploy` tees output to `~/.easynet/logs/deploy-<timestamp>.log` (`latest.log`).

New protocols must declare `MODULE_CONFIG_DIR` in their manifest so the hub indexes them.

## Deployment Environments (固定约定)

| 环境 | 域名 | 策略 | 协议 | 用途 |
|---|---|---|---|---|
| **测试 VPS** | 由 `.env` 决定（不写入本仓库） | `compat` | 全部 4 种（Reality / Hysteria2 / SS2022 / AmneziaWG） | 功能迭代与验收；每次发版后走一遍完整流程 |
| **正式 VPS** | 由 `.env` 决定（不写入本仓库） | `balanced` | 仅最安全的 2 种协议 | 生产；改动必须先在测试 VPS 验收通过 |

- 测试环境**永远**用 `compat`（四种协议全开），不要为了省时间改成 `balanced`。
- 正式环境**永远**用 `balanced`（最安全的两/三种），且域名与测试环境不同。
- **本仓库保持公开（已评估的决策，勿再改动可见性）**：理由——服务域名本身已通过 Certificate
  Transparency 日志公开可查（Let's Encrypt / Cloudflare 签发的每张证书都必须公示），
  私有化既隐藏不了域名，又会破坏 `install.sh` 一键安装与 `easynet update`（release 资产需认证）。
  因此采取「公开仓库 + 不写运行标识」的组合。
- **真实域名、IP、订阅路径前缀等运行标识一律不得写入仓库**（含文档、注释、测试、提交信息）。
  仓库内示例统一用保留域名 `example.com`；各环境的真实值只放在那台机器上的 `.env`（600）或本地验收目录。
  `tests/test_no_private_identifiers.bats` 会在 CI 里拦截已知标识的回归（含哨兵断言，防止检查本身失效）。
- **VPS 上一律用 `.env` 文件驱动部署**，不要在命令行内联环境变量：`.env` 是唯一配置来源，
  既能反复重部署得到一致结果，也能直接 diff/回滚配置。部署命令永远是 `bash scripts/deploy.sh`
  （`deploy.sh` 自动加载同目录 `.env`）。
- `.env` 只接受 `EASYNET_[A-Z0-9_]+`（见 `core/env_file.sh`）；权限保持 600（含订阅路径密钥）。
  模板：测试 `.env.test-vps`、正式 `.env.prod-vps`（存于本地验收目录，不入库）。
- 发版后的验收走官方一键安装器（与真实用户一致）：
  `bash ~/Desktop/easynet-acceptance/reset-acceptance.sh --release <tag>`
  （改动了尚未发版的代码时才用不带 `--release` 的本地工作树模式）。

## 已评估但不做（勿重复提议，除非有新证据）

- **伪装站「模板级」随机化**（多套版式让各部署看起来不同）：模板在开源仓库里人人可读，随机化只抬高扫描成本；已有域名级内容/配色/`robots.txt` 随机化（`exposure/edge/render_site.sh`）。收益低、成本高。
- **分流规则集的自动生成 / 周期 timer**：见上文决策——手动 `easynet rules`，未发布时订阅自动降级并有两处提示。
- **AmneziaWG 版本 pin**：上游只发 PPA/源码，无静态资产可校验；apt GPG 已是该渠道最强校验，接受为残余风险。
- **Reality 节点用 IP 而非域名**（`EASYNET_REALITY_SERVER_HOST`）：自偷模式下 `server=域名` + `SNI=同一域名` 恰好自洽，改成 IP 反而制造不一致。
- **URI 方言（`porthopping*`）自动校验**：mihomo 的 URI 解析器不读这些参数，Shadowrocket 需真机 → 无法自动化；已在 `docs/clients.md` 标注"未验证"。
- **服务端 UDP masquerade 探测**：`obfs: salamander` 使未混淆 QUIC 探针收不到响应，属验证局限而非缺陷。

## Important Practices

- **ShellCheck**: All scripts must pass `--severity=style`. Suppressions use targeted `# shellcheck disable=CODE` with justification comment.
- **metadata.json**: Central state artifact. Write with `metadata_write()`, validates structural contract. Only root-readable (`chmod 600`).
- **Lineage**: Code is primarily Chinese + English mixed. Error messages (log_info/log_error) use Chinese; internal logic and comments use English.
- **State dirs**: `/var/lib/easynet/` for metadata + edge state. Protocol configs in `/etc/<name>/`.
- **Test pattern**: Tests run actual `export.sh` scripts with fixture configs, validate metadata schema, then run subscription generation pipeline. Tests never need real network or root. A lint test (`test_lint_unbound_vars.bats`) verifies that all `set -u` scripts use `${VAR:-}` for env var references.
- **伪装站必须自洽（域名 / 证书 / 内容三者一致）**：Edge 根路径默认返回按域名生成的
  自托管静态站（`scripts/exposure/edge/render_site.sh`，`EASYNET_EDGE_SITE_DIR` 可放自有内容）。
  **不得**再引入「反代第三方大站」的默认值 —— 透明镜像会在响应里自曝（`canonical` 指向第三方、
  `Set-Cookie: domain=.第三方`、base64 `origin` 字段、镜像对方 `robots.txt`、任意 Host 返回对方首页），
  这是比 TLS 指纹更容易被自动化识别的内容层特征。回归守卫：`tests/test_camouflage_site.bats`。
- **`set -u` / `${VAR:-}`**: All scripts with `set -u` (or `set -euo pipefail`) must reference environment variables with `${VAR:-}` instead of bare `$VAR`. A bare reference crashes the script when the variable is unset. This applies to `EASYNET_*`, `NGINX_*`, `JOURNALD_*` and similar env-guided variables. Library files (*.sh sourced by set -u contexts) follow the same rule. See `tests/test_lint_unbound_vars.bats` for the regex patterns.
- **Trap temp variables**: When using `trap ... RETURN` with a temp directory, declare `local tmp_dir=""` (initialize to empty) and use `"${tmp_dir:-}"` in the trap body. This prevents `set -u` from crashing on trap invocation.
- **No `curl | bash`**: All external downloads go through `download.sh`'s `run_downloaded_script()` which writes to temp file, optionally verifies SHA256, then executes. Downstream installers (get.hy2.sh, Xray-install, acme.sh) are treated the same way.
- **客户端配置字段必须用真二进制校验（硬规则）**：生成的 Clash/sing-box 订阅里，字段名、类型、
  单位都是**按客户端方言**区分的（例：端口跳跃间隔——sing-box 要 `hop_interval: "30s"`，mihomo 要整数秒
  `hop-interval: 30`，见 `docs/clients.md` 方言表）。字符串断言只能防回归，无法判定正确性。
  改动任何客户端渲染字段后，必须跑 `scripts/client_check.sh check-clash|check-singbox <生成物>`；
  CI 的 `client-config-validation` job 是 release 的硬前置（真客户端拒收则发不出 release）。
  历史事故：0.0.13 之前把 `"30s"` 写给 mihomo，报 `invalid range: 30s` 并**拒绝整份订阅**。
- **分流规则集保持手动（决策，勿自动加 timer）**：`easynet rules` 是有意的手动步骤。生成需从上游下载约 90MB 数据，放进部署会拖慢主流程并增加失败面；周期 timer 会让每台机器每周固定产生大流量下载。未发布时订阅自动省去 `rule_set`（客户端仍可正常代理），`deploy.sh` 打 WARN、`easynet status` 显示状态 —— 可观测性已足够。
- **升级路径**：release 安装（生产唯一推荐）用 `easynet upgrade [<tag>]` 或
  `EASYNET_VERSION=<tag> bash scripts/install.sh`（保留 `.env`）；`easynet update` 仅对 git 安装有效。
  `deploy.sh` **不安装 git**，仓库里的 `git clone` 文档仅面向贡献者。
- **协议排序规则 — 按抗 DPI 能力从高到低 (中心化函数)**：`MODULE_SECURITY_RANK` 值越低抗 DPI 越强。所有用户可见的协议排序必须调用 `discovery_list_modules_by_security()`（定义在 `core/discovery.sh`），不得自行实现排序逻辑。当前顺序：Xray+Reality(10) → Hysteria2(20) → Shadowsocks(40) → AmneziaWG(50)。`deploy.sh` 菜单、`profiles.sh`、`generate_subscription.sh` 均已使用。新增协议时填入对应的 rank 值使其自动插入正确位置。
