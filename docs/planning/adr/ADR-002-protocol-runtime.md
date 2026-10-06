# ADR-002 — Preserve native runtimes behind explicit driver contracts

- Date: 2026-10-06.
- Status: accepted-for-evolution-design; accepted by root review on 2026-10-06.
- Scope: G0-03.3b; G0-03.1a–c/2a–c draft v1, capability baseline v1 and accepted
  [ADR-001](ADR-001-local-first.md).
- Acceptance concerns the architecture and extension gates below, not a complete
  production driver interface, runtime migration or target support certification.

## Context and accepted design decision

Keep the four existing native server implementations and Bash deployment/plugin
boundaries: Xray, Hysteria2, Shadowsocks-rust and AmneziaWG. A future ProtocolDriver
adapts their lifecycle and export behavior into shared application services;
backends remain independently running services. Preserve manifest/metadata v1,
the existing CLI, Edge/TLS and subscription consumers. This does not declare Bash
the controller language or change any existing service, renderer, pin or package.

Initial management follows ADR-001's Local-first/SSH baseline. ProtocolDriver
owns runtime-specific install/configuration/lifecycle/export/health behavior;
ProviderAdapter owns cloud resource lifecycle; VPNEngine owns local client
connection behavior. Shared application services own target resolution, trust/
authorization gates and Operation handling. A driver may not silently bypass
these gates, select a different protocol, or infer authorization from metadata.

The [roadmap](../product-evolution-roadmap.md) records issue #5 as closed /
not_planned; that repository decision is retained. It is context for runtime
evolution, not an instruction to migrate servers to sing-box. Hysteria2 is the
first planned management closure, not authorization to remove the other runtimes.

## Identity and native-format boundaries

| Source / draft identity | Preserved boundary |
|---|---|
| Hysteria2; module `hysteria2` | Existing manifest selects `hysteria-server.service`. Draft `hysteria2-native` / protocol `hysteria2` / format `hysteria2-native-config` names the proposed native descriptor tuple. |
| AmneziaWG; legacy module `wireguard` | Manifest display/config/service identify AWG and `awg-quick@wg0`, despite legacy `wireguard` labels. Draft `amneziawg-native` / `amneziawg` / `amneziawg-native-config` must retain AWG semantics. |
| Xray; module `xray-reality` | Manifest names service `xray` and protocol/type `vless`. Concrete transport/security semantics must accompany later driver/profile contracts; a type label alone does not describe REALITY/XHTTP capability. |
| Shadowsocks-rust; module `shadowsocks` | Manifest names `shadowsocks-rust-server`; protocol/type aliases `ss` and `shadowsocks` remain compatibility labels. Later native profiles must bind actual method/key semantics. |

`runtimeId`, `protocolId`, `moduleId` and Profile format are distinct namespaces.
New Xray/SS production runtime IDs are not selected here. Native payloads are
separately protected configuration, resolved through Profile `configRef` and bound
to target/runtime/protocol/format/revision. A passing Profile descriptor neither
resolves that payload nor proves export implementation or a working connection.

AWG is not native WireGuard. The repository's AWG `render_singbox.jq` currently
emits `empty`, intentionally omitting AWG from sing-box subscriptions; this matches
the documented client boundary. Legacy renderer/type labels confer no native
parity. Draft AWG `exportSingboxNative` and `nativeWireguard` are unsupported.
Native WireGuard has a separate G4-02.3 evaluation; future format parity needs
explicit reviewed evidence for the selected pinned implementation. This review
does not establish current upstream support beyond the inspected repository.

## Capability dimensions and evidence

Future capability reporting must distinguish these questions, even if the public
result combines them for a particular request:

| Dimension | Evidence needed / interpretation |
|---|---|
| Driver method implementation | The selected driver/version implements the method and its stated inputs, effects and result contract; focused behavior/error tests establish that bounded claim. Existing Bash source entry points alone do not certify the new adapter. |
| Protocol/format semantics | Exact runtime/protocol/transport/format tuple and required options are faithfully represented; native/pinned client validation checks the exported payload. A renderer name or syntactically valid JSON is insufficient. |
| Target eligibility | Read-only facts for the selected host: OS/release, architecture, privileges, ownership, services, ports and required kernel/packages/TLS/UDP conditions. Unknown facts block applicable mutation; they are not unsupported by inference. |
| Live acceptance | A matching runtime/version/configuration/OS/architecture target and client acceptance report. Fixture, source identity and target preflight results cannot substitute for this result. |

`supported` is always scoped to the dimension and evidence actually established.
A working install adapter can have supported method implementation while live
platform acceptance remains unknown. Conversely, source-identity support for
`describe` grants no install/export/mutation ability. An unsupported required
method/format refuses with `capability-unsupported`; missing required capability
evidence refuses with `capability-unknown`. Neither permits fallback. Execution
additionally requires resolved target/secrets, trusted SSH, effective privilege,
read-only preflight, approved plan and Operation ownership. A capability flag is
not authority, and capability evidence claims need validation by the consumer.

Live support unknown is a limit on published support claims, not a permanent ban
on explicitly authorized, scoped test acceptance. Such acceptance requires its
own frozen target/action/plan authorization and all safety prerequisites; unknown
method implementation or incompatible semantics cannot be bypassed as a test.
No such execution is authorized or performed by this ADR.

## Draft v1 is a bounded fixture, not the future production interface

All six jq checkers cover restricted example contracts. ProtocolRuntime v1 accepts
only Hysteria2/AWG tuples and four callable names, fixes install/exportNative to
unknown, and allows only source-identity/format-boundary/unverified evidence.
`nativeWireguard` is a compatibility flag, never a callable method. Profile v1
accepts two descriptor tuples while both native exporters remain unknown.
Operation/Event/Error cover one operation history and typed framing/results;
none is a production importer, native payload validator or security implementation.

These restrictions correctly freeze the current research evidence. They cannot
represent an implemented install/export method or broader lifecycle interface.
Therefore **do not use this checker unchanged as a production capability registry,
hardcode install/exportNative unknown forever, or merely relax its unknown checks
while retaining source-identity as mutation evidence**. No generic production
schema or complete lifecycle API is accepted by this ADR.

Before an adapter uses a broader tuple, method or evidence kind, the responsible
ready card must freeze and review a successor contract: exact identity/format,
method inputs/effects/permissions, read-only versus mutation classification,
typed results, evidence scope/provenance and failure semantics. Incompatible
versions/vocabularies need a new version or separately versioned interface; v1
consumers continue rejecting unknown fields/types/methods. Explicit migration and
old-consumer compatibility tests accompany extensions, rather than silent widening.
Method implementation and live-support evidence must be expressible independently.
Changes to trust, secret access, destructive effects or operation ownership require
security review before execution. Preserve the frozen fixtures as research evidence.

Mutation methods reuse immutable Operation identity/plan binding, same-target
ownership, disconnect/unknown reconciliation and cancellation-as-intent. Event
framing plus Operation validation and Error binding checks remain complementary.
Receipt syntax/local exit is not proof of completion; a future trusted resolver
must authenticate remote evidence. Read-only health must distinguish service
active, protocol/client connectivity and unknown reachability rather than collapse
them into one success. Export uses a protected channel, not automation logs/events.

## Implementation and acceptance gates

- G1-09.3 binds BashDriver to plan/ownership/approval; G1-11.1–3 implements
  Hysteria2 install/config/start/restart/health with explicit method contracts.
- G1-12.1–3 implements protected native Hysteria2 export and format correspondence;
  G1-13 validates pinned real clients; G1-14 supplies fixture and authorized target
  acceptance. New rendering requires those client checks, not string assertions.
- G4-01 expands Xray/SS drivers/profiles and client transport acceptance;
  G4-02 expands AWG native/kernel/PPA evidence and separately decides native WG.
  Broader lifecycle/adoption methods require their own reviewed successor contracts
  and scoped acceptance before advertising support or dispatching them.

These are later task gates, not completed work or automatic unlocks. Target/ref
resolution, duplicate JSON-key rejection, secret safety, receipt authenticity,
remote locks/recovery and real support remain unimplemented/unverified here.

## Alternatives and review outcome

| Alternative | Disposition / tradeoff |
|---|---|
| Replace all native servers with sing-box | Not selected. Would require explicit runtime/feature/client parity and migration/rollback evidence; issue #5 grants no such authority. |
| Treat module/type aliases as native parity | Rejected: conflates protocol, implementation and export semantics, notably AWG/WG. |
| Direct GUI shell lifecycle commands | Rejected under ADR-001: bypasses shared capability/plan/operation policy. |
| Freeze the example checker as the complete driver API | Rejected: cannot express implemented methods or future lifecycle/evidence scopes. Reviewed extensions are required. |

No correction to the current bounded research contracts is required for this
design disposition. Their inability to express production methods is explicitly
retained as a future implementation prerequisite, not certified away. This ADR
chooses no language, GUI, VPN engine or management Agent. Full G0–G6 scope and
candidate dispositions remain required before the single final main merge.
