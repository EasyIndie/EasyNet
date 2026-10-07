# Go-to-Rust IPC-only bootstrap gate

2026-10-07; reviewed IPC-only gate passed; full Rust SSH remains pending.
Scope: owned Go loopback fixture supplies dynamic port and host key; in-memory
OpenSSH credential framing; actual Rust fd3 Unix control bootstrap only.
No Rust SSH/TCP/auth/dispatch, native vault or production language acceptance.

Fresh offline Rust binary build passed. Tagged Go compile initially failed:
frozen `ssh.CryptoSigner` extraction API is absent in pinned x/crypto v0.57.0.
Root rejected an independent key workaround; verified prerequisite G0-04.2ae
provides matching `Fixture.ClientPrivateKeyPEM()`. Test now uses that API and
clears the temporary returned PEM after encoding. Fresh Rust build and tagged
Go compile-only `-tags bridgeipc -timeout 30s -run ^$` both pass (exit 0).
No actual child/socket/loopback test execution performed by this worker.

Root independently ran the tagged race-enabled matrix against the fresh owned Rust
binary. Seven subtests and their parent test passed; package exit 0, 2.851 s,
zero failures/skips and no DATA RACE in the JSON log. Cases: G-C, C first, EOF,
malformed input, control deadline, external cancellation and invalid local control.
All cases verify fixture authentication/execution/command counters remain zero.
Successful cases observe not-dispatched then joined; process-kill cases do not
claim internal join. Parent writes after Wait return net.ErrClosed. Eight concurrent
Wait calls after completion return identical summaries; repeated Close succeeds.
This does not establish concurrent callers waiting during cancellation, Rust SSH
session cleanup, process-tree containment, native vault or production acceptance.
Security review: Sol high approved bounded descriptors, framing, redaction and
cleanup assertions before root execution. Raw JSON remains temporary test output;
no credential bytes are included in this report.
