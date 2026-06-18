# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

EasyNet is a Bash-based server deployment tool that installs and manages proxy protocol servers (Xray+Reality, Hysteria2, Shadowsocks 2022, WireGuard) on Ubuntu/Debian VPS. It features a plugin-based protocol architecture, Nginx-based Edge Gateway for TLS termination and subscription distribution, and a sing-box client installer for end devices.

## Key Commands

| Command | Description |
|---------|-------------|
| `bats tests/*.bats` | Run all 262 tests (23 test files) |
| `bats tests/test_protocol_metadata.bats` | Run a single test file |
| `bats --formatter tap tests/` | TAP output (used in CI) |
| `shellcheck --rcfile=.shellcheckrc --shell=bash --severity=style scripts/` | Lint all scripts |
| `bash scripts/deploy.sh` | Start deployment (must run as root on target VPS) |

CI runs both shellcheck and bats on push/PR to `main` (see `.github/workflows/tests.yml`). All tests use temp directories (`mktemp`) and are fully isolated — no real VPS needed.

## Architecture

```
scripts/
  deploy.sh / uninstall.sh     ← Main orchestrators
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

## Important Practices

- **ShellCheck**: All scripts must pass `--severity=style`. Suppressions use targeted `# shellcheck disable=CODE` with justification comment.
- **metadata.json**: Central state artifact. Write with `metadata_write()`, validates structural contract. Only root-readable (`chmod 600`).
- **Lineage**: Code is primarily Chinese + English mixed. Error messages (log_info/log_error) use Chinese; internal logic and comments use English.
- **State dirs**: `/var/lib/easynet/` for metadata + edge state. Protocol configs in `/etc/<name>/`.
- **Test pattern**: Tests run actual `export.sh` scripts with fixture configs, validate metadata schema, then run subscription generation pipeline. Tests never need real network or root. A lint test (`test_lint_unbound_vars.bats`) verifies that all `set -u` scripts use `${VAR:-}` for env var references.
- **`set -u` / `${VAR:-}`**: All scripts with `set -u` (or `set -euo pipefail`) must reference environment variables with `${VAR:-}` instead of bare `$VAR`. A bare reference crashes the script when the variable is unset. This applies to `EASYNET_*`, `NGINX_*`, `JOURNALD_*` and similar env-guided variables. Library files (*.sh sourced by set -u contexts) follow the same rule. See `tests/test_lint_unbound_vars.bats` for the regex patterns.
- **Trap temp variables**: When using `trap ... RETURN` with a temp directory, declare `local tmp_dir=""` (initialize to empty) and use `"${tmp_dir:-}"` in the trap body. This prevents `set -u` from crashing on trap invocation.
- **No `curl | bash`**: All external downloads go through `download.sh`'s `run_downloaded_script()` which writes to temp file, optionally verifies SHA256, then executes. Downstream installers (get.hy2.sh, Xray-install, acme.sh) are treated the same way.
- **协议排序规则 — 按抗 DPI 能力从高到低 (中心化函数)**：`MODULE_SECURITY_RANK` 值越低抗 DPI 越强。所有用户可见的协议排序必须调用 `discovery_list_modules_by_security()`（定义在 `core/discovery.sh`），不得自行实现排序逻辑。当前顺序：Xray+Reality(10) → Hysteria2(20) → Shadowsocks(40) → WireGuard(60)。`deploy.sh` 菜单、`profiles.sh`、`generate_subscription.sh` 均已使用。新增协议时填入对应的 rank 值使其自动插入正确位置。
