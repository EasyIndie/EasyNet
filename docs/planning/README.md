# Product planning

These documents describe proposed evolution, not already implemented features.
The current implementation remains the Bash deployment tool documented in the
root README. Technical choices require evidence and an ADR before implementation.

- [Agent execution and feature branch policy](agent-execution-policy.md) — low-cost task cards and final merge gate
- [Task cards and per-card models](task-cards/README.md) — 220 independent cards with prerequisites, behavior cases and unlock conditions
- [Model routing and cost calibration](model-routing.md) — Luna/Sol/Astra roles, review and escalation
- [Atomic task catalog](atomic-task-catalog.md) — 168 original entries mapped to the concrete task cards
- [Executable phased backlog](execution-backlog.md) — current task IDs, dependencies, deliverables and gates
- [Product evolution roadmap](product-evolution-roadmap.md) — consolidated product direction and staged capabilities
- [Frozen capability baseline](capability-matrix.md) — code eligibility, tested fixtures, and unknown live support
- [Reviewed application-service contract examples](contracts/README.md) — six bounded examples and production extension gates
- [G0 first-batch completion](progress-2026-10-06.md) — accepted design decisions, checks and next ready card
- [Repository audit and gap analysis](repository-audit-2026-10-06.md)
- [Phase 1 proposed issues](phase-1-issue-plan.md)
- [Total Epic body](self-hosted-epic.md) — published as [#13](https://github.com/EasyIndie/EasyNet/issues/13)

The initial handoff has been consolidated into these project documents and removed.
Future work should update the roadmap, ADRs and linked issues rather than preserve
one-off execution prompts. Proposed issues remain proposals until explicitly opened.
