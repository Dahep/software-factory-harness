# The v1 issue-driven loop: owner at two checkpoints, gates in the harness

Factory's first milestone is the issue-driven loop — intake → triage → implement → gates → review → PR → merge — and its shape commits the harness to owning the gate, not judging it. The Owner approves the triage decision and the merge; every step between runs agent-side under deterministic, harness-enforced gates whose failure policies are themselves workflow-defined. Waves are workflow data (default: one implementer, two reviewers), projects are adopted by an in-repo Workflow Artifact added through an init PR, and Factory adopts itself first so it manages its own changes from then on.

## Considered Options

- **No triage step in v1 (label-gated intake)** — rejected: triage is the agent step most worth proving, and it is where scope is set.
- **Auto-merge after gates (no owner merge checkpoint)** — rejected: trust must be earned by a track record; the merge checkpoint is the owner-first guard.
- **In-thread review without PRs (DeltaDB's model)** — pattern copied (review evidence and verdicts in the work thread), but the PR remains the durable, protected merge surface in v1.
- **Agent-executed merges** — rejected outright: the gate that authorizes a merge must be a harness rule, not an agent's claim.

## Consequences

- The loop's stages, waves, gates, and failure policies are Workflow data in each Managed Project — the harness provides enforcement, not project policy.
- Factory's own repository is subproject one; the initial build is manual, after which Factory drives its own changes.
- Every Run records the metrics the measure-to-improve directive requires, including agent-confusion proxies.

Status: accepted 2026-11-18 (wayfinder ticket: shape of the first milestone, the issue-driven loop). Amended 2026-11-22: the loop's stages are display groups in a node/edge graph; waves, gates, and failure routes are node and edge data (ADR-0010).
