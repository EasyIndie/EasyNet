# Q-B native compile preparation — independent R source review

2026-10-10. Reviewed only native-build-contract.md, native-lab/Host.swift, Info.plist,
build.py (376 lines), Tests/test_build.py (202 lines), and the disabled native workflow.
Disposition: **changes required; no synthetic execution grant yet**. No tests, compiler,
GUI, engine, download, guest, secret or historical ar/av workflow executed by this reviewer.
This is one consolidated correction packet for the existing I package, not a new task chain.

## Accepted source/effect boundaries

Host is an actual SwiftUI App/WindowGroup with four disabled controls and honest unqualified
state; no simulated readiness, macro, process, network, storage or permission effect.
Plist is the fixed ordinary app identity and OS floor, with no entitlement/background mode.
Driver has standard-library imports, closed child environment, argument arrays, no candidate
binary launch, no signing/settings/credential operation and finite result emission.
Absent binding refuses before build. Main resolves the repository from its fixed source path.
Manifest has the exact five-file allowlist, byte/mode/digest checks, workflow/contract hashes
and full feature/checkout assertions. These assertions do not independently prove checkout:
the future trusted launcher must establish Git SHA and Python identity before candidate import.
Workflow is inert (`if: false`, zero SHA, unconditional refusal), pinned checkout action,
read-only permission, no secrets, no upload, ten-minute limit. This is acceptable preparation;
verification-before-import must be implemented/reviewed in the later activation binding.
Fresh-vendor compile trust is legitimate within this reviewed inert-source scope. Full
toolchain-library hashes, Apple account, NE profile and visible GUI are not compile prerequisites.
The trust exception supplies no external-denial or arbitrary-descendant runtime qualification.

## One actionable correction packet

1. **Process ownership, drain and cancellation — blocks synthetic grant.**
   `build.py:118,143` calls `poll()`, which can reap the session leader while inherited
   writers remain. A later timeout cannot safely signal that group; the test at `test_build.py:136`
   only covers an inherited writer that finishes quickly. `build.py:157–163` probes a group
   after reaping and cannot prove owned-group absence against reuse. Preserve an unreaped
   leader through abnormal TERM/KILL cleanup; on natural pipe EOF, use bounded wait and
   record group observation as not-requested/not-proven instead of a post-reap identity claim.
   Guard against inherited SIGCHLD auto-reaping/replacement of child wait ownership.
   Continue bounded pipe draining during TERM/KILL/reap; closing unread pipes is not `drained`.
   SIGTERM currently bypasses Python finally blocks; install bounded sticky cancellation
   handling, restore handlers, and avoid a second signal interrupting cleanup. KeyboardInterrupt
   must also preserve cleanup/results. No group signal after identity/reaping becomes ambiguous.
   Add safe owned fixtures for early leader exit plus a hung inherited writer, flood/TERM output,
   and cancellation during capture; an independently held fixture owner must guarantee test
   cleanup even if the function under test fails. Do not run a leak-producing regression first.

2. **Deterministic generated inventory and failure cleanup — blocks acceptance.**
   `build.py:305,312,337` snapshots sorted top-level names, while `cleanup():256` inventories
   unsorted `iterdir()` names. Multi-directory cleanup can reject identical content solely
   because enumeration differs. Canonicalize ordering everywhere; add a multi-directory test.
   `run():309–312` inventories only successful capture. A failed compile that creates tmp/cache/
   output entries therefore uses the old manifest and retains the root, masking the primary
   error as cleanup. After bounded process cleanup, inventory allowed generated subtrees on
   failure/cancel as well, keeping source/plist and nongenerated paths frozen. Retain on unknown
   types/ownership/links/bounds or ambiguous live processes; do not adopt unexpected src/result
   entries. Preserve a finite primary failure alongside retained-root cleanup evidence.

3. **Selected SDK and compiler entry — fix before any hosted build.**
   `identity():182` demands the literal SDK locator string equal `MacOSX15.5.sdk`; a vendor
   `MacOSX.sdk` alias with that exact canonical target is legitimate under the contract.
   Keep the exact logical Swift locator requirement, but compare the selected SDK's existing
   canonical directory with the frozen expected SDK and selected-Xcode boundary. No fallback
   toolchain or different SDK. Test both safe alias and outside-tree rejection without vendor
   execution. `identity():185` reads/hashes the entry with an unsupported 64MiB ceiling;
   an alias to a larger frontend could reject the selected vendor tool before qualification.
   Use a separately explicit finite entry limit and streaming hash with bounded chunks/shared
   deadline; report identity rejection on violation, not source mismatch. Actual entry size/
   version/hash remain unknown until the separately granted build; do not probe them here.

4. **Artifact claims — fix or explicitly review a narrower contract claim.**
   `artifact():205–216` validates generic framing and LC_BUILD_VERSION, but accepts the
   56-byte test fixture with no loadable segments or entry point. An arbitrary length-eight
   known segment/entry command also passes. This supports header/framing evidence, not the
   contract's valid executable/load-command claim. Add bounded LC_SEGMENT_64/LC_MAIN structure,
   file-range/entry checks appropriate to the compiler executable and malformed cases, without
   launching an artifact. Alternatively root must explicitly accept a narrower framing-only
   evidence statement; do not silently label a malformed executable validated.

5. **Whole deadline and finite observation semantics — finish in the same correction.**
   Shared 180s deadline currently constrains capture but not source/hash/inventory/artifact
   phases or the final success decision. Check the shared deadline at phase/chunk boundaries
   and reserve cleanup time consistently. Five-second metadata calls deliberately reserve
   four seconds for cleanup: document the effective one-second work allowance, do not silently
   extend it. `build():320` stores unvalidated metadata stdout before baseline rejection;
   emit fixed mismatch status/validated bounded fields rather than raw rejected tool output.
   Compiler version needs a finite validated printable representation. Add synthetic whole-
   deadline and rejected-output cases; never execute a vendor tool to obtain these fixtures.

## Return and next grant

Repair only driver/tests; report any concrete line-budget shortfall rather than compressing
code or dropping cases. Root may amend narrowly necessary result/group semantics in the
contract. Return updated source hashes and one consolidated static review follow-up.
The existing tests include real bounded owned Python subprocesses; they are not a compiler
grant. Once the ownership fixes and safe regression harness are reviewed, root can freeze
the trusted absolute Python interpreter and grant only `-I -B` plus the absolute
`/Users/joker/Documents/EasyNet/docs/planning/poc/client-framework/native-lab/Tests/test_build.py`
path, fixed repository cwd, finite suite deadline/output and owned temporary-fixture cleanup.
No exact runnable grant is issued here while item 1 can leave an owned descendant alive.
Compile/GUI/engine/NE remain unexecuted; .2d stays locked and old budgets remain zero.

## Consolidated repair follow-up — synthetic grant accepted

Reviewed the repaired driver/tests and amended contract (driver <=520, tests <=300).
All five packets above are resolved for this compile-preparation scope: unreaped ownership,
sticky signal cancellation and cleanup draining; canonical fixed/generated inventory on
success/failure; exact canonical SDK and bounded streaming entry hash; segment/entry artifact
checks; shared deadline and validated finite observations. Natural EOF records group as
not-requested and supplies no arbitrary-descendant qualification. The independent hung-writer
fixture uses its private FIFO and live current owned group, with a six-second self-expiry;
it never signals a remembered/reaped PID. Other direct sleep fixtures are finite (30 seconds).
The last mechanical repair compares stable dev/inode/mode/size/mtime_ns/ctime_ns at both
entry-hash fstat checks, excluding read-mutated atime; those exact edits were inspected.

Frozen SHA-256, verified by root before command:
- `build.py` (511 lines): `15a8d3053d430be4e33d311372d68addf74f63dc6aecaf3686d8812fbe78f35b`
- `Tests/test_build.py` (299 lines): `c88b1cb8674fec91e0e86414e0d6897325026851562043e71c65fa291f78e487`

Grant exactly one root-executed synthetic suite, cwd `/Users/joker/Documents/EasyNet`:
```text
/usr/bin/python3 -I -B /Users/joker/Documents/EasyNet/docs/planning/poc/client-framework/native-lab/Tests/test_build.py
```
Suite deadline <=60 seconds; retain <=4096 output bytes while draining; bytecode disabled.
Only trusted reviewed standard-library tests and owned synthetic Python subprocesses;
compiler identity/SDK fixtures are mocked. Root runner may signal only its verified direct
child on suite failure/cancel, never an unverified descendant/group. Owned temp cleanup and
fixture expiry remain bounded. Any hash change invalidates this grant. Expected: all tests
pass and no owned fixture residue; failures retain bounded evidence and require correction.
This authorizes no compiler, engine, app/GUI, dependency download, guest, secret, signing,
workflow activation or renewed historical probe. Reviewer executed no test. Actual synthetic
results remain pending root execution; .2d and compile execution remain separately locked.

## Local result and independent hosted disposition

Root's once-only local observation: 14/17 pass, three cleanup assertions fail (flood,
early-exit writer, TERM output), 2.477s, with an unreaped-direct-child warning. The failed
OS predicate and cause remain unknown; this proves neither a code diagnosis nor qualified
local group semantics. Local budget is zero: no rerun, exploratory probe or name/PID cleanup.
**Accept the independent hosted conditional-build direction; no execution grant issued yet.**
One new fresh `macos-15` job may run the frozen synthetic suite, then the fixed trusted-vendor
compile only if exactly 17 tests pass with zero failures/errors/skips and finite cleanup
evidence. Local failures stay recorded; hosted success would qualify only its actual target.
Mandatory small source changes: buffer/cap unittest diagnostics and emit only a finite JSON
count/result record (no raw paths/logs), retain finite fixture expiry, and prepare the exact
immutable source binding plus disabled workflow's trusted verification-before-import bootstrap.
Review their final hashes before granting the one guest; no extra helper or diagnostic stage.
Synthetic timeout/cleanup ambiguity/non-pass prevents compiler invocation and ends this job's
budget. Compile failure/cleanup ambiguity likewise stops; no automatic rerun or fallback.
The accepted vendor-compile exception remains narrow; no engine/GUI/NE/secret execution,
ar/av restoration, external-denial claim or arbitrary-descendant qualification follows.
Current concrete block is the unreviewed finite test entry and exact hosted bootstrap/binding,
not another local experiment, Apple credential, full library-hash gate or isolation redesign.

## Finite entry and dormant bootstrap accepted

Reviewed only the revised test entry/tearDown, 73-line workflow and contract budget changes.
**Accept source bootstrap for checkpoint/binding preparation; no guest execution grant yet.**
Test entry buffers diagnostics and emits only JSON counts/status; tearDown asserts owned
root removal. Bootstrap checks literal checkout SHA, exact five-file hashes and manifest/
contract digests before test import; fixed 17-pass/zero-error/failure/skip plus cleanup record
is required before exclusive fixed-path binding creation and compiler-driver invocation.
Suite timeout 60s, compile-driver timeout 185s; no raw test diagnostics are published.
The workflow remains inert: job false, source SHA zero, binding empty. Activation must bind
the source checkpoint SHA, exact inline binding, reviewed final workflow digest/action pin
and once-only trigger; their final review is the remaining execution prerequisite.
Frozen SHA-256: tests `ccaca6f95bede58d54f77205a3cb9a74c6621fb42c59a5608ddf4f2af0bae1df`
(313 lines); workflow `789c40cf336bf316594442d69b907f906d1a3587458c2f37af1f89b4d86175da`
(73 lines); contract `6db69f2c08a7ef729aac87b1b3948632792a303c7c37c1c3736e4b7732bd1b337`.
Driver remains the reviewed 511-line `15a8d305…be78f35b` snapshot above. No new helper,
diagnostic stage, local rerun or expanded runtime privilege is required or granted.
