# G0-06.2ai — sandbox startup decision

Root accepted source-only preparation (no runtime authorization), 2026-10-08; R baseline feature `45986ff5ccae04d331b69e3355e8e49d7613e3f2`, 2026-10-08.
**The aborting image, denied operation and required startup capability are unknown.**
Repair1 decision: prepare one bounded executable-mapping diagnostic hypothesis.
New primary evidence supports testing a named operation; it does not prove the
observed abort's cause. No profile grant or native run is authorized by this text.

## Observations and source limits

The [actual ah report](../../task-results/G0/G0-06.2ah.md) records A direct
`/bin/cat`/DEVNULL rc0 and B sandboxed cat/DEVNULL rc−6 (SIGABRT), empty streams.
Both owned leaders had healthy verified Wait/reap/EOF/FD cleanup; C was not run.
A pass/B abort associates failure with the sandboxed launch chain, but supplies
no image/stage marker, permission errno or denial classification. Hashes matched
before the fake suite and after execution; immediate separate pre-driver checking
was omitted. This is observational evidence, not exact per-command qualification.

The nine-line [fixture profile](../../../../poc/client-framework/lab/fixture.sb)
denies by default, permits named executable/library/dyld reads, synthetic
ALLOWED_ROOT reads/writes, process-fork and four named exec targets. It has no
explicit `file-map-executable` rule. Reviewed `_environment`, `_probe_guards` and
`run_startup_control` in [isolate.py](../../../../poc/client-framework/lab/isolate.py)
retain the fixed profile hash, unprivileged Darwin, canonical owned fixture and
no-live-child guards. A/B retain identical minimal environment and unchanged
HOME/CODEX_HOME. The guards do not establish implicit loader needs.

Reuse three facts from [startup-decision](startup-decision.md): shipped
[sandbox-exec(1)](/usr/share/man/man1/sandbox-exec.1) documents profile/parameter
use and command execution, not abort attribution;
[dyld4 startup](https://github.com/apple-oss-distributions/dyld/blob/main/doc/dyld4.md)
places loader entry before target startup; and
[execve(2)](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/execve.2)
retains PID/PGID across image replacement. No matched sandbox-exec implementation
was established. Upstream source is not verified to match installed host binaries.

Four new primary references inspected for repair1:

1. Shipped [bootinstalld profile](/usr/share/sandbox/com.apple.bootinstalld.sb:13)
   explicitly denies `file-map-executable`; lines84–85 allow it for a named
   CoreServicesInternal binary. Its header warns of a changeable Apple private
   interface. It demonstrates a distinct operation, not a policy to import.
2. Apple's [dyld Loader.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/Loader.cpp#L1587-L1609)
   maps image segments with their protections; EPERM can arise from sandbox or
   code signing, distinguished by a separate sandbox check.
3. Apple's [DyldDelegates.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/DyldDelegates.cpp#L943-L964)
   checks `file-map-executable` for mmap, separately from `file-read-data` and
   `file-read-metadata`. This links the named operation to loader mapping.
4. Apple's [mmap manual](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/mmap.2#L100-L119)
   distinguishes requested read/write/execute protections, with platform caveats.

Inference: the missing explicit mapping grant is a source-supported candidate to
test. Neither these sources nor the zero-output observation prove that cat took
this path, that the grant is sufficient, or that file-read* implies mapping here.
The initial Apple Developer VM search exceeded allowed reference categories; its
results remain excluded. Repair1 does not erase that deviation or qualify a VM.

## One next contract — preparation, independent review, then one attempt

A new bounded source I card and independent R review may prepare a separately
hashed diagnostic profile differing only by `allow file-map-executable` targeting
EXACTLY the existing trusted executable/library/dyld read allowlist:
`literal /bin/sh`, `literal /bin/cat`, `literal /usr/bin/touch`,
`literal /usr/bin/curl`, `subpath /usr/lib`, `subpath /System/Library/dyld`.
Do not grant mapping on ALLOWED_ROOT, decoy, home, Library or broader System paths.
No imports, Mach grants, JIT entitlements, permission waiver or changed exec/read/
write/network admission. Original fixture/profile hash remains intact; new guards
must pin only the separately reviewed diagnostic variant and reject all others.

Risk: this permits executable mappings of more system code within those existing
library/dyld subtrees, beyond cat's proven needs; it is not a per-library minimum.
Do not assume code signing, process-exec limits or trusted reads remove that risk.
Owned writable fixtures remain outside the mapping grant. Reusing only fixed cat
argv limits this diagnostic's request surface; production policy is undecided.

Source/fake acceptance must prove the exact single-operation delta, unchanged
guards/env/lifecycle/command admission, permitted mapping target membership and
rejection of synthetic ALLOWED_ROOT/decoy/outside/sibling-prefix mapping targets.
No runtime mmap helper/interpreter grant is allowed to manufacture these checks.

Later root execution requires a new frozen binding: absolute interpreter/driver,
all source/profile hashes checked immediately before each exact command and after,
a fresh canonical synthetic fixture, reviewed manifest and fixed argv only.
One attempt contains four sequential cases, each once: direct cat EOF → rc0/zero
counts; diagnostic sandbox cat EOF → rc0/zero counts; cat owned allowed seed →
rc0/exact nonce; cat owned outside-root decoy → explicit recognized permission
failure with no decoy bytes. Freeze the negative error matcher in source review;
abort, generic nonzero or empty output never counts as successful denial.
Each case retains the 2s deadline/8KiB stream caps and verified identity/Wait/reap/
EOF/FD cleanup; driver budget12s including at most4s setup/finish. Stop on first
failure, ambiguity or lifecycle error; retain fixture for separately reviewed
cleanup. No retry of ac/ae/ah, old fixture reuse, private logs or native inspection.

Passing only associates changed behavior with the constrained profile delta and
qualifies synthetic reads/denial in this slice. Source/fake mapping negatives do
not qualify actual executable-map denial; full isolation/native acceptance stays
blocked. Failure supplies no permission diagnosis and permits no automatic grant
widening. Original ac/ae/ah budgets remain exhausted; G0–G6 scope is preserved.
No VM/account provisioning is demanded now; independent planning/source/fake work
can proceed. An isolation alternative would need a separate reviewed decision.
