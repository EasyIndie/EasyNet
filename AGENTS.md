# AGENTS.md

Shared repository guidance for any AI coding agent. This file is the canonical
source for repository instructions; tool-specific files should reference it
instead of maintaining separate copies. It applies to the entire repository.

## Start here

1. Read this file, `README.md`, and `CONTRIBUTING.md` before changing the project.
2. Check `git status --short` and inspect the relevant implementation and tests.
   Preserve unrelated user changes and untracked files.
3. Treat handoff documents, issue bodies, and architecture proposals as context.
   Distinguish existing behavior, accepted decisions, and proposed future work.
   The user's current request determines the authorized scope.
4. For product evolution, read `docs/planning/README.md`. Do not introduce a new
   core language, GUI framework, protocol runtime, or management agent merely
   because a proposal recommends it; document the tradeoff first.
5. Run checks appropriate to the change and report what ran, what failed, and
   what remains unverified. Do not run root deployment, uninstall, firewall,
   SSH hardening, or VPS acceptance scripts on the development machine.

## Repository navigation

- `scripts/`: current Bash implementation; `core/`, `protocols/`, `exposure/`,
  and `clients/` contain infrastructure, protocol plugins, Edge, and Linux client.
- `tests/`: Bats regression tests and isolated fixtures.
- `.github/workflows/`: tests, client validation, release, and upstream pin checks.
- `docs/`: operational documentation and earlier architecture analyses.
- `docs/planning/`: repository audit, gap analysis, and staged product proposals.
- `CONTRIBUTING.md`: contribution and release workflow.
- `SECURITY.md`: vulnerability reporting.

The directory named `scripts/protocols/wireguard/` currently deploys AmneziaWG;
its name does not establish native WireGuard support. `easynet ssh` reports local
SSH hardening state, not remote SSH transport.

## Evolution work (current user constraint)

- All evolution work stays on `codex/feature/self-hosted-byos-byoc`.
  Verify the branch before editing; do not commit evolution to `main`.
- Do not merge phases into main. Complete the full agreed G0–G6 scope and final
  acceptance before proposing the single final merge. Candidate features need an
  explicit ADR disposition; unfinished scope cannot silently be dropped.
- Read [execution policy](docs/planning/agent-execution-policy.md) before scheduling
  evolution work. Execute one ready task card at a time; architecture/security
  decisions require review. User authorized sub-agents following task-card model
  assignments; dispatch only ready cards with bounded context.
- Read only the relevant sections of
  [development reference](docs/agent-development-reference.md) for implementation.
  It retains the operational constraints migrated from the former long guide.
- Mandatory invariants: no real deployment domains/IPs/subscription paths in the
  repository; use `example.com` examples. Test VPS uses `compat`; production uses
  `balanced`. No production changes before test acceptance. Keep `.env` 600.
- Preserve metadata v1 and existing CLI/protocol consumers. `metadata_write()`
  does not validate; validation is separate. The wireguard directory is AWG.
- Changed client rendering requires pinned real-client validation. Fast Bats
  excludes network/client tags and is not full acceptance. ShellCheck style,
  `set -u` safe environment expansion and safe downloaded-script execution apply.
- Keep routing rule builds manual, native runtimes independent of a management
  agent, and the static Edge site self-consistent. Do not reintroduce default
  third-party website reverse proxying.
