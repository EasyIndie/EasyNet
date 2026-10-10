# Q-B SDK semantic source package — frozen R proposal

2026-10-10; source-only preparation under continued G0 authorization and the
mixed routing rule: root implements this short frozen change; R reviews it.
No I implementation agent, runtime, compiler, helper, guest, credentials,
commit, push or workflow activation is authorized by this document.

## Baseline and disposition

Feature branch: `codex/feature/self-hosted-byos-byoc`;
reviewed clean HEAD: `0afb416d317de75f0ec91b009cc6aac878532e1b`.
Read AGENTS, README, CONTRIBUTING, planning entry/execution policy, relevant
development practices, the exact 85-line [SDK review](artifact-sdk-review.md),
native build contract, driver artifact/result/emit and existing artifact matrix.
No further framework or producer research belongs to this package.

Accepted prior observation: hosted run `38033726243` passed all 18 synthetic
cases and compile/link exited 0; only SDK equality failed among the four build
checks. The actual SDK number remains unknown. This package adds truthful
bounded semantic evidence; it does not change the expected SDK or infer cause.
All previous local/hosted budgets remain zero and workflows remain disabled.

## Exact three-file root implementation plan

Let `P=docs/planning/poc/client-framework/native-lab`.

| Allowed file | Frozen responsibility | Final line cap |
|---|---|---:|
| `P/build.py` | Add one semantic field in artifact/result/overflow handling. | 615 |
| `P/Tests/test_build.py` | Extend the same artifact matrix method only. | 490 |
| `docs/planning/poc/client-framework/native-build-contract.md` | State this sole semantic exception and unchanged gates. | 225 |

Current line counts are 591, 455 and 212 respectively. Report a shortfall before
exceeding a cap; do not compress unrelated code or add helpers to evade it.
R accepts the root's pre-edit estimate of approximately 30 additional test
lines: the 490-line cap preserves all five SDK cases, stale reset and strict
overflow refusal coverage without compressed assertions. No behavior scope,
new helper, test method, driver/contract cap or execution grant is added.
The R report is this document only, capped at 260 lines for closure review. All other files,
workflow bodies/bindings, compiler argv, source inputs and phases stay outside
the implementation scope.

## Frozen field semantics

`artifact_sdk_version` is null by default in `result()` and reset to null at
`artifact()` entry, including caller-supplied mappings reused across calls.
It remains null if validation stops before the existing LC_BUILD_VERSION
unpack. Immediately after that unpack, derive `major = sdk >> 16`,
`minor = (sdk >> 8) & 255` and `patch = sdk & 255` from the existing unsigned
32-bit SDK value. The full high 16 bits are used for major, without masking.

If major is at most 255, store exactly the object
`{"major": major, "minor": minor, "patch": patch}`; every value is an integer
in 0..255. If major is larger, leave null. No clamping, wrapping, truncation,
string version, encoded integer/hex, other header value, address, path, section
content, exception or binary dump may be emitted by this exception.

Preserve the original SDK equality, the original platform/minimum/sdk/length
mismatch map, every artifact check and fixed refusal. An out-of-range major
still fails the unchanged SDK equality at `build-fields`, with error
`artifact`; the field remains null. Existing digest/size return semantics,
artifact=null on failed build, cleanup and finite result limits remain intact.

For the existing >16KiB `emit()` fallback, retain this field only when its
value has exactly the key set `major`, `minor`, `patch`, each value has
`type(value) is int` (bool excluded), and each is in 0..255. Otherwise the
fresh `result()` default stays null. Copy only these three semantic values;
retain the existing finite overflow error and mismatch/predicate validation.
The exception applies solely to this field; the other raw-header bans persist.

## Same-method fixture acceptance

Extend only `BuildTests.test_artifact_valid_and_rejection_matrix`; keep the
same 18 test method names and full-suite runner behavior. Use its existing
owned pure-file binary/plist fixtures, without subprocesses or real compiler.

| SDK semantic fixture | Expected field | Original outcome |
|---|---|---|
| 15.5.0 | `{major:15, minor:5, patch:0}` | Valid artifact; SDK mismatch false. |
| 0.0.0 | `{major:0, minor:0, patch:0}` | Artifact refusal; SDK mismatch true. |
| 15.5.1 | `{major:15, minor:5, patch:1}` | Artifact refusal; SDK mismatch true. |
| 255.255.255 | `{major:255, minor:255, patch:255}` | Artifact refusal; SDK mismatch true. |
| 256.0.0 | null | Artifact refusal; no major truncation; SDK mismatch true. |

For each refusal assert `artifact` and `build-fields`, with only SDK true in
the existing mismatch map; assert the exact semantic field. Keep the current
platform/minimum/length refusal matrix. Reuse the output mapping for a later
pre-unpack malformed case and assert null to prove stale semantic data clears.
Check overflow output preserves a valid semantic object and rejects malformed
shape, bool, missing/extra keys, negative and >255 values to null, while staying
finite. Do these checks inside the same method, without a helper/new test name.

## Review and execution boundary

Root first produces the three-file diff and exact SHA-256 hashes; R then
reviews field shape, decoding, unchanged checks/argv, fallback, fixtures,
line caps and the same 18 names. This proposal is not an execution grant.

After that review, root may separately grant one isolated invocation targeting
only `BuildTests.test_artifact_valid_and_rejection_matrix`, using the reviewed
trusted Python interpreter with `-I -B` and file-path import. Freeze its exact
command and source hashes before that grant. Target <=10 seconds total and
<=1KiB finite output, exit 0, one test, no failures/errors/skips, and owned
fixture cleanup. Failures stop; no retry, full18 run or compiler follows from
the isolated grant. Source-only diff/line/hash checks are permitted now.

A future actual hosted observation requires separately reviewed immutable
feature/contract/source-manifest/workflow/action/binding identity and actual
activation under the new continued G0 authorization. Its once-only target
grant must run the revised full18 gate before conditional compile and retain
existing fixed limits and failure stop. Do not restore old budgets or
automatically activate a workflow, compile, probe or retain a binary.

Semantic output alone neither establishes producer cause nor changes SDK
acceptance. GUI/engine/NE/signing/device qualifications, A/B final ADR
dispositions, all G0–G6 acceptance and final main merge authorization remain.

Status: frozen source proposal; implementation and exact review pending;
isolated test and new hosted observation remain ungranted.

## Exact root source review and isolated successor grant

R accepts the root's three-file diff. Default/entry null, full major decoding,
bounded named object, unchanged equality/map/argv and strict overflow copy
match the proposal. Fixtures retain the five SDK cases, seeded stale-output
reset and eight valid/invalid overflow objects in the same artifact method.
AST comparison confirms the same 18 test names; line caps and diff check pass.
This review ran only source parsing, hashing and mechanical checks; no candidate
import, test, compiler, guest, framework research or credentials were used.

Reviewed exact SHA-256 and line counts:

| File | Lines | SHA-256 |
|---|---:|---|
| `P/build.py` | 599 | `8f230e9a9d7f45f42a16e4be57f42a685c7eee1d7f7f06e3aa3651c605f6cc1f` |
| `P/Tests/test_build.py` | 477 | `cbc114e5e526881ddac1d60c11684998998a8c2ef8a31b2221e09533f9d4757a` |
| `native-build-contract.md` | 218 | `9c3f3a37366927008b23dcfcff6ecccbeb39d811261de768857ca38ababbb13c` |

Freeze `local-sdk-semantic-v1`: derive argv from the consumed
`docs/planning/task-bindings/local-artifact-build-map-v1.json`, preserving
its reviewed SHA-256 `d767420034fc36ff5e2706189601d8dfe0aa4f77f574ff0046e8ac086afc25a1`;
`[/usr/bin/python3, -I, -B, -c]`. In argv[4], replace only the old target string
with `local-sdk-semantic-v1` and the three old expected hashes with the reviewed
hashes above. The unchanged method is `test_artifact_valid_and_rejection_matrix`;
the run_name remains `artifact_predicate_target`. R computed the exact resulting
1964-byte UTF-8 wrapper SHA-256:
`c8ce55ff477810774db79199d3fb972804c2ab16a1a0b64c176fbe7386f93875`.

Root may materialize that new frozen binding and execute exactly once under
the current successor authorization: cwd `/Users/joker/Documents/EasyNet`,
deadline_seconds=10, max_output_bytes=1024, local_remaining=1,
guest_remaining=0. Hash verification precedes candidate import; only the
artifact method executes, using owned pure-file fixtures and no subprocesses.
Expected finite output: target matches, tests=1, passed, failures/errors/skipped=0,
fixture_cleanup=passed, exit 0. Consume the new allowance at dispatch; failure
stops with no automatic retry. Every old grant remains zero/consumed.

Local closure: [record](sdk-semantic-local-record.json) reports one artifact
test passed, exit 0, failures/errors/skips=0, cleanup passed, 192 stdout bytes
and 0.233088417 seconds. The new binding is consumed/local_remaining=0;
this closes only the isolated grant. No further test or runtime grant follows.
All GUI/engine/NE/signing/device and G0–G6/main gates remain intact.

## Hosted successor preparation conditions — not a grant

Reuse the disabled 78-line native workflow/bootstrap and archived
`artifact-build-map-runtime.json` schema. Freeze one new semantic qualification,
checkpoint feature=checkout SHA, contract digest, five exact regular 0644 source
entries with sizes/hashes, canonical manifest digest, disabled workflow digest,
checkout action SHA, Python trust and consumed native-binding digest. Review
those together with the actual one-shot activation body/identity after checkpoint;
do not grant or review activation from branch tips or placeholders.

One macos-15-arm64 target only, no matrix/install/secrets: revised full18 exact
passed record and cleanup first, then one conditional compile under existing
10-minute job/60-second suite/185-second driver wrappers and driver's
180-second whole/120-second compile/14-second metadata bounds. Preserve the
bootstrap SHA/manifest verification before candidate import and ephemeral
consumed-binding replacement only. No new command, inspection phase or binary
retention; the sole new observed datum is the bounded semantic SDK object.
New allowance, if separately accepted, is local=0/guest=1, consumed at dispatch;
failure stops, then workflow disabled/inline cleared. Old grants stay zero.

Source-cap correction accepted: 25,718 test bytes exceeded the original
24,576-byte cap, missed by R's initial review. Root accepted only a 26,624-byte
same-file cap and one contract sentence; R verified exactly those two changes.
Final driver SHA `aa7cefb0e8a12179e54cacfc89f806f0285af7cf9358b450b3e16ff823d3150a` (599 lines);
contract SHA `7f123df03b3638da814efe9a2405c11d5fceefd8b72a1a606dc027f60f577822` (219 lines).
Test/hash unchanged; historical local evidence binds the original hashes.
Root may make the source-only checkpoint, without a cap-only retest or runtime.

## Consolidated immutable hosted package — accepted once

R accepts checkpoint `ffcb6cfb1f080639ff2756fdda0f258aa2dc9a7a` and
`docs/planning/task-bindings/sdk-semantic-runtime.json`, SHA-256
`47f71ad7b26bdb4bc743d959ed3747a2ef0c1af32035471285e06bcf7ef19938`.
Canonical source manifest SHA-256:
`13f462d81cf486864f68a4de6ed787e0b4bfbfd289313e1f3aea416f592e1150`.
All five immutable source blobs match their exact regular 0644 entries and
size bounds, including test 25,718<=26,624 and driver 28,730<=32,768 bytes.
Contract and consumed native-binding digests match the immutable tree;
the prior native binding remains consumed with both budgets zero.

The checked-out disabled 78-line workflow digest is
`4d76087a9a50c713a712632e50be660e23793b086a61a33cfcd0a2813c1af0a7`.
The actual reviewed activated 78-line workflow digest is separately
`ff6643f7bf6816dd05a0b9fdf18e5b6ad181cc048c6564e734a2aa612ac9b976`.
Its inline binding equals the new binding; its complete bootstrap/run body
equals the disabled immutable workflow. Only names, exact push-message gate,
immutable checkout ref and frozen inline binding change. The pinned checkout
action remains `3d3c42e5aac5ba805825da76410c181273ba90b1` with credentials,
submodules and LFS disabled; permissions remain contents:read, without secrets.

Root may commit this review with that exact activation using the sole message
`Run one native SDK semantic observation ffcb6cfb1f080639ff2756fdda0f258aa2dc9a7a`
and push once on the feature branch. Before dispatch, mechanically record the
resulting full activation SHA and verify the reviewed workflow/binding hashes,
message and immutable checkout ref; do not modify them after this review.
This accepts the user-authorized once-only `sdk-semantic-hosted18-v1` target
macos-15-arm64, local=0/guest=1: revised full18 exact pass/cleanup precedes
one conditional compile under the existing fixed bounds. Workflow dispatch
cannot activate the push-only gate. No candidate executable, helper, GUI,
engine, NE, signing material or binary retention is permitted.

Consume the guest allowance at dispatch, reflected in closure after the
observation; no second attempt or automatic budget restoration. Preserve only
bounded synthetic/compile JSON and relevant activation/run identity, then
disable the workflow and clear the inline binding. Any failure stops even
if it follows compile exit 0 or reveals a semantic SDK value. Such a value
neither proves producer cause nor changes SDK equality or artifact acceptance.

Review checks: immutable Git blobs, hashes/sizes/modes, manifest, binding/inline
equality, old budget closure, exact workflow diff and bootstrap AST; all pass.
R executed no candidate import, tests, compiler, guest or external research.
All GUI/engine/NE/signing/device, candidate disposition, G0–G6/main gates remain.

## Hosted closure and next source disposition

Accept [finite record](sdk-semantic-hosted-records.json), run `38044984525`,
activation `cf22191bac43e8cc5a9ee37810adb188b7c1d683`: full18 passed;
commands 0–9 exited 0, drained/FD-closed/reaped; artifact rejected only SDK,
now truthfully 15.0.0. Qualified xcrun remained 15.5; artifact null, cleanup
removed, candidate false and GUI/engine/NE not-run. Archive is consumed/zero;
local workflow false/inline empty is accepted, pending root closure commit/push.

Accept a bounded next source proposal: use the already-validated exact logical
`SDK` constant (MacOSX15.5.sdk) as identity's returned compile SDK path, rather
than canonical `sdk.resolve()`. Preserve strict canonical equality/containment,
SDK 15.5 query and artifact equality, compiler/other flags and every check.
The cited linker source permits path-sensitive SDK inference; 15.0.0 makes
the differential actionable, without proving cause or promising 15.5 output.
Do not force platform metadata, read SDK settings or add probes.
Freeze only driver<=615, tests<=490/26KiB, contract<=225: one return-path
change; same identity test also covers versioned alias→unversioned directory,
asserting logical path retained, canonical target equal and escape refused;
same18 names; contract states the qualified logical SDK argv exception.
Root may prepare source only, then R reviews exact diff/hashes. No local test
or hosted budget is granted now. Any later differential compile needs a fresh
immutable package/full18 gate and one separate grant; failure stops without
weakening acceptance. Full G0/build qualification and all final gates stay open.
