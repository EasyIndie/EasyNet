# SSH language PoC lab contract v1

Reviewed preparation: Sol high recommended Go candidate A, Rust candidate B;
root accepts this comparison scope only. Production language stays pending ADR-004.
Swift/system OpenSSH remains the macOS comparator, not silently removed from evidence.

## Tools and isolation

Root installed official hash-verified archives only below `/tmp/easynet-poc-toolchains`:
Go 1.27.1 darwin/arm64 and Rust 1.99.0 aarch64-apple-darwin. Existing Go, HOME,
shell profiles and system services are untouched. Go exceeds x/crypto v0.57.0's
Go 1.26 minimum; this lab's newer compiler is not a product minimum-OS decision.
Official [Go manifest](https://go.dev/dl/?mode=json) lists archive SHA256
`ee215d57e0ec269c60cc9ceca68e6bda321ba9ee5afe24f4b0988703c2d87d12`.
Rust 2026-10-01 [manifest](https://static.rust-lang.org/dist/2026-10-01/channel-rust-stable.toml)
provided per-component hashes, checked before extraction and local installer execution.
Rust components were reconciled sequentially after preparation; tool versions passed.

Use absolute tool paths and task-owned temporary caches. Go: `GOTOOLCHAIN=local`,
`GOENV=off`, `GOPATH=/tmp/easynet-poc-cache/go`, `GOCACHE=/tmp/easynet-poc-cache/go-build`.
Rust: temporary CARGO_HOME/target only. Never read personal SSH or Keychain state.
Dependencies: Go `golang.org/x/crypto v0.57.0`, checked go.sum; Rust candidate
`russh =0.64.1` proposed; verified published crate Cargo.toml requires Rust 1.89 and
offers `ring` as an explicit feature. Rust 1.99 satisfies that declared minimum;
transitive graph, exact features and lockfile/build must still pass before its card.
The downloaded crate SHA256 matched registry metadata:
`ba61e87b9ec9a39a59a6bbed4c0b8ff7fb07073405b24a767a1f2c8560ac8f58`.
Package downloads and loopback socket tests are authorized preparation/test effects;
restricted execution may require automatic approval, not a change in user scope.

## Disposable real-SSH fixture

Use Go NewServerConn on a loopback-only ephemeral port, non-root. Generate ephemeral
Ed25519 host/client keys in memory, synthetic username `fixture`. No OS users,
sshd/PAM, real credentials, shell/exec subprocess, PTY, subsystem or forwarding.
Accept only matching generated public-key auth and session channels. Count auth
callbacks and exec attempts; none of these counters contain secret payloads.
Commands are exact closed tokens: `fixture.complete`, `fixture.block`, `fixture.large`.
The fixture only returns fixed bytes, waits on an owned channel, or emits a bounded
oversize response. Reject all other requests. Cleanup closes only owned resources.

## Identical A/B client assertions

Trust is externally supplied expected key bytes, never auto-enrolled observation.
Reject unknown/mismatched keys before any auth callback; preserve trust bytes.
Success proves actual SSH key exchange, signed key auth and fixed-token execution.
Wrong key cannot execute. Do not invoke agent APIs or forward credentials.
Connection/handshake/auth/output waits are bounded by an absolute deadline;
response limit 4096 bytes; connect only the fixture's loopback endpoint, no arbitrary
commands/hosts supplied by imports. Cancellation before dispatch means no exec;
after server-acknowledged dispatch means unknown with the same operation ID and
ownership, no replay. Observation loss must not claim remote cancel or terminal state.
Independently observe fixture counters/state; these are test evidence, not authenticated
production receipts or reconciliation. Use generous bounded timing tolerances, no races
hidden with sleeps. Vault and strict JSON are separate cards, not simulated success here.

## Small-card sequence

G0-04.2g creates the Go fixture/module and success tests. G0-04.2j separately checks
wrong key, forwarding/PTY/arbitrary requests and owned cleanup. G0-04.2h adds
Go key auth and unknown/changed-key gates. G0-04.2k checks handshake/auth
deadlines; G0-04.2l checks combined output limits; G0-04.2m checks bounded Run
and observed/unknown results; G0-04.2i checks cancellation
and retained unknown operation outcomes. Original G0-04.2a then verifies candidate A's complete SSH evidence.
Each implementation is reviewed before the next card unlocks. No production adapter,
user trust enrollment, remote ownership engine or deployment authorization is implemented.
