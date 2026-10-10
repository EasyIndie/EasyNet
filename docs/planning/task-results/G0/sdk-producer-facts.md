# G0 SDK producer facts — bounded source review

2026-10-10; source review only. No compiler, linker, fixture, runtime, or Git mutation was performed.

## Accepted observations

- Hosted identity: Apple Swift 6.1.2 (`swiftlang-6.1.2.1.2`, Clang 1700.0.13.5), SDK query 15.5, selected SDK path `MacOSX15.5.sdk`.
- Accepted finite records [sdk-semantic-hosted-records.json](sdk-semantic-hosted-records.json) and [sdk-logical-path-hosted-records.json](sdk-logical-path-hosted-records.json) together report artifact SDK `15.0.0` for two compile observations, including the fixed versioned-alias path; artifact acceptance failed solely on the SDK field among the four recorded build-field predicates.
- Fixed argv in `native-lab/build.py` passes `-target arm64-apple-macosx15.0` and `-sdk <MacOSX15.5.sdk>`. The preceding [artifact review](artifact-sdk-review.md) notes the emitted downstream argv was not retained.

## Primary-source facts

- The official [swift-driver 6.1.2 release source, Options.swift](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftOptions/Options.swift#L282) defines `-driver-print-jobs` as printing jobs. The [same release's Driver.run](https://github.com/swiftlang/swift-driver/blob/swift-6.1.2-RELEASE/Sources/SwiftDriver/Driver/Driver.swift#L1506-L1512) prints each planned job description and returns before job execution. This is a supported compile/link-argv observation path; it does not itself execute the printed compiler or linker jobs.
- The [swift-driver Darwin linker support on main](https://github.com/swiftlang/swift-driver/blob/main/Sources/SwiftDriver/Jobs/DarwinToolchain%2BLinkerSupport.swift) forms a Clang link invocation forwarding the SDK as `-isysroot` and target triple as `--target`. This is current-main explanatory evidence only; the 6.1.2 tagged file URL could not be retrieved in this bounded review, so it does not prove the installed vendor binary's exact implementation.
- Apple's [ld64 Options.cpp](https://github.com/apple-oss-distributions/ld64/blob/main/src/ld/Options.cpp#L3145-L3169) parses `-platform_version` into platform, minimum-version, and SDK-version values; [SDK inference](https://github.com/apple-oss-distributions/ld64/blob/main/src/ld/Options.cpp#L5694-L5711) otherwise extracts trailing version digits from the first `-syslibroot` path when no explicit platform-version or SDK-version overrides apply. The official [ld-classic man page](https://github.com/apple-oss-distributions/ld64/blob/main/doc/man/man1/ld-classic.1) describes `-platform_version platform min_version sdk_version` as the platform, deployment minimum, and SDK used to build the output.

## Bounded conclusion

These sources show plausible producer routes, not which route the hosted Apple linker took. In particular, they do not establish that this artifact's 15.0.0 came from the target triple, the SDK path, a linker default, or another toolchain layer. SDK query version, selected SDK directory, and Mach-O encoded SDK metadata remain distinct facts. Do not infer a cause, inject `-platform_version`, or weaken SDK equality from these records.

One bounded follow-up proposal, subject to its own review/authorization: on an otherwise authorized reproduction, invoke the exact fixed `swiftc` argv with the supported `-driver-print-jobs` diagnostic and retain only bounded frontend/link job argument arrays. This can show the Swift driver's downstream arguments without running the printed compile/link jobs; it cannot prove linker behavior or cause by itself. No observation grant or implementation is made here.

## Limits

The reviewed exact release sources establish the print-jobs behavior. Swift Darwin-link code was reviewed only on `main`, and ld64 code on `main`; no immutable ld64 revision was resolved. No source establishes vendor-binary identity, executed downstream argv, actual linker implementation/version, or the producer cause of the recorded SDK value.
