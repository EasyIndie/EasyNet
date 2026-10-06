# Repository Audit and Gap Analysis — 2026-10-06

## Scope and conclusion

Baseline: `1d288dc747862486c930d5d21042b3fc4339e16f` in `EasyIndie/EasyNet`.
The working tree initially contained only the untracked user handoff document.
This audit changes agent guidance and planning documents, not deployment behavior.

The Self-hosted / BYOS / BYOC / Local-first direction is compatible with the
current implementation **as an additive management layer**. A wholesale runtime
migration, immediate Rust rewrite, or a claim of generic Linux/NAS support would
conflict with current evidence. Existing Bash modules remain the server execution
backend. First prove Existing Ubuntu VPS → trusted SSH → read-only preflight →
explicit deployment plan → Hysteria2 deployment → portable profile export.

The handoff is product context; its embedded prompt and suggestion to create
Phase 1 issues are not the current instruction. Only the total Epic is to be
created now, with #5 linked and Phase 1 issues proposed, not opened.

## Repository audit

| Area | Evidence and current behavior | Implication |
|---|---|---|
| Language / structure | Bash + jq; four filesystem-discovered plugins in `scripts/protocols/`; Python QR utility; no Rust core or desktop app | Reuse server scripts; language/framework choice remains open |
| Orchestration | `scripts/deploy.sh`, `core/bootstrap.sh`; root-only Ubuntu/Debian, apt, systemd, UFW; `.env` and module/profile selection | Designed to execute on one target host, not manage servers remotely |
| Side-effect ordering | `main()` calls system/security bootstrap before `deploy_modules()` preflight; preflight failure is advisory unless `EASYNET_STRICT_PRECHECK=true` | Remote management needs a separate read-only gate before any bootstrap, not merely this flag |
| Protocol modules | manifests, deploy/export/uninstall, Clash and sing-box renderers; rank-sorted discovery | Strong starting point for a compatibility ProtocolDriver adapter |
| Runtime distinctions | Xray Reality, official Hysteria2, shadowsocks runtime, `wireguard` directory using `awg` / `awg-quick` | Protocol and runtime IDs must differ; AmneziaWG is not interchangeable with native WireGuard |
| SSH | `security/harden_ssh.sh`, `easynet ssh` and `harden-ssh` manage local sshd with rollback guard | No remote transport, host identity store, credential vault or remote sudo orchestration |
| State | `core/env.sh`, `.env`, per-module `metadata.json`, Edge state under `/var/lib/easynet`; hub symlinks span FHS | No multi-server inventory or local operation journal; the hub is an index, not backup data |
| Metadata | `metadata_write()` formats JSON and chmods 600; `metadata_validate_file()` performs separate jq checks; schema file exists | Writer does not validate automatically; jq checks do not fully implement the JSON Schema contract |
| Export | URI/QR, Clash/Mihomo and sing-box subscriptions; AWG client `.conf`; Hysteria export writes metadata | Portable formats exist, but metadata export is not native Hysteria client YAML or a complete escape hatch |
| Edge / TLS | Nginx, acme.sh, shared Hysteria TLS certs, randomized subscription paths and static camouflage | Preserve domain/certificate/renewal requirements; home/NAT server path needs separate capability work |
| CLI / clients | `scripts/easynet` offers local status/logs/restart/deploy/upgrade/monitor; Linux sing-box installer offers mixed/TUN modes | Existing CLI is real; no need to invent a duplicate server CLI. Desktop connection manager remains missing |
| Observability | `core/monitor.sh`, audit/smoke/reachability scripts, operational runbooks | Reuse collectors, add structured remote results; not a provider-billing or traffic forecast engine |
| Backup | optional deployment `create_backup()` archives state and `rollback()` restores state | No full restoration of `/etc` runtime configs, keys/certs, packages/units, firewall or local inventory; not disaster recovery |
| Supply chain / upgrade | `core/pins.sh`, download verification, release tarball/checksum installer; AWG apt/PPA exception; `easynet upgrade` | Retain verified release delivery; do not promise every component is pinned or transactional rollback |
| Tests | 34 Bats files, 465 `@test` declarations at audit baseline; fast runner excludes network/client tags | README's 455 and CONTRIBUTING's 366 counts are stale; declaration count is not a passing result |
| CI/CD | `tests.yml`: Ubuntu 24.04/26.04 Bats/ShellCheck, config integration, pinned real-client validation; tag release requires all three jobs; `pins.yml` weekly advisory | Reuse CI; remote transport, state migrations and recovery need additional tests later |
| GitHub | On 2026-10-06, open Issue search and open PR search returned none; #5 is closed / `not_planned`, five comments read | No active conflicting PR found; #5 is historical/runtime direction, not an accepted migration task |

GitHub sources: [#5](https://github.com/EasyIndie/EasyNet/issues/5), especially its
[closure](https://github.com/EasyIndie/EasyNet/issues/5#issuecomment-6013914485), and
[earlier correction](https://github.com/EasyIndie/EasyNet/issues/5#issuecomment-5875031992).
Statements about upstream versions/features in those comments and old analyses
are historical evidence, not newly verified upstream facts. This audit does not
select an upstream runtime or assert those version comparisons are current.

## Gap analysis

Migration cost below is relative engineering scope, not a delivery estimate.

| Current capability | Target capability | Gap | Reuse strategy | Cost |
|---|---|---|---|---|
| On-host `.env` deployment | ServerTarget / ExistingServer | Stable IDs, SSH endpoint, provenance, capabilities, credential references | Add local model; translate intent to existing `.env` | Medium |
| Local SSH hardening | Remote SSH + secure credentials | Host-key trust/changes, timeouts, cancellation, privilege escalation, vault | SSH transport adapter; preserve hardening as an optional operation | High |
| OS/tools/domain/static port checks | Read-only structured preflight | Actual listeners, resources, services, effective ports/transports, TUN/NAT, probe uncertainty | Reuse checks selectively; collect facts before mutation; unsupported/unknown are explicit | Medium–High |
| Bash plugin contracts | ProtocolDriver | Lifecycle/result schema, runtime capabilities, upgrade semantics, per-client lifecycle | Wrap manifest/entrypoints; avoid rewriting native runtime logic | Medium |
| URI/Clash/sing-box/AWG export | Native Export / Escape Hatch | Selected native client profile, offline delivery, version compatibility, keys and recovery instructions | Reuse metadata and renderers; add Hysteria client YAML | Medium |
| Remote metadata + hub | Local-first multi-server state | Versioning, transactions, secret refs, operation recovery, reconciliation | Separate local inventory from remote source facts; retain schema v1 consumers | Medium–High |
| State tar + error trap | Encrypted Backup / Restore | Complete manifest, secret encryption, safe extraction, alternate-host reconstruction | Collect allowlisted real files; reuse validated install/configuration paths | High |
| Server CLI + Linux client installer | macOS client / VPNEngine | App service layer, secure store, connection lifecycle, platform permission and packaging | CLI integration harness first; reuse portable profiles; evaluate UI separately | High |
| No cloud APIs | BYOC providers | Credential scopes, provisioning, cloud firewall, reconciliation, safe destruction | Future ProviderAdapter shares ServerTarget and SSH | High; deferred |
| Local monitoring | Transparent cost / traffic forecasts | Billing units, currencies, allowance/overage, pricing freshness | Phase 1 manual cost metadata; later cost engine and provider data | Medium–High |
| No management agent | Optional management agent | Authenticated API, lifecycle and SSH recovery | SSH-only first; preserve independently running systemd data plane | High; deferred |
| No third-party installation import | Discover/import existing VPN | Ownership proof, safe adoption and format compatibility | Phase 1 detect conflicts and refuse overwrite; later adoption | High; deferred |

## Conflicts resolved before Epic creation

1. **#5**: preserve closed status and existing conclusions. Link under Protocol
   Runtime / sing-box evolution, not as a completed child or mandatory dependency.
   Future migration requires fresh capability evidence and explicit evaluation.
2. **Client technology**: existing `unified-client-analysis.md` proposes Flutter +
   sing-box; handoff proposes SwiftUI + Rust. Neither is implemented. Compare
   alternatives in an ADR; do not silently supersede either proposal.
3. **Runtime neutrality**: sing-box is already a client/config target, not the
   installed universal server backend. Keep Xray/Hysteria/AWG distinct.
4. **First protocol**: recommend Hysteria2 because it has pinned asset verification,
   secret preservation regression tests, service-unit management and portable
   renderer coverage, without AWG kernel/PPA integration or Reality transport
   differences. Native client YAML is still new work; it is not already delivered.
   Requires a valid domain/TLS and reachable UDP. Failed preflight blocks deployment;
   do not lower existing production security profiles to accommodate it.
5. **Platform scope**: first supported target is Existing Ubuntu VPS with systemd;
   Debian, ARM64, NAT/home/NAS are explicit later acceptance matrices, not promises.
6. **Recovery**: current state rollback cannot underpin disaster-recovery claims.
   Remote job interruption/retry and complete encrypted backup are separate work.
7. **Independence**: existing backends run locally. Installation, upgrades and
   subscription refresh may use external sources; control-plane independence is
   not a promise of no network use. An exported profile must keep connecting when
   the manager/project API is unavailable.

## ADR recommendations (proposed, not accepted decisions)

| ADR | Preferred starting point | Alternatives and evidence required |
|---|---|---|
| ADR-001 Local-first Control Plane | Local application services; independent remote data plane | Optional sync/central plane; prove offline inventory and native-client operation |
| ADR-002 Protocol Runtime Abstraction | Protocol + runtime capability map and Bash compatibility adapter | Unified runtime; compare exact transport, export and upgrade compatibility; include #5 |
| ADR-003 SSH vs Optional Agent | SSH-only first, verified host identity; optional agent later | Agent API/mTLS; prove agent removal and SSH recovery preserve VPN |
| ADR-004 Shared Core Language | Keep Bash server backend; language decision for new controller remains open | Rust/Go/platform core; compare SSH/vault support, packaging, maintenance and FFI via small PoC |
| ADR-005 Local State | Versioned local store with vault references and operation journal | JSON vs SQLite; evaluate atomic writes, concurrent access, migrations and reconciliation |
| ADR-006 Backup / Recovery Format | Versioned encrypted manifest + allowlisted payload, offline restore instructions | age or other established encryption; specify recovery-key ownership, integrity, upgrades and safe extraction |

## Verification

Local fast Bats: **444 tests, 0 failures, 5 skipped**, exit 0. ShellCheck over
all scripts/tests `.sh` and `.bash` files at style severity: exit 0.
`git diff --check`: passed. Baseline contains 465 test declarations; fast
selection and skips must not be reported as 465 executed passing tests.
Fast mode intentionally excludes network and real-client tests. No VPS mutation,
root deployment, full network suite or live migration/restore was performed.
CI configuration was inspected; this does not establish latest CI run success.

## GitHub execution

Total Epic created: [#13](https://github.com/EasyIndie/EasyNet/issues/13).
#5 is linked under Protocol Runtime / sing-box evolution, preserving its closure.
No proposed Phase 1 child issues were created. The connector returned write 403;
the authorized creation succeeded through the local GitHub CLI.
