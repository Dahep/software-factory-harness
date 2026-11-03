---
title: Study Zed's DeltaDB (operation-level version control) as a Factory design input
type: wayfinder:research
blocked-by: []
---

## Question

Zed announced **DeltaDB** ("Software Is Made Between Commits"): a new kind of version control where "your conversations with agents and the worktrees they edit [become] shared artifacts" — a stream of fine-grained deltas with stable identity, CRDT-replicated worktrees that remain real files, and Git interop. The product on top, **Delta**, treats a thread with an agent as the primary artifact; its public-beta post reports Zed's own team **disabled pull requests** (+570 changes landed to main since). Zed plans to open-source DeltaDB. Study it and extract what Factory should adopt, adapt, or avoid:

1. **The data structure/abstraction**: what exactly a "delta" is — identity, storage, how agent conversations and worktree edits link; how CRDT replication interacts with Git repos; interop story; what technical write-ups (MindStudio hands-on, HN thread) and Zed's implementation notes say.
2. **Factory's durable-state designs**: Factory already owns durable run state, task/run records, audit history, and an append-only process event log (closed/004). Could a DeltaDB-like operation-log substrate replace or simplify those internal designs — and what of Zed's "every operation with stable identity" maps onto Factory's "every action measurable" (map directive #15, adopted 2026-11-03)?
3. **The issue-driven loop without PRs**: 008 (open) must decide what "merge" means (PR via review gate?). Delta's public-beta evidence — a real team running code review in-DB without PR ceremony — is the strongest data point available. What operational details does that post (and any follow-ups) give, and does it reshape ticket 008's open questions?
4. **Substrate & seam fit**: is DeltaDB (a substrate owned by another product) a candidate behind the RuntimeAdapter for substate tracking (ticket 006), or only a pattern to copy? Watch for coupling: Delta is an app+service, not (yet?) a standalone embeddable store; note license/source availability status as of 2026-11-03 and what self-hosting would take.
5. **Maturity & risk**: private-beta → public-beta timeline, HN critique (costs of recording everything, VCS-vs-DB tension), anything about Zed's roadmap for open-sourcing DeltaDB.

Verdict must state: per-concept adopt/adapt/avoid recommendations, whether the measured-everything directive (note #15) finds a native substrate here, which map tickets (006, 008, closed/004) the findings touch and whether any should re-open or reshape, and what Factory would measure first if patterns adopted. Date claims 2026-11-03; prefer Zed's own posts and technical write-ups over coverage aggregators.
