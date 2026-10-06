# Application-service contract research baseline

These six draft-v1 artifacts are reviewed offline examples, not an implemented
controller, general production schema or proof of SSH/native-client acceptance.
Accepted design decisions: [Local-first](../adr/ADR-001-local-first.md),
[native runtimes](../adr/ADR-002-protocol-runtime.md),
[SSH-first](../adr/ADR-003-ssh-first.md).

| Contract | Scope | Example checker |
|---|---|---|
| [ServerTarget](server-target.md) | Inventory identity, endpoint, privilege requirement and credential refs | [jq](validate-server-target.jq) |
| [ProtocolRuntime](protocol-runtime.md) | Separate runtime/protocol/module identities and bounded capability claims | [jq](validate-protocol-runtime.jq) |
| [Profile](profile.md) | Native format descriptor and protected configuration reference | [jq](validate-profile.jq) |
| [Operation](operation.md) | Immutable operation/target/plan binding and interrupted-execution histories | [jq](validate-operation.jq) |
| [Events](events.md) | Complete sequenced snapshots; also validate the projected Operation history | [jq](validate-events.jq) |
| [Errors](errors.md) | Fixed safe codes/actions; also validate any embedded Operation | [jq](validate-errors.jq) |

Each document links its examples and explains checker limits. The corresponding
Bats tests are in `tests/test_*_contract.bats`. Event/Error framing alone cannot
validate state transitions or certify a remote outcome. Reference syntax does not
resolve credentials, inventory or authenticated receipts; duplicate JSON keys
are not detected by these jq checkers.

Before implementing production adapters, follow ADR-002: freeze and review a
successor contract with method/format/target/live-evidence dimensions, inputs,
effects, permissions and migration behavior. Do not copy the two-runtime example
registry or permanently unknown exporters into a production capability registry.
Language, store and client engine choices remain G0-04/05/06 work. Existing Bash,
metadata v1, human logs and native backends remain compatible.
