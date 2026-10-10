# SDK producer contract — Q-B static review

R disposition: accept the source-only successor design below; root accepted 2026-10-10 for implementation only. Runtime qualification pending.
Scope: Swift 6.1.2 native macOS arm64 SDK metadata → controlled SDKROOT → one compile/link → existing artifact predicates.
The current [native contract](native-build-contract.md) stays authoritative until root freezes its reviewed successor.
No compiler, SDK read, guest, personal Keychain, workflow activation or old grant was executed here.

## Primary source ledger (read 2026-10-10)

Sources are inert text. Upstream tag `swift-6.1.2-RELEASE` does not identify Apple's installed binary.

| Text / identity | Lines / supported fact |
|---|---|
| [Swift DarwinToolchain.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Toolchains/DarwinToolchain.swift#L281-L405), blob `79bce9cc2613216328b905e26836e54211d5eb01`, 22,909 B | 281–352 metadata fields/mapping decoder; 369–374 read SDKSettings; 392–405 frontend SDK flags; 73–74 dynamic linker resolves clang. |
| [FrontendJobHelpers.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Jobs/FrontendJobHelpers.swift#L171-L173), blob `bf76abf0efcd890daf0d99812117624a451ca037`, 43,493 B | 171–173 frontend `-sdk`; 522–525 call common SDK argument builder. |
| [DarwinToolchain+LinkerSupport.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Jobs/DarwinToolchain%2BLinkerSupport.swift#L81-L93), blob `929e5fe1aaf11f1e0014604c10b6456098f12cdb`, 10,893 B | 81–93 executable uses dynamic linker; 224–226 `--sysroot <sdk>`; 236–237 `--target=<triple>`. |
| [clang Darwin.cpp](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L2318-L2365), blob `959d29587f2386753677e88934a89f3bfdc680bb`, 145,289 B | 2318–2331 SDK parser consults `OPT_isysroot`; 2340–2360 valid absolute SDKROOT supplies it; 3499–3561 construct platform/minimum/SDK linker tuple. |
| [clang Basic/DarwinSDKInfo.cpp](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Basic/DarwinSDKInfo.cpp#L65-L151), blob `00aa5f9e63cd3fc754a252a7fb254320c8843325`, 5,876 B | 65–84 Version/MaximumDeploymentTarget strings must parse; 88–123 mappings; 131–151 bounded-target filename and read/JSON failures. |

Both newly retrieved LLVM sources used exact Contents path/ref; decoded length matched declared size and each was ≤256 KiB.
Initial `clang/lib/Driver/DarwinSDKInfo.cpp` request returned404: path failure, not absence evidence.
Two permitted directory metadata reads (ToolChains, Driver) had no SDK helper; exact Basic helper request then succeeded.
Source budget used: two new source files, two directory metadata reads; existing Swift texts were supplied inputs. No broad search or SDK download.

## Actual observations

- [semantic hosted record](../../task-results/G0/sdk-semantic-hosted-records.json) and [logical-path hosted record](../../task-results/G0/sdk-logical-path-hosted-records.json) each report synthetic18 pass and real compile/link exit0, followed by artifact `build-fields` failure.
- Both report xcrun SDK15.5 and Mach-O SDK15.0.0; mismatch flags are `sdk=true`, `length/minimum/platform=false`.
- Both report Xcode16.4/16F6 and Apple Swift6.1.2 (`swiftlang-6.1.2.1.2 clang-1700.0.13.5`); compiler SHA256 `bf77cc8826cd1a74f1a9734c5c63a182bd26b9472682b58f01e435cc064e1bc8`.
- Actual SDKSettings, child SDKROOT, frontend/clang/ld printed jobs are unobserved. GUI/engine/NE not run, candidate not executed, artifacts removed.
- [local sysroot record](../../task-results/G0/sdk-sysroot-local-record.json) passes one pure mocked parser/grant case; three reported pure-mock passes do not establish full19 or hosted acceptance.
- [prior facts](../../task-results/G0/sdk-linker-metadata-facts.md) support frontend metadata but did not resolve the linker channel. Old grants remain zero and workflow disabled.

## Static producer trace and its limits

1. Swift reads SDKSettings: Version and CanonicalName strings, macosx VersionMap with `macOS_iOSMac` string-to-string versions (281–352, 369–374).
   Native macOS uses Version; Catalyst mapping is a separate branch (355–363). Frontend gets `-sdk` and metadata-derived `-target-sdk-version` (392–405; frontend171–173/522–525).
2. Executable links through clang; Swift passes `--sysroot <sdk>` and `--target=arm64-apple-macosx15.0` (linker81–93/224–237; toolchain73–74).
   No inspected source forwards the frontend SDK scalar into that link job.
3. clang library root and metadata are separate channels: [431–439](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L431-L439) forwards general sysroot to ld `-syslibroot`; 2318–2331 parses SDKSettings only via `-isysroot`.
4. [2340–2360](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L2340-L2360): if no `-isysroot`, SDKROOT is used only when absolute, existing and not `/`.
   Setting SDKROOT to the already qualified SDK deliberately supplies this supported metadata channel; it does not directly override an encoded SDK marker.
5. Basic helper reads `<root>/SDKSettings.json`; unreadable yields no SDKInfo, malformed JSON/top-level/non-parsing required fields yields invalid-settings error (65–84,131–151).
   Present `macOS_iOSMac` or `iOSMac_macOS` object mappings must be valid/nonempty (108–123); parseJSON accepts string version pairs, ignores nonstring values and rejects invalid version pairs/empty parsed maps (37–62).
6. For linker version≥520, LLD or xrOS, clang emits `-platform_version <platform> <minimum> <sdk>` (359–362, [3499–3564](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L3499-L3564)).
   With native SDKInfo, SDK is Version without build; absent SDKInfo uses effective targetVersion (3546–3561). Target minimum may be raised by the effective triple (3513–3524).
7. Apple ld consumes the tuple and produces the inspected Mach-O; its encoding implementation and the installed jobs were not retrieved.
   Retain the existing bounded reader's exact LC_BUILD_VERSION predicates as runtime evidence, without asserting source proves every installed vendor layer.

Deduction: absent clang SDKInfo is a coherent model of the recorded15.0.0, not a proved diagnosis of those runs.
Official SDKROOT mechanism plus validated metadata and a fresh artifact satisfying all original predicates is sufficient successor build qualification; proving every ld causal step is not a prerequisite.

## SDK15.5 requirement disposition

Native contract22–24 chooses inputSDK15.5;118–126 pins SDK identity;160–165 additionally requires outputSDK15.5.
xcrun15.5 alone does not justify output equality. Retrieved code supports equality when clang receives valid SDKInfo15.5; therefore fix the controlled metadata input and retain equality.
Do not force `-platform_version`, rewrite output, relax a range or use arbitrary first observed marker as success. Keep minimum15.0 and every structural predicate.
No proposed output15.0 acceptance is needed for this package. If the fresh package still emits15.0, report failure, stop new runtime attempts and return complete evidence to R.

## Frozen minimal implementation package

The reviewed change is one controlled environment addition after metadata preflight, not a new jobs/clang diagnostic system.
Exact paths (two implementation/document paths, one test path; below ≤3+≤2 allowance):

| Path | Change |
|---|---|
| `docs/planning/poc/client-framework/native-lab/build.py` | Qualified SDKSettings strict bounded reader; limited record; construct compiler env with `SDKROOT=str(qualified_sdk)` only after successful preflight. |
| `docs/planning/poc/client-framework/native-build-contract.md` | Freeze metadata predicates, explicit qualified SDKROOT, evidence/limits and new integrated grant. |
| `docs/planning/poc/client-framework/native-lab/Tests/test_build.py` | Preserve old18 cases and source-card parser/grant tests; add metadata/env/conditional-compile cases. |

No Host.swift/Info.plist, driver-jobs parser, nested clang, compile argv, Mach-O reader or other runtime changes.
Root separately freezes new binding/workflow hashes; old binding/budget/workflow stay closed in this code package.
Proposed once-frozen ceilings: driver≤950 lines/65,536B; tests≤900 lines/65,536B; contract≤300 lines/40,960B; no deletion/compression of old cases.
Source-card `c82420c` is a preserved input, not full-suite runtime acceptance.

`read_sdk_metadata(qualified_sdk)` must open only that SDK's SDKSettings.json; selected SDK qualification precedes it.
Require canonical existing absolute SDK directory inside frozen Xcode, not `/`; metadata canonical target inside that SDK, bounded regular file, no escaping symlink.
Read/hash from one file descriptor, detect identity/size change, obey existing overall deadline; ≤256KiB and no raw-byte output.
Strict UTF-8 JSON object, no duplicate keys/NaN, bounded nesting≤16 and total members≤4,096; unknown harmless top-level keys need not be logged.
Require Version normalized15.5.0, CanonicalName exactly frozen `macosx15.5`, MaximumDeploymentTarget valid and ≥15.0.0; absent/wrong type/malformed → `sdk-metadata` before compile.
Version strings use an explicit admissible subset:1–3 nonnegative decimal components, each≤65,535; normalize missing components to zero. Unsupported shape fails, never coerces or falls back.
Require VersionMap object and nonempty `macOS_iOSMac` object of valid string version pairs; optional `iOSMac_macOS`, if present, has the same valid/nonempty shape.
For every case-insensitive `ios_` mapping key, require object values containing valid/nonempty string version pairs, a conservative subset of helper37–62/88–105; unknown mapping semantics never authorizes a new target.
These strict mapping predicates intentionally reject shapes that upstream might ignore; native target is unchanged and no Catalyst version is emitted.
Record only SDKSettings SHA256/size, normalized Version/MaximumDeploymentTarget, CanonicalName and `sdkroot-qualified=true` (≤1KiB added structured data).
Do not print mapping pairs, SDK raw JSON, inherited environment or credentials; existing redacted SDK identity supplies the path association.
Construct controlled child env and overwrite any inherited SDKROOT with the qualified SDK path. Use it for the already approved compiler jobs/compile calls; no extra command.
Preflight failure emits stable `sdk-metadata`, records bounded failure stage, invokes compile zero times and performs existing owned cleanup.
A successful metadata check permits one original compile argv; artifact predicates decide final pass. SDKROOT presence alone can never produce PASS.

## Behavior cases and one integrated validation

- Valid15.5 metadata/known canonical SDK, hostile inherited SDKROOT → controlled env points only to qualifiedSDK; unchanged original compile argv runs once.
- Missing/unreadable/oversize/changed-file/escaping symlink/duplicate JSON/invalid required version/name/map → `sdk-metadata`, compile calls0, cleanup succeeds.
- Relative/nonexistent/root SDK path → prior identity failure, no metadata/compile; malformed ios mapping object → preflight refusal rather than unsafe vendor parse.
- Metadata15.5 + mocked compiler exit0 + artifact SDK15.0 → original artifact failure; correctSDK but wrong minimum/platform/segments/LC_MAIN/plist remains failure.
- Metadata15.5 + compiler exit0 + exact valid artifact15.5/minimum15.0 → pass only with all original identity/structural predicates.
- Assert child env overwrite, unchanged target/sdk/framework argv, no marker injection, no extra vendor command; preserve fat/x86/truncation/symlink/process/deadline/cleanup tests.

No current grant permits runtime. After I implementation and this R's integrated review, root must freeze exact feature/source/contract/manifest/action/tool/environment identity and one fresh hosted grant.
Run the full current19-case pure-mock suite plus added cases with zero skips; keep original18 coverage. Pure mock PASS does not replace actual qualification.
One hosted macos-15 arm64/Xcode16.4 cell: existing qualified compiler/SDK identity → SDKSettings bounded preflight → SDKROOT construction → original compile/link≤120s → original artifact inspection≤32MiB → owned cleanup.
Use existing bounded compiler versions/help/job outputs and process deadlines; compiler hash remains≤512MiB. Whole package≤300s, structured report≤64KiB; no new external observation commands.
Metadata/hash/version are first real observations under the frozen trusted SDK identity; record them even when a later compile/artifact fails. On success root freezes the metadata fingerprint for successor reproducibility.
Missing metadata or producer mismatch consumes the once-only attempt and returns failure; no automatic retry, alias/flag experiments, new guest or platform expansion.
Workflow is disabled and new grant exhausted after the result. GUI/engine/NE/system consent/organization signing/notarization and full G0/final gates remain required.
