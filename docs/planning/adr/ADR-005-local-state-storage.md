# ADR-005 — Device-local ordinary inventory storage

- Date: 2026-10-08; task: G0-05.3; configured review model: Sol high.
- Status: **accepted — root reviewed; limited inventory direction**.
- Scope: one backend direction for ordinary device-local inventory in the
  [Go application service](ADR-004-controller-language.md), not a production
  store, driver, schema or platform qualification.

## Decision and preserved boundaries

Select **SQLite** as the ordinary device-local inventory backend direction for
subsequent ready engineering cards. Root accepted the reviewed decision;
production integration must first pass
the gates below; the Darwin+cgo lab adapter is evidence, not the production driver.

Keep [ADR-001](ADR-001-local-first.md)'s separate protected credential/native-config
stores and host-trust state. Inventory holds opaque references; copying/importing
it grants no trust, ownership, approval or execution authority. Raw credentials,
native configuration and secret-bearing URIs do not belong in ordinary inventory.
This decision chooses no vault, encryption, GUI, sync, Agent or protocol runtime.

Existing Bash, `easynet` CLI, metadata v1 and all protocol consumers stay compatible.
`metadata_write()` remains a writer with separate validation. Existing metadata
and `.env` stay mode 600. All four native deployments remain independent of the
controller; the `wireguard` directory denotes AmneziaWG, not native WireGuard.
Routing builds remain manual and the static Edge site self-consistent.

## Comparable accepted evidence

Use only [LocalStateLab-v1](../poc/local-state/state-lab-contract.md), accepted
[JSON evidence](../task-results/G0/G0-05.2a.md) and accepted
[SQLite evidence](../task-results/G0/G0-05.2b.md). Both ran on Darwin arm64 with
Go 1.27.1, owned temporary paths and fake exact protected-store bindings.
The common scope is complete bounded snapshots, not a production operation engine.

| Same logical requirement | Accepted JSON observation | Accepted SQLite observation |
|---|---|---|
| Seed/read/CRUD and exact refs | Explicit seed, absent-open refusal, whole copies and revision/ref validation passed | Same logical cases passed; persisted types/schema additionally checked |
| CAS and migration | Real flock writers/migrators: one complete winner, one conflict | BEGIN IMMEDIATE/conditional update under outer flock: same outcome |
| Unknown binding | Mirror insertion/reopen passed; remove/retarget/rehash refused unchanged | Same immutable mirror and refusal boundary passed |
| Invalid/corrupt/future | Strict malformed/shape/ref/version refusals preserved original state | Same logical refusals plus physical schema/header/type/constraint/extra-object refusals preserved state |
| Read purity | Frozen post-recovery baseline unchanged through three read repetitions | READONLY diagnosis before RW; frozen post-recovery baseline unchanged through three repetitions |
| Controlled crash | Before/after/boundary kills recovered complete old/new; owned staging cleanup after reap | Same complete old/new rule; ten observed hot journals recovered natively, four committed cases needed no journal recovery |
| Location and process bounds | Owner/mode/type/link guards, post-flock guard and owned child reap/cleanup passed | Guarded native access/journal inventory and owned child reap/cleanup passed |

Purity means observed names, bytes, modes and generation; atime is excluded.
JSON boundary trials observed both old/new; SQLite boundary trials happened to
observe old. Neither outcome distribution ranks the mechanisms. SQLite's timed
lock-replacement test and source-reviewed ordering do not qualify adversarial
same-UID VFS races; JSON's deterministic guard helper does not prove sandboxing.
Wrong-UID tests were pure stat guards, not live cross-UID access.

SQLite stores **one canonical JSON BLOB plus typed headers**, not normalized
entities. STRICT ANY plus typeof checks avoids coercion in this fixture. The PoC
proves no indexed-query, scalability, storage-size or performance advantage.
Test counts, package runtimes and source LOC reflect differing harness/native
work and are not a fair benchmark or backend ranking.

## Reason for selection and cost

Both candidates met the same bounded behavior contract. The selection is a
maintenance judgment: SQLite transactions and native rollback-journal recovery
provide an engine-owned publication/recovery mechanism to build upon, rather than
continuing to own the entire file-publication mechanism in application code.
This is an inference about the intended engineering boundary, not tested lower
maintenance effort or superior durability. Validation, reference binding, error
mapping, location safety, CAS policy and authority remain application duties.

JSON offers a readable whole-snapshot representation and avoids this lab's native
SQLite/cgo linkage. Its reviewed path explicitly owns stable flock serialization,
post-lock guards, exclusive staging, full writes, file fsync/close, atomic rename,
directory sync and ambiguous publication handling. Keeping those correct across
platforms requires filesystem/locking-specific implementation and qualification;
the successful Darwin path does not establish Windows or Linux behavior.

SQLite does not remove those platform obligations. The lab still uses outer flock
and pathname/identity guards, READONLY-first diagnostics, fixed SQL and explicit
native statement/handle/buffer ownership. DELETE journals, synchronous EXTRA,
fullfsync and connection limits were query-verified against linked system SQLite
3.54.0. Reads do not assign PRAGMAs; writer settings do not describe read defaults.
WAL is not selected or exempted from purity. Compiled-out extension loading was
accepted only after verifying OMIT_LOAD_EXTENSION; API failure alone is no bypass.
Different SQLite versions/options must meet equivalent reviewed guards.

The Darwin+cgo/system-library adapter adds C ABI, compiler/SDK, native ownership,
dependency/license and packaging/version costs. A production driver/library
choice remains open and must demonstrate equivalent semantics; choosing SQLite
does not automatically choose this adapter or eliminate its outer lock.

Observed JSON and SQLite card metrics both include substantial root/review work;
SQLite also includes main repairs, interruptions and a prior measurement tail.
These unmatched windows prove no causal token, billing, implementation-effort or
main-only cost winner and do not determine this backend choice. Root collects
this review's actual usage separately; no fees or savings are inferred.

## Candidate dispositions

| Candidate | Accepted disposition | Retained value / revisit trigger |
|---|---|---|
| SQLite | selected for ordinary inventory direction, production gates pending | Transactional snapshot/CAS and controlled journal evidence; choose production adapter separately |
| JSON | not selected for this inventory direction; accepted lab evidence retained | Strict codec/model, publication and purity cases remain references; revisit if SQLite cannot meet an explicit supported-platform, packaging or purity gate |

Neither disposition deletes promised scope or declares an unimplemented feature
complete. G0–G6 candidate decisions, phase acceptance and the single final main
merge gate remain required. No new experiment is authorized by this ADR.

## Recovery, migration and production gates

1. Freeze successor production schemas/APIs and supported targets before creating
   an adapter. Preserve strict version/shape/type/ref checks and whole-generation
   CAS; unknown schema refuses use/write/migration with original storage preserved.
   No fallback, automatic initialization, permission repair or startup migration.
2. Design explicit, reviewed migrations, backup/export/import and rollback policy.
   Lab v0 merely renames sequence to generation and increments once; it is not a
   legacy metadata importer or real upgrade/downgrade policy. Stage purely, commit
   under serialization, preserve exact bindings and old state on definite failure;
   never merge/rebind refs or import trust/authority. Specify interrupted migration
   and incompatible-version recovery without treating a future schema as corrupt.
3. Freeze production recovery provenance/authorization and diagnostics separately.
   Ordinary corrupt/future opens preserve storage; safe journal presence in this
   fixture refuses rather than repairing. Only known-valid, killed-and-reaped owned
   child provenance authorized lab recovery. Production cannot infer that authority
   from file existence or reuse the harness recovery method. Preserve evidence on
   failed recovery; qualify physical changes, then freeze/recheck read purity.
4. Keep prepublication I/O failure distinct from commit-unknown once publication
   may have occurred. Reload/reconcile complete old/new state before another
   intent; no automatic replay. Persisted unknown mirrors grant no remote result,
   owner release or retry. G1 must separately implement authenticated receipts,
   durable remote exclusion/ownership and original operation/target/plan recovery.
5. Qualify owned locations, locking, atomicity, permissions/ACLs, filesystem and
   diagnostic purity on each supported platform. Neither candidate qualifies
   Linux, Windows, live cross-UID, disk-full, power loss, faulty filesystems or
   hardware durability. Process kills are not power-loss tests or production
   security proof; same-UID tampering is not a sandbox guarantee.
6. Review production driver/dependency/license closure, minimum SQLite/toolchain
   versions, compile/runtime guard equivalence, ABI and release/update packaging.
   Test native-library variation and resource closure on supported targets; any
   WAL/normalized schema or changed lock/recovery design needs explicit evidence.
   Production vault, trust lifecycle, UI, sync, Agent and runtime gates remain
   independent, as do metadata/client compatibility and real-client/VPS acceptance.

Next: freeze the next dependency-ready G0 card using this
direction. Do not introduce G1 schemas/directories or reuse the lab as production;
G0 acceptance and subsequent reviewed contracts still govern engineering entry.
