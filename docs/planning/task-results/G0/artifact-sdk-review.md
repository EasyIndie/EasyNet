# Q-B SDK mismatch closure and bounded producer review

2026-10-10; R source/evidence review only. No implementation, fixture/compiler,
guest, candidate, credential, binary retention or diagnostic tool ran in this review.

## Observation closure — accepted

Accept [finite hosted evidence](artifact-build-map-hosted-records.json), run
`38033726243`, activation `36e484f945fb611ca82d30b8fe644a29d0190b87`:
synthetic18 passed with zero failures/errors/skips, passed cleanup and empty failures;
metadata/version/help and compile/link commands 0-9 exited 0. Artifact validation
then rejected build-fields with platform=false, minimum=false, sdk=true, length=false.
Artifact remains null, staging cleanup removed, candidate-executed false and
GUI/engine/NE not-run. Thus SDK equality alone failed within this command's four checks.
The actual emitted SDK value was not retained and remains unknown.

Accept workflow false gate/empty inline and artifact-build-map archive consumed with
local_remaining=guest_remaining=0. Old grants remain consumed/zero; no replacement
runtime grant follows. Source-only instrumentation/fixtures are accepted; artifact/build
qualification and G0/full acceptance are still pending.

## Narrow primary producer evidence

Two relevant primary source files were consulted; the Swift 6.1.2 tag URL could not be
retrieved, so the available main-branch code is explanatory, not the installed binary's
implementation identity. No further source/framework sweep was performed.

The current [Swift Darwin linker support](https://raw.githubusercontent.com/swiftlang/swift-driver/main/Sources/SwiftDriver/Jobs/DarwinToolchain%2BLinkerSupport.swift)
constructs a Clang link command: it forwards the SDK path as -isysroot and the target
triple as --target. This file does not directly form a -platform_version SDK argument.
It does not establish how the observed Apple Swift 6.1.2/Clang/linker chain chose its
emitted SDK value. No actual downstream argv or SDK settings were observed.

Apple's public [ld64 option handling](https://raw.githubusercontent.com/apple-oss-distributions/ld64/main/src/ld/Options.cpp)
parses -platform_version as platform, minimum and SDK versions, updating the stored
platform SDK value; supplying that option also marks explicit version selection.
Without explicit selection, this source can infer SDK version from digits in
-syslibroot, with a macOS fallback if inference fails. This describes supported
producer routes; it is not proof that the hosted vendor linker used either fallback.

Repository identity() separately validates the xcrun version string 15.5 and selected
SDK canonical containment/equality, then returns sdk.resolve(); the fixed compile argv
uses that resolved path. Hosted sdk.path is the unversioned MacOSX.sdk name. Losing a
version-bearing alias is therefore a source-level inference risk for a path-sensitive
producer, but the actual linker route and emitted number remain unobserved. SDK query
identity, directory identity and encoded artifact SDK metadata are distinct evidence.

## Disposition — preserve checks and compiler argv

No independently demonstrated format or producer defect is established. Do not infer
zero, a patch release, 26, a driver bug or a particular linker fallback from sdk=true.
The primary sources establish that explicit -platform_version can set the recorded
SDK, but do not establish that 15.5.0 is this artifact's truthful emitted value. Adding
it merely to satisfy the equality could suppress inference or overwrite metadata;
no fixed-flag repair is accepted. Preserve all current artifact checks and compiler argv.

Deriving a truthful version from SDK settings would be a new qualified driver input:
freeze its exact selected-SDK relative file/key, bounded regular-file read, canonical
containment and semantic parser/identity before use. This review has not read that
file, established its schema/key/value or authorized such a preparation package.

## Actionable source-only proposal; no observation grant

The smallest next proposal is an R-reviewed contract exception for one semantic field,
artifact_sdk_version, from the SDK value already unpacked by artifact(): null before
the build-fields check, otherwise exactly major/minor/patch integers each in 0..255.
Decode major from the full high 16 bits and validate the bound; do not mask/truncate
an out-of-range major. Preserve the original SDK equality and mismatch map unchanged.
Emit no encoded hex/integer, other header values, addresses, paths, section data or dump.
This limited semantic metadata exception must be explicit; the prior raw-header ban
continues for every other value. Malformed/out-of-range evidence stays null with a
fixed refusal; result/overflow handling remains finite and does not expose exceptions.

Before implementation, freeze a bounded three-file source plan and meaningful isolated
fixtures for normal/zero/nonzero-patch/max/out-of-range semantic cases and unchanged
SDK mismatch rejection. It is preparation toward learning a semantic value, not an
accepted SDK expectation change. No helper, inspection phase, extra command or binary
retention is needed. Neither implementation nor tests are granted by this proposal.

Any future actual observation requires a new exact immutable source/contract/manifest/
workflow/action/binding/activation identity and independent once-only target grant,
with the revised full18 gate before conditional compile and existing fixed limits.
No old budget is restored, no automatic further compile/probe is authorized, and failure
must stop. Even semantic output would not by itself prove producer cause or justify
weakening acceptance. GUI/engine/NE/signing/device and all G0-G6/main gates remain intact.
