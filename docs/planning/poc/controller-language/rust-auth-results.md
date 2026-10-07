# Rust signed-auth gate — G0-04.2aj

Status: **verified signed-auth phase gate on 2026-10-08**. Fresh Sol high
review approved the fixed matrix; root ran and independently counted actual
Unix `bridgeipc` race/JSON tests.
Scope: RustBridge-v1 / reviewed Auth-only stage-v1 / signed-auth faultmatrix-v1;
feature branch `codex/feature/self-hosted-byos-byoc`. No source/dependency changes.

| Passed case | Fixed events after ready | Expected result | Original auth callbacks |
|---|---|---|---|
| signed-success | authenticated, not-dispatched, joined | exit 0, nil error, empty diagnostic | >=1 |
| wrong-client-key | not-dispatched, joined | exit 2, ErrBridgeChildIO, fixture SSH failure | >=1 |
| host-mismatch | not-dispatched, joined | exit 2, ErrBridgeChildIO, fixture SSH failure | 0 |
| auth-deadline | not-dispatched, joined | exit 2, ErrBridgeChildIO, fixture SSH failure | >=1 |
| auth-cancel | not-dispatched, joined | exit 0, nil error, empty diagnostic | >=1 |
| auth-eof | not-dispatched, joined | exit 0, nil error, empty diagnostic | >=1 |
| invalid-auth-control | not-dispatched, joined | exit 2, ErrBridgeChildIO, fixture I/O failure | >=1 |
| pre-cancel | not-dispatched, joined | exit 0, nil error, empty diagnostic | 0 |

All cases assert zero ExecAttempts/Commands, closed event channel, each output
cap <=4096 bytes, closed parent descriptor after Wait, and immutable Wait replay.
Wrong key/host mismatch substitute only independently owned fixture material;
substitute stats must remain zero. PEM/frame test buffers are cleared without
logging contents; library, allocator, kernel and compiler zeroization is unclaimed.
The fixed binary is `/tmp/easynet-poc-cache/rust-target/debug/ssh_auth_fixture`,
with no arguments; the frame uses original fixture port and operation ID
`fixture-auth`, command 0, deadline 500 ms for auth-deadline and 3000 ms otherwise.

Stall cases wait up to 2 s for AuthReached before C, EOF, raw X, or natural
deadline. AuthReached marks an unsigned public-key probe callback, not signed
authentication. Signed success requires the reviewed AuthResult success event
`authenticated` and server callback count >=1. Raw X is one fixed byte written
directly to this child's owned IPC, bypassing parent Control for negative input.
After child Wait, stalled fixture.done must remain open: the server callback
continues until fixture Close. Cleanup registers servers before child so LIFO
reaps the child first; fixture Close releases callbacks and joins server workers.
Client interruption does not prove remote job cancellation or reconciliation.
Exit 0 is only phase acceptance; no exec/output/full candidate B, vault, JSON,
durable ownership, platform qualification or ADR-004 language-selection claim.

Compile-only bound command passed, exit 0, `0.628s [no tests to run]`:
`env GOENV=off GOTOOLCHAIN=local GOPATH=/tmp/easynet-poc-cache/go GOCACHE=/tmp/easynet-poc-cache/go-build /tmp/easynet-poc-toolchains/go/bin/go -C poc/controller-language/go test -tags bridgeipc -timeout 30s -run ^$ .`.
Actual bound `TestBridgeAuth` race/JSON run: exit 0; 8 subcases plus parent
passed, package 2.806 s, parent 1.12 s; zero failures, skips or DATA RACE.
Subcase elapsed seconds, in table order: 0.53, 0.02, 0.02, 0.51, 0.02, 0.01,
0.02, 0.01. Shared-helper regression `^TestBridge(Transport|ChildIPCLifecycle)$`
with `-tags bridgeipc -race -timeout 90s -count=1 -json`: exit 0; 14 subcases
plus 2 parents passed, package 3.042 s; zero failures, skips or DATA RACE.
Root parsed `/tmp/easynet-rust-auth-gate.json` and
`/tmp/easynet-auth-shared-bridge-regression.json`; temporary logs are not release
artifacts. Unchanged full Go/Bash suites were not repeated.

Actual owned binary SHA-256:
- auth: `feddedaf9346522eb98dc90fa8c231c4ece037c2f9bef49d81dda69e9e96e49c`;
- KEX after shared helper extraction: `394fe35f3a475a3f2ca29e9268770244ebacf0535793e7d8dbc9b45c603d72ef`.

Command dispatch, bounded SSH output and post-ack cancellation remain pending,
as do full candidate B, Rust vault/result gates and ADR-004. This phase gate
never selects the production language or proves remote cancellation.
