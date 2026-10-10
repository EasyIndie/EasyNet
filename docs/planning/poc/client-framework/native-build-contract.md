# Q-B native source and compile qualification contract v1 — proposed

2026-10-10; independent R preparation accepted by root for source preparation only,
toward G0-06.2d, not framework/engine selection or runtime permission.
Scope: one small native SwiftUI source/build package, then one separately granted hosted
compile-only job. No compiler, engine, GUI, download, signing or guest ran for this document.
Historical ar/av workflows remain disabled with zero budget; this is independent qualification.

## Evidence and deliberate build choice

[Actual metadata record](../../task-results/G0/hosted-metadata-record.json) observed
macOS 15.7.9 / 24G830, arm64, ImageOS `macos15`, ImageVersion `20260907.0337.1`,
Xcode 16.4 / 16F6 and SDK 15.5. Compiler path/version/hash and build remain unqualified.
The [frozen vendor image description](https://github.com/actions/runner-images/blob/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md)
lists `/Applications/Xcode_16.4.app` and its macOS 15.5 SDK; a fresh job must verify them.
`macos-15` cannot pin this image. Reject changed baseline values; no OS/toolchain fallback.

Use direct `swiftc` compilation and a handwritten `.app` bundle: no generated Xcode
project/scheme, SwiftPM manifest, package resolution, CocoaPods, plugins or custom build hooks.
This reduces unknown build inputs while retaining Apple's actual
[SwiftUI App entry and scenes](https://developer.apple.com/documentation/swiftui/app).
SDK 15.5 and target `arm64-apple-macosx15.0` are experiment choices; they do not establish
minimum product OS support. Use Swift language mode 6; compile errors are evidence, not
permission to silently change language/toolchain. Keep Go services and Bash consumers intact.

## Freeze-ready source preparation package

Let `P=docs/planning/poc/client-framework/native-lab`. One I implementation card writes:

| File | Exact responsibility |
|---|---|
| `P/Host.swift` | One `@main` SwiftUI App, `WindowGroup`, regular foreground window, visible Connect/Cancel/Stop/Restart and state/error/generation labels. |
| `P/Info.plist` | Fixed `APPL`, executable `EasyNetNativeLab`, identifier `com.example.easynet.native-lab`, experiment version and `LSMinimumSystemVersion=15.0`; no entitlements or background-agent setting. |
| `P/build.py` | Standard-library-only bounded launcher, provenance checks, owned staging/bundle assembly, fixed compiler argv, output inspection and finite JSON result. |
| `P/Tests/test_build.py` | Synthetic identity/input rejection, timeout/flood/reaping, malformed output and artifact validation; no real compiler/GUI or tests that merely repeat compiler flags. |
| `.github/workflows/g0-client-native-build.yml` | Inert manual workflow with job `if: false`, no secrets, fixed reviewed commands/action pins; activation excluded from preparation. |

Source review records all five files' exact paths/types/modes/byte limits/SHA-256 as a
version-1 source manifest in the future binding; no separate generator or fixture stage.
Budget: Host <=60 lines, plist <=30, driver <=590, tests <=445, workflow <=75.
Root accepts the independent R's consolidated correction estimate (+100/+80), solely
for ownership/cancel/drain, failure cleanup, bounded hashing and valid artifact cases.
Root accepts +20 test/+15 workflow lines for finite buffered suite output and immutable
verification-before-import bootstrap; no new helper or experiment stage is added.
Post-failure source-only repair adds one mocked signal-error/reap case (+15 test lines).
The resulting suite has 18 cases, unexecuted; old 17-case binding is consumed and cannot
authorize current source. No renewed local/guest attempt is granted by this amendment.
Root accepts the bounded [capture successor repair](../../task-results/G0/native-capture-successor-review.md)
for source preparation: EOF/wait before KILL, finite failure fields, logical swiftc invocation,
and a fixture-proven negative identity-refusal case. Compiler invocation still needs a
passing corrected suite and new exact binding; all consumed grants remain zero.
The no-fork flood fixture may verify an explicit identity/absent cleanup refusal only
after observed overflow plus EOF/direct reap/FD closure; it remains a refusal, not
positive group containment. This small frozen negative-case correction adds six lines.
Report a concrete shortfall before exceeding these limits; do not compress code to fit.

The first Host is a real window implementation, with honest `idle / runtime unqualified`
presentation and disabled lifecycle controls; it must never simulate ready or nonce success.
No `#Preview`, macros, external imports, Process, network, preferences, keychain or filesystem
effects in Host. Only SwiftUI/AppKit/Foundation imports are eligible. Source review verifies
these exclusions. The same Host path later binds the real lifecycle; its compile result
alone cannot verify the visible window or any lifecycle behavior.
This narrows the initial source allocation proposed by [native preparation](native-lifecycle-preparation.md),
without dropping its eventual `P/Lifecycle.swift` serialized controller and `P/Guardian.swift`
separate ownership process, or their tests. Those files belong to the later runtime package.

Source preparation needs accepted contract and the feature branch, not a runtime budget.
It may create/review these five files and run only isolated synthetic tests:
`python3 -I -B P/Tests/test_build.py` (expand P literally; fixed trusted interpreter).
Expect all synthetic cases pass and `git diff --check` exit 0. Review that no test invokes
the real toolchain; fake subprocesses are bounded owned test fixtures only. No CI activation,
commit/push, compiler invocation, dependency acquisition or signing belongs to this card.

## Immutable inputs and one future hosted job

After source review, freeze a full feature commit SHA, this contract digest, source manifest
digest, reviewed workflow digest, and every action SHA in one execution binding. One manual
job on `macos-15`, no matrix, `permissions: contents: read`, no environment/secrets, ten-minute
job limit. Checkout that exact SHA with persisted credentials/submodules/LFS disabled;
reject any checkout SHA or manifest mismatch before importing/running candidate code.
Branch tips, PR code, caller-supplied argv, ref expressions and arbitrary workflow inputs
cannot choose code or tool flags. Freeze the trusted Python launcher path/version and origin
using the accepted hosted baseline route; no setup/install step or dependency cache.
Checkout and optional reviewed result upload are platform network phases; candidate build
requests no network. Only finite JSON evidence is uploaded, never the app, cache or raw logs.

Allocate a fresh `0700 /private/tmp/easynet-qb-build-<random>`; record canonical root/owner/inode
and run token; reject symlink components, existing root, or ownership mismatch. Owned tree:
`src/`, `tmp/`, `module-cache/`, `app/EasyNetNativeLab.app/Contents/MacOS/`, `result/`.
Copy only manifest-verified regular source/plist files without link following, then rehash.
Sources/plist/results `0600`; app executable `0700`; directory parents `0700`.
All requested writes, compiler intermediates and cache go here. No shared CI cache,
DerivedData, product paths, installation, launch registration or persistent settings writes.

Child environment is constructed, not inherited: `PATH=/usr/bin:/bin`, `LC_ALL=C`,
`DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer`, `TMPDIR=<root>/tmp`.
Preserve HOME and CODEX_HOME unchanged only if present; allow no other variables.
Exclude credentials, SSH agent, proxies, DYLD injection, toolchain/Git/Python overrides;
no shell invocation, startup scripts, env persistence or home-path/settings inspection.
Driver cwd is the owned root; every subprocess takes an argument array.

Trust exception: this compile-only job trusts the fresh vendor image's selected compiler,
frontend/linker/system SDK and their ordinary vendor effects while compiling reviewed inert
source. It does not claim kernel denial of external effects or full toolchain-library hashes.
Planned writes are owned; actual external reads/writes/network remain `trusted-vendor-not-denied`.
No personal signing material exists in the job. This exception stops before any generated
executable, engine, guardian, probe or GUI is run; their full denial/decoy/inheritance gates
are mandatory. It cannot be copied into Q-B runtime or Q-NE as isolation evidence.

## Fixed build and bounded verification

Allowed preflight argv only: `/usr/bin/sw_vers -productVersion`, `-buildVersion`;
`/usr/bin/uname -m`; selected developer `usr/bin/xcodebuild -version`;
`/usr/bin/xcrun --toolchain XcodeDefault --find swiftc`;
`/usr/bin/xcrun --sdk macosx --show-sdk-path` and `--show-sdk-version`;
resolved `swiftc --version` and `swiftc -help`. No xcode-select mutation or tool discovery scan.
Require the exact observed baseline above. The compiler locator must return
`<DEVELOPER_DIR>/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc`; canonical compiler/SDK
must stay inside the selected Xcode tree, rejecting escape/unknown paths. Record entry
binary SHA-256, complete
bounded compiler version, SDK path and version. Swift version/hash are first observations
under the explicitly trusted Xcode build, not guessed preconditions; successors freeze them.
Missing required flags, invalid identity or unreadable entry fails before compilation.
Accept a selected SDK alias only when its existing canonical target is the exact frozen
15.5 SDK directory inside selected Xcode. Stream compiler hashing in bounded chunks,
maximum 512MiB, checking the whole deadline; record actual size as first observation.

One compile/link argv, with absolute resolved paths and no extra inputs:

```text
<swiftc> -parse-as-library -emit-executable -swift-version 6 -Onone
  -target arm64-apple-macosx15.0 -sdk <sdk>
  -module-cache-path <root>/module-cache -module-name EasyNetNativeLab
  -framework SwiftUI -framework AppKit -framework Foundation
  <root>/src/Host.swift -o <root>/app/EasyNetNativeLab.app/Contents/MacOS/EasyNetNativeLab
```

[Tagged Swift options](https://github.com/swiftlang/swift/blob/swift-6.1.2-RELEASE/include/swift/Option/Options.td)
support the library parse mode, executable emission, language/target/SDK, output and module
cache flags. This primary source supports the proposal, not identity of Apple's binary.
The selected compiler's bounded help and actual result verify compatibility. Module-cache
and TMPDIR relocation are requested controls, not proof of all vendor effect locations.
No explicit codesign, keychain, certificate, notarization or provisioning invocation.
Do not call the output fully unsigned: the vendor linker may supply an ad-hoc signature;
this grants neither distribution nor GUI/NE qualification, and uses no organization secret.

Metadata calls: fixed 14s each including cleanup; compile: 120s including TERM 2s/KILL+reap 2s;
whole driver: 180s monotonic absolute deadline, including source/hash/inventory/artifact
phases. Fourteen-second metadata budgets reserve four seconds for cleanup (ten seconds work).
Whole-cap exhaustion fails closed; no adaptive budget, retries or renewed runtime grant.
Retain at most 64KiB per stream, drain
continuously with byte counters; preflight overflow fails, compile overflow fails after
bounded cleanup. Start each command in a new owned group, track child identity and reaping;
signal only the verified owned group/PID. Natural EOF permits bounded wait, then
group=not-requested and descendants=not-proven; no post-reap group identity claims.
Hold wait ownership through abnormal group cleanup, reject SIGCHLD auto-reap, use sticky
SIGTERM/interrupt cancellation and drain/close pipes on success, failure/cancel.
Leak/ambiguous ownership/FD failure stops reuse; no automatic repeat or alternate toolchain.

Copy the fixed plist; inspect without launching: executable is a bounded regular file
(maximum 32MiB), thin little-endian arm64 Mach-O `MH_EXECUTE`, valid bounded load commands,
minimum OS 15.0 / SDK 15.5 build version, and matching bundle executable/plist identity.
Require bounded LC_SEGMENT_64 structures/file ranges and a valid LC_MAIN entry in an
executable file-backed segment. Reject truncated/overlapping/invalid commands, FAT/x86 output and symlinks; record output
SHA-256/size. Fake tests include each rejection, not just successful fixture assembly.
After each phase, inventory generated entries only under the owned tmp/module-cache/app
subtrees: bounded count/bytes, regular files/directories, same owner, no symlinks or special
types. This generated manifest supplements fixed source ownership, without reading outside
the root. Cleanup compares root owner/inode, removes only those owned entries without
following links, then rmdir; unexpected entries retain the root and report failure. VM destruction remains
provider-managed/unverified, not evidence of child cleanup or external-effect denial.

## Result and remaining gates

Emit one JSON object, maximum 16KiB: `schema=1`, `phase=compile`, result enum
`compiled|rejected|failed`, error enum `none|source-mismatch|identity|tool-unavailable|flags|
spawn|compile|timeout|overflow|artifact|cleanup|internal`; feature/workflow/contract/manifest
digests, run token, validated baseline values, bounded printable compiler version/hash,
SDK path/version, source
digests, artifact digest/size, fixed per-command exit/deadline/byte/drain/FD/reaping status,
root cleanup status, `external-effects=trusted-vendor-not-denied`,
`candidate-executed=false`, `gui=not-run`, `engine=not-run`, `ne=not-run`.
Preserve a finite primary-error on cleanup failure; cancellation uses error=cancelled.
Never emit raw rejected metadata/diagnostics, environment, credentials or unbounded exception strings.
Successful compilation qualifies only this source/toolchain/build shape; .2d remains locked.

`artifact_predicate` is a closed diagnostic field: `not-run` until artifact checking,
then one of `file-preflight`, `file-mode-bounds`, `header-length`, `header-fields`,
`command-header`, `command-length`, `build-length`, `build-fields`, `segment-length`,
`segment-bounds`, `segment-overlap`, `section-vm`, `section-file`, `entry-command`,
`entry-bounds`, `plist-read`, `plist-content` or `passed`. It carries no rejected bytes,
exception text or addresses. Rejections retain error=`artifact`; `passed` records validator
acceptance only, before later inventory and cleanup. Calls without an output mapping keep
the same digest/size return. Synthetic tests cover the existing zero-section shape plus a
multi-section shape with file-backed and zerofill sections and VM/file-boundary rejection;
this adds no compiler-produced evidence and does not change acceptance. Predicate refusals
retain error=`artifact`; timeout, internal and cleanup behavior keeps its existing semantics.

Compile prerequisites are finite: source/build preparation and review, immutable binding,
one new compile-only grant, fresh matching hosted image and usable selected toolchain.
No Apple login, developer certificate, NE profile, real VPS, GUI session or engine is needed.
Two later actionable qualifications remain: (1) engine/GUI contract must freeze sing-box
1.14.2 archive/config semantics, numeric loopback nonce fixture, actual visible UI access,
owned-root/decoy external denial and child inheritance, guardian identities/reaping and
the entire accepted lifecycle/fault matrix; (2) Q-NE must obtain the absent eligible profile,
provider/entitlement/signing target and actual system-consent/routing/DNS evidence.
GUI incapability blocks visible UI acceptance; headless success never substitutes for it.
Signing/distribution stays independent and credential-bearing jobs cannot run candidates.
Retain A/B engine/permission/signing gates, final ADR dispositions and all G0–G6/main gates.

`artifact_build_mismatches` defaults null; after build-version unpack it contains only
platform/minimum/sdk/length booleans, retained on refusal with unchanged validation.

One semantic exception: `artifact_sdk_version` is null before build-version unpack,
or exactly major/minor/patch integers in 0..255. Decode the full high 16-bit major;
an out-of-range major stays null, without truncation. No other raw header data is
permitted. SDK equality, mismatch map, compiler argv and acceptance remain unchanged.
Overflow fallback retains only an exact-key, integer-only, bounded semantic object.
The expanded synthetic test source has a finite 40KiB admission cap; the driver cap is amended below.
Compile uses the fixed versioned SDK logical path after strict canonical equality/containment and version qualification.
This preserves qualified input spelling; artifact SDK equality and all other argv/checks remain unchanged.

## Frozen driver-jobs source phase — no runtime grant

The [accepted SDK producer review](../../task-results/G0/sdk-producer-review.md) freezes
only driver/parser, existing tests and this contract: 700/600/245 lines respectively,
40,960/40,960/32,768 bytes, per the [corrective review](../../task-results/G0/sdk-plan-source-review.md).
FILES and future bootstrap 40KiB reads apply only to exact driver/test paths; other source reads stay 32KiB.
The pure-file parser/grant case joins unchanged 18 names (19 total); future immutable
activation must separately update expected19/planned rules. AST/hash/diff checks
authorize no candidate import, test, compiler, guest, push or activation.
Select driver-jobs only for grant `one-driver-jobs-only` and qualification
`sdk-driver-jobs-hosted19-v1`; non-dict bindings or mismatched pairs reject before commands/staging.
Use qualified fixed compile argv plus only `-driver-print-jobs`, existing 120s/180s
bounds, adopted inventory/cleanup; failed adoption stays refused. Parse stdout in memory; never execute
printed commands or read response/file lists. Return planned/driver-jobs before artifact
checks, artifact null/predicate not-run, candidate false and GUI/engine/NE not-run.
`driver_jobs` defaults null; `plan-format` and overflow retain no rejected text.
`driver_jobs(text, logical_sdk, canonical_sdk)` accepts strings, strict UTF-8 <=64KiB,
1..8 nonblank shlex POSIX lines, <=512 tokens/job and <=4096 UTF-8 bytes/token.
Reject NUL/quote/encoding errors, @ references, -filelist, dangling wrappers and malformed/duplicate
relevant options. Exact target/SDK flags and three platform forms follow the review;
unknown relevant prefix/joined/wrapped forms refuse. Keep only tool/target/sdk enums
and platform_version_present boolean; no raw argv/path/version text. Planned forwarding
proves no executed downstream argv, installed compiler implementation or mismatch cause.
