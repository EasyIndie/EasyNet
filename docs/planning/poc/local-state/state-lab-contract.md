# LocalStateLab-v1 — reviewed common storage experiment contract

G0-05.1 research contract; Sol high and root accepted for owned experiments only.
Contract acceptance itself claimed no implementation or behavior pass. JSON and SQLite must qualify against
this same bounded model, API and cases; ADR-005 chooses the backend later.
[ADR-004](../../adr/ADR-004-controller-language.md) selects Go for application services,
not a storage, encryption, vault, GUI or runtime choice.

Subsequent evidence: [G0-05.2a](../../task-results/G0/G0-05.2a.md) qualified the
owned Darwin JSON fixture matrix. SQLite qualification and ADR-005 remain pending;
this does not qualify a production store.

## Scope and accepted boundaries

The lab is a device-local ordinary inventory snapshot, distinct from VPS metadata v1.
Existing Bash/CLI/protocol consumers, metadata paths and secret-bearing files remain
unchanged. `metadata_write()` writes, not validates; its separate validator stays
separate. Existing metadata and `.env` remain mode 600. Nothing is imported from them.

The following are deliberately small lab projections of the reviewed
[target](../../contracts/server-target.md), [profile](../../contracts/profile.md) and
[operation](../../contracts/operation.md) boundaries, not successor production schemas.
Credentials and native configuration live in separate protected stores; host trust
is separate device security state per [ADR-001](../../adr/ADR-001-local-first.md) and
[ADR-003](../../adr/ADR-003-ssh-first.md). No personal state, network, live target,
secret material, trust enrollment, cloud action or remote mutation is part of this lab.

## Exact logical records and syntax

The v1 envelope has exactly `schemaVersion`, `generation`, `targets`, `profiles`,
`operations`. `schemaVersion` is 1; generation starts at 0 and is monotonic per store.
Each collection is an array of 0–4 records; ordering is immaterial and IDs are unique
within its namespace. Candidate encodings must expose identical logical snapshots.

| Record | Exact fields / bounded values |
|---|---|
| Target | `id`, `revision`, `credentialRef`; revision is positive. No endpoint/trust/privilege is represented. |
| Profile | `id`, `revision`, `targetId`, `runtimeId`, `protocolId`, `format`, `configRef`; revision is positive. |
| Operation mirror | `operationId`, `targetId`, `planHash`, `remoteState`; remoteState is exactly `unknown`. |

IDs and targetId are 1–64 ASCII letters/digits/underscore/hyphen, first character a
letter. References are `cred_` or `config_` plus 1–64 ASCII letters/digits/underscore/
hyphen. `planHash` is `sha256:` plus 64 lowercase hex digits. All matches consume the
whole string; controls, whitespace suffixes, paths and material fields are rejected.
Opaque syntax cannot prove that a malicious producer did not hide secret content.
Profile tuples are exactly `(hysteria2-native,hysteria2,hysteria2-native-config)` or
`(amneziawg-native,amneziawg,amneziawg-native-config)`; these grant no native capability.

Closed objects: unknown/missing fields reject at every level; null is forbidden in
all fields. JSON fixture input is UTF-8, at most 16 KiB, one object with no trailing
value; duplicate object keys reject before projection. Integer tokens use only
`0` or `[1-9][0-9]*`, range 0–2147483647; floats, exponents, signs, booleans and
numeric strings reject even when mathematically integral. Revision excludes zero.
Both adapters apply this shared input rule before encoding; SQLite additionally
rejects incompatible persisted types/columns/constraints, never coerces them.
Malformed encoding/storage integrity failure is `state-corrupt`; a decoded value
violating these rules is `state-invalid`. Version other than 0/1 is
`state-schema-unsupported`; version 0 is migration-only, never a writable v1 store.
Ordinary load/snapshot/commit on v0 return `state-migration-required` unchanged.

Each profile/operation targetId must resolve within this snapshot. A target's
credential ref must resolve in an owned fake protected-store adapter to exactly
that target id/revision; a profile config ref to its exact
targetId/runtimeId/protocolId/format/revision. This fake resolver returns only
`available`, `missing`, `locked` or `mismatch`, never material or a path. Missing
inventory/protected refs give `state-ref-unresolved`, locked gives
`state-secret-locked`, wrong binding gives `state-ref-mismatch`. All refuse use/write
without prompting, fallback, rebinding or revealing contents. Protected stores and
trust are neither copied into this envelope nor mutated by a storage transaction.

## Common API and atomic boundary

The future harness seeds a new owned store with the empty v1 envelope at generation
0; opening an absent existing store returns `state-not-found`, never initializes it.
Only explicit fixture setup may seed. API results are either a complete logical
snapshot or one fixed error code, with no raw content/path/native error messages.

| API | Exact behavior |
|---|---|
| `load()` / `snapshot()` | Identical read-only validated copy of one complete committed v1 generation; resolve refs with fake adapter, no repair/migration/write. |
| `commit(expectedGeneration, candidate)` | Candidate is a complete v1 envelope with generation exactly expectedGeneration+1; validate current/candidate and refs, compare current generation, atomically replace all records, return new snapshot. |
| `stageMigration(v0Snapshot)` | Pure validation and staging: rename v0 `sequence` to v1 `generation`, increment once; preserve every record, id, revision, ref and binding exactly. No store write or secret lookup mutation. |
| `commitMigration(expectedGeneration, staged)` | Under serialization, current v1/already-migrated or stale v0 sequence gives state-generation-conflict; otherwise validate v0/refs and exact stageMigration(current), CAS sequence, atomically publish v1. |

Lab v0 has exactly the v1 fields/rules except `schemaVersion: 0` and `sequence`
instead of `generation`; this synthetic rename tests migration mechanics only.
No real legacy-data importer, downgrade or automatic startup migration exists.
Read-only v0 inspection for staging uses the same validation/reference gates.
Unsupported-version diagnosis exposes only `state-schema-unsupported`, never
records for use; preserve original storage and refuse writes/migration.

CRUD is expressed by candidate replacement: add/read/update/delete unreferenced
targets/profiles. Target/profile revisions increment exactly one on update; unchanged
records keep revision. Replacing an identity uses a new id. Deleting a target with
remaining references rejects as unresolved. Profile updates require the new exact
config binding. Operation mirrors may be inserted but their four fields are
immutable and cannot be removed in this lab (`state-binding-immutable`). This
qualifies persistence of unknown bindings without inventing a remote owner engine.

CAS check and publication are one serialized operation across candidate processes;
two writers using generation g cannot both commit g+1. A stale writer gets
`state-generation-conflict`, without merge, retry or lost update. Invalid expected
generation/candidate successor is `state-invalid`. For valid expected/current generation
at maximum, return `state-generation-exhausted` before constructing/validating a
successor; stageMigration(maximum sequence) does the same. Definitive prepublication
failures publish nothing; ambiguous publication instead follows commit-unknown below. Candidate
validation order is encoding, schema version, shape, references, then CAS and
immutable/revision rules under serialization; per-category inspection follows table/array
order. Use one-fault negative fixtures to avoid backend-specific error precedence.
Precommit I/O failure gives `state-io`; once publication might have occurred and no
acknowledgment exists, return `state-commit-unknown` and reload before any new intent.
No automatic replay. Reload must expose exactly complete g or complete g+1.

JSON must demonstrate synchronized publication (including relevant file/directory
sync and atomic replacement) plus interprocess CAS serialization. SQLite must
declare a rollback-journal/read-only mode compatible with exact read-purity and
transactional CAS. WAL auxiliary writes are not implicitly exempt from read-purity;
a future WAL candidate needs a separate explicit qualification contract.
`recoverOwnedCrashFixture()` is harness-only after controlled owned-child kill/reap
from a known-valid seed/successor; declared recovery stays in owned 0700/0600 paths.
Record file/journal/auxiliary changes; recover complete g or g+1, never mixed/g+2.
Freeze the recovered baseline, then prove exact load/snapshot purity for both candidates.
Ordinary corrupt/future opens never recover; no production authority or power-loss claim.
Contract acceptance did not qualify either mechanism; subsequent JSON fixture evidence is linked above. Crashes before publication recover complete
old g; after publication recover complete new g+1, exactly one increment. A crash
at the boundary may recover either, never a mixture or g+2. Process-kill evidence
does not prove power-loss, faulty filesystem, disk-full or hardware durability.

## Same required future evidence matrix

| Case | Setup/action → expected observation |
|---|---|
| Seed/read/CRUD | g0 empty; add bound T/P → g1; read unchanged; revise P with exact new config binding → g2; remove P then unreferenced T in separate commits → g3/g4. |
| Read purity | After any explicit controlled-crash recovery, freeze baseline; repeated load/snapshot → equal logical state and unchanged bytes/files/generation, no resolver prompt. |
| Shape negatives | Duplicate keys/IDs, unknown/missing/null field, lexical number variants, bound/size overflow → state-invalid (malformed encoding → state-corrupt); original preserved. |
| Ref negatives | Missing target, missing cred/config, locked resolver, mismatched profile revision → respective ref/locked error; no use/write, original preserved. |
| Corrupt/future | Damaged candidate store or version 2 → corrupt/unsupported; no auto-initialization, repair, migration or mutation; original preserved for diagnosis. |
| Stale/CAS race | Two owned writers read g and propose distinct additions; barrier then commit → exactly one success g+1, one generation-conflict; winner complete, loser absent. |
| Crash before/after | Owned child paused immediately before/after publication, kill and reap, reopen → full g/full g+1 respectively; repeat at boundary → one of those, no mixed records. |
| Migration success | v0 sequence g, bound T/P/unknown mirror → v1 g+1 with same records/refs/bindings; no trust/secret/provider changes. |
| Migration failure/race | Invalid/locked/missing ref or prepublication fault preserves current committed state (v0 only absent competing publication). Two migrations from g: one v1 g+1 winner, one generation-conflict loser; loser preserves winner. Crash follows complete old/new rule. |
| Unknown mirror | Insert mirror then reopen; attempt remove/retarget/rehash → binding-immutable and same mirror/g; snapshot never releases a remote owner or permits replay. |
| Unsafe location | Wrong owner/mode, symlink or outside owned fixture root → state-location-unsafe before access/publication; no outside files changed. |

Future harness uses only its own temporary directory, owner-only mode 0700, files
0600 (including lock/journal/staging artifacts), no symlinks or unsafe paths; refuse
unsafe preexisting fixtures without chmod/repair. Kill/reap only owned children and
clean only owned fixtures. Each candidate reports exact host/backend/version/options,
cases, repetitions and recovered generations; inspect whole snapshots, not exit
codes alone. No benchmark/backend winner follows from this document check.

## Production gates and authority limits

Durable snapshots, plan hashes and unknown mirrors prove no authentication, approval,
receipt authenticity, freshness or remote outcome. Unknown still requires original
operation/target/plan reconciliation and cannot release ownership or replay work;
remote exclusion/recovery/receipt resolution stays G1-07 under ADR-003. Inventory
changes cannot redirect that reconciliation. Resolved target, credential/privilege,
host-trust or relevant configuration revision changes invalidate approval; enforcement
and immutable resolved bindings remain future reviewed production contracts.
Plain inventory/archive exports never contain credentials/configuration or trust
grants; import cannot establish trust/ownership/authorization or rebind refs.
Production schemas/importers, secure lifecycle/export/backup, platform vault access,
migrations/recovery and multi-device remote authority require their separate gates.
This experiment contract introduces no production policy and qualifies none of those gates.
