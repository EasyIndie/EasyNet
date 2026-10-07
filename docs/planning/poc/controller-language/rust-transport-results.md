# Rust KEX-only transport gate

Status: **passed reviewed actual owned-loopback transport gate (2026-10-08)**.
Branch: `codex/feature/self-hosted-byos-byoc`; contract RustBridge-v1 / reviewed KEX-only stage-v1 / actual loopback matrix-v1; card G0-04.2ah.

The tagged Go matrix uses the fixed freshly built owned Rust binary and ephemeral
Go-owned fixture credentials. No key files, external endpoints, authentication,
channels or commands are used. KEX-stage success/cancellation exit 0 is the lab
exception, not completed SSH operation acceptance.

| Case | Required terminal outcome | Runtime evidence |
| --- | --- | --- |
| kex-success | exit 0, nil error, empty diagnostic | passed |
| host-mismatch | exit 2, ErrBridgeChildIO, fixed fixture SSH failure | passed |
| id-deadline | 500 ms deadline; same fixed SSH failure | passed |
| id-cancel | observed client identification before C; exit 0 | passed |
| kex-deadline | observed first clear packet KEXINIT (20); 500 ms deadline; fixed SSH failure | passed |
| kex-cancel | observed first clear packet KEXINIT (20) before C; exit 0 | passed |
| pre-cancel | C before G; exit 0 | passed |

Each case requires ready, not-dispatched, joined and closed event delivery;
stdout/stderr each at most 4096 bytes; a write on the actual parent IPC connection
must fail with net.ErrClosed. All owned SSH Fixture counters must remain zero
(AuthCallbacks/ExecAttempts/Commands); counters do not count TCP attempts.
Host mismatch retains the original client credential/endpoint and substitutes a
second owned fixture's equal-length Ed25519 host wire key, with no TOFU.

One worker per stall listener binds 127.0.0.1:0. Identification reads are bounded;
ID stall sends no banner. KEX stall sends a fixed banner and validates a bounded
whole first clear packet (at most 32768 bytes, padding bounds, message 20) before
publishing phase. Cancellation waits for phase, with no sleeps. Peer EOF is a
separate bounded corroboration of actual transport closure, not proof of task
join. The closed flag and active connection share a mutex; cleanup closes owned
resources and bounds the worker join. Child cancellation/reap cleanup runs first
through LIFO test cleanup. Rust's reviewed source join proof and terminal joined
event remain necessary; an externally killed child cannot satisfy these assertions.

Executed: tagged compile only, `go test -tags bridgeipc -timeout 30s -run '^$' .`,
using the frozen environment/toolchain in the binding: exit 0,
`[no tests to run]`, package time 0.707 s. No children/listeners/transport tests
were launched by this preparation check. `git diff --check` passed.

Full auth, wrong-client-key, post-ack cancellation, output, vault, JSON result,
language selection and ADR-004 remain pending their respective acceptance.

Root actual evidence: Sol high review approved before the frozen race-enabled JSON
run. Seven subtests and parent passed, package3.203s (parent1.56s); zero failures,
skips or DATA RACE. kex-success0.50s; mismatch0.02s; ID/KEX deadlines0.51s each;
ID/KEX cancel0.01s each; pre-cancel0.00s. Each passed the fixed events, descriptors,
zeroauth/exec and relevant independent peer EOF assertions. Existing seven-case
IPC regression after the child change also passed under race, package1.537s.
These are actual timings, not guaranteed latency/service limits. Host binary
SHA256 c81ef6d86acc27fb8ba1315083fff36a1a49e2efa1cff58c29d37c851d3caec1.
No complete SSH operation, production controller language or nonhost qualification
is established; the listed remaining gates are unchanged.
