# Product planning

These documents describe proposed evolution, not already implemented features.
The current implementation remains the Bash deployment tool documented in the
root README. Technical choices require evidence and an ADR before implementation.

- [Agent execution and feature branch policy](agent-execution-policy.md) — low-cost task cards and final merge gate
- [Task cards and per-card models](task-cards/README.md) — 259 independent cards with prerequisites, behavior cases and unlock conditions
- [Model routing and cost calibration](model-routing.md) — Luna/Sol/Astra roles, review and escalation
- [Main-session/subagent usage comparison](agent-cost-comparison.md) — measured cache/token baseline and per-task comparison method; cost winner unproven
- [Atomic task catalog](atomic-task-catalog.md) — 168 original entries mapped to the concrete task cards
- [Executable phased backlog](execution-backlog.md) — current task IDs, dependencies, deliverables and gates
- [Product evolution roadmap](product-evolution-roadmap.md) — consolidated product direction and staged capabilities
- [Frozen capability baseline](capability-matrix.md) — code eligibility, tested fixtures, and unknown live support
- [Reviewed application-service contract examples](contracts/README.md) — six bounded examples and production extension gates
- [Reviewed local-state lab contract](poc/local-state/state-lab-contract.md) — common owned JSON/SQLite experiment cases; runtime qualification pending
- [Accepted controller language decision](adr/ADR-004-controller-language.md) — Go service foundation, candidate evidence and production gates; current Bash preserved
- [Go SSH candidate gate](poc/controller-language/go-ssh-results.md) — reviewed loopback SSH fault matrix; production language selection pending
- [Go scoped vault evidence](poc/controller-language/go-vault-results.md) — owned temporary file-Keychain pass; production vault selection pending
- [Go result CLI and host packaging](poc/controller-language/go-result-results.md) — strict redacted record and actual host artifact facts
- [Go–Rust IPC gate](poc/controller-language/go-rust-ipc-results.md) — owned child lifecycle passed; Rust SSH sessions remain pending
- [Rust KEX transport gate](poc/controller-language/rust-transport-results.md) — reviewed owned-loopback success/refusal/deadline/cancel pass; auth and dispatch pending
- [Rust signed-auth gate](poc/controller-language/rust-auth-results.md) — actual signed success/refusal/deadline/cancel pass; commands pending
- [Rust fixed-command gate](poc/controller-language/rust-command-results.md) — six actual completion/overflow/deadline/cancel cases passed; full fault qualification pending
- [Rust candidate B SSH gate](poc/controller-language/rust-ssh-results.md) — 33 actual SSH scenarios, full command exit semantics; Rust vault/result and language choice pending
- [Rust SSH bridge contract](poc/controller-language/rust-ssh-lab-contract.md) — reviewed design; dependency/frame/control gates passed, full SSH runtime pending
- [Rust SSH source preparation](poc/controller-language/rust-ssh-preparation.md) — pending candidate, ack and task-join pitfalls
- [Native vault experiment contract](poc/controller-language/vault-lab-contract.md) — scoped temporary helper and safety gates
- [Controller language candidate evidence](progress-2026-10-07.md) — three reviewed candidates and SSH PoC prerequisites
- [G0 first-batch completion](progress-2026-10-06.md) — accepted design decisions, checks and next ready card
- [Repository audit and gap analysis](repository-audit-2026-10-06.md)
- [Phase 1 proposed issues](phase-1-issue-plan.md)
- [Total Epic body](self-hosted-epic.md) — published as [#13](https://github.com/EasyIndie/EasyNet/issues/13)

The initial handoff has been consolidated into these project documents and removed.
Future work should update the roadmap, ADRs and linked issues rather than preserve
one-off execution prompts. Proposed issues remain proposals until explicitly opened.
