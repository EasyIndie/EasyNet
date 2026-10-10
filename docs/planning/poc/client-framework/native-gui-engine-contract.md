# Native GUI / engine source contract preparation

Date: 2026-10-10. Branch: `codex/feature/self-hosted-byos-byoc`.
Status: **planned; not frozen and not ready for GUI/engine implementation or runtime**.
Scope: Candidate B proxy-mode source preparation; no framework/engine/product ADR selection.
This document grants no import, test, compiler, SDK read, download, window, engine, credential or guest operation.

## Accepted facts and authority boundary

- [Native build contract](native-build-contract.md), its SDK-producer successor sections, and
  [producer source review](../../task-results/G0/sdk-producer-source-review.md) accept only the limited unsigned build.
- [Actual record](../../task-results/G0/sdk-producer-hosted-records.json): run `38052833576`, source
  `fc71a550a532a899e19fbe1ae4c1102bc4b94a7f`, full21 synthetic PASS then original compile/artifact PASS and cleanup removed.
- Baseline: macOS15.7.9/build24G830, image20260907.0337.1, arm64, Xcode16.4/16F6;
  Apple Swift6.1.2 (`swiftlang-6.1.2.1.2 clang-1700.0.13.5`), minimum15.0, SDK15.5.0.
- Compiler logical path: `/Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc`;
  resolved swift-frontend SHA `bf77cc8826cd1a74f1a9734c5c63a182bd26b9472682b58f01e435cc064e1bc8`,356421520B.
- SDK logical path: `/Applications/Xcode_16.4.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.5.sdk`;
  SDKSettings6953B/SHA `58a133735f0a55a624a1703067059f6e78925e51725ec6e1f966072e142c9c42`;
  Version15.5.0, CanonicalName macosx15.5, MaximumDeploymentTarget15.5.99.
- Candidate was not executed; GUI/engine/NE not-run; external-effects=`trusted-vendor-not-denied`.
  These identities can be successor predicates; a future guest must match them, not inherit a PASS.
- All old grants are consumed0 and workflows disabled. Prior window/image refusal is un-attributed;
  do not revive it, claim it solved, or treat native build acceptance as validated GUI/Python3.14.
- Only personal development Mac and hosted runner are confirmed. Paid Apple account availability
  proves neither NE profile nor entitlement/provisioning/signing/consent. Q-NE remains separately blocked.

## Source baseline and smallest reuse boundary

`native-lab/Host.swift`:26 lines/880B, SHA `189c478947d08115be289b553f23203d6f2bcf3cbc9001c4256bcb5b857d9a32`;
disabled inert buttons, no controller, engine, event/render proof or guardian.
`native-lab/build.py`:820 lines/40288B, SHA `5c90c9f83f1ccb299f98f7046dcfe1ae09404c2f1ce2f2a55f14286df7548a83`.
Retain it as the accepted compile implementation; do not copy it into a new admission driver.

| Existing unit | Reuse allowed after successor source/hash review | New proof still required |
|---|---|---|
| `sources`, `regular`, `digest` | Exact path/type/mode/size/hash admission pattern | Freeze new FILES/caps/manifest and pre-import launcher; regular-file stability for new hostile inputs |
| `identity`, `entry_hash`, `read_sdk_metadata` | Qualified Xcode/Swift/SDK and SDKROOT mechanism | Same guest identities/fingerprint; no silent version replacement |
| `artifact` | Preserve bounded thin arm64 executable, SDK15.5/min15.0, segments/entry/plist predicates | Changed source artifact; extra source/compiler argv must be reviewed |
| `capture`, `Cancellation` | Bounded concurrent drain/deadline/reap and held direct-child pattern | Independent guardian survival, group inheritance/no-daemon, host crash/EOF, decoy denial |
| `inventory`, `adoption`, `cleanup` | Finite manifest ownership and retain-on-uncertainty pattern | Runtime roots/ports/FDs/processes; do not extend adoption to arbitrary files |

Current build compiles only Host.swift and has exact source/grant pairs; it cannot compile added Lifecycle/Guardian
or run GUI/engine unchanged. Preserve its21 cases and artifact predicates. Successor build adaptation is a
separate source-only card after the Swift source layout is reviewed; no xcodebuild/project generator is needed
merely because the earlier preparation suggested one. Reusing patterns is not importing/executing the candidate.

Old `poc/client-framework/window-admission/driver.py` is a reference only;
only identity profile, binding/effects and admit/report interfaces were inspected. Its exact-true effects map
is an admission obligation, not evidence those effects occurred. Its Python3.14.7 identity is not native GUI qualification.
Reuse its finite refusal/result pattern if useful; do not copy/revive its driver, workflow, binding or diagnostic system.

## Proposed source package and interfaces — requires fact freeze and R review

Use the paths already proposed by [native preparation](native-lifecycle-preparation.md), all under
`docs/planning/poc/client-framework/native-lab/`: `Host.swift`, `Lifecycle.swift`, `Guardian.swift`;
tests: `Tests/LifecycleTests.swift`, `Tests/WindowTests.swift` (three implementation/two test writes).
Guardian is a separate process owner, not an in-host cleanup callback; executable/launch topology remains unfrozen.
Do not add a second Python admission driver, project, package manager, embedded libbox or NE provider.

Proposed narrow interfaces (names/types are design proposals, not accepted platform/schema facts):
- `FixtureSpec`: owned config/engine paths, numeric SOCKS/echo IPv4+ports, nonce and run token; no subscription/URL/shell text.
- `connect(spec, generation)`, `cancel(generation)`, `stop(generation)`, `restart(spec, generation)`;
  serialized controller publishes `state`, finite `error`, `generation`, `runToken`.
- `Guardian.start(spec)` returns verified owned host/child/group identities and control/EOF channel;
  `Guardian.stop(generation, absoluteDeadline)` returns exit/reaped/drained/FD/port/manifest evidence.
  Identity representation and signaling/reaping protocol must be frozen from source facts before authorship.
- `Host` renders Connect/Cancel/Stop/Restart plus observable state/error/generation; controls call controller only.
  Own-window event/render evidence must associate the active generation with each actual action and visible update.

Admission inputs must be exact-key versioned fixtures, with strict bounded integers, paths, hashes, nonce and enum errors.
No concrete JSON/config/guardian wire schema is frozen here. The fact card below must supply its justified fields;
unknown profile grammar, system effects or process identity semantics must not be filled by implementation guesses.
Suggested ample review ceilings: Host≤600 lines/32KiB, Lifecycle≤900/48KiB, Guardian≤900/48KiB,
each test≤1000/64KiB; total≤256KiB. These are proposed authoring limits, not runtime FILES admission.
Exceeding them triggers one scope review; never delete cases/compress code solely to pass the cap.

## Preserved common acceptance cases and effects

Carry [common lifecycle](lifecycle-preparation.md) into native source/tests and later actual GUI suite:
1. Complete SOCKS5 greeting+numeric CONNECT+HTTP exchange+exact nonce → visible ready; spawn/log/listening alone fails.
2. Stop → idle after drain/reap/FD closure; three Connect/Stop cycles reuse both ports and leave no manifest residue.
3. Forced engine crash → failed; explicit Restart reaps old owner before new generation/nonce readiness.
4. Duplicate/concurrent Connect creates exactly one child; stale generation completions cannot set ready.
5. Cancel before spawn and during readiness → no ready/leak; invalid config and occupied port → finite failed evidence.
6. Silent/hung readiness, output flood and absolute timeout → bounded failure with full teardown evidence.
7. Window close, forced host crash, harness failure/cancel and control-pipe EOF → surviving guardian reclaims owned work.

Keep proposed start/probe5s, IO1s, TERM2s, KILL/reap2s; case15s/suite180s absolute monotonic budgets including cleanup.
Retain64KiB per output stream with total counters and continued drain; overflow fails. Future suite/report caps
must include all cases, identity/UI/guardian work and teardown; no budget declared adequate until reviewed.
Every actual case records visible state/actions/generation, owned identity, nonce/exit/deadline/output/FD evidence,
group absence, both listener ports reusable and owned files gone. Leaks/ambiguous identity fail and stop reuse.

Require actual foreground own-window visible/key/active/non-minimized/occlusion proof and normal event-loop
Button actions/rendered updates. Preserve the [own-window admission](runner-window-qualification-contract.md)
negative controls and synthetic own-region render hashes; no direct callback/performClick/headless substitution.
No global input, unrelated-window/desktop capture or new TCC permission mechanism is implied by this proposal.
Engine is pinned CLI1.14.2 archive `sing-box-1.14.2-darwin-arm64.tar.gz`,
SHA `925c5382eca8492b0150f868a6db20b18290a38700e621724b3703fd453e032d`; archive has not been fetched/validated.
Exact config must allow only owned numeric loopback echo via SOCKS, default reject, no DNS/upstream/TUN/system proxy/routes.
Freeze reviewed archive entries/hash/extraction/permission bounds before any download or extraction.
Require separate reviewed Q-B default-deny launcher, allowed owned reads/writes, denied sibling synthetic decoy
reads/writes and external destinations, inherited child denial, reviewed GUI/Mach allowances/effects and no-daemon behavior.
Guest isolation alone, environment relocation, or a boolean effects map cannot discharge these obligations.

## Finite gaps and next single card

The independent SOURCE implementation card is **planned** until exact1.14.2 config/argv/route/exit semantics,
own-window/source mechanism and GUI effect manifest, guardian identity/group inheritance/EOF protocol,
Q-B profile syntax/inherited enforcement plan, and successor source/build manifest receive R disposition.
Observed visibility/modern sandbox efficacy still require a later separately granted actual target; source review
cannot claim them proved. Failure consumes its future bounded attempt; no automatic retry, guest or diagnostic expansion.

Next card: **NATIVE-ENGINE-FACTS-1**, status planned pending root/R scope acceptance; C collects facts only; separate R interprets/approves.
Single goal: trace the smallest real1.14.2 numeric-loopback proxy config; no CLI/process/guardian/GUI investigation.
Inputs: this document engine/common-case sections and `native-lifecycle-preparation.md` pins only.
Allowed write: `docs/planning/poc/client-framework/native-engine-source-facts.md` (≤120 lines/20KiB) only.
No review file, code/bindings/workflows; `native-engine-source-facts-review.md` is reserved for subsequent independent R.
Official queries: GitHub Contents `/repos/SagerNet/sing-box/contents/option?ref=v1.14.2` only;
second permitted directory `/repos/SagerNet/sing-box/contents/route?ref=v1.14.2` only if option types leave direct/reject semantics unresolved.
Budget≤2 directory metadata responses (≤64KiB each), ≤4 inert source files (≤128KiB each/aggregate≤384KiB).
Select only files listed by those responses that define SOCKS/listen, route match/action/default, direct/reject;
record exact path/blob ID/size before retrieval and SHA/line citations after. No recursive tree, search or unrelated directory.
Missing tag/path/field, response above cap or needed fifth source → finite unavailable finding; stop retrieval, no alternate ref.
Do not assume current website docs equal1.14.2. No binary/archive/SDK downloads, imports, tests, commands or guests.
Fields to resolve: SOCKS inbound type/listen/port; numeric destination IP+port match; direct action/outbound and
default reject; any DNS/resolve defaults affecting this fixture. Output field/default ledger with tagged source
citations and finite missing fields; C does not approve a config or infer semantics beyond the cited text.
Unsupported restriction blocks later R config freeze. Do not invent schema.
Validation: exact source provenance/caps, config-to-source field trace, relative document links, `git diff --check`;
no executable acceptance. Escalate if schema/default semantics or extra sources remain unresolved.
Then root prepares one bounded GUI/guardian/Q-B fact-review card; do not mark the full implementation ready after engine facts alone.

Q-NE/profile/signing/system consent, real protocol client gates, final ADR dispositions, fullG0 and all G0–G6/main gates remain.
