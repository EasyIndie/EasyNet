# SQLiteFixture-v1 — reviewed G0-05.2b preparation

Sol high design review, 2026-10-08. This freezes one owned Darwin SQLite
experiment against [LocalStateLab-v1](state-lab-contract.md), following the
[verified JSON experiment](../../task-results/G0/G0-05.2a.md). It is preparation,
not source approval, runtime evidence, production qualification or ADR-005's
backend choice. Root owns binding acceptance, card state, commands and commits.

## Scope, files and gates

- Branch: `codex/feature/self-hosted-byos-byoc`; dependency verified at `d5c153d`.
- Sources: `poc/local-state/go/sqlite_native.go`, `sqlite_schema.go`,
  `sqlite_store.go`; tests: `sqlite_store_test.go`, `sqlite_process_test.go` in
  that directory. All five use `darwin && cgo` build constraints.
- Mandatory evidence: `docs/planning/task-results/G0/G0-05.2b.md`; it is the
  card report, separately accounted from the two executable test files.
- Shared `model.go`, `codec.go`, JSON source/tests, module/checksums and current
  Bash/CLI/metadata consumers remain unchanged. No new driver/module/download,
  install, Linux adapter, production schema, vault access or network use.
- Readable implementation/test target ≤1600 lines, hard limit 2800 across the
  five files: native 500, schema 350, store 650, store tests 650, process tests
  650. Native ownership/guards/recovery justify the headroom over JSON's 1570.
  These explicit integration bounds replace the generic 200-line target;
  exceeding any bound or needing another file requires review/splitting.
- Source/compile review precedes owned fixture/child execution. No side effects
  in `init`/`TestMain`; `test -run '^$'` cannot create fixtures or launch children.
  Two focused repair attempts maximum; security findings escalate immediately.

Go 1.27.1: `/tmp/easynet-poc-toolchains/go/bin/go`; cached x/sys v0.48.0.
Use system SQLite through cgo (`-lsqlite3`), owning every native resource.
Read-only host facts supplied by the coordinator: Darwin arm64, CLI SQLite
3.54.0 aapl, clang 21, SDK
`/Applications/Xcode-27.0.0.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`,
CC `/Applications/Xcode-27.0.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang`.
The linked library version, compile options and required native APIs remain
unverified until the bound compile/runtime gates. Report `sqlite3_libversion()`
and source-id at actual runtime; CLI version is not proof of linked version.
Native ABI ownership and cgo/platform packaging replace new driver dependencies
in this bounded PoC; that tradeoff does not select a production driver.

## API and fixed storage projection

`SeedSQLiteFixture(dir, seed, resolver) error` is explicit setup of an existing
empty owned root, accepting only shared-valid v0/v1 fixtures. Normal initial
fixture is empty v1 g0; v0 is synthetic migration setup. It never repairs an
existing fixture. `OpenSQLiteFixture(dir, resolver) (*SQLiteStore, error)` only
opens/guards root, lock and existing database; absent means `ErrNotFound`.
It does not initialize, recover, migrate or retain a native database connection.
Methods `Load`, `Snapshot`, `InspectMigration`, `Commit(expected uint32, next
Snapshot)`, `CommitMigration(expected uint32, staged Snapshot)` and `Close`
match JSON's signatures/semantics. All snapshot errors return `Snapshot{}`;
only existing fixed `ErrorCode` values escape, never native errors/content/paths.

One canonical JSON BLOB preserves the complete shared snapshot, rather than
inventing normalized production tables. Database names are `state.sqlite`,
`state.lock`, and only the transient `state.sqlite-journal`. Freeze this DDL
(without a trailing semicolon in the stored comparison string):

```sql
CREATE TABLE state_snapshot (
  singleton ANY PRIMARY KEY CHECK(typeof(singleton)='integer' AND singleton=1),
  schema_version ANY NOT NULL CHECK(typeof(schema_version)='integer' AND schema_version BETWEEN 0 AND 2147483647),
  generation ANY NOT NULL CHECK(typeof(generation)='integer' AND generation BETWEEN 0 AND 2147483647),
  payload ANY NOT NULL CHECK(typeof(payload)='blob' AND length(payload) BETWEEN 1 AND 16384)
) STRICT
```

STRICT INTEGER still applies affinity conversions; STRICT ANY preserves stored
types, allowing explicit `typeof` constraints to reject coercion. See
[SQLite STRICT tables](https://www.sqlite.org/stricttables.html).
Only this exact user table plus its exact PK autoindex
`sqlite_autoindex_state_snapshot_1` (NULL SQL) may appear in `sqlite_schema`;
reject extra tables/indexes/views/triggers and differing DDL. Check exact column
order/types/not-null/PK/hidden metadata and STRICT rowid table form. No generated
columns, defaults, functions or schema supplied by a caller are executed.
Read at most two rows: exactly one singleton is required. Check native column
types before conversion: INTEGER singleton/schema/generation, BLOB payload;
bounds as above. Then shared `DecodeFixture`, logical/physical schema and
generation equality, and shared reference validation. Stored type/schema/shape
violations give `ErrInvalid`; malformed SQLite integrity/JSON and mismatched
physical/logical headers give `ErrCorrupt`. Valid future version gives
`ErrUnsupported` without returning records. Shared errors/order remain intact.
Harness-only malformed/future fixtures may bypass seed via fixed creator SQL.

## Owned paths, locking and read purity

Only `/tmp/easynet-state-lab-[A-Za-z0-9_-]{1,64}` or its canonical
`/private/tmp` alias: current nonroot UID, root 0700, regular files 0600 and
link count one, no symlinks/traversal/nonregular entries. Canonicalize only the
known Darwin `/tmp` alias, never arbitrary links. Hold original root and stable
lock descriptors. Reuse JSON's private `openRoot`, `guardedFile`, stat checks,
`JSONStore.acquire`/guard/Close as a locker only; never its state.json methods.
The SQLite store adds named canonical-root inode checking because JSON's guard
checks only its held root. Serialize methods/Close with the locker mutex.

Every operation takes shared/exclusive outer flock, including open's database
inspection; JSON's two-second/10ms bounded flock policy applies. After acquiring,
repeat root/lock checks, then inventory and database guards before native access.
Hold a descriptor-opened database, compare held/named inode before/after native
open and before releasing the lock. Native open uses canonical absolute path and
`SQLITE_OPEN_NOFOLLOW`; check named root again around it. SQLite's pathname/VFS
opens differ from JSON's descriptor-rooted publication: these checks catch tested
replacement races, but do not provide a same-UID adversarial sandbox guarantee.

Before ordinary native open, refuse any journal: guarded safe journal → `ErrIO`,
unsafe journal → `ErrLocationUnsafe`. `-wal`/`-shm` and unknown auxiliary names
are unsupported/unsafe. Checking after flock avoids confusing a cooperating
writer's live journal with a crash. No automatic recovery even for a safe journal.
Bounded descriptor read of the 100-byte header checks SQLite magic, page size
4096, rollback read/write format bytes 18/19 equal 1, and file size 4096..1MiB,
multiple of 4096. Header corruption fails before native access.

Ordinary diagnosis uses READONLY, never CREATE, and verifies
`sqlite3_db_readonly(db,"main")==1`. Reads use fixed bounded unsorted queries,
exact schema checks and `PRAGMA integrity_check(1)` yielding one `ok`; no SQL repair.
Query/report journal DELETE, page size and connection settings; do not assign
PRAGMAs on ordinary diagnostic handles. Require mmap size zero and NORMAL locking.
Synchronous/fullfsync/temp-store settings are connection-local; readonly defaults
need not equal RW settings. No query may sort/spill or create a TEMP object.
Corrupt/future diagnosis therefore opens no RW handle and preserves bytes/names.

Commit first performs this full readonly diagnosis under exclusive flock, including
current references/candidate shared validation, then closes it. Only a fully safe,
valid current state permits RW open; verify readonly flag zero, never CREATE.
Seed exclusively creates empty DB/lock files at 0600 by descriptor, then uses RW
without CREATE to initialize. Seed/RW handles configure and query-verify:
page_size4096 (seed only), journal_mode DELETE, synchronous EXTRA(3), fullfsync ON,
temp_store MEMORY, mmap_size0, locking_mode NORMAL, busy timeout1000ms.
EXTRA adds directory sync after DELETE journal removal; fullfsync requests Darwin's
stronger sync. This is configuration, not observed power-loss durability.
See [SQLite PRAGMAs](https://www.sqlite.org/pragma.html).

## Native boundary and publication

Fixed SQL only; placeholders bind copied bounded canonical BLOBs and integers.
No generic SQL/URI, ATTACH, immutable/nolock, extension or caller filename support.
Before any queries on every handle: defensive ON, trusted_schema OFF, DQS DDL/DML
OFF, load extensions OFF; native limits SQL length4096, value length32768,
attached databases0, plus 1000ms native busy timeout. Check every option result.
Extension guard (runtime fix 2): linked `sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")==1` proves the entire loading mechanism absent; otherwise require disable's SQLITE_OK/actual0.
CLI facts or SQLITE_MISUSE alone cannot prove omission; every other check stays fail-closed.
Primary: [complete omission](https://www.sqlite.org/compile.html#omit_load_extension), [linked-library check](https://www.sqlite.org/c3ref/compileoption_get.html).
Own/close even the handle returned by failed open; finalize every statement on
every path, free C strings/buffers, and use a C SQLITE_TRANSIENT binding shim.
Check native type/byte count before bounded `GoBytes`; retain no Go pointer in C.
Close all native handles before flock release. See
[SQLite open API](https://www.sqlite.org/c3ref/open.html).
Map CORRUPT/NOTADB to Corrupt; persisted constraint/type violations to Invalid;
BUSY/LOCKED and other native failures to IO before publication. Shared validation
errors stay exact; publication uncertainty overrides native mapping as below.

RW path: repeat guards/schema/current validation → `BEGIN IMMEDIATE` → conditional
UPDATE of all three values WHERE singleton=1 AND schema_version=? AND generation=?
→ require exactly one changed row → finalize → beforePublish → COMMIT → afterPublish
→ physical guards/native close → beforeAck → return cloned complete successor.
Normal CAS expects schema1; migration CAS expects schema0 and uses shared
`ValidateMigration`/`StageMigration` exactly. Recheck logical current inside the
transaction; never trust a caller's previous snapshot. Already-v1 migration or stale
generation gives Conflict; no merge/retry/replay. Private hooks are test-only.

Before COMMIT invocation, a failed operation attempts ROLLBACK and close: return
IO only when rollback is definite, autocommit restored, handles closed and guards
show no pending journal; otherwise CommitUnknown. Shared validation/CAS refusals
before DML preserve their fixed errors. Once COMMIT is invoked, any error, close/
guard failure, afterPublish or preack fault is CommitUnknown, even a native result
which might be retryable. Reload precedes new intent; never retry COMMIT or replay.
See [SQLite result codes](https://www.sqlite.org/rescode.html).

## Owned crash harness and evidence

New SQLite harness uses only its current test executable, exact helper selector,
fixed scenarios, fake resolver and minimal LANG/PATH/root/scenario environment.
Children: five-second deadline, one-second WaitDelay, bounded fixed pipe events,
continuously drained stdout/stderr retaining ≤4096 bytes each. Explicit Kill/Wait
only on children it launched; LIFO cleanup reaps every child before fixture cleanup.
Reuse resolver/model assertions where safe, but do not reuse JSON's cleanupStages:
its creator-recorded-name handling does not validate the whole SQLite inventory.

Harness `recoverOwnedCrashFixture` is allowed only after its known owned child's
Kill/Wait from a validated seed/successor, under exclusive outer flock. Validate
the entire DB/lock/journal inventory, named root/inodes/modes before native recovery;
record bounded bytes/names/modes before/after. Allow native RW read/rollback of the
owned journal, never manually unlink it. Recovery must yield exactly old or successor
whole snapshot, no mix/g+2. If a nonhot journal remains after valid recovery, at most
one fixed no-op same-payload/header transaction may complete its lifecycle: preserve
generation/schema/records, record physical effects, require journal absent after
close. Otherwise stop and preserve. This cannot be an ordinary-store fallback.
SQLite reads may roll back a hot journal; deleting it bypasses recovery. See
[SQLite rollback locking](https://www.sqlite.org/lockingv3.html).

Test-only prepublication hook invokes `sqlite3_db_cacheflush` after DML, then pauses.
OK alone does not prove journal spill: page1/in-use pages may remain unflushed.
Deterministic before kills must observe a >512-byte journal with nonzero well-formed
header after child reap. Boundary trials with a surviving precommit journal must
make the same observation; a complete successor with no journal is an accepted
completed-commit outcome, recorded distinctly. Controlled provenance excludes
attached/super-journals. Actual hot-journal recovery evidence is required overall
for normal and migration modes; missing deterministic hot evidence blocks
qualification, never an inferred hot-journal pass.
See [cacheflush API](https://www.sqlite.org/c3ref/db_cacheflush.html).
Freeze recovered baseline; three Load+Snapshot repetitions (v1) or migration
inspection repetitions (v0) must preserve names/bytes/modes/generation; exclude atime.

Matrix: shared seed/CRUD/copies/closed use, all shape/ref/future/corrupt/immutable/
exhaustion refusals; physical header/schema/type/constraint/extra-object negatives;
unsafe roots/files/lock replacement/journal/WAL/SHM, post-flock replacement guard;
normal+migration prepublication IO and postpublication/preack Unknown; two actual
writers and two actual migrators (one whole winner+one Conflict); normal+migration
kill trials ≥2 before, ≥2 after, ≥3 real boundary races each; early-failure child
reap plus whole-inventory cleanup refusals for unsafe/unknown entries.
Final cleanup validates every entry, including creator-recorded DB/lock/journal,
before any deletion; rechecks identity before descriptor-rooted unlink using original
root FD. Refusal preserves the entire fixture and closes FD; no recursive deletion.
Creator teardown may remove its deliberate negative artifacts only after assertions.

No unresolved architecture blocker remains within these bounds. Binding acceptance,
native compile/API checks, source/security review and observed hot-journal/runtime
matrix are still gates, not assumed successes. Report exact options, authored cases,
actual repetitions/generations/children/cleanup and all unverified items. No root,
sudo/chown, personal state, deployment, Linux or hardware power-loss claim.
