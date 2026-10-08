# G0-06.2af — isolated startup decision

Accepted preparation by root 2026-10-08; runtime remains unqualified.
Decision: the aborting startup stage is **unknown**. Prepare one paired startup
control card; do not change the sandbox profile or treat this as a permission fix.
This is source review, not runtime qualification or authorization to run commands.

## Evidence and limits

G0-06.2ae records the actual owned wrapper PID94681 returning −6 (SIGABRT),
stdout/stderr counts0, elapsed0.0492425s. WNOWAIT observed exit; the reserved
leader was the exact sole zombie; helperWait/leaderWait, EOF and both FD closes
succeeded, reaped=true, with no signals or lifecycle errors. This supports that
one leader's cleanup only. It proves neither operation denial nor every lifecycle.
No nonce, touch, decoy, inherited child, network or timeout gate was qualified.

The bounded source chain is `_execute` → Popen of absolute `/usr/bin/sandbox-exec`
→ documented profile entry and command execution → target startup/operation.
Popen uses DEVNULL stdin, PIPE stdout/stderr, `_environment()`, close_fds=true,
start_new_session=true and umask077. The fixed wrapper argv is:
`["/usr/bin/sandbox-exec", "-f", P, "-D", "ALLOWED_ROOT=" + R + "/allowed", *argv]`.
P is the canonical owned/hash-checked nine-line `poc/client-framework/lab/fixture.sb`;
R is a validated owned synthetic root. Neither file contents nor permissions change.
Environment is PATH=/usr/bin:/bin, LC_ALL=C, plus unchanged HOME/CODEX_HOME when
present; other variables are omitted. Minimal environment is not proof of zero
implicit loader/runtime accesses. Never print those inherited values or inspect home.

Apple's local [sandbox-exec(1)](/usr/share/man/man1/sandbox-exec.1) documents entering
the specified sandbox and executing its command; `-f` reads a profile and `-D`
sets parameters. It is deprecated. This manual does not identify its abort paths.
Apple's [dyld4 startup design](https://github.com/apple-oss-distributions/dyld/blob/main/doc/dyld4.md)
places dyld entry before target startup, with argv/envp available to the loader.
Apple's [execve(2) source manual](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/execve.2)
describes image replacement retaining PID/PGID; PID alone cannot identify the image
that aborted. These upstream sources were read 2026-10-08 and are not verified
matches for the installed OS binaries. No matching sandbox-exec implementation was
established. Launcher/loader/target attribution, denial operation and needed
capabilities remain unknown; zero output supplies no stage marker or permission errno.

## Frozen next diagnostic contract — preparation only

One new source implementation/review card, then a separately bound root execution
card, must consume this decision. Scope is three sequential cases, each at most once:

| Case | Exact child argv | Expected result / interpretation |
|---|---|---|
| A: direct EOF baseline | `["/bin/cat"]` | rc0, both counts0; same minimal environment/DEVNULL and collector |
| B: sandbox EOF control | `["/usr/bin/sandbox-exec", "-f", P, "-D", "ALLOWED_ROOT=" + R + "/allowed", "/bin/cat"]` | rc0, both counts0; no requested fixture file operation |
| C: allowed operation | `["/usr/bin/sandbox-exec", "-f", P, "-D", "ALLOWED_ROOT=" + R + "/allowed", "/bin/cat", R + "/allowed/seed"]` | rc0, stdout exact owned nonce, stderr count0 |

A failure stops before B; B failure stops before C. A pass/B abort isolates a
failure associated with the sandboxed launch chain relative to this direct control,
not the particular image or capability. B pass/C failure separates the successful
EOF control from this file-reading case; no silent failure is classified as denial.
All three passes qualify only this diagnostic slice and leave the original gate open.

Next implementation writes only `poc/client-framework/lab/isolate.py` (one fixed
`run_startup_control(profile_path, allowed_root, sandboxed, deadline_s=2)` entry;
boolean mode only, no caller argv) and `poc/client-framework/lab/startup_diag.py`
(fixed A/B/C driver), plus `poc/client-framework/lab/startup_diag_test.py` and its
new task report. Reuse the existing owned fixture preparation and `_execute`;
control entry must retain run_probe's platform/uid/root/profile/hash/live guards.
Do not broaden existing `_case` or run_probe command admission; C uses run_probe.
Root must bind the precise existing fixture creation/manifest source after reading
it in that new card; this review did not inspect that source or authorize its use.
Source/fake checks cover exact argv/env equality, guard rejection and stop-on-failure.

Proposed later driver argv is `["python3", "-I", "-B", "poc/client-framework/lab/startup_diag.py"]`;
the root must replace python3 with a reviewed absolute executable in its binding.
Driver allocates one fresh canonical 0700 synthetic R using the existing manifest
contract; seed is owned synthetic data. No old failed fixture reuse or personal reads.
Each case keeps the existing 2s inclusive deadline, 8KiB/stream cap with drain,
reserved identity/sole-zombie checks, Wait/EOF/FD-close and signal semantics.
Total case budget is6s, setup/finish at most4s; absolute driver deadline10s.
Lifecycle error/ambiguity stops further launches and retains the fixture;
only known manifest cleanup after verified reaping is eligible. No hidden retries.
Record mode, rc, elapsed, counts, exact synthetic expected-byte comparison and
existing lifecycle fields; omit home/env values, raw personal paths and crash payloads.
No new profile imports, Mach grants, filesystem widening, DYLD flags, logs/crash
reports, process inventory, SDK, downloads, GUI or runtime substitution is allowed.

Root must create/review the new card, freeze actual source hashes and exact commands,
and review all source before later execution. Commands above are not permission.
G0-06.2ac/G0-06.2ae stay blocked, repair budgets2 exhausted; G0–G6 scope unchanged.
