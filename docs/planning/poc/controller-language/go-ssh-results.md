# Go candidate A — SSH lab gate

Snapshot: 2026-10-07 10:55:29 +08:00. Scope: SSH lab v1 only.
Go is a compared candidate; no production language decision is made here.
Swift/system OpenSSH remains the macOS comparator; Rust candidate B remains pending.

## Reproduction and environment

macOS 27.0, Darwin arm64; actual runner UID 501 (non-root).
Tool: `/tmp/easynet-poc-toolchains/go/bin/go`, Go 1.27.1 darwin/arm64.
Module pins `golang.org/x/crypto v0.57.0`; declared indirect x/sys v0.48.0.
Compiled local package dependency listing confirms x/crypto v0.57.0.
GOENV=off, GOTOOLCHAIN=local; GOPATH/GOCACHE are task-owned `/tmp` paths.
Only loopback port-0 listeners, synthetic user fixture and generated in-memory
Ed25519 keys; no personal SSH/agent/Keychain/system user/shell/PAM/real credentials.

```text
env GOENV=off GOTOOLCHAIN=local GOPATH=/tmp/easynet-poc-cache/go GOCACHE=/tmp/easynet-poc-cache/go-build /tmp/easynet-poc-toolchains/go/bin/go -C poc/controller-language/go test -timeout 30s -race -count=1 -json ./... > /tmp/easynet-go-ssh-gate.json
```

Exit 0; package elapsed 2.048 s. JSON terminal action counts:

| Scope | pass | fail | skip |
|---|---:|---:|---:|
| Package | 1 | 0 | 0 |
| Top-level test (Test present, no `/`) | 16 | 0 | 0 |
| Subtest (Test contains `/`) | 19 | 0 | 0 |

These are separate parent/subtest event counts; adding them would inflate the
count of independent cases. Race detector reported no races. JSON is an owned
local test-event artifact, not a product result schema or authenticated receipt.

## Common A/B SSH matrix: candidate A results

| Metric | Actual Go evidence | Gate |
|---|---|---|
| Real signed-key SSH | Matching supplied key, signed client auth, exact fixed complete bytes | pass |
| Wrong credential | Generated wrong key refused; positive auth callback, zero exec | pass |
| Unknown/changed host | Unknown before dial; changed before auth; joined zero-auth/exec snapshots, unchanged supplied trust | pass |
| Endpoint/command limits | Literal loopback only, decimal valid port, fixed fixture user/tokens; invalid inputs zero exec | pass |
| Prohibited requests | Valid direct-tcpip typed Prohibited, port-0 tcpip-forward, valid PTY and subsystem refused; malformed/arbitrary exec not accepted | pass |
| Handshake deadline | Server validates actual client SSH identification, withholds KEX; 100 ms context times out below 1 s | pass |
| Auth deadline | Trusted KEX reaches unsigned public-key negotiation callback; 100 ms context times out below 1 s | pass |
| Live setup cancellation | No-deadline contexts cancel after client identification/auth phase; context.Canceled below 1 s, zero exec | pass |
| Combined output cap | One stdout/stderr writer: exactly 4096 allowed; 4097/straddle reject persistently; concurrent copied snapshots race-safe | pass |
| SSH overflow integration | Concurrent 4096 stdout + 4096 stderr; immediate owned-client close; ErrOutputLimit precedence, unknown, retained <=4096 bytes, exec once | pass |
| Pre-dispatch rejection | Invalid/nil inputs and pre-cancelled context: not-dispatched, no retained owner, zero exec | pass |
| Post-ack cancellation/deadline | Server BlockReached plus client Start-success signal; unknown, same operation ID, OwnerRetained=true, exec once/no replay | pass |
| Independent uncertainty | PendingBlocks=1 after client closure; only Fixture.Close releases it to zero | pass |
| Owned cleanup | Joined handshake/auth/block workers; concurrent/idempotent Close; closed listeners refuse dial; Run closes/joins exclusive client | pass |

Reviewed implementation evidence: G0-04.2g/j/h/k/l/m/i; this gate reruns all
package cases together. Successful Run reports fixture-complete-observed and
still retains ownership. AuthReached proves an unsigned probe, not signed-auth
success. BlockReached proves server entry after reply attempt; a distinct
internal-only signal after successful session.Start proves actual client ack.

## Limits and remaining gates

Timing assertions and JSON test elapsed samples are fault-test evidence, not
benchmarks, performance/cost/package-size comparisons or supported platform policy.
OwnerRetained and pending fixture state are lab observations, not durable remote
ownership, cancellation proof, reconciliation, authenticated receipts or journal.
The local client has no user trust enrollment/rotation ceremony or production
credential lifecycle. Vault locked/store tests and strict JSON result packaging,
Rust B matrix, language ADR disposition, deployment/remote privilege acceptance,
macOS signed packaging and real-platform/client acceptance remain unverified here.
No production adapter or language selection, deployment, root/service changes,
Bats acceptance claim, task state changes or commits result from this gate.

2026-10-07 matching fixture credential API follow-up: full Go package race rerun after the fixture change passed, 26 top-level +19 subtests, fail0skip0, elapsed2.242s. This preserves the earlier SSH fault matrix while adding memory-only credential export tests; Rust SSH runtime remains pending.
