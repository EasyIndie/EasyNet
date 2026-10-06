# ADR-001 — Local-first application-service boundary

- Date: 2026-10-06.
- Status: accepted-for-evolution-design; accepted by root review on 2026-10-06.
- Scope: G0-03.3a; joint review of G0-03.1a–c/2a–c draft v1 and capability baseline v1.
- This accepts the reviewed design direction only. It does not certify a
  controller, importer, credential store, remote executor or production security.

## Context

EasyNet currently provides Bash deployment, the existing `easynet` CLI, protocol
plugins, metadata v1, Edge/TLS and subscription consumers. The six new contracts
are bounded offline research artifacts. Their checkers accept restricted JSON
values; their evidence does not establish live capability or execution authority.
The [roadmap](../product-evolution-roadmap.md) calls for user-owned servers and
credentials, an Existing Server entry point and no required central account.

## Accepted design decision

1. Put lifecycle policy in shared application services. Future management CLI
   and GUI call the same service boundary for capability checks, target lookup,
   plan/authorization handling, operations and results. GUI must not construct
   shell commands or implement a second transition/authorization policy. This
   specifies a logical boundary, not a daemon, IPC protocol or core language.
2. Keep inventory and operation journal on the user's device by default. A
   separately reviewed device credential/configuration store resolves opaque
   references. Host trust is separate device security state. Importing inventory
   cannot enroll trust, grant cloud ownership or authorize an action. Local-first
   means no required platform account or central control plane; it does not mean
   installation, upgrades, SSH, subscriptions or Provider APIs work offline.
3. Preserve existing Bash deployment and metadata v1 through future adapters.
   The new inventory/journal contracts do not replace metadata or reinterpret
   legacy human logs as typed events. Existing secret-bearing metadata and CLI
   consumers remain compatible; existing mode-600 state and `.env` requirements
   remain. This ADR does not claim retrospective redaction or a completed migration.
4. Use SSH as the initial server-management path without a mandatory management
   agent. ExistingServer and CloudServer converge at the same target boundary.
   Optional Provider API lifecycle operations remain distinct from SSH deployment.
   Detailed SSH trust, credential and optional Agent decisions belong to ADR-003;
   this decision grants no connection, privilege or resource-operation authority.
5. Deployed native backends must run independently of the controller, GUI,
   project website/API and optional management agent. Controller failure stops
   observation/management and can leave an unknown operation; it must not require
   stopping the backend or VPN data plane. A client VPN session on the local
   device has its own lifecycle. Backend independence is a future acceptance
   requirement, not live proof supplied by these fixture checks.

## Shared identities and boundaries

| Entity / draft | Identity and responsibility |
|---|---|
| [ServerTarget](../contracts/server-target.md) | `id` names an inventory target; `kind` describes its origin. SSH host/user, cloud resource IDs and account names do not prove trust, ownership or effective privilege. `credentialRef` names separate credential material. |
| [ProtocolRuntime](../contracts/protocol-runtime.md) | `runtimeId`, `protocolId` and legacy `moduleId` occupy separate namespaces. Descriptors express bounded capability claims; `targetId` must resolve a ServerTarget before use. Unsupported/unknown capability blocks execution without fallback. |
| [Profile](../contracts/profile.md) | Stable `id` plus `revision`; `targetId` references ServerTarget. Runtime/protocol/format tuples must agree with ProtocolRuntime. `endpoint` is a client destination, not necessarily the SSH host. `configRef` resolves separately bound secret configuration. |
| [Operation](../contracts/operation.md) | `operationId` is permanently bound to `targetId` and `planHash`. A hash is neither approval nor a trusted receipt. Local observer state is separate from remote outcome; a changed plan/target needs a new operation ID. |

Identifiers that happen to have equal text do not merge these namespaces.
Future application services must resolve typed references and refuse absent,
mismatched or unavailable targets, credentials, configs and evidence before use.
Profile configuration must bind to the exact target/runtime/protocol/format/revision.
The offline checkers do not perform these lookups. AWG's legacy `wireguard` module
name does not establish native WireGuard or sing-box native parity; native export
remains unknown for the bounded runtime examples.

Ordinary inventory, snapshots, events and error results contain references rather
than credential/native-config/URI payloads. The journal must not turn raw human
logs or stdout/stderr into automation evidence. Opaque syntax cannot prove that a
producer did not hide a secret in an identifier. Device storage implementation,
protection, secret lifecycle and export channels require subsequent reviewed work.

## Operations, events and errors

[Event v1](../contracts/events.md) carries only `operation.snapshot`, reusing all
seven Operation fields. Consumers validate both event framing and its complete
Operation-history projection. Sequence starts at one, is contiguous and rejects
duplicates; v1 provides no suffix replay or deduplication. A valid nonterminal
prefix is an admissible record of the reported history, not completed execution.
Future journals must preserve this distinction and recover the same full binding.

[Error v1](../contracts/errors.md) is an independent typed result, not a new event
or a second state machine. The first nine codes identify a rejected intent before
dispatch, with null Operation/evidence. After uncertain dispatch, even a local
authentication/permission/disconnect error must use `remote-outcome-unknown`,
retain ownership and reconcile the original operation. `remote-failed` requires
the matching failed terminal history and receipt. Validate its embedded Operation
independently; event-sourced results must also match the validated complete history.
Fixed message keys have no interpolated arguments, and `nextAction` grants no
execution authority or universal safe retry.

For future CLI and GUI execution, same-target mutations require one remote owner
bound to operation ID and plan hash. A second mutation is rejected or queued before
execution. Local disconnect/exit and cancel-request cannot release that owner;
unknown retains it until reconciliation. Cancellation is intent until trusted
remote confirmation. Still-running resumes observation, still-unknown blocks
replay, and only reconciled planned may permit retry of that exact plan. Confirmed
terminal states absorb later observation and never restart the same operation.
Only a confirmed terminal outcome releases ownership. Separate targets may be
independent. A device journal alone cannot provide remote exclusion across
processes/devices; atomic acquisition/release, durable ownership, idempotency and
crash recovery remain G1-07 work. No such mechanism is implemented here.

Every claimed remote conclusion requires a future trusted receipt resolver that
checks existence, authenticity, freshness and binding to operation/target/plan/
outcome. A well-formed receipt reference can pass all offline checks while being
fake. Neither a terminal snapshot, a local process exit nor two passing checkers
is completion authority. Imported inventory, capability evidence enums and plan
hashes similarly cannot substitute for independent trust and authorization.

## Alternatives considered

| Alternative | Disposition and tradeoff |
|---|---|
| Required central account/control plane | Not the default design: introduces a required authority/availability dependency contrary to user-owned recovery. Optional sync/team candidates still need explicit later disposition. |
| Separate CLI/GUI lifecycle implementations | Rejected as the evolution design: duplicates trust, retry and cancellation policy. Shared services require adapter/API consistency work. |
| Mandatory remote management agent | Not the initial baseline: adds bootstrap/security/lifecycle obligations. Optional Agent evaluation remains ADR-003/G4-06 work; native backends remain independent. |
| Replace Bash or choose a controller/GUI/VPN framework now | Deferred: compatibility adapters preserve existing behavior while ADR-004 and later platform evaluations collect implementation evidence. |
| One store containing inventory, trust and raw secrets | Rejected as the logical model: copied inventory must not confer trust or credentials. Physical storage technology and access controls remain ADR-005; backup format/protection remains ADR-006. |

## Review outcome and acceptance limits

No must-fix inconsistency was found between the six documents in this bounded
Local-first review. The Operation/Event/Error checker and test composition agrees
with their documented validation scopes; no dependency correction is requested.
The proposed separation can therefore be accepted as an evolution design while
preserving every unimplemented security/lifecycle obligation above.

Target/reference resolution, duplicate JSON-key rejection, receipt authenticity,
approval enforcement, SSH argument safety/trust rotation, effective root/sudo
preflight, remote exclusion/recovery, cloud ownership and real target/native-client
acceptance remain unimplemented or unverified. An allowlist is neither a secret
scanner nor a production importer. Fail-closed runtime enforcement must be reviewed
before these drafts become execution interfaces.

This ADR chooses no controller language, store engine, GUI, VPN engine, backup
format, new protocol runtime or production platform support. Those decisions and
candidate features remain in their assigned cards/ADRs. All agreed G0–G6 scope,
candidate dispositions and final acceptance remain required before proposing the
single final merge into main, per the [execution policy](../agent-execution-policy.md).
