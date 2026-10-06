# ADR-003 — SSH-first management; Agent requires a later evidence gate

- Date: 2026-10-06.
- Status: accepted-for-evolution-design; accepted by root review on 2026-10-06.
- Scope: G0-03.3c; six reviewed draft-v1 contracts, capability baseline v1 and
  accepted [ADR-001](ADR-001-local-first.md) / [ADR-002](ADR-002-protocol-runtime.md).
- This is a security/lifecycle design disposition, not implemented SSH transport,
  runtime acceptance, root permission or authorization for a VPS operation.

## Initial management decision and existing behavior

Use SSH as the initial server-management transport for ExistingServer and
CloudServer, without a mandatory management Agent or central account. Provider
API resource lifecycle remains a separate boundary. Shared application services
enforce trust, credentials, capability/preflight, approved plans and Operations;
the Bash compatibility driver reuses existing deployment behavior only after those
gates. Preserve existing native runtimes, metadata v1, CLI and consumers.

The current [`scripts/easynet`](../../../scripts/easynet) `cmd_ssh` calls the local
hardening script's `status`; it is not remote transport or host-trust enrollment.
The current [`scripts/deploy.sh`](../../../scripts/deploy.sh) `main` loads env,
checks root/OS and runs system/security bootstrap before module selection. It does
not establish the future independent remote preflight/approval boundary. This ADR
changes neither script and certifies no zero-side-effect deployment preflight.

Native backend services must continue running if the local manager, optional
Agent, project website/API or observation connection disappears. SSH remains the
recovery path; a failed SSH link may prevent recovery until connectivity is
restored, but must not itself stop the VPN backend. Local VPN client sessions
have their own lifecycle. These properties require later acceptance evidence.

## Host trust before authentication

Host trust is separate device security state, established independently of
inventory import. ServerTarget ID, DNS/IP, cloud resource ID and `credentialRef`
are not host-key proof. Importing a target must never import a fingerprint,
known-hosts entry, accepted trust decision or cloud-operation authority.

First connection must display the target endpoint, observed host-key identity/
fingerprint and its verification status in the trusted local UI. It requires an
explicit user confirmation before recording first-use trust or authenticating;
background jobs and imported data cannot perform that confirmation. The user
should compare the fingerprint through an independent trusted source. An explicit
TOFU choice establishes first-use trust, not proof that the initially observed
server was authentic; the implementation must distinguish it from independently
verified identity and must not claim stronger assurance without evidence.
The user-authorized trust ceremony is independent of the inventory and transport's
mere observation; observed keys alone are never accepted trust.

A known-key match may proceed subject to all other gates. A changed key must
stop before authentication, preserve the previous trust record and return
`hostkey-changed` for a pre-dispatch rejection. Re-enrollment/rotation requires
independent host verification and an explicit reviewed replacement decision;
retry, inventory reimport, deleting a known-hosts entry or accepting the new key
automatically is not recovery. Endpoint changes require fresh identity evaluation,
not reusing trust solely because target ID remains the same. No trust enrollment
or rotation implementation is accepted here.

The future SSH CLI/library adapter must enforce this policy. It must not default
to `StrictHostKeyChecking=no`, automatic first-use acceptance, discarded known-hosts
state, or an equivalent verification bypass. Raw endpoint/user/reference inputs
must not become shell fragments or arbitrary SSH options; restricted argument,
command, timeout and output-limit contracts need separate tests/security review.

## Credentials and privilege are separate gates

Prefer user-controlled SSH keys or a local signing agent through opaque
`credentialRef`. A separately reviewed device store resolves it; inventory,
Operation journal, typed events/errors and automation logs contain no private
key/password/token/path/native-config payload. A syntactically valid reference is
not existence, ownership or absence-of-secret evidence. Resolution must bind to
the intended target/user/action and occur only within the trusted connection flow.
Do not forward a signing agent to the remote host by default; broader delegation
requires its own explicit trust/security review.

Later lifecycle contracts must cover provisioning/import, access permissions,
locked/unavailable stores, agent/key expiry, replacement/revocation and user-owned
recovery access. Never overwrite an existing key, enroll remote authorization or
change SSH accounts/policy as an implicit credential-resolution fallback. Secret
rotation and host-key rotation are distinct decisions. Existing `.env` mode 600
and legacy metadata compatibility remain; new refs do not redact historical output.

Target privilege declares a requirement, not proof. `effective-root` requires
observed remote EUID 0, not an account named root. Explicit `sudo` requests only
the noninteractive reviewed route to EUID 0 for the bounded approved action;
verify the effective privilege and permitted command route with read-only probes.
Permission to run one root probe does not prove permission for an arbitrary
deployment script. No password prompt, fallback escalation or automatic sudo-policy
change is authorized. Least privilege and the full approved script's effects must
be reconciled in the implementation review; this ADR grants no root execution.

Before any Bash bootstrap/deployment, perform independent read-only target
preflight: required OS/release/architecture, privileges, services/ownership,
resources, ports, DNS/firewall and runtime-specific facts. It must not install
packages, rewrite configs, change firewall/SSH policy or start/restart services.
Unknown required facts or unsupported capability block mutation. Separate observed
facts from live support claims; a local socket cannot prove public UDP reachability.
Plan construction includes bootstrap's effects, selected runtime, prerequisites
and ownership, then explicit scoped approval and execution-time fact revalidation.
A passed preflight or plan hash alone grants no execution authority.

`targetId` is only an inventory namespace. Before G1-09 production execution,
the reviewed plan contract must bind resolved SSH host/port/user, credential and
privilege references/policies, host-trust identity and relevant observed facts to
the approved plan/hash. Changing any of those under the same target ID invalidates
approval and requires a new reviewed plan; merely comparing targetId or opaque
hash syntax is insufficient. Preserve an unresolved operation's original binding,
rather than redirecting reconciliation to a changed target. Snapshot v1 checks
hash syntax only and supplies neither this approval validation nor receipt trust.

Approved staging/upload needs restricted paths, safe temporary-file handling,
permissions, integrity/version checks and cleanup/recovery contracts. Do not pipe
unverified downloads to a privileged shell. Read-only collection, staging and
mutation must remain distinguishable in authorization and evidence.

## Operation authority and interrupted execution

Every mutation binds the approved plan hash and target to one immutable operation
ID. Before dispatch, remote ownership/locking must atomically reject or queue
competing same-target mutations. Device-local journal/lock state alone is
insufficient across processes/devices. Approval enforcement, durable remote
ownership, idempotent requests and crash recovery remain unimplemented.

Disconnect, local process exit and cancel-request cannot release remote ownership
or certify a remote outcome. Unknown retains ownership until reconciliation of the
same operation/target/plan. Still-running resumes observation; still-unknown blocks
replay; only reconciled planned may permit retry of the exact plan. Cancellation
records intent until trusted remote confirmation; terminal outcomes never restart
that operation. Only confirmed terminal evidence releases the remote owner.

Error v1's local trust/authentication/permission/preflight/secret codes apply only
when this intent is rejected before dispatch. Once dispatch may have occurred,
report `remote-outcome-unknown`, retain ownership and reconcile; do not synthesize
local failure/cancellation or auto-retry. A changed host key during recovery also
blocks connection: retain the unresolved operation while independently resolving
trust. Neither the trust error nor reconnection can authorize replay.

Validate Event framing and its full Operation projection, and Error binding plus
embedded Operation independently. Receipt refs need future trusted resolution of
existence/authenticity/freshness/operation-target-plan-outcome binding. CLI exit 0,
stdout/stderr, remote service active and a well-formed receipt identifier are not
proof of completed deployment or client connectivity. Typed automation records
do not replace legacy human logs or allow raw secret-bearing messages.

## Later gates; none is completed by this ADR

| Boundary | Required task/review evidence |
|---|---|
| Credential references and lifecycle | G1-02.1–3: reviewed store/fake/platform adapters, key/agent binding and failure/export cases; storage/backup choices stay ADR-005/006. |
| First-use/known/changed-key trust and safe SSH | G1-03.1–3: explicit enrollment/assurance semantics, key matching/rotation refusal, constrained execution/timeouts/output and cancellation/disconnect fixtures; security review required. |
| Effective privilege and protected staging | G1-04.1–3: EUID/noninteractive sudo classification, approved-command/path restrictions, upload integrity/permissions and cleanup evidence. |
| Independent preflight and compatible plan | G1-05/06 and G1-09.1–3: read-only collectors, unknown/ownership rules, resolved target/trust/credential/privilege fact binding, approval invalidation/revalidation and BashDriver approval enforcement; preflight failure causes no configuration mutation. |
| Remote ownership, recovery and evidence | G1-07.1–3: persistence, locks/idempotency and reconciliation/cancel tests; trusted receipt-resolution/approval contracts reviewed before execution. |
| Secret-safe automation and staged scripts | G1-08/G1-10: typed/redacted outputs, protected export and pinned/checksummed staging; no full security claim from shape tests. |
| End-to-end/live acceptance | G1-14: isolated SSH faults plus separately authorized target acceptance, including changed key, repeat requests, interruption and compat regression. |
| Optional Agent decision | G4-06.1–3: evidence that SSH management is insufficient, authenticated independent-service PoC and explicit accepted implementation or not-applicable ADR disposition. |
| Agent independence and SSH rescue | If Agent is accepted, G4-07.1–3: reviewed minimal API, same-operation SSH rescue, uninstall/manager-loss evidence that native backend remains running; otherwise explicit not-applicable evidence. |

## Alternatives and disposition

Mandatory Agent/central management is not selected for the initial design; its
security, installation and lifecycle cost requires G4-06 evidence. An optional
Agent cannot carry VPN data traffic, replace native backend ownership or bypass
shared Operations/SSH recovery. Authentication/installation still need that gate.

Automatic host-key acceptance, blanket implicit sudo, direct GUI shell commands
and treating local SSH exit as remote completion are rejected design alternatives.
No must-fix draft inconsistency was found; unimplemented trust/reference/duplicate-
key/receipt/exclusion mechanisms remain later work, not certified by fixture checks.

No language/store/GUI/VPN engine/target is selected and no SSH/root/cloud/main action
is authorized. Full G0–G6 scope, candidate dispositions and final acceptance precede
the single main merge proposal, per the [execution policy](../agent-execution-policy.md).
