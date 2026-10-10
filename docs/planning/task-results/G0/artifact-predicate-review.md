# Q-B artifact predicate source-only review

2026-10-10; R review of HEAD `39b09da` on
`codex/feature/self-hosted-byos-byoc`; working tree initially clean.

## Initial disposition — source-only scope accepted

Freeze one three-file instrumentation package below. No runner, compiler, fixture
execution, guest, binary retention, credential, workflow activation, commit or push
is granted by this review. Root schedules the frozen implementation, then returns
the exact diff for this R review before any separately bounded fixture invocation.
All old local/hosted/ar/av budgets remain zero; G0 and GUI/engine/NE gates remain open.

Reviewed inputs: repository start documents and execution-policy model/gate sections;
`native-build-contract.md`; `build.py` artifact/preflight/result plumbing;
`Tests/test_build.py` artifact fixture/matrix and finite suite output;
the previous review's final closure; `native-metadata-deadline-hosted-records.json`.
Only static reads ran; no behavior tests or compiler/guest commands ran.

## Evidence boundary

Hosted run `38031125723` passed synthetic18, metadata, version/help and compile/link
command 9 (exit 0), then reported failed/artifact, artifact null, cleanup removed.
The removed binary and coarse error leave its actual failed predicate unknown.
Instrumentation must not assign a retrospective cause or claim artifact qualification.

The current valid fixture has one zero-section segment, LC_MAIN and LC_BUILD_VERSION.
Its matrix exercises structural rejection but never enters the section loop, so it
does not qualify section-vm, section-file or zerofill handling. No independently
demonstrated Mach-O mistake is established by these source checks. Lack of section
coverage is actionable test scope, not proof of the hosted cause. No wider research
is necessary for this instrumentation-only package.

## Frozen implementation

Only these files may change, with narrow final line caps:

| File | Cap | Scope |
|---|---:|---|
| `docs/planning/poc/client-framework/native-lab/build.py` | 590 | Closed predicate and existing result plumbing only. |
| `docs/planning/poc/client-framework/native-lab/Tests/test_build.py` | 430 | Extend existing artifact fixture/matrix; keep all 18 method names. |
| `docs/planning/poc/client-framework/native-build-contract.md` | 210 | Document field, unchanged acceptance, synthetic section coverage and caps. |

These limits replace 556/386/197 current sizes only for this package; they are not
a general expansion allowance. Preserve every existing check, deadline, exception
code, cleanup/isolation rule and artifact return shape. No validator fix, helper,
new inspection phase, subprocess fixture, dependency, tool or binary dump belongs here.

Use `artifact(executable, plist, deadline=..., out=None)` with an optional existing
result mapping; allocate only a local empty mapping when absent. Calls without the
mapping retain their current digest/size return and Reject behavior. Add
`artifact_predicate: not-run` to result(). Set file-preflight before the compile-tail
regular-file check and chmod; pass the same mapping into artifact(). Inside artifact,
set each ID immediately before its existing check/read/unpack; set passed only after
plist-content succeeds. Retain the active ID through Reject/internal/cleanup paths.
If the existing oversized-result fallback is touched, preserve only this closed ID
alongside its existing finite fields; do not copy other rejected data into fallback.

The frozen vocabulary has 18 non-default IDs plus not-run (19 labels total):

```text
not-run, file-preflight, file-mode-bounds, header-length, header-fields,
command-header, command-length, build-length, build-fields, segment-length,
segment-bounds, segment-overlap, section-vm, section-file, entry-command,
entry-bounds, plist-read, plist-content, passed
```

file-mode-bounds covers artifact's bounded mode/read preflight; header-fields covers
header unpack/validation; command-header and command-length cover command framing;
build-length/build-fields and segment-length/segment-bounds cover their respective
unpacks/checks. segment-overlap precedes its conditional range check. section-vm
precedes section unpack/VM check; section-file precedes the existing non-zerofill
file-range check. entry-command covers LC_MAIN, entry-bounds the unchanged final
aggregate check. plist-read precedes regular/read/parse, plist-content the exact dict
check. A timeout or parse exception keeps the active ID and existing error semantics.
passed denotes validator acceptance; later inventory/cleanup can still fail.

The field contains no exception text, addresses, paths, raw headers/sections or
binary values. It remains inside the existing 16KiB JSON ceiling and does not change
the artifact acceptance contract or external-effects trust statement.

## Frozen meaningful fixture extension

Keep `test_artifact_valid_and_rejection_matrix` as the only modified test method.
Keep the zero-section valid case and all current malformed/header/CPU/entry/build/
segment/plist/link rejection cases. Associate existing malformed variants with their
actual first failing check and assert both Reject.code == artifact and that fixed ID.
Assert result() starts at not-run and a valid artifact ends at passed with the same
digest/size. Also cover plist-content separately from malformed plist-read.

Extend existing binary() in place with an optional sectioned shape, without a new
helper or test method. Use bounded thin arm64 bytes with correct command sizes,
LC_MAIN beyond the command table, nonoverlapping file-backed segments, two file-backed
sections and a zerofill section in a separate segment. This is synthetic real-shape
coverage, never compiler-produced evidence. Require the valid sectioned fixture to
pass; mutate a section beyond its VM boundary and a regular section beyond its
file-backed range, asserting section-vm and section-file respectively. A zerofill
section may have a non-file-backed offset while remaining VM-bounded; retain the
existing type exemptions exactly. If this cannot fit without compressing code or
changing checks, report the concrete shortfall before editing beyond the caps.

No new all-ID coverage mandate or branch-for-branch suite expansion is implied.
The important additions are stable failed IDs with unchanged rejection, valid
passed behavior, and previously absent section-boundary behavior.

## Next review and execution boundary

Root may dispatch C/Luna medium on this frozen package; R/Sol high reviews its exact
diff, final line/byte limits and closed-field mappings. A subsequent explicitly
bounded target may invoke only `BuildTests.test_artifact_valid_and_rejection_matrix`
with the trusted Python interpreter, isolated flags and no real subprocess/toolchain;
the exact command/target/hash must be frozen and approved before execution.
No full18 run or hosted/compiler grant follows automatically from this source review.
Any future runtime needs a separate immutable finite grant. The previous stop rule
after two material corrections/observations and all final acceptance gates persist.

## Exact diff review — mechanical correction required

Accept tests <=440 solely for the preserved rejection matrix and section coverage;
driver <=590 and contract <=210 remain. The first diff is not execution-ready:
fix each section pack's missing eighth integer, sectioned command count 3->4,
and b.binary->self.binary. Use file-backed payload offsets/addresses 480/496,
size 16, beyond the 464-byte command table. Correct expected IDs: truncated40
header-fields; length64 segment-length; initprot-at92 entry-bounds; nsects-at96
segment-bounds. Require valid digest as well as size/passed; retain no-out compatibility.
Set file-mode-bounds before the initial checkpoint. Overflow fallback must whitelist
the closed vocabulary before copying the ID; preserve timeout/internal/cleanup semantics
explicitly in the contract. No validation condition changes or cause attribution follow.
No behavior target is granted until corrected source identity is independently reviewed.

## Corrected source acceptance and one pure fixture grant

Accept final 584/443/209 lines; tests <=445 replaces <=440 only for requested coverage.
SHA256 driver `e8e4e8b101de974ce1878162a9ebec8335ddd4b1f9a977b52c2682522d903b32`;
tests `bb4896223fe5f12caf0f91cac1016b17e51530e8247d7f4c28d8659787c8fa6c`;
contract `ba550bc774ddc97ab43957f5f7c73b9d1c5a84f359b5ba0f4c77af9d5c47b470`.
Grant local-artifact-predicate-v1 once, <=10s, fixed `/usr/bin/python3 -I -B -c` wrapper
supplied verbatim to root: rehash these inputs, runpy custom name, only the artifact method,
TestResult/owned cleanup, finite <=1KiB JSON/no traceback. Failure stops; attempt consumes 1->0.
R ran only static rehash/diff checks; full18/hosted/compiler/guest/runtime budgets remain zero.

## Local observation closure and one new hosted preparation direction

Accept [local evidence](local-artifact-predicate-record.json): exactly the reviewed method
passed, one test, zero failures/errors/skips, fixture cleanup passed, exit 0, 198 stdout
bytes, 0.227057 seconds. Its exact wrapper binding is consumed/local_remaining 0 and
guest_remaining 0. Independent static rehash confirms all three accepted hashes unchanged.
This qualifies the artifact fixtures and ID assertions only, not full18 or a real artifact.

Under the current continued-G0 request and existing bounded hosted authorization,
accept preparation of `artifact-predicate-hosted18-v1`: one new fresh macos-15-arm64
hosted18 -> conditional compile observation. Stable closed IDs and now-passing section
coverage make a future rejection actionable; unchanged acceptance is deliberate.
This is a materially instrumented source observation, not the removed binary's retry
or any consumed budget's reset. Its hosted allowance may be 1, local allowance remains 0;
the archival guest_remaining counter does not authorize another VM/diagnostic guest.

Before push, freeze a source checkpoint, literal checkout/feature SHA, contract digest,
full five-file manifest, reviewed dormant/activated workflow identities, separate archive/
inline binding, action pins, unique activation predicate and actual activation commit SHA.
Use only the existing immutable hosted bootstrap, with literal identity/grant updates;
retain verification before import and consumed-original-binding substitution boundaries.
Independent R must review that consolidated exact package before activation/push.
Preparation is accepted here; no unidentified executable workflow or push is authorized.

Require exact passed18/zero failures/errors/skips/empty failure evidence and passed cleanup
before one compile in that same job. Keep metadata14/compile120/whole180, synthetic60/
driver185 subprocess caps, ten-minute job, matching baseline, read-only/no-secret trust
scope and <=16KiB records. No extra helper/tool, binary dump/retention, app/GUI/engine/NE.
Any failure/timeout stops without retry; after the one observation disable the gate,
archive consumption/remaining 0 and preserve finite evidence, including the active ID.
The previous automatic-stop rule still prohibits arbitrary follow-on qualification;
this named preparation needs the separate final immutable review and grants no successor.
R executed no behavior here. Historical failure cause and G0/full acceptance stay unknown.
