# G0 Swift frontend SDK argument facts

2026-10-10; bounded official-source collection only. No compiler, runtime, fixture, SDK settings read, or guest action.

## Retrieved tagged source

- Requested the official GitHub Contents API path `Sources/SwiftDriver/Jobs/FrontendJobHelpers.swift` at `swift-6.1.2-RELEASE`; it exists (not a 404). API metadata reports blob SHA `bf76abf0efcd890daf0d99812117624a451ca037`, size 43,493 bytes, under the 256 KiB bound.
- Retrieval: one read-only `gh api` Contents request, then one read-only `gh api` blob request. The blob's base64 `content` was decoded to text in `/tmp` and inspected, never executed. No checkout or broader tree fetch.
- Immutable source: [FrontendJobHelpers.swift at swift-6.1.2-RELEASE](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Jobs/FrontendJobHelpers.swift#L63-L76) (blob SHA above).

## What this source proves

- `addCommonFrontendOptions` appends `-target` followed by `targetTriple.triple` for standard/single/batch compile and PCM modes (lines 63–85).
- It appends `-sdk` plus the path from `frontendTargetInfo.sdkPath` (lines 171–173).
- The adjacent root/version option loop only handles Visual C++ and Windows SDK root/version pairs (lines 175–189); it does not append `-target-sdk-version` from Darwin SDK metadata here.
- The tagged [Options.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftOptions/Options.swift) separately defines `-target-sdk-version` as a frontend option marked `.noDriver`; this declaration establishes option recognition/classification, not the code path that supplies a value to a planned frontend job.

## Boundary and remaining unknowns

The requested exact frontend-generation proof—whether another Swift 6.1.2 path obtains `sdkInfo`/`sdkVersion` and appends `-target-sdk-version` to the planned job—remains missing. The bounded Contents source path existed but was not that producer path; the sole allowed raw-source fallback for the previously identified Darwin linker file was inaccessible (GitHub returned cache miss). No third API read or wider source search was made. Even a source-level path would not prove Apple Swift 6.1.2's installed vendor binary took it, reveal the failed run's actual printed argv, or establish why the artifact encoded its observed SDK token.
