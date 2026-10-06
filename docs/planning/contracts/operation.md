# Operation identity and transitions — draft v1

G0-03.2a offline draft, pending joint ADR/high review; no production state engine.
The envelope has exactly `schemaVersion: 1` and nonempty `history`, describing
one mutation operation against one ServerTarget. Snapshots have exactly these fields:

| Field | Meaning / restriction |
|---|---|
| `operationId`, `targetId` | Stable ASCII identifier, letter then 0–63 letters/digits/underscore/hyphen. |
| `planHash` | `sha256:` plus 64 lowercase hex digits; binds the approved plan, not proof of approval. |
| `remoteState` | `planned`, `running`, `unknown`, `succeeded`, `failed`, `cancelled`. |
| `localState` | `connected`, `disconnected`, `exited`; local observer/SSH process only. |
| `action` | `create`, `start`, `observe`, `disconnect`, `local-exit`, `cancel-request`, `reconcile`, `retry`. |
| `evidenceRef` | null or opaque `receipt_` plus 1–64 ASCII letters/digits/underscore/hyphen. |

`planned` is intent awaiting remote execution, not a proven remote mutation.
`unknown` means remote outcome is unresolved, not failure. Terminal states are
`succeeded`, `failed`, `cancelled`. A local SSH disconnect/process exit never proves
remote success, failure or cancellation; it sets unresolved nonterminal state to
`unknown`. Remote work may continue. Cancel-request records intent only, even if
transmitted; only remote evidence can establish confirmed `cancelled`.

Initial snapshot is planned/connected/create with null evidence. Allowed subsequent
transitions (all others reject; local state connected unless explicitly stated):

| action | remote state before → after | evidence / local restriction |
|---|---|---|
| start, retry | planned → running | Non-null receipt reference; retry requires immediately preceding reconcile to planned. |
| observe | running → running/succeeded/failed/cancelled; terminal → same terminal | Non-null receipt reference. |
| disconnect, local-exit | planned/running/unknown → unknown; terminal → same terminal | local disconnected/exited respectively; null for unknown, retain terminal receipt. |
| cancel-request | running → running; unknown → unknown | Retain previous local state and evidence; request alone proves nothing. |
| reconcile | unknown → planned/running/unknown/succeeded/failed/cancelled | Connected and non-null receipt reference. |

Reconnect queries the same operation before any retry; reconciliation showing still
running resumes observation, unresolved unknown blocks retry. Reconciled planned
means evidence that execution did not start and a retry is safe for this exact plan.
Failed/cancelled/succeeded never resurrect, even after reconnect. Repeating an initial
start is invalid. A subsequent approved plan needs a new operation ID, not history
rewriting. operationId/targetId/planHash are immutable in every snapshot: neither a
changed hash nor a new target may replace the binding under the same operation ID.

A terminal conclusion needs an explicit receipt reference tied by a future trusted
resolver to this operation, target, plan and remote outcome. The reference checker
checks only syntax and transition placement, not receipt existence/authenticity,
freshness, remote execution, approval or binding inside a receipt. A fake well-formed
receipt can pass; consumers must refuse unresolved/mismatched evidence. No raw stdout,
URI, secrets, native configuration or paths belong in these ordinary records.
Restricted strings use strict \A/\z matching, including control suffix rejection.

Same-target mutations must have one remote owner identified by operationId/planHash.
A second mutation is rejected or queued before execution; disconnect, local exit and
cancel-request must not release ownership. Unknown retains ownership until reconcile;
only a confirmed terminal outcome releases it. Different targets may be independent.
Remote locking, atomic acquisition/release, queueing, durable ownership, idempotent
request handling and crash recovery are future G1-07 work, not implemented or verified
by this single-history checker. Target resolution, secret-store binding and metadata
v1 CLI/protocol consumers remain unchanged. Event schemas/error codes are later cards.

`operation.examples.json` contains positive and negative offline histories. Extract
one `.valid[]` or `.invalid[]` envelope, then run `jq -e -f validate-operation.jq`:
true/exit 0 accepts the draft, false/nonzero rejects. This is not a duplicate JSON-key
checker, secret scanner, live acceptance or production importer.
