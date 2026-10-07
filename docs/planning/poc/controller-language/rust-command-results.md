# Rust fixed-command gate — G0-04.2al

Status: **six-case runtime gate verified on 2026-10-08**. Sol high approved
the source; root ran the frozen actual owned child/SSH race/JSON command.
Reviewed Command-stage-v1 and RustBridge-v1; production language pending.

| Case | Command | Observed terminal | Observed exit |
|---|---|---|---|
| complete | fixture.complete | fixture-complete-observed, joined | 0 |
| output-overflow | fixture.large | unknown, joined | 2, fixed SSH failure |
| block-deadline | fixture.block | unknown, joined | 2, fixed SSH failure |
| block-cancel | fixture.block | unknown, joined | 0, stage containment |
| block-eof | fixture.block | unknown, joined | 0, stage containment |
| pre-cancel | fixture.block, no G | not-dispatched, joined | 0, stage containment |

G cases require authenticated and actual Success ack; block cases independently
wait BlockReached before interruption. One exec/command is expected, no replay.
After child Wait, pending block must remain 1 and fixture.done open; only owned
fixture.Close releases the server callback, joins its workers and reduces it to
0. Local cancellation is not remote cancellation or reconciliation.

Combined SSH output retention <=4096 is covered by reviewed source and synthetic
mixed-stream 4096/4097 tests. Real overflow tests only observe the fixed failure
and unknown outcome; event IPC does not expose actual retained SSH output length.
IPC stdout/stderr caps, descriptor closure, immutable Wait and complete event
channel are asserted in all cases. No raw output, ID or credentials logged.

C/EOF exit0 is the reviewed **stage containment exception**, distinct from the
full candidate contract requiring completed-observed and joined for exit0.
Channel-open/exec-ack stalls, acknowledgement lost, missing status/Close,
control/event failure and cleanup-failure qualification remain pending; this
six-case gate cannot complete parent G0-04.2d. Rust vault/result/packaging and
ADR-004 remain pending. Frozen exact commands: task-bindings/G0-04.2al.json.

Actual run: exit0, six subcases plus parent passed, package 2.871s, parent 1.13s;
zero fail/skip/DATA RACE, independently parsed from temporary
`/tmp/easynet-rust-command-gate.json`. Subcase seconds in table order:
0.53, 0.02, 0.51, 0.04, 0.03, 0.01. Compile-only previously passed 0.593s;
unchanged auth/KEX/IPC and Bash suites were not repeated. Actual binary SHA-256:
`974fa3fcfa15fcd93cd48a45f66c5e3eb9d5e2efd661659ca28df1929026a645`.
