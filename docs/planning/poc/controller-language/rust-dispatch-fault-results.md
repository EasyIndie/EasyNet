# Rust dispatch observation fault gate — G0-04.2an

Status: **verified 2026-10-08**, bounded 12-case gate only. Sol high approved the
source; root executed and independently counted the frozen race/JSON runs.

| Passed case | Server exec/commands | Ack observed | Terminal | Exit |
|---|---:|---|---|---:|
| channel-deadline | 0/0 | no | not-dispatched, joined | 2 |
| channel-cancel | 0/0 | no | not-dispatched, joined | 0* |
| channel-eof | 0/0 | no | not-dispatched, joined | 0* |
| ack-deadline | 1/0 | no | unknown, joined | 2 |
| ack-cancel | 1/0 | no | unknown, joined | 0* |
| ack-eof | 1/0 | no | unknown, joined | 0* |
| acklost-cancel | 1/1 | no | unknown, joined | 0* |
| acklost-eof | 1/1 | no | unknown, joined | 0* |
| no-status | 1/1 | yes | unknown, joined | 2 |
| nonzero-status | 1/1 | yes | unknown, joined | 2 |
| no-close-deadline | 1/1 | yes | unknown, joined | 2 |
| invalid-command-control | 1/1 | yes | unknown, joined | 2 |

*Zero means reviewed stage containment, not successful operation. Full-candidate
RustBridge-v1 exit semantics are not accepted by this card. Exit2 has fixed SSH
failure except the single raw-X negative IPC case, which has fixed I/O failure.
All cases observed signed-auth success, one owned child, exact event-stream end,
parent descriptor closure, immutable Wait, capped IPC diagnostics/events and no
replay. Independent phase callbacks precede deadline/cancel/EOF; no sleeps hide
ordering. AckLost pending block remains1 after child Wait; only fixture.Close
releases and joins server workers, then pending0. Other stalls likewise remain
owned/open until fixture.Close. Local interruption does not cancel remote work.

Actual results, independently parsed temporary JSON (not release artifacts):
- New fault matrix: 12 subcases + parent pass, package3.456s, parent1.79s.
  Subcase seconds in table order: .53,.04,.02,.51,.04,.02,.02,.02,.02,.02,.51,.04.
- Ordinary Go fixture regression: 27 top-level +19 subcases pass, package2.021s.
- Existing Rust fixture regression: 28 subcases +4 parents pass, package3.847s.
- Each run exit0; zero failure, skip or DATA RACE. Compile-only passed1.074s.
  Logs: `/tmp/easynet-rust-dispatch-fault-gate.json`,
  `/tmp/easynet-go-command-fixture-regression.json`,
  `/tmp/easynet-rust-fault-fixture-regression.json`.
- Owned command binary unchanged from al, SHA-256
  `974fa3fcfa15fcd93cd48a45f66c5e3eb9d5e2efd661659ca28df1929026a645`.

SSH retained output cap remains reviewed source + synthetic4096/4097 evidence;
IPC tests do not expose retained SSH length/ID telemetry. Event-write/cleanup
failure injection qualification, full-candidate exit contract, Rust vault/result
packaging and ADR-004 remain pending. Parent G0-04.2d stays locked. No production
language, real VPS, personal vault, remote reconciliation or platform acceptance.
