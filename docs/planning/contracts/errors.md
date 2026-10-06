# Error results — draft v1

G0-03.2c reviewed offline draft; design ADRs are accepted (see [index](README.md)). No runtime logging,
redaction, transport or controller implementation is claimed. Legacy metadata v1
and human logs remain unchanged. Event v1 still only carries `operation.snapshot`.

The independent typed result envelope has exactly `schemaVersion: 1`, `result`,
and `operation`. Result has exactly `binding`, `code`, `messageKey`, `nextAction`,
`origin`, `remoteOutcome`, `evidenceRef`. Binding has exactly operationId, targetId,
planHash with the [Operation v1](operation.md) restrictions. Unknown fields/versions
reject. Codes and semantics are stable within v1; incompatible changes require a
new version, never reuse a code for a different meaning.

| code | fixed nextAction | meaning |
|---|---|---|
| method-unsupported | revise-request | Method outside callable contract. |
| capability-unsupported | choose-supported-capability | Known unsupported capability; no fallback. |
| capability-unknown | verify-capability | Capability evidence missing; mutation blocked. |
| host-trust-required | verify-host-independently | Trust absent before authentication. |
| hostkey-changed | review-hostkey-change | Stop; independent host identity/rotation review required. |
| authentication-failed | review-credentials | Authentication denied before mutation dispatch. |
| permission-denied | review-permission | Required effective privilege absent/unknown. |
| preflight-failed | resolve-preflight | Required read-only preflight denied/unknown. |
| secret-unavailable | resolve-secret-reference | Credential/secret resolution unavailable. |
| remote-outcome-unknown | reconcile-same-operation | Dispatch may have occurred; outcome unresolved. |
| remote-failed | review-remote-failure | Authenticated remote terminal failure evidence required. |

`messageKey` is exactly `error.` plus code. Each key selects a fixed generic UI
registry template expressing the table meaning, with zero interpolated arguments.
No free-form message, raw upstream stderr/stdout, secret, token, URI, path or config
is permitted. Opaque identifiers are not proof of secret absence; producers must
never encode secrets in them. This checker is not a secret scanner or redactor.

The first nine codes require local-rejection/not-started, null operation and null
evidenceRef. The binding identifies rejected intent; not-started asserts this
request was rejected before dispatch, not that the target has no other work.
These codes cannot describe a post-dispatch disconnect/auth/permission error:
once dispatch is uncertain, use remote-outcome-unknown and retain ownership.
Remote-observation requires the original Operation envelope. Its immutable binding,
last remoteState and evidenceRef must match the result (unknown or failed).
Consumers MUST also validate that envelope with validate-operation.jq; this checker
alone does not certify transitions. If sourced from events, independently validate
Event framing and its Operation projection and match the complete history.
No synthetic failure event or local-rejection terminal snapshot is introduced.

There is no universal safe retry. hostkey-changed never autoaccepts or retries.
Unknown must reconcile the same operation/target/plan; still-running resumes
observation, still-unknown blocks replay. Only reconciled planned may permit retry
under Operation v1. Terminal failed never restarts that operation. nextAction is
human/planner guidance, not execution authorization. A receipt identifier still
needs trusted existence/authenticity/freshness/binding resolution; local errors
and exit codes never prove remote failure. Trust recovery, evidence resolution,
JSON duplicate-key detection and real acceptance remain unverified.
