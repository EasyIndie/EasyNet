# Application-service events — draft v1

G0-03.2b offline draft, pending joint ADR/high review. Existing human logs are
unchanged; stdout/stderr and local SSH process exit are not automation events.
An envelope has exactly `schemaVersion: 1` and a nonempty `events` array for one
operation. Each event has exactly `seq`, `type`, `payload`:

| Field | Restriction |
|---|---|
| `seq` | Integer 1–9007199254740991, starts at 1, increments by exactly one. |
| `type` | Only `operation.snapshot` in v1. |
| `payload` | Exactly the seven snapshot fields and string/null restrictions in [Operation v1](operation.md). |

The payload reuses Operation identity, states, actions and receipt reference
semantics without adding another state machine. `operationId`, `targetId` and
`planHash` stay fixed across the whole stream. No raw stdout/stderr, free-form
message, secret, native config, URI, timestamp, arbitrary metadata or unknown
field is allowed at either level. Receipt references are opaque identifiers,
not paths or URLs. String restrictions use strict \A/\z and reject controls.
Allowlisting cannot detect a secret disguised as a syntactically valid identifier;
producers must never put secrets in identifiers or references.

Consumers must validate both framing with `validate-events.jq` and the projection
`{schemaVersion: 1, history: [.events[].payload]}` with `validate-operation.jq`.
Both must pass before a history is admissible. The event checker checks shape,
identity and sequence only; Operation owns initial state and legal transitions.
A framing pass alone cannot establish a legal state history or completion.

Replay must supply the complete prefix starting at seq 1 for the same immutable
binding. Reordering, gaps, mixed identities, conflicting duplicates and exact
duplicates are all rejected; v1 does not deduplicate. A consumer receiving an
uncertain/incomplete stream cannot certify completion and must obtain a complete
prefix and reconcile the same operation before retry, per Operation v1. Empty or
partial suffix replay fails. A contiguous prefix ending planned/running/unknown
can be admissible but is not complete. Cancellation request and local exit do
not establish remote cancellation or success.

Every terminal snapshot needs a non-null receipt reference. Even two passing
checkers and a terminal snapshot are only candidate evidence: a future trusted
resolver must verify receipt existence, authenticity, freshness and binding to
operation/target/plan/outcome. Reference syntax does not authenticate a receipt;
this draft creates no attestation, remote executor, durable replay store or
completion authority. Receipt resolution remains unverified.

Forward compatibility is conservative: unknown schema versions, event types or
fields reject, rather than being skipped and hiding a missing state transition.
Future types/version migrations need an explicit contract. Error-code registry
and error payload bindings belong to G0-03.2c; v1 defines no such binding here.

`events.examples.json` provides valid and invalid envelopes. Each `.valid[]` must
pass both checkers; each `.invalid[]` must fail at least one. Boolean true/exit 0
means acceptance only in the checker's stated scope. JSON duplicate-key detection,
production transport, secret-store access and real target acceptance are outside
this offline fixture checker.
