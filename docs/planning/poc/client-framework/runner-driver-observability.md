# Bounded driver-step observability — G0-06.2ao accepted contract

an@f3b6d2d produced all unknown; its failure step cannot be inferred. This extends only driver output, not crash interpretation or access.
The am crash reader contract remains unchanged: exactly six sanitized fields, same filesystem selectors and bounds.
The outer driver emits those six fields plus `driver_step`, a literal controlled entirely by driver code.
Allowed values: preflight, source, fixture, target, target-validation, delivery, reader-arguments, reader, reader-validation, report, cleanup, final-check, complete.
Set the step immediately before entering each bounded block, retain it on exception; complete only after every existing final guard passes.
The field identifies the last block entered, not the precise failing guard, a completed operation, a crash image or cause.
Preflight covers host/environment guards; source covers source verify/load; fixture covers existing isolated setup.
Target covers existing once-B call; target-validation includes post-target hash/health/clock guard. Delivery covers existing 3-second wait and its subsequent guards.
Reader-arguments covers existing argument/fixture checks; reader covers existing once-helper call. Reader-validation covers subsequent hash/schema/health/clock checks.
Report covers observed-outcome/no-live checks and pre-clean hash; cleanup covers existing bounded cleanup; final-check covers post-clean hash/deadline.
Unknown still resets all six crash fields to the am unknown values. Never export exception strings, raw fields, filenames, PID/time, environment or logs.
Use a local state object shared only by main and sequence; no data from the record may set driver_step. Reader never accepts the new field.
Change only driver, its existing fake tests, new binding/contract/report and planning bookkeeping. Preserve old reader, original profile and lifecycle implementation.
Driver binding moves to ao; preserve an frozen binding as historical evidence. Freeze exact same 11 source paths after independent review.
Do not widen permissions, read extra paths, add launches/queries, change deadlines, cleanup qualifications or framework/runtime choices.
Mechanical implementation in root Sol medium; independent R Sol high checks this contract and resulting diff; no separate implementation worker for this small change.
Controlled fake faults verify step retention and unchanged fail-closed behavior; existing reader results reused if reader/hash unchanged.
Any future native attempt needs reviewed source hashes, passing fakes and once-only evidence under a separate explicit runtime binding. No native run authorized by this proposal alone.
Two focused repairs maximum. Native failures remain blocked; do not unlock G0-06.2a or SDK/GUI gates.
