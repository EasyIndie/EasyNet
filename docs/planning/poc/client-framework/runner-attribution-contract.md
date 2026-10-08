# Runner attribution contract v1 — owned synthetic crash record

Status: root accepted source-only G0-06.2am repair1; independent implementation R and frozen successor binding required before runtime.
Scope: one fresh ephemeral GitHub `macos-15` arm64 guest, no personal data/accounts; no personal-host execution.
Baseline: G0-06.2al reports A pass/B rc−6 with healthy lifecycle and empty streams; abort cause remains unknown.
This contract observes a historical record, selects no GUI/engine/VM, and authorizes no new sandbox grants.

## Frozen launch and observer

Keep `isolate.py::_execute`, its lifecycle, `_environment`, and existing exact group helper unchanged.
Use the existing fixture setup/freeze guards; pin all source/interpreter hashes before and after each future command.
Pin mapping profile SHA256 `1dfc6055110b29f06ccd2026eb230433cd5ca6da9be2354b2c43fb88efba0595`; do not edit it.
Invoke `run_mapping_probe(profile, allowed, "sandbox-eof", 2)` exactly once; do not run A/C/D or a separate abort control.
Its argv remains `["/usr/bin/sandbox-exec", "-f", profile, "-D", "ALLOWED_ROOT=" + allowed, "/bin/cat"]`.
Here `allowed` is exactly the frozen fixture's `root/allowed`; stdin is DEVNULL and no user-selected args are accepted.
Single-thread driver records UTC wall nanoseconds `t0` immediately before the call and `t1` immediately after it, plus monotonic counterparts.
Proceed only for healthy lifecycle predicates from `mapping_diag.healthy`, substituting rc−6 and empty expected streams; elapsed <1s.
Do not print that result or its PID; retain positive `owned_pid`, driver PID, t0/t1 only in guest memory.
Require UTC duration nonnegative, <1s, and within 10ms of monotonic duration; clock uncertainty means unknown.
Wait once for 3s for report delivery; then run exactly one fixed observer helper, no polling or retries.
Future scope is two implementation files: `poc/client-framework/lab/attribution_diag.py` and `attribution_record.py`, plus ≤2 bounded fake-test files fixed by successor binding.
The new private guard accepts only the frozen absolute interpreter and record-reader path, isolated `-I`, and this internal token form:
`[python, "-I", reader, "--owned-ips-v1", decimal_pid, decimal_driver_pid, decimal_t0_ns, decimal_t1_ns, decimal_query_wall_ns, decimal_query_mono_ns]`.
All six numbers originate in this driver; query_wall/query_mono are sampled together after the 3s delivery wait, immediately before helper spawn, with elapsed wall/monotonic agreement ≤10ms since t0; reject external args, booleans and invalid bounds.
Invoke unchanged `_execute` once for that exact helper argv with deadline 2s; never expose a generic command/query entry point.
The observer is an unsandboxed owned diagnostic child in the disposable guest; it does not change the target environment/profile.
Its stdout is exactly one JSON record ≤512 bytes; stderr must be empty; driver accepts only strict schema/enums below.
Its lifecycle must independently satisfy existing healthy predicates with rc0 and exact validated stdout, including helper Wait/reap/EOF/FD closure.
The existing scoped `ps -g` metadata checks are lifecycle checks, not additional attribution queries or general inventory permission.

## One bounded record query

Source is only the guest user's `HOME/Library/Logs/DiagnosticReports`; never `/Library`, archives, subdirectories, system logs or Console.
Use Python stdlib `os.open`/`os.scandir`/`os.fstat`/`os.read`/`json` only; no `log show`, private API, shell, downloads or sudo.
Require fixed guest HOME from frozen runner provenance; open each directory component without symlink traversal; ancestors must be root/guest-owned, final directory guest-owned.
The helper performs one flat directory pass, stopping before entry257, with 0.5s monotonic total; iterator/directory FDs close independently in finally.
Only basename fullmatch `(cat|sandbox-exec)[-_][A-Za-z0-9._-]{1,160}\.ips` is a candidate; never emit entry names.
Candidate must be regular, guest-owned, nlink1, not group/world writable, with mtime/ctime in [t0, query-end]; follow no symlinks.
Zero candidates or >1 qualifying candidate means unknown with no report read; enumeration overflow/deadline/error means unknown.
Read at most one candidate solely to verify synthetic ownership; reject size >262144 bytes, use O_NOFOLLOW and nonblocking FD, cap reads at size+1.
Require fstat identity/size/mtime/ctime unchanged before/after read and EOF; always close the report FD even on read/parse failure.
Do not copy, upload, print or persist raw bytes, exception text, paths, environment, stacks, incident IDs, UUIDs or device identifiers.
Decode strict UTF-8 and exactly two JSON objects (first line metadata, remainder body); reject duplicate keys, nonfinite numbers, trailing data and depth >32.
Require metadata bug_type="309", platform=1, name exactly cat or sandbox-exec, incident_id matching body incident; simulated/nonfatal records are rejected.
Exact identity predicate: body pid=owned_pid, parentPid=driver_pid, t0≤procLaunch≤t1, procLaunch≤captureTime≤query-end wall, and procName/name agree.
Helper compares start/end wall and monotonic samples against query_wall/query_mono: spawn delay must be 0..1s on both clocks with durations agreeing ≤10ms; agreement must hold through query-end; driver checks elapsed agreement again after helper return.
Parse procLaunch/captureTime with explicit UTC offset and decimal fraction to nanoseconds; no rounding/timezone/filename-time guesses; deferred capture after t1 is allowed.
Image predicate: procPath exactly `/bin/cat` or `/usr/bin/sandbox-exec`, matching procName, cpuType="ARM-64", translated=false.
Require exactly one usedImages entry matching that procPath/name, arch exactly "arm64" or "arm64e", source="P" and well-formed UUID; duplicates/missing/redacted identity mean unknown.
These identify the crashed executable image, never cat main entry or a denied operation; do not infer executable-map denial, missing entitlement, syscall or required grant.
Driver remains alive, single-threaded, and launches neither accepted image again; target PID was reserved until its Wait completed.
The only subsequent children are the fixed Python reader and existing ps helper, neither an accepted image; driver PID cannot be reused while alive.
Thus reused target PIDs from other parents fail parentPid, and reused PIDs of owned diagnostic helpers fail image identity; time/image/PID alone is insufficient.
After Wait this record has observation value only: never signal, inspect live PID metadata, or authorize cleanup using its identity.

## Sanitization, controls and gates

Exact exported keys are `outcome`, `stage`, `operation`, `termination`, `category`, `code`; no other keys or free strings.
`outcome`: observed|unknown; `stage`: cat-image|sandbox-exec-image|unknown; `operation`: unknown only.
`termination`: sigabrt|unknown; sigabrt requires exception.signal exactly "SIGABRT" and target rc−6; missing/unrecognized signal means all-unknown.
`category`: DYLD|SANDBOX|CODESIGNING|SIGNAL|unknown; copy only an exact allowlisted termination.namespace, without interpreting it as a specific root cause.
`code`: integer0..65535 only for an allowlisted category (strict int, never bool), otherwise null; unknown/absent/out-of-range namespace/code is not widened or guessed.
Identity/read/schema errors emit all-unknown with code=null; valid SIGABRT may have category=unknown/code=null; no outcome unlocks native/GUI qualification. No raw reason/messages.
Fake tests must cover both image matches, stale/wrong PID/parent/time/image, same PID after interval, duplicate records/keys/images, missing fields and clock jumps.
Also cover namespace/code allowlist/type/range, unrecognized signal, message secret canaries, malformed/oversized/deep/truncated JSON, symlinks/hardlinks/mutation and entry/read caps.
Reuse reviewed unchanged _execute fault evidence; new integration fakes cover bad helper result, no second launch/query, cleanup blocked on unreaped state, clocks and independent observer FD closure.
Parser/filesystem fakes cover absent/late/deferred reports, ownership/bounds and no raw export; no native commands or reimplementation of _execute TERM/KILL/Wait tests.
Driver budget is 14s (setup≤4, target≤2, delivery≤3, helper≤2, finish≤3); outer workflow timeout 1 minute; no install/settings changes.
Existing fixture cleanup only after verified target and helper reaping; on uncertainty stop and retain guest state until ephemeral teardown, never recursive deletion.
Next I implements two source files + ≤2 tests without runtime; independent R reviews the new integration/correlation/parser/filesystem limits and freezes exact commands/hashes.
Only a later frozen runtime binding may read this one tentative synthetic candidate in the fresh guest; no broad log authority is created.

[Apple JSON crash-report format](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report), checked 2026-10-09, supports two-object format and identity/termination fields.
[Apple missing-framework crashes](https://developer.apple.com/documentation/xcode/addressing-missing-framework-crashes), checked 2026-10-09, illustrates DYLD launch-abort evidence; this contract exports its category/code, never a missing-library claim.
The first source defines namespace/code as system reason categories; the four literal labels above are a strict report-value allowlist, not a diagnosis. Installed guest schema/location/delivery remain unverified; unsupported evidence stays unknown.

Root architecture clarification: [Apple arm64e definition](https://developer.apple.com/documentation/bundleresources/information-property-list/lsarchitecturepriority) identifies arm64e as 64-bit ARM with pointer authentication; both labels are experiment allowlist values, not installed-schema qualification.
