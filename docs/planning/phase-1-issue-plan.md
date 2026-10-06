# Phase 1 issue proposal

Status: proposal only; no child issues created. These issues should link to the
[total Self-hosted BYOS/BYOC Epic #13](https://github.com/EasyIndie/EasyNet/issues/13) when opened. P1-A through P1-K are document IDs,
not GitHub issue numbers. No implementation language or GUI framework is selected.

Detailed engineering tasks and their mapping to P1-A–K are maintained in the
[executable backlog](execution-backlog.md). Use those task IDs for execution;
this file remains the issue-level grouping, not a second implementation queue.

All Phase 1 work integrates only into `codex/feature/self-hosted-byos-byoc`;
Phase 1 acceptance does not authorize merging into main.
Atomic tasks and model review boundaries follow the execution policy.

## Milestones

**Phase 1A: management vertical slice** — Existing Ubuntu VPS → SSH trust/test →
read-only preflight → reviewed deployment plan → one Hysteria2 native runtime →
native client YAML + existing compatible formats. Begin with a CLI/integration
harness over application services; preserve the existing on-host `easynet` CLI.

**Phase 1B: usable macOS MVP** — connection manager, remote operations, manual
costs and encrypted backup/restore. GUI follows the tested core slice. Cloud
provisioning, broad protocol coverage, automatic third-party adoption and a
management agent are outside Phase 1.

## Proposed issues and acceptance criteria

| ID / proposed title | Deliverable and acceptance | Dependencies |
|---|---|---|
| P1-A `[Architecture] Define Phase 1 contracts and evaluate ADR-001–006` | Document application-service boundary, protocol/runtime IDs, structured results/errors, privilege/ownership model; compare controller languages and state/backup choices; distinguish accepted vs proposed ADRs | None |
| P1-B `[Core] ServerTarget / ExistingServer and local-first inventory` | Stable server ID, SSH host/port/user, capability facts, selected runtime, credential references and manual cost fields; versioned storage with atomic writes/migrations; no secrets in ordinary inventory; round-trip two independent targets | A |
| P1-C `[SSH] Trusted remote transport and credential storage` | Host-key fingerprint verification/explicit first-use trust; changed key blocked; vault interface and macOS secure-store implementation; key/agent auth; root or scoped sudo policy; bounded timeouts/cancellation; remote temp cleanup; secrets absent from command args/logs | A, B |
| P1-D `[Preflight] Read-only compatibility report before bootstrap` | Structured OS/version/arch/systemd/resources/listeners/firewall/DNS/TLS/privilege facts; port conflicts based on effective config and TCP/UDP; network facts distinguish observed/unknown; reject unsupported target before apt/firewall/config writes; detect existing installs without adopting or overwriting | A, C |
| P1-E `[Protocol] Bash-compatible ProtocolDriver and deployment plan` | Separate protocol from runtime; wrap existing manifest/deploy/export/health/service operations; explicitly unsupported methods; `.env` transfer 600; serialize target operations; verified release staging; surface bootstrap/firewall/cron effects; interrupted runs reconciled before retry; preserve existing profiles and modules | A, C, D |
| P1-F `[Export] Hysteria2 native client profile and offline escape hatch` | Generate standalone Hysteria2 client YAML, URI, existing Clash/sing-box artifacts from validated facts; preserve secrets/SNI/obfs/port-hop semantics; validate with pinned relevant real runtimes; export protected files and recovery instructions; native client works without manager or subscription refresh | A, E |
| P1-G `[Integration] Existing Ubuntu VPS → SSH → Deploy → Native Export` | Application-service CLI/harness composes B–F; explicit test VPS verifies first deploy and redeploy retain secrets, failed preflight makes no changes, lost SSH resumes safely, TLS/UDP connection works; all four existing modules retain regression coverage | B–F |
| P1-H `[Backup] Encrypted manifest backup and restore to another VPS` | Versioned allowlisted deployment manifest, configs/keys/certs/rules and local metadata; credential-reference handling excludes raw provider tokens by default; authenticated encryption/recovery key; validate before extraction, reject traversal/symlinks; rebuild using pinned artifacts; remap IP/domain/certs explicitly; new-host restore and wrong-key/tamper tests | B, E, F, G; ADR-006 |
| P1-I `[Operations] Remote status, traffic, restart and upgrade` | Structured SSH-based status/logs, redacted errors, traffic counters with reset semantics; guarded restart and verified release upgrade; preserve credentials and subscription paths; show partial failure; account for current state-only rollback limitations | B, C, E, G |
| P1-J `[Cost] Manual existing-server costs and TCO summary` | Billing cycle/currency, included traffic and overage units, unknown vs Free/Already Owned, monthly/yearly totals; no current provider prices hardcoded; test boundary/unit handling; estimated vs observed usage explicit | B; I for observed usage |
| P1-K `[Client] macOS MVP over application services and VPNEngine` | After framework/engine ADR: server import, fingerprint trust, preflight/plan/deploy, import native profile, connect/disconnect/status, operations/export/backup/cost; secure storage; platform permissions and packaging evaluated; survives app restart; independent native client works with app stopped | G, H, I, J; client framework/engine ADR |

## Order and minimal implementation plan

1. Decide minimal contracts and controller language with A; implement B and C.
2. Implement D as a separate read-only remote command/report before calling the
   current installer. `EASYNET_STRICT_PRECHECK` alone is insufficient because the
   current script already bootstraps before its module preflight.
3. Implement E for Hysteria2 only. Keep existing deployment and renderers behind
   a compatibility adapter, send a validated `.env`, install a pinned release and
   report structured outcomes alongside redacted human logs.
4. Deliver F and prove G with an explicit test VPS. The test environment continues
   to use `compat` for full acceptance; the single-protocol slice is a scoped
   isolated validation and does not replace that acceptance convention.
5. Deliver H–J, then K. P1A completion is not equivalent to the complete Phase 1
   macOS MVP or the total Epic being done.

## Phase 1 exit criteria

- Fresh and already-managed Ubuntu fixtures pass first deploy, redeploy and
  interruption recovery without silently rotating keys or overwriting unrelated
  installations. Unknown preflight facts cannot masquerade as success.
- SSH failures, changed host keys, insufficient sudo, command quoting, concurrency
  and secret redaction have automated coverage.
- Native profiles pass actual runtime validation and live connection acceptance;
  the manager can be stopped while the VPN data plane continues.
- Local state survives restart/migration; backup decrypts and restores on a second
  target with a documented endpoint/certificate update procedure.
- macOS connection/operations/cost/export/recovery flows pass their acceptance
  matrix; current Bash CLI, metadata v1 consumers and four plugins still work.
- No required account, central API, provider API, paid VPN service or server agent.
