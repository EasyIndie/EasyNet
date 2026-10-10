# Q-B SDK producer contract review

Date:2026-10-10. Branch verified `codex/feature/self-hosted-byos-byoc`; initial tree clean.
Deliverable:[producer contract](../../poc/client-framework/sdk-producer-contract.md).
R disposition: source-only minimal SDKROOT design accepted; runtime and completeG0 unqualified.

## Directly freezeable implementation

- Existing build.py: after qualified SDK identity, read/hash/validate only SDKSettings.json; then explicitly construct child SDKROOT from that same SDK.
- Version/MaximumDeploymentTarget strings and mapping predicates have retrieved helper evidence; strict conservative accepted shapes, fail closed before compile.
- Existing compile argv and artifactSDK15.5/minimum15.0/all structural checks remain. No output marker forcing, lowering equality or new driver-jobs subsystem.
- Existing Tests/test_build.py keeps original18/source-card coverage and adds bounded metadata/env/compile0/refusal/unchanged-argv cases; full19 plus additions still required.
- Existing native-build-contract.md freezes limits and new integrated grant. Proposed driver950/test900/contract300-line headroom avoids old600-line limit churn.
- Root can dispatch one I code package, one integrated R review, then freeze one complete hosted runtime grant; old grants/workflow remain closed.

## Static causal support

[Darwin.cpp](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L2339-L2360), blob `959d29587f2386753677e88934a89f3bfdc680bb`, confirms SDKROOT absolute/existing/not-root criteria and SDKSettings parsing through synthesized-isysroot.
[Basic/DarwinSDKInfo.cpp](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Basic/DarwinSDKInfo.cpp#L65-L151), blob `00aa5f9e63cd3fc754a252a7fb254320c8843325`, requires valid Version/MaximumDeploymentTarget and validates present Catalyst mapping objects.
Initial Driver helper404 was a path error, not absence. Two bounded directory metadata reads and exact Basic helper retrieval resolved it; used2/3 new sources and2/2 directories.
Swift frontend reads SDK metadata independently; Swift link uses clang--sysroot, which is separate from metadata-isysroot.
[Darwin.cpp3499–3561](https://github.com/swiftlang/llvm-project/blob/swift-6.1.2-RELEASE/clang/lib/Driver/ToolChains/Darwin.cpp#L3499-L3561) emits metadata Version or target fallback into-platform_version SDK operand.
The controlled SDKROOT choice uses an official selection mechanism; it does not set the final marker directly.

## Fresh observation still required

Actual SDKSettings identity/size/hash/semantic values have not been read; freeze predicates now, observe within the conditional complete runtime package.
Installed Apple behavior may differ from upstream. Actual one compile/output is required; input metadata success alone cannot qualify the producer.
Old artifact15.0 is consistent with missingSDKInfo, but installed root cause is not proved or required to claim after successful successor qualification.
Apple ld encoding implementation/printedjobs remain unobserved; no new nested-clang/source/guest diagnostic system is needed.
If metadata valid15.5 plus controlled SDKROOT still fails exact artifact predicates, stop and review complete evidence; do not silently accept15.0 or retry flags.
GUI/engine/NE/organization signing/system-consent/fullG0 gates remain pending independently of unsigned build success.

## Verification

Only static source review, document line limits/local links and git diff--check; no SDK read/compiler/test-suite/hosted/guest/Keychain operation.
Source URLs, lines, inert local text links, failed/successful retrieval evidence and existing observed records are in the contract.
No old contract/source/CI/budget/ledger edit, commit or push.
Next action: root accepts/freeze this bounded design and dispatches I implementation; one integrated R review then one fresh complete hosted grant.
