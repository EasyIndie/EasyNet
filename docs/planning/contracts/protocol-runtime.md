# ProtocolRuntime example contract — draft v1

G0-03.1b reviewed research draft; design ADRs are accepted (see [index](README.md)). Native runtimes remain
independent of any management agent. No sing-box server replacement, controller
language, driver implementation or production capability decision is introduced.
Legacy metadata/manifest v1, discovery, pins and actual renderers stay unchanged.

An envelope has exactly `schemaVersion: 1`, nonempty `runtimes`, and `request`.
Each descriptor has exactly `runtimeId`, `protocolId`, `moduleId`, `capabilities`.
Runtime IDs identify an implementation; protocol IDs identify wire semantics;
module IDs bridge existing Bash plugin names. They occupy separate namespaces,
even when two values happen to match. Runtime IDs are unique in this envelope.

| runtimeId | protocolId | moduleId | Evidence boundary |
|---|---|---|---|
| `hysteria2-native` | `hysteria2` | `hysteria2` | Hysteria2 manifest source identity. |
| `amneziawg-native` | `amneziawg` | `wireguard` | AWG config/service identity despite legacy manifest protocol/type labels. |

Only these two tuples are in this bounded checker. AWG is neither native
WireGuard nor a sing-box native runtime/format. Existing compatibility renderer
labels are preserved and do not establish AWG native parity in those engines.
The current AWG sing-box renderer emits `empty` for incompatible native semantics
(source fact supplied by orchestrator); the legacy `wireguard` type is no evidence.
`exportSingboxNative` means faithful native semantics, not a legacy renderer path.
Native WireGuard and other runtime candidates need separate evaluation; #5's
closed/not_planned status does not authorize unified server migration.

Capabilities are exactly `describe`, `install`, `exportNative`,
`exportSingboxNative`, `nativeWireguard`. Each has exactly `state` (supported,
unsupported, unknown) and `evidence` (source-identity, format-boundary, unverified).
`describe` supported/source-identity describes the inspected manifest identity
only; install/exportNative unknown/unverified preserve missing live/driver evidence.
AWG nativeWireguard/exportSingboxNative must be unsupported/format-boundary.
Other example capabilities may remain unknown; nothing here certifies execution.

`request` has exactly `runtimeId`, `targetId`, `method`; IDs use strict ASCII
identifiers and methods use the callable subset below. targetId references the separate
ServerTarget contract; this checker does not resolve inventory, authenticate or
establish trust. The positive example requests only source identity description.
Unknown fields, duplicate runtime IDs, unknown methods and control characters fail.
Callable methods are describe/install/exportNative/exportSingboxNative;
nativeWireguard is a semantic compatibility flag and cannot be requested as a method.

Run `jq -e -f docs/planning/contracts/validate-protocol-runtime.jq` on the envelope.
Valid example description returns true/exit 0; malformed shape returns false/exit 1.
A syntactically valid unsupported request errors `capability-unsupported`; unknown
errors `capability-unknown` (both nonzero). No fallback or automatic execution is
permitted. Even supported requires later target preflight, trust and authorization.
This offline reference checker is not a full JSON Schema validator, importer,
native exporter or live acceptance result. Evidence enums are claims checked for
shape, not independently authenticated evidence. Broader methods, real native
config validation and lifecycle/security semantics require successor-contract review before production implementation.
