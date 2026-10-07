# Rust candidate B — SSH gate

Status: **verified candidate B SSH evidence gate**, 2026-10-08. This is an isolated SSH
candidate gate, not a production language decision, runtime replacement or G0
completion. Rust vault (E), result/CLI (F), platform packaging and ADR-004 remain
separate. User G0–G6 final scope and single final main merge gate are unchanged.

| Boundary | Accepted evidence | Limit |
|---|---|---|
| Dependencies/host build | [u](../../task-results/G0/G0-04.2u.md), pinned lock/crates, temporary toolchain | Rust1.99 host only; no1.89 MSRV or release/platform qualification |
| Credential frame | [x](../../task-results/G0/G0-04.2x.md), strict memory-only Ed25519 parsing, 3 tests | No allocator/library/kernel zeroization claim |
| Unknown trust/type/certificate | [af](../../task-results/G0/G0-04.2af.md), typed pre-dial/source plus 8 memory tests | Unknown typed trust refused before dial; not empty-key wire TCP evidence |
| Connection/KEX/trust mismatch | [transport gate](rust-transport-results.md), 7 actual cases | KEX-only phase binary exit0 differs from full command binary |
| Signed auth/wrong key/auth stalls | [auth gate](rust-auth-results.md), 8 actual cases | AuthReached is unsigned probe; signed success requires reviewed AuthResult success |
| Dispatch/output/completion | [ao](../../task-results/G0/G0-04.2ao.md), 18 actual command/fault cases | Only complete+joined exit0; all cancellation/EOF exit2 |
| ID/owner/retained cap | [ak](../../task-results/G0/G0-04.2ak.md), typed memory record/source +3 synthetic tests | Combined cap4096, but no actual retained SSH byte/ID telemetry in event IPC; JSON is F |
| Join/resource lifetime | retained connect/Handle plus OwnedStream Drop; actual fault joined events, closed IPC/peer EOF and owned fixture workers | Stream Drop/EOF alone not join proof; no arbitrary process-tree containment |
| Remote uncertainty/no replay | actual ack-loss/block faults, exact server counters, pending1 until fixture.Close->0 | No remote cancellation, receipts, durable ownership or reconciliation claim |

There are **33 distinct actual SSH scenarios** (7 KEX +8 auth +18 full command),
plus7 IPC-only lifecycle scenarios. Repeated regression runs are not counted as
new coverage. RustBridge-v1 keeps the event pipe fixed and free of credentials,
raw SSH output, endpoint and operation-ID payloads. The parent retains input
identity; reviewed typed Rust state preserves ID/owner once exec might enqueue.
Exactly one exec with want_reply=true is allowed; only actual ChannelMsg::Success
is acknowledgement. Missing status, nonzero status and missing explicit Close
never complete. EOF is not required by the fixed Go complete fixture.

Current full-command artifact SHA-256:
`6a0edea6fd8233904d688cac4779b289d3d9e7942555b19da294523cd1512a5f`.
AO's 18 subcases+2 parents passed, package4.538s, zero fail/skip/race. AL/AN stage
zero-cancel reports refer to earlier SHA974fa3fc… and remain historical; they do
not override current full exit semantics. Independent auth/KEX stage binaries
still accept their phase-only success/cancel exceptions, never operation success.

Root re-counted immutable temporary JSON evidence: shared KEX/IPC16 test-pass,
auth9, full commands20, ordinary Go46; each has one package-pass and no failure,
skip or DATA RACE. The Go count is27 top-level+19 subcases, not46 distinct SSH
fault scenarios. Fixture-change regression28 Rust cases passed separately in AN.
No unchanged test suites were relaunched by this aggregate card. Plan/whitespace
checks only validate documentation; prior real race/JSON runs supply runtime
proof. Ordinary Bash, native vault and VPS acceptance were not rerun or claimed.

Cleanup uses a single absolute operation deadline≤3000ms plus a separately
persisted1000ms cleanup allowance; these are not a500ms wall-time promise.
CleanupFailure retains the owner, emits fixed failure and no joined, then direct
child containment. Event-write failure paths were source-reviewed; forced
stdout failure/cleanup timeout were not injected into a real child. Owned-future
memory tests exercise retained timeout/reborrow/no-proof behavior. These are
explicit qualification limits; the accepted original SSH matrix requires real
bounded cleanup under its tested faults, not these additional injection slots.
No planned G0–G6 product capability is omitted through this disposition.

Final Sol high evidence/scope review approved G0-04.2d. Native Rust
vault/read-no-UI lock behavior and strict redacted JSON/CLI must pass E/F before
candidate comparison can resolve ADR-004. No GUI/framework/management agent,
protocol migration, production deployment or main merge is authorized here.
