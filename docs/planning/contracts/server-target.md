# ServerTarget example contract — draft v1

G0-03.1a research artifact, reviewed by Sol high; design ADRs are accepted (see [index](README.md)). This is a proposed
controller inventory contract, not an implemented controller or accepted ADR.
It preserves legacy module metadata v1 and all existing CLI/protocol consumers.

The document envelope has exactly `schemaVersion: 1` and a nonempty `targets`
array. Each target has a unique `id`, `kind`, `ssh`, `credentialRef`, `privilege`,
and, only for CloudServer, `cloud`. Unknown fields are rejected at every level.

| Field | Draft example restriction / meaning |
|---|---|
| `id` | 1–64 ASCII letters/digits/underscore/hyphen, starting with a letter; inventory identity only. |
| `kind` | `ExistingServer` or `CloudServer`; both share the same SSH connection boundary. |
| `ssh` | Exactly `host`, `port`, `user`; host is a DNS name or canonical IPv4, port integer 1–65535, user a restricted ASCII account name. |
| `credentialRef` | Opaque `cred_` identifier; a separate device credential store resolves it. No password, key, token, path, or credential material belongs in inventory. |
| `privilege` | `{ "mode": "effective-root" }` or `{ "mode": "sudo", "sudoPolicy": "noninteractive-root" }`; no implicit escalation. |
| `cloud` | Exactly `provider`, `resourceId` opaque identifiers; required for CloudServer and forbidden for ExistingServer. |

Every restricted string uses strict whole-string matching, rejecting LF/CR.
IPv4 requires exactly four decimal octets in 0–255 with no leading zero except
`0` itself; numeric or hex-form dotted hosts must pass IPv4 validation, never DNS fallback.
IPv6, internationalized names, SSH aliases and proxy/jump configuration remain
explicitly pending. This syntax support establishes no live IP/SSH acceptance.
Targets contain no
protocol/runtime/profile configuration or deployment secrets. Separate deployment
inputs and observed capability results must not be inferred from inventory.

Host trust is separate device security state. Imported inventory cannot contain
or accept a fingerprint, trust decision or known-hosts record. Future connection
code must obtain independently established host trust before authentication;
this checker neither establishes trust nor permits a connection. Credential
resolution and SSH argument-safe invocation require separate reviewed contracts.

`effective-root` expresses a required remote EUID of 0, not proof based on an
account name. `sudo` explicitly requests a noninteractive route to remote EUID 0;
future read-only preflight must establish that route before deployment. Failure
or unknown privilege must block mutation; no password prompting or fallback is
authorized by this draft. No root/sudo path is exercised here.

Cloud identity is bookkeeping, not ownership, takeover, deletion, or billing
authority. Imported resource IDs grant no cloud operation permission. Ownership
proof and action authorization remain separate security decisions.

Run `jq -e -f docs/planning/contracts/validate-server-target.jq` on an example
envelope. It returns `true`/exit 0 for the restricted shape and `false`/nonzero
for rejected JSON values. It is a reference example-contract checker, not a full
JSON Schema validator, duplicate-JSON-key detector, secret scanner, or production
importer. Syntactically opaque strings cannot prove absence of secret content.
Trust enrollment/rotation, credential lifecycle, sudo enforcement, cloud ownership,
and broader endpoint formats remain unresolved and require high/security review.
