# SDK to linker metadata facts

Source request: official `swiftlang/swift-driver`, tag `swift-6.1.2-RELEASE`,
`Sources/SwiftDriver/Jobs/DarwinToolchain+LinkerSupport.swift`.
My initial exact-path GitHub Contents request returned HTTP 404 / Not Found.
The task owner then located and retrieved the tagged source by read-only
Contents directory traversal. The actual file is
[`DarwinToolchain.swift` at `swift-6.1.2-RELEASE`](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Toolchains/DarwinToolchain.swift),
blob `79bce9cc2613216328b905e26836e54211d5eb01` (22,909 bytes).

## Evidence in existing contract

- `docs/planning/poc/client-framework/native-build-contract.md:22-24` calls
  SDK 15.5 and target `arm64-apple-macosx15.0` experiment choices.
- `docs/planning/poc/client-framework/native-build-contract.md:161-163`
  requires the produced thin arm64 Mach-O executable to declare minimum OS
  15.0 and SDK 15.5 in its build version load command.
- `docs/planning/task-results/G0/sdk-frontend-review.md` under
  “SDK 合同依据 disposition” says xcrun lookup supports input identity but
  alone does not establish a required 15.5 Mach-O producer marker. It records
  the source from SDK metadata to that marker as missing and retains the
  existing equality check pending evidence.

## Findings and unknowns

- `DarwinToolchain.swift:281-286, 329-352` decodes SDKSettings.json keys
  `Version`, `CanonicalName`, and (for `macosx`) `VersionMap`; lines 369-374
  read and JSON-decode that file beneath the supplied SDK path.
- Lines 355-363 select the SDK version for the target triple, including the
  Catalyst mapping. Lines 392-400 append `-target-sdk-version` and its value
  (plus variant version when present); lines 403-405 conditionally append
  `-target-sdk-name` and the canonical name if the frontend supports it.
- `FrontendJobHelpers.swift:522-525` calls this method while building common
  frontend options. This proves an SDKSettings-to-frontend-argument chain.
- This evidence does not show `-sdk`/`-isysroot` forwarding into a linker job,
  linker mode (clang versus `ld`), or how the final Mach-O build-version field
  is obtained/encoded. The “down to the linker” comment at line 358-359
  describes the Catalyst version mapping but does not prove that production
  chain. No direct xcrun query is shown in these inspected ranges.
- Thus the frontend `-target-sdk-version` value is evidenced; its causal link
  to the contract's required Mach-O SDK 15.5 marker remains unknown.
- Installed Apple binary behavior and the real failed token remain unobserved;
  no cause for a mismatch can be inferred from this source attempt.
