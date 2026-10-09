# Candidate B native lifecycle preparation — source facts and proposed gate

Date: 2026-10-10. Scope: bounded source/primary-fact preparation for G0-06.2at.
This records facts, proposals, and gaps; it does not select a product framework or engine,
grant runtime permission, or establish qualification.

## Verified source facts

- The frozen GitHub Actions image URL is [`macos-15-arm64` image `20260907.0337`](https://github.com/actions/runner-images/blob/macos-15-arm64/20260907.0337/images/macos/macos-15-arm64-Readme.md).
  Its README identifies macOS 15.7.9 and image version 20260907.0337.1; Xcode 16.4
  (build 16F6) is the default. It lists macOS SDKs through 26.2 and Xcode 26.3 as
  installed, but does not identify the Swift compiler version/path. This is image
  metadata, not evidence that a workflow can present/interact with a real SwiftUI window.
- The official [sing-box 1.14.2 release assets](https://github.com/SagerNet/sing-box/releases/expanded_assets/v1.14.2)
  list `sing-box-1.14.2-darwin-arm64.tar.gz`, SHA-256
  `925c5382eca8492b0150f868a6db20b18290a38700e621724b3703fd453e032d`.
  This identifies a CLI archive only; no artifact was fetched or checked locally.
- Accepted preparation v1 defines the common proxy lifecycle and isolation cases. Its
  Flutter-specific UI/host description does not establish native implementation behavior.

## Proposed B source/UI qualification

Keep this as a native-host candidate experiment: one actual foreground SwiftUI window
owns one child CLI process through a controller. This is a test proposal, not an ADR,
product architecture choice, or commitment to SwiftUI or sing-box. Do not substitute a
headless executable, mocked window, engine-only run, embedded libbox, or Network Extension.

Suggested future owned paths (proposals; create only in a separately frozen card):
`docs/planning/poc/client-framework/native-lab/Host.swift` (SwiftUI window and app entry),
`Lifecycle.swift` (serialized controller/process owner), and `Guardian.swift` (separate
process-group and pipe cleanup owner); focused tests:
`native-lab/Tests/LifecycleTests.swift` and `native-lab/Tests/WindowTests.swift`.
These are exactly three proposed implementation files and two test files, not existing
interfaces or permission to create them. A proposed controller surface is
`connect(config, generation)`, `cancel(generation)`, `stop(generation)`,
`restart(config, generation)`, with published `state`, `error`, and `runToken`; the
controller serializes generation changes and delegates verified child ownership to the
guardian. Freeze source/artifact provenance, generated project/build files, exact
compiler/SDK, build/cache writes and ownership before implementation. Pin and review CLI
schema/config and direct-route semantics before constructing an executable config.

Documentation-only build shape for a later card: invoke the selected Xcode toolchain's
`xcodebuild` on the frozen native-lab project/scheme, with an owned DerivedData/build
directory and explicit destination; launch that built app directly under the guardian
in the actual GUI session. This is not a runnable command: project, scheme, destination,
signing mode, flags, module-cache location and exact command remain unknown. The pinned
runner README does not prove the selected Swift compiler executable/version or these
build options. A future R-reviewed binding must verify compiler/SDK/source identity and
all write locations from primary sources before authorizing even a build; do not guess
flags, redefine HOME, or treat this shape as a frozen command.

Proposed behavior contract: render visible Connect, Cancel, Stop, Restart controls and
observable state, error and run generation. Start a single pinned CLI with an argument
array (no shell); use explicit environment/working directory, bounded continuously drained
stdout/stderr and awaited exit. Use a separate guardian that owns the launched process
group and pipe lifetime, and may terminate only verified owned identities. Preserve the
accepted process identity, group inheritance, reaping, FD closure, deadlines, output caps,
and no-daemon constraints. No name-based kill or unverified PID signal.

Use only owned temporary fixtures, numeric loopback endpoints, and a unique run nonce.
Readiness means a complete SOCKS5 CONNECT to the local fixture, a valid HTTP exchange,
and the matching nonce response. Do not configure TUN, system proxy, routes, DNS writes,
subscriptions, or non-loopback destinations. A real visible window must be operated and
its transitions observed; headless/controller tests are supporting evidence only.

Carry forward the complete accepted common case set: genuine nonce readiness; Stop;
forced child crash then explicit Restart; repeated Connect/Stop cycles; duplicate and
concurrent Connect; Cancel before spawn and during readiness; invalid config; occupied
port; silent/hung readiness; output flood; absolute timeout; window close; forced host
crash; and harness failure/cancel with guardian EOF cleanup. Assert stale generations
cannot become ready; every case records visible state, owned process identities, nonce
result, exit/deadline/output/FD evidence, cleanup, and listener-port reuse. No leak or
fixture residue may pass.

## Qualification gaps and stop conditions

Unknown: actual Xcode/Swift compiler selected by the pinned workflow, Swift compiler
version/path, exact macOS SDK used by a future target, project template/generated files,
build side effects, and whether the pinned runner supports observable interactive GUI.
Unknown: exact 1.14.2 config schema/route semantics in a locally validated configuration,
actual engine process behavior, UI lifecycle, isolation denial/guardian properties, and
any native client qualification. Do not fill these gaps by downloading, compiling,
running, querying user settings, or making permission assumptions in this preparation.

No independent Mac/VM is confirmed; the user reports the current development Mac and
GitHub runner only. Apple Developer account availability is recorded, but does not prove
an eligible signing channel, provisioning, entitlement, consent, or credential access.
Keep visible proxy UI, Network Extension/system VPN, signing/distribution as separate
gates. Whole-guest isolation alone does not prove owned-root/decoy protection or denial of
external reads, writes, and network access. Require a separately reviewed Q-B security
contract before any run. If no actual visible UI target is qualified, report the UI gate
blocked; never count headless success as UI qualification or relax isolation.

Future command lines, if later frozen, are proposals only. No source was created here,
and no SDK, engine, compiler, GUI, signature, VM, test, or runtime command was executed.
