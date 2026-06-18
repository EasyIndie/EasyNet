# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

EasyNet is a Bash-based server deployment tool that installs and manages proxy protocol servers (Xray+Reality, Hysteria2, Shadowsocks 2022, WireGuard) on Ubuntu/Debian VPS. It features a plugin-based protocol architecture, Nginx-based Edge Gateway for TLS termination and subscription distribution, and a sing-box client installer for end devices.

## Key Commands

| Command | Description |
|---------|-------------|
| `bats tests/*.bats` | Run all 179 tests |
| `bats tests/test_protocol_metadata.bats` | Run a single test file |
| `bats --formatter tap tests/` | TAP output (used in CI) |
| `shellcheck --rcfile=.shellcheckrc --shell=bash --severity=style scripts/` | Lint all scripts |
| `bash scripts/deploy.sh` | Start deployment (must run as root on target VPS) |

CI runs both shellcheck and bats on push/PR to `main` (see `.github/workflows/tests.yml`). All tests use temp directories (`mktemp`) and are fully isolated — no real VPS needed.

## Architecture

```
scripts/
  deploy.sh / uninstall.sh     ← Main orchestrators
  core/                         ← Shared infrastructure (20 files)
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
MODULE_SECURITY_RANK=20          # Lower = stronger anti-DPI
MODULE_DEFAULT_PORT=443
MODULE_EDGE_MODE="shared_tls"    # "shared_tls" | "backend" | "none"
MODULE_PROFILES="balanced compat"  # Which deployment profiles include this
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
- **Test pattern**: Tests run actual `export.sh` scripts with fixture configs, validate metadata schema, then run subscription generation pipeline. Tests never need real network or root.
- **No `curl | bash`**: All external downloads go through `download.sh`'s `run_downloaded_script()` which writes to temp file, optionally verifies SHA256, then executes. Downstream installers (get.hy2.sh, Xray-install, acme.sh) are treated the same way.
