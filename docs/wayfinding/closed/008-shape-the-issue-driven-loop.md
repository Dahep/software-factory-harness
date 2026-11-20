---
title: Decide — shape of the first milestone, the issue-driven loop
type: wayfinder:grilling
assignee: done
status: resolved
---

## Question

The spec's first milestone is the issue-driven loop: issues → triage → agent team implements approved ones → review → merge, on one project, from a coordinating process. What exactly is in the loop for v1? Open questions to settle with the owner: which steps are agents vs the owner (triage suggestions — owner approves?), how many agents in the implementer/reviewer wave, what "merge" means (PR via review gate?), what happens when the loop stalls, and which parts land in the spec's first milestone vs the fog. Grilling + domain-modeling; the loop's vocabulary (Managed Project, Task, Triage states, Loop, Gate) goes into a CONTEXT.md as it crystallises.

Context pointer (2026-11-03): [Study Zed's DeltaDB](014-research-deltadb-operation-level-vcs.md) adds trade evidence for merge-gate design — review as subthread + isolated worktree + change-guide skill, verdicts posted back, "Land" as a project-defined skill; and the sharp rule the owner must decide against: **the gate lives in harness-enforced rules, never in an LLM-interpreted skill**. Read its Resolution before grilling this ticket.

## Resolution

**Decided 2026-11-18 (HITL with the owner).**

**The v1 Loop:** intake → triage → implement → gates → review → PR → merge, with the owner at two checkpoints.

1. **Stages and ownership.** Every new Issue enters Triage. Triage produces a typed **TriageDecision** (labels, priority, acceptance criteria, plan sketch, size, confidence, open questions); the Owner approves or edits it, and approval labels the Issue `ready-for-agent` and creates the Task. Existing backlog stays out until labeled. Implement and Review run agent-side under harness-enforced gates. The Owner approves the merge. Nothing between the checkpoints needs the Owner.
2. **Waves are Workflow-defined.** The default v1 workflow dispatches one implementer and two reviewers (spec-fidelity + adversarial). Wave composition lives in each Managed Project's Workflow, not in harness code; **the first subproject is Factory itself**.
3. **Gates carry their own failure policy**, defined in the Workflow: retry within the Stage, return the Task to an earlier Stage, open a follow-up Issue, change Issue state, or wait for the Owner. A Gate's verdict is deterministic and harness-enforced — never an agent's judgment, never a skill's assertion (ticket 014's rule). The default policy bounds fix rounds at two before the Task enters a Blocked state requiring the Owner.
4. **Merge = PR + harness-enforced gate.** A PR is always required. Factory holds the only merge capability and merges with the `gh` CLI after every harness-verified gate passes and the Owner approves; **squash merge is the supported default** (clean revert). Branch protection guards the remote; agents never run the merge.
5. **Concurrency** is a Workflow setting per Managed Project (max in-flight Tasks); v1 defaults to 1.
6. **Project Init / Workflow Artifact.** Adopting a repository as a Managed Project runs an init process that proposes a PR adding a **Workflow Artifact** — the Workflow plus runtime configuration, version-controlled inside the project's own repo. The Owner merges the init PR; the project is then manageable. Factory's own repository is adopted the same way: the initial build is manual, and from then on **Factory drives changes to itself** through its own Loop.
7. **Measurement (directive #15).** Per Run/Task: per-Stage cycle time; Gate pass/deny rates; review findings per Wave; retry counts; token + cost per Task; PR merge latency; tool-call error rates; and **Agent Confusion proxies** — repeated identical tool calls, file thrash, plan revisions, abandonment/retry rate, reviewer-flagged misunderstanding, self-reported uncertainty.
8. **In v1 vs fog.** In: the Loop above, GitHub Issues as the only tracker, one Managed Project plus Factory-as-subproject, the default Workflow, Project Init. Fog/post-v1: post-merge monitoring and fix cycles, sub-Issue decomposition in Triage, workflow authoring tooling (now ticket 016), other trackers, multi-project fleets, runtime plurality, the sandboxed composition capability.

Glossary terms crystallised into `CONTEXT.md`: Gate (+ Failure Policy), TriageDecision, Workflow Artifact, Project Init, Agent Confusion.

**Amendment (2026-11-19).** Item 6's "runtime configuration" is the project-owned Agent Roster in `.factory/roster.dhall` (ADR-0007), compiled into the IR; the init PR renders the roster's primary models and writes secret names, never values.
