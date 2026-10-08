# SwiftUI / native client route: official evidence

Checked 2026-10-08; single candidate evidence, not an accepted framework, engine,
platform support or permission decision. Facts describe cited documentation;
inferences are engineering constraints, not executed behavior. Unknown means
not established for EasyNet. Existing Go services and inventory direction remain
separate from UI and VPN engines. Related [Flutter evidence](flutter-evidence.md)
provides unchanged same-day protocol/libbox/NE facts; no behavior was rerun.

| Fixed row | Fact, inference and unverified boundary |
|---|---|
| Platform/architecture/minimum OS | **Fact:** Apple describes [SwiftUI apps](https://developer.apple.com/documentation/technologyoverviews/swiftui) for Apple platforms, including shared views for iOS/iPadOS/macOS/tvOS/visionOS; its [UI overview](https://developer.apple.com/documentation/technologyoverviews/app-design-and-ui) also names watchOS. **Inference:** this official route does not establish Android/AndroidTV/Windows/Linux UI coverage; those promised targets need separate UI/adapter work or a different later framework decision, never silent removal. **Unknown:** EasyNet supported architectures, per-API deployment availability, combined minimum OS, SDK compatibility and actual target builds. No old Xcode release note is used to infer a current application minimum. |
| Go service/native bridge/libbox | **Fact:** Apple documents [C/Objective-C interoperability](https://developer.apple.com/documentation/swift/imported-c-and-objective-c-apis), with C functions/types and imported Objective-C declarations. The [official libbox script](https://raw.githubusercontent.com/SagerNet/sing-box/testing/cmd/internal/build_libbox/main.go) declares gomobile bindings/XCFramework production, including macOS13/iOS15 minimum flags, as recorded in the related evidence. **Inference:** these can be bridge inputs; SwiftUI does not make a Go service, C ABI or libbox integration exist. **Unknown:** actual service IPC, memory/resource ownership across the boundary, API/ABI compatibility, artifact production and lifecycle. Script uses moving testing ref, no SHA/pin/build qualification. Go remains the service language; no business-policy duplication is selected. |
| Apple provider/process/entitlement/signing | **Fact:** [NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider) is a packet-tunnel provider extension class. [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment) distinguishes app-extension user context from system-extension global context; macOS packet tunnel app extensions are App Store only, while system extensions from10.15 support eligible direct Developer ID distribution. [Entitlement docs](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension) describe Network Extension capability/provisioning. **Inference:** a native SwiftUI host still requires a separate provider packaging/lifecycle/permission design. **Unknown:** selected provider form, team entitlement/profiles/signing, user consent, release acceptance and target behavior. GUI support grants no VPN entitlement or authority. |
| Android coverage/service lifecycle | **Fact:** Android's [VPN guide](https://developer.android.com/develop/connectivity/vpn) requires VpnService.prepare consent when needed, socket protection and native service/TUN lifecycle. **Inference:** SwiftUI's Apple UI description does not implement this path. **Unknown:** Android/TV UI strategy, service bridge, foreground/recovery behavior and device support; these stay in agreed scope pending later decisions. |
| Desktop TUN/privilege vs UI | **Fact:** Apple provider deployment varies with extension form/context and distribution, not the UI language. **Inference:** macOS native UI alone proves no TUN access; Linux/Windows require their own privilege/integration and UI solution. The existing Linux systemd client installer qualifies no native macOS app. **Unknown:** user-consent/installer/privilege flow, target architectures and real client connections. No helper, root/TUN action or system extension was launched. |
| Licenses/dependencies/release | **Fact:** the [Swift compiler repository license](https://github.com/swiftlang/swift/blob/main/LICENSE.txt) contains Apache2.0 and a Runtime Library Exception; the [sing-box repository](https://github.com/SagerNet/sing-box) states GPL3-or-later and an additional naming/association clause. **Inference:** compiler licensing does not establish SwiftUI/Apple SDK or complete application/dependency terms. **Unknown:** complete source/notice/dependency closure, SDK/distribution terms, reproducible artifacts, update ownership and release/signing gates. No compatibility or legal conclusion is made. |
| Four protocols/config formats | **Fact:** [current capability matrix](../../capability-matrix.md) retains Xray+Reality, Hy2, SS2022 and AmneziaWG; the wireguard directory is AWG. The related evidence links distinct upstream AWG/REALITY and generic sing-box outbound sources. **Inference:** a native UI does not settle engine parity or format compatibility; neither WireGuard nor a generic protocol list proves AWG/SS2022/current Xray transport qualification. **Unknown:** exact native-client imports/exports and live four-protocol parity. No engine selected or protocol dropped. |

## Retrieval and future qualification

Apple dynamic HTML/Markdown retrieval was limited; official indexed documentation
content supports the cited facts. Per-API minimum versions/architectures remain
unknown here. New primary sources are SwiftUI apps/UI overview, C/Objective-C
interop and Swift compiler license; NE/Android/libbox/protocol sources are reused
from same-day evidence. No framework version, deployment target or build pin selected.

A future single-host PoC must freeze SDK/toolchain/API availability and exact
UI-service ABI or IPC before building; record host/architecture/artifact/lifecycle.
Provider deployment, entitlement/signing and actual VPN acceptance need distinct
reviewed gates. All G0–G6 targets remain required; Apple-only evidence cannot close
non-Apple scope. Existing Bash/native runtimes/metadata1/CLI remain unchanged.

## Cost observation boundary

Main Sol medium executed this authorized frozen low-risk fact card; no subagent
was created. This and Flutter's Luna arm share seven headings but differ in sources,
platform scope, source reuse and models. They are related unpaired observations,
not a controlled experiment proving delegation or billing savings.
