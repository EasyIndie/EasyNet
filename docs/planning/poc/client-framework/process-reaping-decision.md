# G0-06.2ad — owned leader cleanup correction

Accepted corrective design by root, 2026-10-08; actual implementation/source/runtime gates remain.
Scope: immediate isolation only; accepted G0-06.2ab design remains binding.
G0-06.2ac is still blocked: its two-repair budget is exhausted.

## Evidence and source limits

The approved diagnostic run observed PID89905 exit via waitid/WNOWAIT, then
group TERM PermissionError/errno1 and cleanup PermissionError/errno1.
Leader Wait did not complete; returncode was null; no output was observed.
The later exact-PID ps absence does not prove group absence or the first run's cleanup.
Source inspection shows both signal exceptions can bypass Wait.
Neither the profile, a missing privilege, nor a universal Darwin bug is established.

Official references inspected 2026-10-08 (four sources only):
- [Apple XNU kern_sig.c, main, killpg1](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_sig.c), lines1549–1624: explicit-group iteration filters SZOMB; a found group with no counted signalable member can yield EPERM. This explains a possible zombie-only path; main is not identified with this host's kernel.
- [POSIX.1-2024 _exit](https://pubs.opengroup.org/onlinepubs/9799919799/functions/_exit.html): status remains until consumed by a wait operation without WNOWAIT; terminating a parent does not directly terminate its children. WNOWAIT observation is not reclamation.
- [POSIX.1-2017 shell wait](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/wait.html): the shell knows asynchronous child IDs, and wait with a known ID waits for termination and returns its status. This specifies the planned joined-child case, not this host's sandbox inheritance.
- Local Apple `/usr/share/man/man1/ps.1`, `-g`, `-o`, `state`: group-leader selection and headerless numeric PID/PPID/PGID/state fields support a narrow metadata query. Its availability, completeness and permission in the execution host remain unqualified.
Web fetches of individual wait/fork pages failed; no conclusions rely on them.
No SDK, guardian, GUI, signing or general process-tree guarantee follows.

## One frozen correction: observe group before consuming leader status

Change only `_execute`/its diagnostics and corresponding cases in
`poc/client-framework/lab/isolate.py` and `poc/client-framework/lab/test_isolate.py`.
Keep the profile bytes/hash, canonical fixture, filesystem and network rules unchanged.
Keep 2s total per command, 20s suite, 8KiB retained per stream, continued byte counting.

1. Retain waitid WEXITED|WNOHANG|WNOWAIT, own new-session PID/PGID identity and
   the reservation until every planned signal attempt and final group observation ends.
   Do not call poll, communicate, Wait or other consuming wait before that boundary.
2. Natural exit does not itself trigger TERM/KILL. Drain concurrently; before Wait,
   query only `/bin/ps -g <owned-leader-pid> -o pid=,ppid=,pgid=,state=` outside
   the sandbox. No command names, argv, environment, broad inventory or name kills.
   Freeze this supervisor helper's own timeout/output cap/reap in the next binding.
   It shares the command deadline; failure to reap the helper fails the result.
3. Qualify a normal group snapshot only when the reserved, exited leader is the
   sole row, its PGID matches its PID, and its state is Z. Missing leader, malformed,
   incomplete/truncated or denied inspection is unknown, even if pipes have EOF.
   Other rows, including zombie descendants, prevent success. Fixed reviewed commands
   must not detach/change groups; shell cases must join their explicit children.
   This is a bounded fixed-command invariant, not a generic descendant guardian.
4. If live owned members remain, or the leader has not exited by end−0.35s, attempt
   group TERM once, then KILL by end−0.20s if unresolved. Inspect/drain until the
   deadline; unknown membership permits only the already owned reserved group signal,
   never success. An exited sole zombie needs no signal. Signals do not prove death.
5. Record each TERM/KILL failure separately (including errno and phase); never
   reinterpret EPERM as absent or erase it after a later successful step.
   ESRCH is a signal result, not descendant proof; metadata still controls qualification.
6. Finish all group signals before consuming leader status. An independent finally
   branch ALWAYS attempts `child.wait(timeout=max(0, end−now))` after every spawned
   leader, including signal, metadata and drain errors. No preceding exception may
   skip it. Preserve first failure and independent wait/cleanup failure diagnostics.
7. Close selector and both streams independently, including after Wait failure.
   Return actual Wait returncode, Wait completion, EOF/closed flags and bounded counts.
   Never signal/query the numerical PGID after leader Wait: it may be recycled.
8. Set reaped=true only after leader Wait, pre-wait sole-zombie group proof, completed
   EOF drain/FD closure, no lifecycle error and no timeout. Otherwise preserve the
   fixture and an unresolved tombstone; stop further fixture commands/reuse.
   A tombstone after successful Wait is not PID ownership: it authorizes no signal.
   Keep genuine operation denial separate from supervisor signal/metadata errors.

## Exact next-card acceptance cases

The implementation card proposed path is `docs/planning/task-cards/G0/G0-06.2ae.md`;
freeze `docs/planning/task-bindings/G0-06.2ae.json` after root accepts this decision.
Implementation performs no fixture run. Independent R reviews source and fault cases,
then root freezes a separate actual-run binding including exact helper argv/hash.

- Controlled API fakes: TERM EPERM, KILL EPERM and both failures; assert ordered
  signals-before-Wait, one independent Wait attempt, retained errors, reaped=false,
  both FDs closed, no post-Wait signal/query and suite stop/fixture retention.
- Fakes: group sole zombie, live member, zombie descendant, denied/malformed/truncated
  metadata; EOF alone and killpg(0)/EPERM alone never produce group absence.
  Simulate recycled PGID after Wait and require zero subsequent group operations.
- Fakes: Wait timeout/EINTR, drain error/overflow, helper timeout/reap failure;
  all failure paths attempt leader Wait and close both streams within the same budget.
- Actual normal completion: existing allowed cat nonce and touch retain exact result;
  require returncode0, no signals, Wait completed, EOF and FDs closed, reaped=true,
  and elapsed<1s (well before the 1.65s TERM boundary). No mocked time/API evidence.
- Actual fork-only inheritance: `/bin/sh -c '( : < "$1" ) & child=$!; printf "owned-child %s %s\n" "$$" "$child" >&2; wait "$child"' probe <seed>`.
  Run allowed seed control then decoy seed denial; parse exactly one marker with
  positive distinct leader/child IDs, require child wait status, no stdout/nonce,
  allowed returncode0 and decoy nonzero plus path-specific Operation not permitted.
  Builtin `:`/redirection in an asynchronous subshell avoids exec; actual marker,
  waited completion and denial are required, not a shell tail-command inference.
- Keep a distinct joined fork+exec cat case: `/bin/sh -c '/bin/cat "$1" & child=$!; printf "owned-child %s %s\n" "$$" "$child" >&2; wait "$child"' probe <decoy/seed>`;
  require distinct child marker, returncode1, no stdout/nonce and cat path denial.
- Actual timeout control must be separately source-reviewed/frozen: a fixed shell
  builtin loop, no detach, no arbitrary shell input; require timeout failure,
  bounded TERM/KILL/Wait/FD closure and no assertion of absence from signal success.
  Fault injection must never send a signal to an unowned process.

Listener closure/join, pre/post reachability and ambiguous-denial rejection remain.
Unsupported metadata means blocked actual qualification, not a relaxed reaped check.
Plan/whitespace checks qualify this decision only; runtime and profile efficacy remain unknown.
