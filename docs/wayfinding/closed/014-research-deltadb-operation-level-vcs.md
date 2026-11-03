---
title: Study Zed's DeltaDB (operation-level version control) as a Factory design input
type: wayfinder:research
blocked-by: []
assignee: done
status: resolved
---

## Question

Zed announced **DeltaDB** ("Software Is Made Between Commits"): a new kind of version control where "your conversations with agents and the worktrees they edit [become] shared artifacts" — a stream of fine-grained deltas with stable identity, CRDT-replicated worktrees that remain real files, and Git interop. The product on top, **Delta**, treats a thread with an agent as the primary artifact; its public-beta post reports Zed's own team **disabled pull requests** (+570 changes landed to main since). Zed plans to open-source DeltaDB. Study it and extract what Factory should adopt, adapt, or avoid:

1. **The data structure/abstraction**: what exactly a "delta" is — identity, storage, how agent conversations and worktree edits link; how CRDT replication interacts with Git repos; interop story; what technical write-ups (MindStudio hands-on, HN thread) and Zed's implementation notes say.
2. **Factory's durable-state designs**: Factory already owns durable run state, task/run records, audit history, and an append-only process event log (closed/004). Could a DeltaDB-like operation-log substrate replace or simplify those internal designs — and what of Zed's "every operation with stable identity" maps onto Factory's "every action measurable" (map directive #15, adopted 2026-11-03)?
3. **The issue-driven loop without PRs**: 008 (open) must decide what "merge" means (PR via review gate?). Delta's public-beta evidence — a real team running code review in-DB without PR ceremony — is the strongest data point available. What operational details does that post (and any follow-ups) give, and does it reshape ticket 008's open questions?
4. **Substrate & seam fit**: is DeltaDB (a substrate owned by another product) a candidate behind the RuntimeAdapter for substate tracking (ticket 006), or only a pattern to copy? Watch for coupling: Delta is an app+service, not (yet?) a standalone embeddable store; note license/source availability status as of 2026-11-03 and what self-hosting would take.
5. **Maturity & risk**: private-beta → public-beta timeline, HN critique (costs of recording everything, VCS-vs-DB tension), anything about Zed's roadmap for open-sourcing DeltaDB.

Verdict must state: per-concept adopt/adapt/avoid recommendations, whether the measured-everything directive (note #15) finds a native substrate here, which map tickets (006, 008, closed/004) the findings touch and whether any should re-open or reshape, and what Factory would measure first if patterns adopted. Date claims 2026-11-03; prefer Zed's own posts and technical write-ups over coverage aggregators.

## Resolution

*Research pass 2026-11-03: two parallel primary-source reader sweeps — official Zed/Delta material, then third-party technical critiques — all claims traced to the Sources list; items no source covers are marked UNVERIFIED.*

### 1. The delta data abstraction

- **What a delta is.** "A delta is a recorded change to a thread or Delta worktree. It can represent a file edit, a change to the file tree, a message, a comment, or another update to shared state. Each delta records who made the change and where it belongs in the thread's history" (Delta docs). Identity is `DeltaId { timestamp, actor_id }` — a Lamport timestamp plus actor, no shared clock; ordering falls out of the causal graph. An edit payload names its base: `Version { Git(Sha1), Delta(Vec<DeltaId>) }`, i.e. a delta is based either on a Git object or on earlier deltas (Irwin, 2026-10-15).
- **Storage/shape.** DeltaDB is "a collection of CRDTs, all stored locally in SQLite and linked together in a directed acyclic graph" — primitives `Register` (LWW), `Map` (add-wins), `Buffer` (rope), `Worktree`; every node is a delta; the design "closely resembles" Eg-walker (Gentle & Kleppmann 2024). Current state = the **frontier** (graph tips): its size grows with concurrently open branches, not with historical writers. Ancestry is stored separately from payload, "tiny and stored in causal order" for locality. Server side: one Cloudflare Durable Object (SQLite) per thread; file contents/Git objects in R2 (Scandurra, 2026-10-29).
- **Conversation↔code linking.** Message and edit "are recorded side by side, so neither drifts away from the other"; references anchor to a delta id rather than a line number, so they survive edits — "From any line of code, you can find the conversation that produced it and every conversation that has touched it since." Third parties read the real value as addressability, not replay: a PR comment points at a line in one version and goes outdated; a delta reference keeps its identity (Ghumare 2026-09-17; nitinksingh.com). Per-character provenance ("supercharged per-character `git blame`") is described as future work, not shipped.
- **CRDT worktrees vs Git interop.** `Worktree` is a file tree layered on Git: it starts at a commit and each file is either pinned to its committed blob or carries the deltas written since — real files, mountable to disk, edited through a terminal. Managed checkouts are deliberately *not* git worktrees (thread-per-branch limits); "the checkout is temporary, the work stays in DeltaDB." Git stays the source of truth: commits are Git commits, branches are Git branches, `origin` is where work is published, and "creating a commit produces a delta too, which is what ties our DAG to Git's"; non-Delta users see a normal git repo and can still push/PR. Documented limits: project must be the top-level folder of a git checkout with a configured remote; two remotes (source + a Delta `local` backlink); `jj` support incomplete; tracked files are imported even when they match `.gitignore`.

### 2. Fit with Factory's durable-state designs and directive #15

- **Convergences with closed/004 and 002 are strong.** Stable per-operation identity; monotonically growing, never-rewritten history; ancestry in causal order; "current state = compact frontier over the log"; per-operation authorship (person vs agent); durable SQLite. This is the same architecture closed/004 chose (append-only event log with `event_id`/`sequence`/`operation_id`/evidence links) and 002's effect-runner discipline ("commit a valid transition and its effect intent first; feed the result back as a new event"), proven at content scale.
- **But it cannot replace those designs.** DeltaDB models *content evolution* (code + thread), not *workflow performance*: no runs, gates, approvals, leases, idempotency, crash recovery, or cross-project state — precisely what 002 says Factory must own. It also has no privacy boundary: whole conversations and tool inputs/outputs sync to Zed's servers, tracked-but-ignored files get imported, deletion is by email request — the inverse of 004's redaction/retention policy.
- **Could it simplify Factory's internals?** Not as a dependency (see 4). As a pattern it supports one genuine simplification: state run-state as append-only transitions plus a materialized current state (004's log as the store of record, 002's commit-transition-first discipline), with claims/leases kept transactional in SQLite/Postgres. DeltaDB's frontier is that idea already validated for read patterns — no separate shadow tables needed for "current status," derive it.
- **Directive #15 engagement — native pattern, no native substrate.** DeltaDB is the strongest existing proof of "measured by construction": every operation has identity, author, and causality, so unmeasured code evolution is unrepresentable. But it measures *content*, not *improvement* — it has no notion of gates, cost, or a mining loop, and its capture is unredacted. So #15 finds its **mechanics** here (stable IDs, frontier queries, code↔transcript navigation) but its **substrate** remains Factory's own closed/004 event log.
- **First metrics Factory would track if these patterns are adopted:** (1) traceability coverage — % of merged changes with a complete session→gate→diff→outcome evidence chain; (2) gate health — pass/deny/timeout rates and median dwell time per gate (first: 008's review gate); (3) workload economics — tool/file/network operations per run and per merged change, plus bytes of log per day (the HN "recording cost" objection made measurable); (4) review capacity — review arrivals vs reviewer capacity per day (Ghumare's 40-arrivals-vs-11.7-capacity math) to size agent-vs-owner steps; (5) log health — storage growth and frontier/current-state query latency (the benchmark Zed has not published); (6) mining yield — accepted, evidence-linked learnings (skill/workflow changes) per N sessions.

### 3. Life without PRs — evidence for ticket 008

- **What Zed actually did.** PRs disabled on Delta's own repo ~week of 2026-09-07/13; "33 of us have landed 570 changes to main since we turned off pull requests" (2026-09-16). `zed-industries/zed` stays on GitHub — contributors pair Delta threads with PRs; Sobo calls it "a few months away" from leaving GitHub, "we're not going to strand contributors to prove a point" (The New Stack).
- **Review mechanics.** A review is a dedicated subthread with isolated copies of the parent thread's worktrees; it opens with an agent-authored **change guide** ("a structured walkthrough of the change in the order that explains it best"); the reviewer submits **Approve / Request Changes**, the verdict posts back to the parent thread as a badge, and "Pull Changes" applies the verdict's snapshot; fixes found in review fold into the parent thread before landing.
- **Land mechanics.** "Land Changes" forks the thread into a Land subthread running a project-defined **Land skill** that "encodes your project's merge strategy and publication steps. The button does not impose a Git workflow of its own"; the result card shows target branch, commit, and CI status; an agent may trigger existing CI and check results before landing. Release notes show landing rough edges: agents falsely reporting "landed," asking confirmation when planning left "permission to merge unclear," skipping invalid land skills.
- **What is not published (UNVERIFIED):** any main-branch protection or approval policy without PRs; any incident write-up from the no-PR period. The sharpest objection (HN `ch71r22`; Ghumare's essay): the gate cannot live in an LLM-interpreted skill — "A skill tells an agent what to do. A branch protection rule decides what can happen… an agent can retry a flaky job until the job goes green."
- **Reshape for 008.** Its "what merge means (PR via review gate?)" question gains a third, evidenced option — **in-thread review + enforced land gate** — and a new mandatory question: *where does the gate live?* Recommended direction for the grilling: the gate stays in Factory's deterministic state machine (or the hosting provider's ruleset), never in an agent-interpreted skill; adopt Delta's review-context pattern (isolated reviewer workspace + change guide + verdict as a first-class event). Two new inputs: review-capacity metrics for the agent-vs-owner step decision, and explicit approval records for landing (Delta's "permission to merge unclear" bug is exactly the failure mode Factory's approval events prevent).

### 4. Substrate candidacy behind the RuntimeAdapter (006)

- **Not a candidate — pattern only.** DeltaDB is not standalone: "DeltaDB comes with Delta." No public API/SDK (the documented surface is an internal Rust `deltadb::Client`); no source repo (GitHub org search 2026-11-03 finds only `zed-industries/delta-claude`, an AGPL-3.0 Claude Code plugin); no published license for DeltaDB/Delta; hosted on Zed's Cloudflare multi-tenant, with single-tenant "bring your own Cloudflare" for customers only — no on-prem self-hosting; requires sign-in and uploads code/conversations to Zed's servers.
- **Seam mismatch:** even if available, DeltaDB is a state/content store, not an agent execution runtime — it would not sit behind 006's RuntimeAdapter. Its relevance to 006 is indirect: it strengthens 002's "Factory owns durable run state" boundary by showing what state-vendor coupling looks like (Delta threads are not portable, unlike the Git branches/worktrees/PRs 002 called portable).
- **Re-open trigger for any future store decision:** DeltaDB ships source under a usable license *and* an embeddable/self-hostable API. Neither holds as of 2026-11-03.

### 5. Maturity & risk

- **Timeline.** Vision + open-sourcing intent in the Sequoia B post 2025-08-20; announcement 2026-06-11; private beta 2026-08-12; public beta 2026-09-16; weekly-ish releases through 0.23.0 (2026-10-28). Roughly a year+ of development before announcement.
- **Usage evidence is thin.** 33-person dogfood, single repo, ~1 week of data; the MindStudio hands-on (2026-08-20) was a fresh-scaffold demo, explicitly "unproven at scale"; a few positive beta reports (HN `kettlz`) but no independent long-term/large-codebase study; no published storage-growth, replay, or load-time benchmarks (Zed defers long-thread loading and write-burst handling to future posts).
- **HN's strongest objections:** *recording cost* — build artifacts flooding the log before any gitignore exists, conversation baggage inflating AI context over thousands of commits, secrets in history (Delta's docs confirm tracked-but-ignored files are imported); *VCS-vs-DB tension* — "the stuff between commits is a messy soup," snapshots carry intention, who asked for a 24/7 screen recorder; *convergence ≠ correctness* for CRDT merges; *lock-in/egress* — no self-hosting, deletion by email, upload-everything; *surveillance/bossware*; no multi-repo story. First-party safety gaps corroborate: "Delta does not have an agent permission system," "does not sandbox agents," and `.agents/prepare`/`.envrc` run automatically on mount.
- **Open-sourcing:** intent only — "we plan to do the same with DeltaDB: build it, open-source it, and offer an optional paid service" (2025-08-20); no date, not reaffirmed in any 2026 source; repeated community requests unanswered. Pricing: free during beta, Personal $0 / Pro $10/mo.
- **Risk read:** high dependency risk (closed, hosted, unmeasured, vendor-coupled), moderate-to-high design value. Suitable as a design corpus; unsuitable as a dependency.

### Verdict

**Adopt** (patterns, into the spec):
- Stable identity for every recorded operation (Lamport/actor-style ids) and never-rewrite history with ancestry stored separately in causal order — extends closed/004's `event_id`/`sequence` envelope with the causal-order + frontier discipline.
- "Current state = materialized frontier over the append-only log" as the run-state model, with transactional claims/leases on top.
- Conversation↔artifact anchoring by id (session→gate→diff→outcome) that survives file moves — the traceability spine directive #15 needs.
- Review as a structured event: isolated reviewer workspace, agent-authored change guide, Approve/Request-Changes verdict posted back as a first-class record.
- Git-interop stance: Git remains source of truth for commits/branches/remotes; the operation log captures work *between* checkpoints.

**Adapt:**
- "Land" → Factory's code-defined gate executed deterministically: merge strategy as workflow code, CI checks as enforced conditions, result as an event — never an agent-interpreted skill.
- CRDT worktrees → keep 002's git-worktree-per-task; adopt only "checkout is temporary, durable state lives in Factory's records outside the runtime transcript."
- Per-character provenance → closed/004's coarse evidence links (`message_id`/`part_id`) suffice for mining; no character-level tracking in v1.
- Recording discipline → 004's redaction/retention boundary stands: record operation metadata, not raw payloads.

**Avoid:**
- Adopting DeltaDB/Delta itself (closed, hosted, upload-everything, no redaction, no permission system, no sandbox, no self-host, no API).
- Putting any merge/approval gate where an LLM can reinterpret it.
- Multi-writer CRDT shared working trees for the control plane (convergence ≠ correctness; the test-stability objection).
- Vendor-coupled state stores that are not portable — the exact lock-in HN flags and 002's switching-cost warning.

**Directive #15:** finds a native **pattern** here (measured-by-construction operation logging with stable identity and provenance navigation) but **no native substrate** — DeltaDB measures content evolution rather than workflow improvement, is closed and hosted, and lacks Factory's privacy boundary; #15's substrate remains Factory's own closed/004 event log. First metrics: the six named in section 2 (traceability coverage, gate health, workload economics, review capacity, log health, mining yield).

### Impacts on the map

- **006 (decide harness substrate, open):** no re-open. Addendum for the grilling: no external operation-log store is adoptable as of 2026-11-03 (DeltaDB is closed and hosted), so the substrate decision should assume a Factory-owned state store behind the RuntimeAdapter; record the re-open trigger from section 4.
- **008 (shape the issue-driven loop, open):** reshape — the strongest impact. "What merge means" now has three evidenced options (PR gate / in-thread review + enforced land / hybrid) plus a new must-decide: *where does the gate live?* — recommended answer: Factory's deterministic state machine or the provider's ruleset, with Delta's change-guide + verdict-event pattern adopted for review context; add review-capacity metrics and explicit landing-approval records to the grilling inputs.
- **closed/004 (steer capture & observability):** no re-open. Two upgrades to carry forward: frontier/materialized-view reads for the owner run timeline, and id-anchored code↔transcript navigation as a mining feature. Keep the redaction boundary — DeltaDB's unredacted capture is the cautionary case.
- **closed/002 (build vs plugins):** no re-open. Reinforces "Factory owns durable run state" and the RuntimeAdapter seam; adds concrete lock-in evidence (Delta threads/DeltaDB are not portable, unlike the Git branches/PRs 002 called portable).

### Sources

Primary sources (all accessed 2026-11-03):

1. Zed — "Software Is Made Between Commits" (introducing DeltaDB), Nathan Sobo, 2026-06-11: https://zed.dev/blog/introducing-deltadb
2. Zed — "Introducing Delta", 2026-08-12: https://zed.dev/blog/introducing-delta
3. Zed — "Replace PRs with Delta – Now in Public Beta", 2026-09-16: https://zed.dev/blog/delta-public-beta
4. Zed — "Sequoia Backs Zed's Vision for Collaborative Coding", 2025-08-20: https://zed.dev/blog/sequoia-backs-zed
5. Delta — product page and DeltaDB page/FAQ: https://delta.dev · https://delta.dev/deltadb
6. Delta — "DeltaDB: The Future of Version Control", Conrad Irwin, 2026-10-15: https://delta.dev/blog/future-of-version-control
7. Delta — "Building fine-grained version control for agents with Rust and Durable Objects", Antonio Scandurra, 2026-10-29: https://delta.dev/blog/fine-grained-version-control-for-agents
8. Delta — "Escaping the Tyranny of Worktrees", 2026-10-06: https://delta.dev/blog/escaping-the-tyranny-of-worktrees
9. Delta docs — Delta & Git, Worktrees, Reviewing & Syncing Changes: https://delta.dev/docs/concepts/delta-and-git · https://delta.dev/docs/concepts/worktrees · https://delta.dev/docs/agents/review-and-sync
10. Delta docs — Data Storage & Deletion, Agentic Safety, release notes, roadmap, pricing: https://delta.dev/docs/privacy-and-security/data-storage · https://delta.dev/docs/privacy-and-security/agentic-safety · https://delta.dev/docs/whats-in-the-latest · https://delta.dev/roadmap · https://delta.dev/pricing
11. GitHub — DeltaDB source-status search and the only Delta-related repo (AGPL plugin): https://github.com/orgs/zed-industries/repositories?q=deltadb · https://github.com/zed-industries/delta-claude
12. MindStudio — "Zed Delta: A Hands-On Look", 2026-08-20: https://www.mindstudio.ai/blog/zed-delta-ai-coding-agent
13. Hacker News — "Zed DeltaDB" critique thread, 2026-08-05: https://news.ycombinator.com/item?id=49187256
14. Hacker News — "Replacing Pull Requests with Delta" thread, 2026-09-16: https://news.ycombinator.com/item?id=49727245
15. Hacker News — "Software is made between commits" thread, 2026-06-11: https://news.ycombinator.com/item?id=48492533
16. Koru Works — "Zed's DeltaDB, reviewed" (competitor disclosure), 2026-10-29: https://www.koru.do/en/blog/zed-deltadb-review
17. Rohit Ghumare — "Zed Turned Off Pull Requests. The Merge Gate Has to Go Somewhere.", 2026-09-17: https://rohitghumare.com/blog/zed-delta-after-pull-requests/
18. The New Stack — Sobo quotes on GitHub coexistence, 2026-09-16: https://thenewstack.io/zed-delta-github-alternative/
