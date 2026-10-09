# Hosted runner own-window admission v1

G0-06.2au; 2026-10-10; source/contract preparation only, not runtime authorization.
Basis: [native source facts](native-lifecycle-preparation.md), [environment gates](environment-qualification-plan.md); question: one hosted macOS 15 arm64 guest showing/operating its own real SwiftUI window.
This admission does not reset ar diagnostic budget 0 or investigate its crash; only dev Mac/runner confirmed, account availability grants no credential use.

## One coherent future card and review boundary

Proposed implementation paths (only these three):
`poc/client-framework/window-admission/Host.swift`, `poc/client-framework/window-admission/driver.py`,
`.github/workflows/client-window-admission.yml`; proposed tests (only these two):
`tests/client_framework/WindowAdmissionTests.swift`, `tests/client_framework/test_window_admission_driver.py`.
Host contains AppKit entry/event instrumentation, NSHostingView with actual SwiftUI Buttons and state;
driver contains identity preflight, bounded build/launch, ownership, report validation and cleanup.
Workflow uses `push` only on `codex/feature/self-hosted-byos-byoc`, `timeout-minutes: 5`, one job/guest.
`paths` is exactly the five files above plus proposed runtime metadata `docs/planning/task-bindings/client-window-admission-runtime.json`.
No docs-only path, main/default-branch edit or manual-dispatch prerequisite; `permissions: contents: read`;
checkout action at independently reviewed full commit SHA, exact feature SHA, `persist-credentials: false`.
No secrets/Apple account, inherited credential variables, personal directories, settings or crash-log access.
Root must review all five exact sources, workflow/action/source SHA-256, generated-file manifest,
command argv, environment, process ownership and runtime binding BEFORE imports/tests/build/launch.
Next source card prepares code only; no runtime is ready while compiler/provenance or side effects remain unknown.
Source-specific R acceptance must freeze compiler-provenance/version predicate and actual Cocoa/toolchild manifests;
hashes freeze after authorship/review. This contract has no executable source hashes or runtime grant.
Before push, root must accept that source commit and binding's one-guest cap, then authorize one reviewed source push.
That card carries source, focused tests and one guest; later docs-only publication must not retrigger it.
Fakes support safety only; no unchanged rerun, extra probe/grant or automatic version substitution.

## Image/toolchain admission before compilation

`macos-15`/arm64 is a scheduling request; historical `20260907.0337.1` metadata cannot select/guarantee that image.
Freeze the exact supported arm64 runner selector and reviewer-accepted image provenance/version predicate;
observe ImageOS/ImageVersion, OS build/arm64, resolved developer/compiler/SDK paths and versions in that guest.
Prefer installed `/Applications/Xcode_16.4.app/Contents/Developer`, Xcode 16.4 build 16F6, SDK 15.5;
freeze expected Swift version/build from that vendor toolchain before admission, not from current PATH.
Proposed bounded identity argv: explicit `xcodebuild -version`, explicit `swiftc --version`,
`/usr/bin/xcrun --sdk macosx --show-sdk-path` under that DEVELOPER_DIR; fixed-format results only.
Hash resolved compiler/toolchain inputs as evidence, not preknown pins; reviewer accepts vendor provenance/version predicate or supplies prior hashes;
unknown hash is never silently asserted to match. Mismatch/missing SDK/path/version stops before compile.
Exact selector, allowed image identity/provenance, Swift version and resolved SDK path remain unfrozen; resolve in the same card's reviewed binding/preflight.
If that trust decision cannot be made before compilation, stop this one guest without build/GUI or rerun.

## Owned writes and proposed command/interface

driver creates one fresh owned root R under runner temp, mode 0700, no symlink traversal;
manifest: source copies, tmp/, cache/{swift,clang}/, build/Host, fixed report and bounded private logs.
No package manager, project generator, SDK/engine download, signing step or shell command interpolation.
Child env allowlist: fixed PATH, LANG=C, TMPDIR=R/tmp, DEVELOPER_DIR, explicit module-cache paths;
HOME is neither redefined nor forwarded; add no other environment key without source review.
Driver preflight reads only allowlisted identity metadata and owned source; guest must contain no personal data.
Proposed build argv, with C/S/R resolved and reviewed, not runnable authorization:
`C -sdk S -target arm64-apple-macosx15.0 -module-cache-path R/cache/swift -Xcc -fmodules-cache-path=R/cache/clang -o R/build/Host R/Host.swift`.
[Swift driver options](https://github.com/swiftlang/swift-driver/blob/main/Sources/SwiftOptions/Options.swift) support SDK/target/cache selection;
current main is not proof of installed Xcode flag support, all compiler writes or absence of linker children.
Binding must confirm selected-driver options, implicit signing behavior and toolchild/write manifest first;
no explicit signing, Keychain, provisioning, App Sandbox/NE setup or user-default persistence is allowed.
Proposed driver interface: `driver.py --binding <reviewed-json> --phase admit`; host argv: `R/build/Host --admit`.
No config/engine/network child; host only runs synthetic UI. Framework/system writes outside R remain an
unverified boundary: enumerate unavoidable guest-system side effects or block; do not call this Q-B isolation.

## Actual window and control event proof

Host runs NSApplication's normal main event loop and one NSWindow containing NSHostingView<AdmissionView>.
No offscreen-only view. Require own window visible, non-minimized, key, app active, and occlusion visible;
sample these before each interaction and after state display updates, within the single 15 s run budget.
AdmissionView shows `idle` initially, enabled Select and Reset Buttons, and a disabled Disabled Button.
Only actual Button actions change model idle→selected→idle; rendered state is observed after layout.
Proposal: construct `.leftMouseDown`/`.leftMouseUp` with own nonzero windowNumber, content-local points,
nil graphics context, empty modifiers, monotonic timestamps, distinct event numbers, clickCount 1.
[Apple NSEvent factory](https://developer.apple.com/documentation/appkit/nsevent/mouseevent(with:location:modifierflags:timestamp:windownumber:context:eventnumber:clickcount:pressure:)) permits mouse event construction;
[Apple NSWindow event API](https://developer.apple.com/documentation/appkit/nswindow/sendevent(_:)) says never call sendEvent directly and lists postEvent forwarding to the application.
Queue the pair with `ownWindow.postEvent(event, atStart: false)`; let the normal event loop dispatch.
Instrument receipt by overriding own-window sendEvent solely to record matching events then call super.
Fixed Button bounds come from that SwiftUI layout, converted to window coordinates; do not query other windows.
Require matching down/up receipt, actual Button action under matching current event, model transition and
updated SwiftUI Text observation. Receipt alone or model/action invocation alone cannot pass.
After layout/display, cache only the own hosting view's fixed status-label region to an owned bitmap;
hash idle/selected/reset renders: selected differs, reset equals idle; model values alone are insufficient.
Within the same run, padding-click and disabled-Button-click must leave state/action evidence unchanged.
Direct callback, sendAction/performClick, controller-only tests and snapshots are supporting evidence only.
This is actual own-control dispatch from synthetic local events, not proof of physical/human/global input.
No CGEvent posting, global event taps, Accessibility automation, desktop capture or Screen Recording/TCC grants.
Do not infer permission requirements from failure; nil event, no GUI/key/visible window, unmatched action,
missed rendering or unsupported dispatch is a precise failed admission, not permission to change mechanisms.

## Bounds, evidence, cleanup and retained gates

Build ≤120 s including teardown; host ≤15 s including teardown; total job ≤5 min; no network from driver/host.
Bound/drain stdout and stderr concurrently (≤16 KiB private per phase); overflow fails and stops owned work.
driver owns unreaped direct-child identities; TERM then KILL only still-owned identities, wait/reap and close FDs.
Compiler/linker descendants need an explicitly reviewed retained group leader/guardian and group ownership;
never signal a reaped/reused PID/group, use name-based kill or add an unexplained native child/process group.
On EOF/cancel/timeout, guardian must reclaim owned build descendants and host; uncertainty/leak fails closed.
Cleanup only manifest-owned entries after no-symlink/owner checks; never remove checkout, home or shared caches.
Report ≤4 KiB: schema/version, fixed result enum, identity/source hashes, booleans for visibility/key/events,
actions/state-text/negative checks, exit/deadline/output bounds, reaped/FD/manifest cleanup; no paths/raw logs.
Export hashes only from own synthetic view/event evidence, never desktop/unrelated-window captures.
Missing identity/cleanup, unsafe source or out-of-root effects fail closed; fakes cover refusals. Success admits this window target only: Q-A/Q-B external read/write/network denial, decoys, inheritance,
guardian/full fault proofs, A/B real engine readiness/lifecycle, NE, signing/distribution, ADR and G0–G6 remain open.
