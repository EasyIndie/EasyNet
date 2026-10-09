# G0-06.2ap — driver/reader binding consistency repair

Proven source conflict at ao@18199e7: attribution_diag.py reads ao binding, but attribution_record.py main still reads an binding before executing driver guard.
an retains the previous driver hash; the ao driver differs. Thus the helper rejects the current driver source before scan and emits unknown. This explains a guaranteed rejection path in ao; initial an failure remains unexplained.
Fix both fixed binding identifiers to ap, preserve all historical an/ao bindings, and freeze the same exact eleven source paths.
After guarded driver compilation, require its BINDING to equal the reader's fixed binding path before guard.verify/scan. No caller-controlled selector or dynamic fallback.
Reader retains six-field schema; driver retains seventh literal driver_step; no extra report data or failure reasons.
Regression test must make Path.read_text path-aware against the actual import-safe driver BINDING rather than returning one fake binding for any path.
Test good current binding reaches exactly one mocked scan; stale binding/source hash/path mismatch stops before scan, plus existing parent/HOME/posthash failures. No real logs/fixture/native calls in fakes.
Same original profile, candidate selectors, lifecycle, clocks, limits and cleanup guards; no permission widening or runtime/framework decision.
Root Sol medium performs the bounded mechanical fix; fresh independent R Sol high reviews proposal/diff/exact hashes before any authored imports/fakes.
One newly repaired GitHub observation only after passing controlled suites and independent concrete runtime binding review. No unchanged rerun, no local native, no raw logs, no retry after unknown/failure.
Source/fake validation cannot qualify full isolation/SDK/GUI; outcome unknown stays blocked. Two targeted repairs maximum.
