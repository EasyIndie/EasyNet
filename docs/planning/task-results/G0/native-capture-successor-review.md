# Native capture successor review — source repair contract

2026-10-10; R static review on `codex/feature/self-hosted-byos-byoc`.
Reviewed `capture()`, relevant process tests, compiler identity, and the native build
contract's runtime/trust blocks. No test, compiler, guest, candidate or GUI ran.
Existing local/hosted/ar/av budgets remain zero; hosted failing cases/cause are unknown.
The 18-test source package remains unexecuted. This is a materially corrected successor
contract for root acceptance, not restoration of the consumed qualification grant.

## Decision and bounded changes

Accept the split always-attempted direct reap repair, but freeze the following additional
repair before any full-suite/hosted qualification. Driver ≤560 lines; tests ≤380 lines.
No new bootstrap, generic process helper, dependency, diagnostic experiment or retries.

1. Preserve the existing primary rejection (`timeout`, `overflow`, `cancelled`, etc.)
   separately from cleanup refusal; cleanup failure still makes the final error `cleanup`.
   Do not infer that the hosted failures have the same cause as local failures.
2. On abnormal cleanup, issue TERM only while ownership is held, returncode is unknown,
   SIGCHLD is default, and fresh getpgid verifies the owned group. Drain to `end - 2`.
   If both streams reach EOF, attempt bounded direct-child wait within that TERM allowance.
   If wait succeeds, set reaped/released immediately and skip KILL and all further group
   lookups/signals. Keep the original failure; TERM exit is not command success.
3. If streams remain open, do not poll/wait before escalation: inherited writers may hang.
   If EOF wait times out, ownership remains held. In either case attempt KILL only after
   the same fresh ownership checks, then bounded final drain and direct wait through `end`.
   A closed pipe alone is insufficient evidence of exit; timeout never authorizes signaling
   a released or unverified group. No signal retries after identity/signal failure.
4. Signal/identity/drain failure must not bypass bounded direct-child reap or FD closure.
   Always attempt direct wait if unreaped, independently of group operations; expired
   deadlines permit a zero-time wait, not a new allowance. Keep cleanup refusal sticky even
   if direct reaping succeeds. Record EOF and FD status honestly; no descendant-exit claim.
   Cancellation stays sticky; original 64KiB caps and monotonic work/cleanup budgets remain.
5. Add only finite capture diagnostics: `primary_error` uses existing rejection codes;
   `group_stage=none|term|kill|identity`, `group_errno=none|absent|permission|other`.
   Identity lookup failure uses `identity`; killpg failure uses its signal stage.
   Map ESRCH to absent, EPERM/EACCES to permission, other OSError to other; a guard refusal
   has errno none. Keep the first group failure. No paths, PIDs, exception text or raw output.
6. Preserve logical validated `swiftc` as argv[0] for version/help/compile. Resolve only
   for containment and canonical entry hash/size; report both validated logical invocation
   and canonical hash target. Amend the old “absolute resolved paths” wording accordingly.
   Extend the existing synthetic SDK/identity case with a contained swiftc symlink and
   fake_run argv assertion, without running a compiler or expanding the suite count.

## Static platform evidence and limits

Apple's [getpgid implementation](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_prot.c)
returns ESRCH when proc_find fails. Apple's [signal implementation](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_sig.c)
explicitly handles a zombie separately from proc_find for positive-PID kill; group kill uses
group lookup/iteration. Thus an unreaped child does not justify assuming getpgid succeeds.
This supports avoiding unnecessary post-TERM lookups; it does not qualify this host/image.
An early-exited leader plus inherited writer can still cause identity refusal on Darwin;
retain cleanup refusal, rather than bypassing identity checks to force a pass. The trusted
compile-only fixture may qualify this negative guard under the exact contract below.

Swift's [driver entry point](https://raw.githubusercontent.com/swiftlang/swift/main/lib/DriverTool/driver.cpp)
dispatches basename swift-frontend into frontend mode; its [driver selection](https://raw.githubusercontent.com/swiftlang/swift/main/lib/Driver/Driver.cpp)
uses swiftc for standard driver mode. Resolving argv[0] can therefore change semantics.
The selected Apple's symlink target remains unobserved; no vendor probing is needed for repair.

## Existing hung-writer case: platform-specific negative guard

Keep the same 18 test names. In `test_owned_early_exit_hung_writer_and_cancellation`, accept
either timeout with drained/reaped/closed and signals-issued-unproven, or cleanup with
primary_error timeout, first group_stage identity/group_errno absent, reaped/closed, and
no group-cleanup claim. No other cleanup cause passes. Cancellation assertions stay intact.
For either branch, independently establish the known fixture owner's readiness and exit:
after opening its existing private FIFO reader, write one owned private ready marker; keep
that reader open until the existing six-second watchdog or cleanup command self-kills its
current group. Test cleanup uses only that FIFO, never a remembered PID/PGID. Require the
ready marker, deliver cleanup if a reader exists, then boundedly require ENXIO from fresh
nonblocking writer opens by fixture start + 7s. A vanished reader means this known source
exited; missing readiness or reader persistence fails fixture cleanup and the suite.
This permits an explicit safe refusal, not positive descendant-cleanup qualification. A real
compile timeout taking this path still fails closed. Engine/GUI containment gates retain
their positive cleanup requirements; this disposition cannot transfer to those candidates.

## Tiny mock-only grant and later gate

Root may accept one invocation of the existing 18th test after source/hash review; it mocks
Popen/getpgid/killpg and uses closed local pipes, so starts no child or toolchain. From repo
root, exact command (fixed trusted `/usr/bin/python3`, allowance one invocation, 10s maximum):

```sh
/usr/bin/python3 -I -B -c 'import json,runpy,unittest; n=runpy.run_path("docs/planning/poc/client-framework/native-lab/Tests/test_build.py"); r=unittest.TestResult(); n["BuildTests"]("test_signal_failure_does_not_skip_direct_child_reap").run(r); print(json.dumps({"case":"test_signal_failure_does_not_skip_direct_child_reap","tests":r.testsRun,"failures":len(r.failures),"errors":len(r.errors),"passed":r.wasSuccessful()})); raise SystemExit(0 if r.wasSuccessful() else 1)'
```

This checks only the skipped-reap regression; it cannot qualify TERM/EOF or actual processes.
No full suite until these source corrections and hashes are frozen/reviewed. A later fresh
finite grant must bind that corrected package and the same 18-case suite, once per named target.
Use only failure case IDs selected from the frozen 18 unittest names and ≤2 capture records
per case, with whitelist command/exit/deadline/bytes/drained/fd_closed/reaped/cancelled/
group_observation/ownership plus the three finite fields above. Bound summary to 16KiB;
omit unittest tracebacks/messages/raw diagnostics. No failure-driven extra observation/retry.
If still failing, retain the finite case/cause evidence and stop for review; unknown is unknown.

Compiler stays disabled until a passing reviewed suite and separately bound compile-only
grant; vendor effects remain trusted-vendor-not-denied. Compilation cannot qualify app,
GUI, engine, descendant containment, signing or NE. G0-06.2d and final G0–G6 gates remain.

## Corrected source review

Accept the implemented driver repair and finite 18-name/≤2-record summary. The reviewed
flood case accepts overflow, or cleanup iff primary_error overflow, first group_stage identity,
group_errno absent, bytes[0] >65536 and drained/reaped/fd_closed all true. No pre-observation,
permission/other, undrained or unreaped failure passes; TERM-ignoring SIGKILL checks remain.
This is a no-fork fixture's safe negative guard, not universal group-cleanup qualification.
Exact full18 command for the named local target below:

```sh
/usr/bin/python3 -I -B /Users/joker/Documents/EasyNet/docs/planning/poc/client-framework/native-lab/Tests/test_build.py
```

## Final local successor binding — accepted

Root implemented precisely the six-line flood assertion branch above; static recheck accepts
tests SHA256 `ed9f3345cbc06cfce31215703e34f1f5f7239d080e931c27dd385438e07b70e7`.
Tests now 386 lines; accept a narrowly increased ≤390-line cap for these assertions only.
Driver remains SHA256 `5db8e29126fb97fcd3dc14721ec4895c3f4cbd222e9ffbf4dd9f98a4f136fb50`.
The earlier testcase blocker/proposed status is superseded for exactly these two hashes.
Authorize `native-capture-successor-local18-v1` once, ≤70s, cwd `/Users/joker/Documents/EasyNet`,
≤16KiB JSON stdout, using the exact full18 command above. No separate mock invocation remains.
This is a fresh reviewed material successor under the user's continued-work authorization;
old 17-case/local/hosted/ar/av budgets stay zero. A passing suite qualifies these synthetic
cases, including case-specific primary refusal; it does not qualify group containment.
Any failure preserves bounded case/capture evidence and stops without another run. Compiler,
guest and hosted grants remain absent; future engine/GUI/NE/full acceptance gates stay intact.
Only static source/hash/diff checks ran here; root executes the granted invocation.

## Local evidence accepted; one conditional hosted successor direction

Root's [finite local record](native-capture-successor-local-record.json) reports 18 tests,
zero failures/errors/skips, passed fixture cleanup, empty failed_cases/captures. Root reports
exit 0 and 137-byte stdout. Static rehash confirms both final accepted hashes unchanged.
Accept this exact synthetic scope; named local attempt consumed 1→0. All older budgets stay 0.
Passing aggregate evidence does not identify which permitted negative-guard branch occurred.

Accept preparation of one new hosted18→compile-only binding for this corrected package.
Before activation/push, freeze a new source checkpoint, literal feature/checkout SHA,
contract digest and complete five-file manifest; review the final activated workflow hash,
inline public binding and unique activation commit/message together. Existing dormant false
gate/empty inline binding remains non-executable until that review. No fresh helpers/research.
Use one fresh macos-15 hosted target, no matrix/secrets/signing, read-only permissions and
the existing ≤10-minute job, ≤60s synthetic/≤185s driver subprocess limits and 16KiB records.
Only exact passed18/empty failure evidence unlocks compiler within that single job. Any
failure/timeout stops; no retry or independent compiler attempt. The selected vendor compiler
trust exception remains compile-only. No guest/app/GUI/engine/NE or G0 completion is accepted.
This direction permits binding preparation; execution still requires final immutable review.

## Hosted successor activation package — scoped acceptance

Source checkpoint `b7c21bc0059fb7fa2a845f359e987cbf06514bb2` matches accepted driver/tests,
Host/plist, contract digest and consumed original binding. Its dormant workflow digest is
`3942cbfcec6042440508fea828bbbb86c6d40eeff964c735b64449a91a1f6ff9`.
Accept final activation workflow SHA256
`6cae26f85b867acf70990fee9465b15b222142bef7b216b21fea62067909f9de` and successor archive SHA256
`b9ede1a91a39e25c991a0b42df275c8f34cd38a4271bee9f01b05c9048d54d50`.
Static calculation verifies inline/archive equality and manifest
`70d428f04502861f2e34c11c6632107d3bdeb9902c4dbe03f7e25d2ad0d0ea92`.
These digests have separate scopes: five source entries include the checkpoint's dormant
workflow; the activation digest covers the executable bootstrap/inline grant reviewed here.
No activated-workflow self-hash or replacement source digest is implied.

Accept 78 workflow lines under a narrow ≤80-line exception to the former 75-line cap.
The four added bootstrap lines verify the fixed original consumed-binding digest, require
status consumed/guest_remaining 0, then unlink only its ephemeral checkout copy after the
passing synthetic gate, before the driver's unchanged O_EXCL runtime-binding write. The
archived original grant remains consumed; separate successor archive records the new grant.
This permits fixed-path binding substitution, not arbitrary checkout deletion or budget reset.

Grant `native-capture-successor-hosted18-v1` one fresh macos-15-arm64 job, hosted allowance
1→0 on attempt, local allowance 0. The exact push-only repository/feature/message predicate is
`Run one native capture successor b7c21bc0059fb7fa2a845f359e987cbf06514bb2`.
Checkout remains the literal source checkpoint; only exact passed18/empty failure evidence
unlocks one conditional compile within that job. Preserve existing time/output/trust limits.
No workflow_dispatch run, manual rerun, independent compile or old-grant replenishment.
Root must first supply the actual activation commit SHA for final static identity approval;
this acceptance does not yet authorize push of an unidentified commit. After observation,
disable the gate and archive the successor's consumed outcome/remaining 0, even on failure.
No tests/toolchain/candidate ran in this review. App/GUI/engine/NE/G0/final gates remain intact.
