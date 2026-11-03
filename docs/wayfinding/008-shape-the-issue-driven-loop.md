---
title: Decide — shape of the first milestone, the issue-driven loop
type: wayfinder:grilling
---

## Question

The spec's first milestone is the issue-driven loop: issues → triage → agent team implements approved ones → review → merge, on one project, from a coordinating process. What exactly is in the loop for v1? Open questions to settle with the owner: which steps are agents vs the owner (triage suggestions — owner approves?), how many agents in the implementer/reviewer wave, what "merge" means (PR via review gate?), what happens when the loop stalls, and which parts land in the spec's first milestone vs the fog. Grilling + domain-modeling; the loop's vocabulary (Managed Project, Task, Triage states, Loop, Gate) goes into a CONTEXT.md as it crystallises.

Context pointer (2026-11-03): [Study Zed's DeltaDB](closed/014-research-deltadb-operation-level-vcs.md) adds trade evidence for merge-gate design — review as subthread + isolated worktree + change-guide skill, verdicts posted back, "Land" as a project-defined skill; and the sharp rule the owner must decide against: **the gate lives in harness-enforced rules, never in an LLM-interpreted skill**. Read its Resolution before grilling this ticket.
