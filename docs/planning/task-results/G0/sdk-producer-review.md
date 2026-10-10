# Q-B SDK producer diagnostic — bounded R decision

2026-10-10; review only. Exactly two tagged official source opens, followed by
in-page lookup of the same symbols; no other source/framework research,
candidate import, compiler, linker, test, guest or credential access.

## Supported fact and limits

Accept the corrected [fact report](sdk-producer-facts.md): current input is the
qualified logical MacOSX15.5.sdk, and both semantic/logical finite observations
record artifact SDK 15.0.0 with SDK-only mismatch. Logical spelling did not fix it.

[Tagged Options.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftOptions/Options.swift#L282)
defines hidden `-driver-print-jobs` as a flag. The same tagged
[Driver.run](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Driver/Driver.swift#L1506-L1512)
prints each planned job's executor description and returns before the subsequent
job-execution path. This supports observing planned jobs without executing those
printed jobs in that implementation. It does not establish the installed Apple
binary's driver implementation, executed downstream argv, ld identity or cause.
Job planning/description can have trusted vendor effects; this is not a process
or filesystem denial guarantee. Hidden-option presence in ordinary help is not
an accepted prerequisite; do not add a new help-hidden command implicitly.

Correct the fact report's proposed retention: raw argument arrays are too broad.
Only the semantic observations below may survive capture; raw descriptions,
unknown values, paths and source bodies must never be archived or emitted.

## Accepted source-preparation proposal — no runtime grant

Use only the existing selected swiftc fixed compile argv, with the single
additional `-driver-print-jobs` flag. Prepare a separately bound `driver-jobs`
phase, not a diagnostic followed by actual compilation. Keep canonical SDK
qualification, logical operand, source/identity/environment verification and
all current compile/artifact checks for the normal compile phase unchanged.
Require a distinct future `one-driver-jobs-only` grant/qualification; the old
compile grant or a caller argv/mode must not select this path.

Reuse existing owned staging, capture/drain/overflow/cancel/reap/deadline,
inventory and cleanup. Keep 64KiB per stream, 120-second command and 180-second
whole limits. Parse stdout only in memory after success; never execute printed
commands or read response files/file lists. No helper tool or added inspection.
Retain at most eight planned jobs, <=512 tokens per job, <=4096 bytes per token;
strict bounded line/quote tokenization. Malformed/unknown format, response-file
reference, duplicate/conflicting observed option or excess bounds fails closed
with a fixed error and null semantic observation, never the rejected text.

Freeze semantic output only: job tool enum `frontend|clang|ld|other`; target
enum `expected|other|absent`; SDK operand enum
`qualified-logical|qualified-canonical|other|absent`; and explicit platform-version
option presence boolean. Recognize only exact target/SDK flags and direct or
explicitly frozen wrapped platform-option forms; token-aware matching, no
substring inference. Compare operands with already-qualified expected values,
emit neither operand text nor arbitrary versions. Unknown tools use `other`;
unknown relevant syntax refuses rather than claiming an absent option.

Finite result remains <=16KiB with phase=driver-jobs and a distinct planned
result, never compiled. Artifact/null and predicate/not-run stay truthful;
candidate false, GUI/engine/NE not-run. Semantic success proves only planned
forwarding; it cannot justify forcing platform metadata or weakening SDK 15.5.

Root next freezes the exact three-file source plan: driver phase/parser,
same test file's meaningful quoted/forwarding/malformed/conflict/bounds/redaction
fixtures, and contract. Preserve normal 18-case compile gate; explicitly budget
any new diagnostic cases and line/byte-cap changes before editing, without
compressing code or silently widening existing caps. R reviews exact diff/hashes.
No source checkpoint, local test, compile, guest, push or activation is granted
here. A later diagnostic needs its own immutable package, actual activation,
once-only target grant, synthetic gate and fixed bounds; failure stops.
All old budgets remain zero, workflows disabled, and full build/G0,
GUI/engine/NE/signing/device, candidate disposition, G0–G6/main gates remain.

## Concrete root source plan — accepted with closed rules

Allow only `native-lab/build.py`, `native-lab/Tests/test_build.py` and
`native-build-contract.md` under the existing client-framework directory.
Caps: driver 680 lines/32,768 bytes; tests 550 lines/30,720 bytes; contract
245 lines/32,768 bytes. Root estimates +75/+55/+20 lines. Raise only FILES'
test-source byte cap from 26,624 to 30,720; no other admission bound changes.
Stop before any cap excess; no unrelated compression. Explicitly allow the
single standard-library `import shlex` required by the plan; no external
dependency/import, helper file or plugin. One parser function is in the driver.

Freeze `driver_jobs(text, logical_sdk, canonical_sdk)`: strings only, bounded strict UTF-8
<=64KiB; reject NUL/encoding/quote errors with fixed `plan-format`. Ignore blank
lines, require 1..8 nonempty jobs; use shlex.split(posix=True, comments=False)
per line; <=512 tokens/job, <=4096 UTF-8 bytes/token. Reject any response-file
`@` token or exact `-filelist` option without reading a referenced file.
Never execute or preserve token arrays. All unrecognized irrelevant arguments
are transient and ignored; malformed relevant syntax refuses to null observation.

Output per-job exact keys: tool, target, sdk, platform_version_present. Tool is
`frontend` for basename swift-frontend, `clang`, `ld`, otherwise `other`;
basename is classification only, not executable identity. Target compares fixed
arm64-apple-macosx15.0; SDK compares already-qualified logical/canonical strings.
Keep only the previously frozen enums and boolean, no operand/version/path text.
Recognize direct `-target`, `--target`, `--target=VALUE`, `-sdk`, `-isysroot`,
`-syslibroot`; duplicate target or SDK category refuses even if values agree.
Missing/empty or flag-looking operand refuses; joined target value cannot be empty.
Unrecognized joined/prefix spelling of these relevant options refuses rather
than being ignored or mistaken for absent. No substring classification.

Only three platform forms are admitted, each at most once across a job:
direct `-platform_version` followed by three nonempty non-flag operands;
one `-Wl,-platform_version,platform,min,sdk` token with exactly five CSV parts;
or exactly eight tokens `-Xlinker -platform_version -Xlinker platform -Xlinker
min -Xlinker sdk`. Values stay transient. Wrapped target/SDK options, malformed
platform forms or other wrappers containing a relevant option refuse. Determine
relevance by complete tokens/CSV components, never substring search. Irrelevant
wrappers stay transient; do not let a wrapped relevant flag become a direct one.

Phase selects only exact grant=`one-driver-jobs-only` plus
qualification=`sdk-driver-jobs-hosted19-v1`. Reject partial/mismatched diagnostic
pairs before any command/root creation; never fall through to compile. Normal `one-compile-only`
behavior stays intact. Share existing compile argv; diagnostic appends only
`-driver-print-jobs`, uses existing capture 120s/whole 180s and unchanged identity,
staging/adoption/inventory/cleanup. After parsed output/inventory, return
planned/driver-jobs before artifact checking; artifact null/predicate not-run,
candidate false, GUI/engine/NE not-run. No subsequent compile. `driver_jobs` field
defaults null; parser/overflow failures retain finite errors/null, never raw data.

Add one pure-file `test_driver_jobs_parser_and_grant`, covering quoted tokens, direct forwarding,
all three platform forms, other tool/operand enums, malformed/duplicate/conflicting
relevant options, wrapped relevant refusal, response/file lists, byte/line/token
bounds and redaction, plus malformed grant/qualification no-command/no-root
cases using existing manifest fixtures. Add its name to the closed failed-case
set; preserve all old 18 names =>19. A phase-selection helper is allowed only
within the driver if needed for the budget; no helper file or further imports.
Future bootstrap
expected19/planned changes belong only to a separately reviewed immutable activation.
Root may dispatch the accepted I/Sol medium source card now; only the three paths
above are implementation writes. R then reviews exact diff/hashes/limits; local
parser execution requires its own bounded grant. No code/test/compiler/guest or
new runtime grant is performed or issued by this source-contract disposition.

## Explicit source-budget amendment — accepted

Root reports I's readable draft reached 680 lines/33,620 driver bytes, exceeding
the frozen 32,768-byte cap by 852; I stopped before execution. The test estimate
also exceeded its proposed byte cap. Freeze both bounds together once: driver
700 lines/40,960 bytes, tests 550 lines/32,768 bytes, contract 245 lines/32,768.
R observed driver/contract baseline and a saved test draft (535 lines/30,076
bytes), not a fully restored tree; leave the related draft intact for review.

Set FILES driver entry to 40,960 and test entry to 32,768, preserving every
other bound. No helper file, compression, dropped
case, action, input or semantic scope change. I may resume the same draft/context
within the same three allowed source paths; stop before any new cap excess.
Complete all three sources before one exact diff/hash R review. No incremental
test or runtime grant is added by either source-budget correction.

The future immutable workflow bootstrap must use max 40,960 only when
`name == base + 'build.py'`; all other verified files retain max 32,768.
That exact bound adjustment needs source-checkpoint/activation review with
the eventual complete binding. It adds no command and does not change manifest
authentication, exact hashes, modes, file counts or action pins. No workflow
activation, test, compiler, guest or renewed runtime allowance is granted now.
