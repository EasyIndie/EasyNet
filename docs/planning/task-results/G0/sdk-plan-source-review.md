# Q-B planned-job source — consolidated R findings

2026-10-10; exact three-file source review against
[frozen producer contract](sdk-producer-review.md). No candidate import,
fixture, test, compiler, guest, probe or further research ran.

## Reviewed package

| File | SHA-256 | Lines/bytes |
|---|---|---:|
| `native-lab/build.py` | `19a6bdc0721b62a9a3361bbeffe4b263043b8d59ffcb4ec09dc234e1abdeb75c` | 681/33,712 |
| `native-lab/Tests/test_build.py` | `884330698d9aa52b0d998de95b10c01fa7553e0ab836d643026a12e3a069b1fc` | 535/30,076 |
| `native-build-contract.md` | `9c5b8ebc6ec94991c767c6fd357b6254ed56ddf330a5b2f2b52b57aa1d5b9c32` | 245/18,672 |

Paths are under `docs/planning/poc/client-framework/`. All exact hashes match;
caps 700/40KiB, 550/32KiB, 245/32KiB pass. AST confirms the old 18 test
methods are unchanged and exactly one parser/grant case joins the closed names.
Diff check passes. Shared compile argv differs only by conditional diagnostic
flag; artifact SDK checks and normal compile flags remain unchanged.

## One consolidated correction list — source not accepted yet

1. **P1: retain adoption authority.** After diagnostic `run()`, its finally can
   set `expected=None` when fixed source/result/plist adoption or child cleanup
   fails. The diagnostic's unconditional inventory assignment then replaces
   that refusal with a fresh snapshot. A fixed-entry mutation can therefore
   become planned/success and removed cleanup. Require the existing `expected`
   to remain non-null immediately after diagnostic run; do not replace it with
   blind inventory. Preserve `run()`'s adopted snapshot and existing final
   cleanup ownership checks. Failure must stay fixed cleanup/retained, with
   no successful semantic observation or binary execution.

2. **P2: preserve malformed binding refusal.** New phase selection calls
   `binding.get()` before `sources()` checks dict type. None/list now cause an
   internal AttributeError instead of prior fixed source-mismatch. Add a dict
   guard before `.get()`, preserving source-mismatch with no commands, root or
   raw exception. Include None/list fixtures with capture/mkdir not called.

3. **P2: close dangling wrapper syntax.** The parser's generic `-X*` branch
   accepts an absent operand as empty `wrapped`, increments past the end and
   emits apparently parsed absent forwarding. Because this branch structurally
   consumes a wrapper/operand pair, require the next nonempty token to exist.
   Keep ordinary irrelevant pairs transient/ignored; refuse dangling/empty
   `-Xlinker`/other `-X*` with plan-format and add corresponding pure fixtures.
   Frozen platform forms and relevant wrapped refusals stay unchanged.

Consolidate these into one I correction pass. Add a no-tool mocked positive
diagnostic/adoption-failure case in the same new method if it fits: demonstrate
valid adopted plan returns planned with artifact not-run and removed staging,
and failed adoption cannot reach planned or call artifact/ordinary compile.
Any retained fixture tree must be cleaned only as its owned test fixture.
Do not spawn a compiler/candidate or change the old 18 test bodies. If meaningful
coverage exceeds a cap, report the concrete estimate before editing; do not
compress or silently omit it. Root reviews any explicit additional bound.

## Remaining disposition

Parser semantics, bounded shlex admission, enums/redaction, direct/platform
forms, duplicate category refusal and exact diagnostic grant pairing otherwise
match the frozen proposal. Fixed planned-job output is classified evidence;
tool basename is not identity and no value proves producer cause.

The isolated new method uses pure parsing/owned manifest files and mocked
capture/mkdir for mismatched pairs. It presently executes no subprocess or
native tool. Its source hashes must change with the corrections, so freeze no
wrapper or local allowance yet. Old grants stay consumed/zero and workflow
disabled. R reviews the corrected complete three-file diff/hashes once, then
may freeze one bounded isolated test. Hosted immutable binding/bootstrap
40KiB-exact-driver/32KiB-others, 19-case/planned changes and actual activation
remain future separately reviewed work. All SDK/build/G0/final gates persist.

## Final fixture-budget disposition — accepted

Accept tests 600 lines/40,960 bytes for the retained no-tool positive-phase and
adoption-failure fixtures; driver stays 700/40,960 and contract 245/32,768.
All mocked staging/path mapping stays inside owned `self.root`; no subprocess,
candidate, toolchain or unrelated path access. Preserve every case without compression.
Future bootstrap 40,960 applies only to exact build.py and Tests/test_build.py;
other files stay 32,768. I resumes the same draft with the consolidated three
corrections; one complete source/hash review follows. No preliminary runtime/local
grant is added; prior grants remain zero and workflow disabled.

## Corrected complete source package — accepted

R accepts the same three corrected source files; prior findings are resolved.
Non-dict guard precedes `.get()` and preserves source-mismatch; malformed
diagnostic pairs stop before commands/root creation. Generic `-X*` requires a
nonempty operand. Diagnostic run requires its adopted `expected` to remain
non-null, preserving refusal/retained cleanup without blind re-inventory.
Parser semantics, bounded admission, finite output and artifact gate remain.

| File | Exact SHA-256 | Lines/bytes |
|---|---|---:|
| `native-lab/build.py` | `983ed20135a64d05250e33790eb37d4a36aa41570c55d8010ccc96b58853ad20` | 683/33,792 |
| `native-lab/Tests/test_build.py` | `b3b446f113bad3d0452ba1674317c0e003f42413fb62d2e29e40b8b93bd3100b` | 578/33,127 |
| `native-build-contract.md` | `c502d465adbb4d8808e96da904db9000ee2c2544624171b489318ff1bc170f20` | 245/18,768 |

All hashes/caps match and AST preserves every old 18 method body with one new
method (19 names). Only the standard-library shlex import is added. Compile
argv and artifact checks remain unchanged outside the distinct diagnostic.

The new method's positive/adoption-failure harness maps only literal
`/private/tmp` to owned `self.root`; remaining Path values are lexical/owned.
Sources are owned manifest fixtures. Identity/capture are mocked and Popen is
also mocked/asserted not called; capture asserts every staging root is under
self.root. No vendor tool/path is inspected or executed. Six mocked captures
prove the single driver-jobs flag path and no ordinary compile/artifact call.
Fixed Host mutation produces failed/cleanup/retained with null driver_jobs;
its owned fixture alone is then inventoried and deleted. The positive case
returns planned, artifact null/not-run and removed staging. Both assert the
owned staging is gone. None/list, grant mismatches and dangling wrappers retain
their explicit no-command/refusal fixtures. R executed none of these tests.

## One isolated local successor — frozen, not executed

Derive `local-sdk-driver-jobs-v1` from consumed
`docs/planning/task-bindings/local-sdk-logical-path-v1.json`, preserving argv
whose reviewed file digest is
`0efc87b6cc12897a5cf491e8b1f99c128a1ef2c943d5ec84bdcafe7847c4ecd5`;
`[/usr/bin/python3, -I, -B, -c]` and run_name `artifact_predicate_target`.
In argv[4] replace only the old target with `local-sdk-driver-jobs-v1`, method
with `test_driver_jobs_parser_and_grant`, and three hashes with this package's
exact hashes. Resulting wrapper is 1960 UTF-8 bytes, SHA-256
`22c92c0cfc65daa920d45ef73f9b35fc22d6b58481703ba9a7ed06ee02e6c80e`.
Root may create a new frozen binding, cwd
`/Users/joker/Documents/EasyNet`, deadline_seconds=10, max_output_bytes=1024,
local_remaining=1/guest_remaining=0, then execute exactly once. Hash verification
precedes candidate import. Target only this owned-file/parser/mocked method;
no actual subprocess, toolchain, native candidate, network or guest.

Require target/method match, tests=1, passed, failures/errors/skips=0,
fixture_cleanup=passed, exit 0 and <=1KiB finite output. Consume at dispatch;
failure stops without retry, and close the new binding at zero afterward.
This never restores old grants or permits full19, driver-jobs invocation,
compile, guest, push or activation. A later source checkpoint/hosted package
needs local closure and independently reviewed immutable binding, actual
bootstrap 40KiB-exact-driver/test versus 32KiB-others, 19-case/planned rules and
activation. SDK/build/G0, GUI/engine/NE/signing and all final gates remain.

## Local closure and source checkpoint disposition

R verified `sdk-driver-jobs-local-record.json`: the exact isolated target
exited 0, passed one `test_driver_jobs_parser_and_grant`, with zero failures,
errors/skips and passed fixture cleanup. Wall time was 0.253321625 seconds;
finite stdout was 188 bytes. The binding is consumed with local/guest budgets
both zero; its wrapper hash remains the frozen `22c92c0c...e02e6c80e` above.
All three accepted source hashes remain unchanged; `git diff --check` passes.
R accepts a source-only checkpoint of this exact package; no runtime is granted.

After that checkpoint, review one consolidated immutable hosted package with
actual bootstrap admitting 40,960 bytes only for exact build.py/test_build.py
paths and 32,768 for other files. It must bind one-driver-jobs-only to
sdk-driver-jobs-hosted19-v1, pass the closed 19 tests, then require planned /
driver-jobs, artifact null, candidate false, GUI/engine/NE not-run and removed
cleanup. driver_jobs must have at most eight entries with exact keys, closed
enums and strict bool platform fields. Existing deadlines/output/action limits
remain; no subsequent compile, app, signing, secrets or upload is authorized.
Any hosted allowance awaits the checkpoint and exact binding/workflow review.

## Consolidated immutable hosted package — accepted

R accepts the narrow bootstrap ceiling of 100 lines: the actual activation is
87 lines, adding nine explicit semantic/result checks without dropping prior
checks or changing actions, permissions, deadlines, output limits or source
count. Exact-path admission is 40,960 bytes for build.py and Tests/test_build.py;
all other bootstrap reads retain 32,768 bytes. Bootstrap AST/diff checks pass.

Source checkpoint: `3f0f0bda6e4a85aa0e80e4afb1f4957bdd292e9f`.
Binding `docs/planning/task-bindings/sdk-driver-jobs-runtime.json` SHA-256:
`7b6bf7bd534121e05acdec5059b6779d7614d0f8694f739c2428ae50457f0a10`.
Manifest: `9467a77b00bcc8699acb06b32e050c3629255100d6d8608004fb841762e18706`.
Actual activated workflow SHA-256:
`202efd2d4ea5929fc4b2aed60f599c5ccd471919b685fbd9e0cc7a9d8e8c1744`.
The separate immutable 78-line disabled source workflow SHA-256 is
`fd5cf19072fc03b2f10c294ab380ba61e93a32eae31fd6b4f3ff81f7437b0d4e`.
R verified immutable blob hashes, sizes and 100644 modes, the three accepted
source hashes, canonical manifest hash and exact inline/binding equality.
The archived native binding is consumed, both budgets zero; only its ephemeral
checkout copy is replaced after verified synthetic success. No old grant revives.

Grant exactly one new macos-15-arm64 hosted allowance, guest=1/local=0,
one-driver-jobs-only / sdk-driver-jobs-hosted19-v1: closed full19 must pass,
then the distinct driver-jobs phase must return planned with cleanup removed,
artifact null/predicate not-run, candidate false and GUI/engine/NE not-run.
Its 1..8 semantic jobs require exact keys, closed tool/target/SDK enums and
strict bool platform fields. The diagnostic appends only -driver-print-jobs;
no subsequent compile, app, signing, install, secrets or upload is allowed.

Root may commit this reviewed activation/binding/report with exact message
`Run one bounded native SDK driver plan 3f0f0bda6e4a85aa0e80e4afb1f4957bdd292e9f`,
verify that actual commit's identity and unchanged reviewed blobs, then push
once. Consume at dispatch; failure stops without retry. Archive the outcome at
zero and disable the workflow/clear inline binding afterward. Source/binding/
workflow changes invalidate this grant. R ran no tests, driver or hosted work.
SDK artifact equality and all G0/build/final acceptance gates remain open.
