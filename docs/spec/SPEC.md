# Factory — Specification (v1)

**Status:** build-ready planning artifact · 2026-11-18, amended 2026-11-19 (ADR-0007), 2026-11-20 (ADR-0008), 2026-11-20 (ADR-0009), 2026-11-20 (post-v1 clarification conversations), and 2026-11-22 (ADR-0010: node/edge workflow core, concurrency, PR feedback, agent liveness)

**Relationship to the record.** This spec is the destination of the wayfinder map at [`docs/wayfinding/map.md`](../wayfinding/map.md). It restates decisions; it does not make them. Decisions live in [`docs/adr/`](../adr/) and in the resolutions of the closed tickets under [`docs/wayfinding/closed/`](../wayfinding/closed/); the glossary is [`CONTEXT.md`](../../CONTEXT.md). Where this spec is silent, the ADR and ticket win. The conflicts found while writing it were reconciled against the ADRs and are recorded, with the artifacts changed, in §10. Bare `ADR-000N` and `ticket NNN` references resolve through §11; load-bearing claims link their path directly.

**Spec defaults.** Sentences marked **⟨default Dn⟩** are choices this spec makes where the source artifacts are silent — scheduler ordering, denial paths, timeouts, and similar build-time detail. They are review targets, not recorded decisions, and are collected by id in §9.2.

**Building is out of scope here.** This is a planning artifact: no production code, no scaffolding. A later effort implements it.

**Contents.** [1 Purpose](#1-purpose-audience-scope) · [2 Architecture](#2-architecture) · [3 The default Workflow graph](#3-the-default-workflow-graph) · [4 Workflow Artifact](#4-workflow-artifact) · [5 Containment and secrets](#5-containment-and-secrets) · [6 Observability](#6-observability-and-measurement) · [7 Adoption and self-hosting](#7-adoption-init-and-self-hosting) · [8 Build prerequisites and risks](#8-build-prerequisites-and-risks) · [9 Open questions](#9-open-questions-fog) · [10 Reconciliations](#10-reconciliations) · [11 Source index](#11-source-index)

---

## 1. Purpose, audience, scope

### 1.1 What Factory is

Factory is a user-defined agent harness: a resident control plane that runs deterministic, project-defined workflows which orchestrate agent teams across Managed Projects. Factory owns workflow state, gates, and audit, and delegates agent execution to a runtime through a `RuntimeAdapter` ([`CONTEXT.md`](../../CONTEXT.md), ADR-0002).

The v1 milestone is the issue-driven Loop: an Issue enters, an agent triages it, the Owner approves a `TriageDecision`, an implementer Wave produces a branch, harness-owned Gates and a reviewer Wave pass judgment, Factory opens a PR, and the Owner approves a squash merge. Nothing between the two Checkpoints needs the Owner (ADR-0003).

### 1.2 Audience and the path to other users

The Owner is the audience: the author of workflows and the authority at Checkpoints. v1 is sized to one Owner on one machine (ADR-0005).

The path to other users is preserved by four seams, not by designing for them now: a tracker adapter boundary (§2.6), a Workflow Artifact that lives in each Managed Project's own repository (§4), a `RuntimeAdapter` that keeps the runtime swappable (§2.4), and a local API that a future TUI or web UI can consume without touching the database (ADR-0005). Packaging, onboarding, and a configuration UI are fog (§9.1); designing them now is out of scope.

### 1.3 v1 scope

| Capability | v1 shape | Source |
| --- | --- | --- |
| Process model | Resident Go daemon + thin CLI over a local JSON API on a Unix socket | ADR-0005 |
| Durable state | One SQLite (WAL) database: append-only transition log, projections, snapshots | ADR-0002, ADR-0005 |
| Runtime | `RuntimeAdapter` seam; OpenCode as the one real adapter; a test double proves the seam | ADR-0002 |
| Workflow core | typed node/edge graph; Stage is a display group, not an execution unit | ADR-0010 |
| Agent Roster | `.factory/roster.dhall`: project-owned entries, ordered model lists, policy references; agent nodes select by id; compiled into the IR | ADR-0007 |
| Default artifact | `defaults/`: typed workflow graph, roster, envelope, schema, bindings; fixture golden IR in CI; Project Init renders it into a project copy | ADR-0008 |
| Containment | One Project VM (devvm) per Managed Project; Project Envelope compiled from the artifact | ADR-0004, ticket 017 |
| Egress | Local devvm allowlist and secret scopes; Egress decisions recorded in SQLite; no artifact PR | ADR-0009 |
| Tracker | GitHub Issues via `gh`; adapter interface designed for others | ticket 003, ticket 008 |
| Loop | the default graph: intake → triage → implement → gates → review → PR → merge, Owner at two Checkpoints | ADR-0003, ADR-0010 |
| Default Wave | one implementer, two reviewers (spec-fidelity + adversarial), dispatched by agent nodes | ticket 008 |
| Gates | deterministic, harness-enforced gate nodes; a failing edge routes and may carry feedback | ADR-0003, ADR-0010 |
| Concurrency | configurable per Managed Project; above one, each Task gets its own worktree inside the Project VM and merges are serialized | ADR-0010, ticket 008 |
| PR feedback | `pr-watch` trigger + `sync` action + `rework` agent node for human review, base movement, and conflicts | ADR-0010 |
| Agent liveness | session heartbeat where declared, idle timeout and deadline fallback, typed outcomes, bounded feedback retries | ADR-0010 |
| Agent access | read-only project token inside the VM; host-side push; Factory-mediated comments (agent comment plugin post-v1) | ADR-0004, ADR-0010 |
| Adoption | Project Init PR renders `.factory/` from `defaults/`; copy-on-init; deviation by PR | ADR-0006, ADR-0008 |
| Measurement | append-only log, default metric set, Agent Confusion proxies, stall/incomplete/feedback metrics | ticket 004, ticket 008, ADR-0010 |
| Self-hosting | Factory's repository is Subproject one; manual first build, then self-driven | ticket 008 |

v1 validates the Loop on **one Managed Project plus Factory-as-Subproject**. The architecture is per-project throughout (rows, VMs, Agent Rosters), but a multi-project fleet is not a v1 goal (ticket 008).

### 1.4 Non-goals

Out of scope by decision, not by omission:

- **Deploy.** Each Managed Project owns its deploy path (its own CI, e.g. GitHub Actions). Factory's Loop ends at merge; no deploy step, no host inventory, no deploy credentials in a Project VM (ticket 018, map note #7).
- **Capability Profiles.** No per-role profiles in v1; containment is per Managed Project (ADR-0004). A Roster Entry carries a policy reference for post-v1 profiles, but v1 resolves every entry to the project-wide policy. Profiles return post-v1 as narrower envelopes on the same path.
- **PR-format validators.** Reserved in the model, not built (ADR-0004).
- **Other trackers.** GitHub Issues only; Fizzy/Linear follow the adapter interface later (ticket 003, ticket 008).
- **Runtime plurality.** One real adapter plus a test double; harness neutrality is a property of the seam, not of the shipping surface (ADR-0002).
- **Webhooks and public ingress.** Intake and PR feedback poll; webhooks are post-v1 (ADR-0005).
- **External-server mode.** OpenCode runs as a Factory-managed server per Project VM; attaching to an existing external server is post-v1 (ticket 006).
- **Owner TUI/web UI.** The CLI is the surface; TUI and web clients arrive on the same API (ADR-0005).
- **Multiple Workflow definitions per Managed Project.** v1 carries one Workflow graph per project; the IR and API keep a `workflowId` so a later multi-workflow release is additive, but validation rejects a second definition (ADR-0010).
- **Direct agent PR/issue comments and write tokens.** The Project VM gets a read-only project token; Factory pushes and merges, and comments are Factory-mediated (the agent comment plugin is post-v1). Inline agent replies are the post-v1 comment plugin (ADR-0010).
- **Parallel/join nodes inside one Task.** An agent node's wave covers parallel sessions; cross-Task concurrency is a scheduler setting, not a graph primitive (ADR-0010).
- **Project Console, Node View, and Project Assistant.** v1 is CLI only; the post-v1 direction is §7.4.
- **Clarification conversations.** v1 triage is decision-only. The post-v1 `NeedsInfo` branch and its conversation surfaces are §7.5.
- **Spend caps and budgets.** Cost is tracked when the adapter reports usage; v1 has no `budget` field and no cap (ADR-0004, ADR-0009).
- **Post-merge monitoring and fix cycles**, and **sub-Issue decomposition in Triage** (ticket 008).
- **Code-mode / sandboxed composition** as a Workflow layer. The pattern is reserved as a future adapter capability; an LLM-authored script is never the Workflow and never a Gate (ADR-0002, ticket 015).
- **Remote/worker mode and multi-machine fleets.** Local daemon only (ADR-0005).
- **A public registry of reusable Workflows** (ticket 013; path-to-other-users fog).

### 1.5 Definition of done for v1

v1 is done when, on Factory's own repository as a Managed Project, all of the following hold:

1. A new Issue reaches a merged squash commit through the Loop with Owner action only at the triage and merge Checkpoints.
2. Every Gate verdict is recorded with its inputs; no agent judgment, plugin, or skill file decides advancement.
3. A daemon restart mid-Task either resumes from the last transition or parks the Task Blocked with evidence; no Task is silently re-dispatched (ADR-0005).
4. Every Run carries the default metric set, including the six Agent Confusion proxies and the stall, incomplete, and feedback-round measures.
5. Each blocked egress attempt that needed a decision has an Egress Request outcome recorded in Factory's local database.
6. The Dhall conformance gate is green in CI, and the Default Workflow Artifact at `defaults/` compiles to its committed golden IR, `defaults/fixtures/golden.ir.json`.
7. A Workflow Artifact change lands only through a PR against the Managed Project's copy.
8. Two Tasks can be in flight at once, each in its own worktree inside the Project VM, and their merges serialize without either stalling on a moved base.
9. A human `CHANGES_REQUESTED` review or Owner PR comment routes the Task to a rework node, and the next merge Checkpoint is fresh; a base conflict routes through `sync`/`rework` rather than parking the Task.
10. An agent session that stalls, crashes, or returns without its required outputs is detected, retried automatically with typed feedback up to the configured bound, then parked Blocked with evidence.

---

## 2. Architecture

### 2.1 Topology

```
Owner
  │  CLI (thin client, no DB access)
  ▼
Unix socket ── typed JSON API ──▶ Factory daemon (Go, systemd user unit)
                                   │  SQLite (WAL)
                                   │    append-only transitions · projections · snapshots
                                   │
                                   ├─ tracker adapter ── gh ──▶ GitHub Issues
                                   ├─ PR + merge ──────── gh ──▶ GitHub PRs (host identity)
                                   │
                                   └─ devvm host + ssh
                                        ▼
                                   Project VM  (one per Managed Project, devvm)
                                        ├─ repo clone (--clone) + per-Task worktrees
                                        ├─ OpenCode server ── sessions (Waves)
                                        └─ egress proxy ── allowlist + secret injection
```

Two GitHub paths exist by design: the daemon host holds the write identity for push, PR creation, merge, and tracker transitions, while the Project VM holds a **read-only** project token for direct `git`/`gh` reads (ADR-0004, ADR-0010). The VM does not push and does not comment; Factory pushes the agent's branch with the host identity, and comments are Factory-mediated (the agent comment plugin is post-v1).

### 2.2 The daemon

One long-running Go process on the daemon host, installed as a **systemd user unit** (ADR-0005). It owns the queue, scheduling, Project VM lifecycle, node and edge execution, Gate evaluation, Checkpoint delivery, trigger polling, PR and merge execution, egress decisions, and the audit log. It is the only writer to the database.

The daemon's responsibilities are deliberately narrow in one direction: it decides *which work is eligible, who owns it, when it runs, what Gates it must pass, and how outcomes are recorded*. It never decides *how* an agent solves its Task (ticket 002), and it does not know the default Loop's node names; it executes the compiled graph.

The CLI is a client. Commands are idempotent and carry persisted receipts; even locally the client uses a scoped Owner session; no client opens the database (ADR-0005). Ticket 010 names `factory inbox`, `factory approve`, and `factory egress allow`; ADR-0005 fixes the architecture, and §7.3 lists the surface this spec expects.

### 2.3 Durable state

One SQLite database in WAL mode, daemon-only writer, project-scoped rows (ADR-0005).

| Store | Role | Guarantees |
| --- | --- | --- |
| Transition log | Audit truth: every command, node execution, edge traversal, Gate verdict, Checkpoint decision, agent Outcome, feedback round, tracker/PR effect, and reconciliation | Append-only; monotonic sequence per database; actor, time, cause, and evidence on every row; long retention (map note #15) |
| Projections | Current state per Managed Project, Task, Run, node, Gate, and pending trigger/checkpoint | Derived from the log; safe to rebuild; never authoritative over the log |
| Snapshots | Bounded replay | Taken at a log sequence; a snapshot plus its suffix reproduces state |

The write discipline follows the effect-runner shape (ticket 002): **commit a valid transition and its effect intent first; perform the external effect outside that decision; record the result as a new transition.** External effects are reconciled before retry — read provider state, then act (§3.11).

Log event types the transition log must carry (fields, not DDL):

| Event type | Required content |
| --- | --- |
| Command | idempotency key, actor, target, receipt reference |
| Transition | sequence, Managed Project, Task, Run, node id, edge id, before/after node and generic state, cause (Gate, Checkpoint, event, feedback, reconciliation), IR digest |
| Gate verdict | Gate node id, check, input references with digests and the PR head where relevant, result, reason, attempts, outgoing edge |
| Checkpoint | checkpoint node id, asks (artifact references), decision, edits or reason, actor, time |
| Agent Outcome | node id, session refs, status (`Completed`, `Incomplete`, `Stalled`, `Crashed`, `Exhausted`, `Blocked`, `Refused`), missing outputs, last event, transcript ref, liveness evidence |
| Feedback | source (Gate, review, PR, agent), summary, check evidence, attempt, target node |
| Run | adapter instance, Task input digest, Outcome, model attempts (requested, resolved, outcome, reason), usage, transcript reference, completeness |
| Effect | tracker/PR/merge/VM/git action, idempotency key, result, provider reference |
| Egress Request | host, method, path, reason, decision (allow/deny), applied local rule, actor, time, local-config reference |

Pre-Task transitions (intake, triage, the triage Checkpoint) carry the Issue and the triage Run; `Task` is absent until approval creates it.

Backups are one file (ADR-0005). Retention of transcripts and activity events is governed by §6.7.

### 2.4 RuntimeAdapter

The seam is T3-shaped (ticket 006, ADR-0002). Four parts:

| Part | Contract |
| --- | --- |
| Task in | typed: node config, prompt, workspace reference, resolved roster entry (id, instructions, ordered model list, policy reference), input artifacts including optional `Feedback`, capability-profile ref (the Project Envelope in v1) |
| Outcome out | typed: one of `Completed`, `Incomplete`, `Stalled`, `Crashed`, `Exhausted`, `Blocked`, `Refused`; artifacts, diff reference, transcript reference, usage, missing outputs, liveness evidence, and the model attempt trail (requested model, resolved model, outcome, failure reason where an attempt failed) |
| Events | normalized stream for session / message / tool / permission / liveness. Telemetry only — never Workflow state |
| Capabilities | an explicit descriptor per driver: streaming, steer/interrupt, checkpoints, rollback, sandboxed composition, native option IDs, Model Catalog, failure-reason set, and `liveness` (`heartbeat`, `idle-timeout-only`, or `none`) |

Rules that keep the seam honest:

- **Declared, not assumed.** Factory must not use a capability the adapter did not declare. A node that requires an undeclared capability is rejected at validation or blocks the Task with evidence; it never degrades silently.
- **Model fallback is declared.** The adapter tries only the entry's ordered model list and never substitutes a model the roster did not name; model IDs are Model Catalog IDs, never host-resolved aliases. It records every attempt — requested model, resolved model, outcome — and, for a failed attempt, one reason from the closed set — `unavailable`, `rate-limited`, `auth-failed`, `context-exceeded`, `refused`, `unknown`. The attempt trail travels with every Outcome, so a successful fallback is as visible as an exhausted list. When the list is exhausted, the adapter returns `Exhausted`; the Workflow edge decides what happens next.
- **Agent outcomes are typed.** The engine classifies a session as `Completed` only when it ended normally and every required output is present. A normal end with missing outputs is `Incomplete`; a missing heartbeat or idle timeout is `Stalled`; a session/process failure is `Crashed`; a self-reported blocker is `Blocked`; a model refusal is `Refused`. The Workflow routes each outcome; it does not have to interpret prose.
- **Liveness is declared and evidence-backed.** An adapter that declares `heartbeat` emits a session-liveness signal independent of model/tool events. If it declares `idle-timeout-only`, the engine uses event silence plus the deadline. If it declares `none`, liveness is `unobserved`; the engine never pretends the session is alive. Heartbeats prove the session is reachable, not that work is progressing; idle timeout and the Agent Confusion proxies catch a live but stuck agent.
- **Driver kind vs instance.** Two configurations or accounts never share mutable session or catalog state. The adapter records which instance produced an Outcome.
- **Native option IDs survive normalization.** Display labels are not valid replies for permission or question prompts.
- **No setup as a health-check side effect.** Opening a session must not trigger MCP servers, hooks, or logins (ticket 006).
- **Runtime events are not state.** Only a committed transition advances a Task (ticket 002).

**Post-v1 capability: `conversation_threads`.** The Conversation model (§7.5) needs a declared capability to open or attach a conversation thread, send, read, close, and link it to an Issue or Run. v1 does not use it, so it is not in the capability table above and no v1 adapter declares it. When it lands, the capability is enforced at compile time: a node that requires it against an adapter that does not declare it is rejected, never blocked later or degraded silently.

`driver` and `workspace reference` are ticket 006's contract vocabulary; elsewhere this spec says adapter kind and working copy.

The Task's `capability-profile ref` **resolves to the Managed Project's Project Envelope in v1**, validated against the compiled envelope; the field stays reserved for post-v1 profiles (ticket 006 amendment, ADR-0004). Post-v1, a profile attaches to a Roster Entry's policy reference (ADR-0007).

**OpenCode as the v1 adapter.** Factory starts, version-probes, idles out, and speaks to an OpenCode server over its API; external-server mode is post-v1. One server per Project VM — the instance is the Managed Project's running runtime, configured from its Agent Roster (§4.1, ADR-0007) — with many sessions (one per agent in a Wave). The server runs inside the Project VM; the daemon reaches it through `devvm host` + SSH (ticket 006, ticket 017).

**The Agent Roster** (`.factory/roster.dhall`, ADR-0007) declares the project's Roster Entries: agent identity, role and persona, instructions, ordered model list, tool and permission policy reference, adapter options, and declared requirements (secret names, tool classes, modality). It compiles into the IR, so a Task's pin covers the models and permissions that execute it. Factory validates it against the adapter's Model Catalog at compile time; interactive Project Init validates provider availability live (§7.1). Provider authentication stays harness- and host-side, Factory stores no secret values, and the Envelope names them (§5.5). Correctness never depends on the host's global OpenCode config (ADR-0002, ticket 006).

**The minimal Factory plugin** exposes only: report a blocker, attach an artifact, read Gate status, inject Task context, and enforce permission rules. It never advances Workflow state (ticket 002, ticket 006).

**The test double.** A fake adapter proves the seam and runs the default graph's contract tests, including liveness/outcome classification and feedback edges, in CI. No second real adapter ships in v1 (ADR-0002, ADR-0010).

### 2.5 Project VM

A **Project VM** is the devvm instance backing a Managed Project: the sandbox, network, and secret boundary for every agent session and for the runtime server of that project ([`CONTEXT.md`](../../CONTEXT.md)).

The Owner's decision is **one Project VM per Managed Project**, reused across Tasks and Waves ([ticket 017](../wayfinding/closed/017-research-devvm-sandboxing.md#owner-decision-2026-11-18)). Consequences this spec carries:

- The boundary is the project, not the Task, the agent, or the Wave. Every session of a Wave shares the Task's Project VM.
- A per-Run VM is an escalation option (untrusted input, destructive work), not a default; v1 does not need it. The 17-concurrent-VM cap is therefore not a v1 constraint.
- When concurrency is greater than one (§3.9), each Task gets its own working copy inside the Project VM — a `git worktree` on a unique branch is the default, with a separate clone as the fallback. Worktrees isolate files and branches, not build caches, ports, databases, or CPU; a project whose tests need exclusive services keeps concurrency at 1. **⟨default D4⟩**
- The VM starts on first work and stops only when no Task is active and the idle period has elapsed (default ~30 minutes, configurable — ticket 010); starting a Task pays a VM start cost (ADR-0005).
- The VM holds the Managed Project's **read-only** GitHub token; push, PR creation, merge, and tracker transitions use the host identity (ADR-0010, §5.3).
- `devvm rm` deletes the VM's network logs and state; Factory ingests what it needs before any removal (§6.6).

**Lifecycle and control.** Factory drives devvm as a CLI: `--no-input`, versioned `--json` output (version 1, additive-only), and folder-scoped commands resolved by the working directory plus folder identity (path + device + inode + birth time). The daemon either `chdir`s into the Managed Project's run directory or uses `devvm adopt`. The headless command path is `devvm host --no-input` followed by plain `ssh` to the VM; there is no devvm API or SDK (ticket 017).

**Clone mode.** The envelope's clone mode compiles to `devvm --clone`: the VM holds its own copy of the repository, and the host working tree is never mounted. On Linux this is also the mitigation for the missing `.git` protection (§8.4, R4).

**Inside the VM:** the repository clone, toolchains, the OpenCode server, and every agent session of the project. The Go control plane never runs inside it.

### 2.6 TrackerAdapter

The adapter is a translation and authorization boundary, not a lowest-common-denominator schema (ticket 003). v1 implements GitHub Issues via `gh`; the interface is designed so another tracker is one adapter, not a rewrite.

| Capability | v1 use |
| --- | --- |
| `capabilities()` | Report read/write fidelity per operation; Factory refuses what the provider cannot do instead of emulating it |
| `listIssues`, `getIssue` | Intake polling and reconciliation |
| `createIssue` | One caller in v1: a failure edge opening a follow-up Issue (§3.6); otherwise the Owner creates Issues in the tracker. The post-v1 Project Assistant adds confirmed assistant-initiated creation (§7.4) |
| `updateIssue`, `transitionIssue` | Labels, workflow state, close — **through Factory only** |
| `assign` / `unassign` | Available; the v1 default graph does not assign agents to Issues |
| `listComments`, `addComment` | Agents read comments directly via `gh`; comments are Factory-mediated in v1 (and the post-v1 comment plugin), never direct from the VM |
| `listActivity` | Provider activity for reconciliation; never treated as an immutable audit log |
| `listDependencies`, `addDependency`, `removeDependency` | Available; the v1 default graph does not consume blocking relations |
| `authorize` | Early UX only; the harness re-checks every mutation immediately before the call |

The adapter exposes more than the default graph consumes (ticket 003): `assign` and dependency operations stay available without being graph inputs. `createIssue` stays in the contract for the one caller v1 has — a failure edge opening a follow-up Issue (ticket 008) — and the Owner otherwise creates Issues in the tracker; assistant-initiated creation arrives with the post-v1 Project Assistant (§7.4).

Rules: provider IDs stay opaque; provider-specific fields and events are preserved; unsupported operations are reported, never faked with tags or comments; important writes are verified by reading back (ticket 003).

**Authority split** (ADR-0004, ADR-0010):

- Reads: the agent may use `git` and `gh` directly inside the Project VM with the read-only project token.
- Comments: **Factory-mediated**; v1 may post a summary or blocker on the agent's behalf, and the post-v1 comment plugin lets the agent request a reply. The VM has no issue-write token.
- Label, state, and close transitions: **Factory tools only**, after the Triage Checkpoint. The agent proposes; Factory records and applies.
- Merge: not a tracker operation, and not an agent operation (§3.8).

There are two principals throughout: the provider credential and the harness agent principal. The harness gates every mutation even when the provider credential could perform it (ticket 003).

---

## 3. The default Workflow graph

### 3.1 Nodes, edges, and the default graph

The Workflow's core primitive is the **Node**, connected by **Edges** (ADR-0010). The engine executes nodes and evaluates edges; it does not execute Stages. The default issue-driven Loop is one graph in `defaults/`, not engine logic. A **Stage** is only a `group` label on nodes for display, metrics, and the later Node View.

A node has a stable id, a kind, typed config, an optional group, optional measures, and an optional visit bound. An edge has `from`, `to`, an `on` condition (`success`, `failure`, `event`, `decision`, `timeout`, or `always`), an optional CEL guard, and an optional traversal bound. Only one outgoing edge is taken; edges are evaluated in declaration order and the first match wins. If no edge matches for an active node's outcome, the Task blocks with `no_transition` evidence; a waiting node stays `Waiting` until an event or timeout. A Task starts at exactly one entry node and ends at a terminal node.

| Node kind | What it does |
| --- | --- |
| `agent` | Dispatches a wave of one or more Roster Entries; declares required outputs, deadline, idle timeout, heartbeat, and event edges; follows an edge on an outcome |
| `gate` | Evaluates one deterministic check from the closed registry; follows pass or fail |
| `checkpoint` | Waits for an Owner decision, with asked artifacts; event edges can interrupt it; follows the decision or event |
| `action` | Performs one typed effect from the closed registry (`git.push`, `git.sync`, `pr.create`, `pr.merge`, tracker effects); follows success, failure, or a typed conflict/stale outcome |
| `trigger` | Waits for typed external events; the engine polls/dedupes, the Workflow matches and routes |
| `route` | Evaluates a pure CEL expression; chooses an edge |
| `terminal` | Ends the Task as `merged`, `abandoned`, or `failed` |

The default graph keeps the familiar Loop grouping:

| Group | Default nodes (kind) | Purpose |
| --- | --- | --- |
| Intake | `intake` (trigger) | Admit Issues carrying the intake label |
| Triage | `triage` (agent), `decision-shape`/`scope-declared` (gate), `triage-approval` (checkpoint) | Produce and approve a `TriageDecision`; approval creates the Task |
| Implement | `implement` (agent), `build`/`tests`/`diff-present` (gate) | Implement in the Task worktree; run deterministic gates |
| Review | `review` (agent wave), `review-verdict` (gate) | Spec-fidelity and adversarial findings; aggregate verdict |
| PR | `push`/`pr-create` (action), `pr-watch` (trigger), `sync` (action) | Host-side push and PR creation; react to base movement, conflicts, and human feedback |
| Rework | `rework` (agent) | Rework on gate failures, review findings, PR feedback, and merge conflicts |
| Merge | `pr-open`/`checks-green` (gate), `merge-checkpoint` (checkpoint), `merge` (action), `merged` (terminal) | Gate the PR state, take Owner approval, and squash-merge host-side |

The default is data: a project changes its process by editing nodes and edges in a PR, not by asking for engine code. The golden IR asserts every node id, edge, and group. Every node emits the default metric set (§6.4); the artifact may add measures (§4.7). Cycles are allowed only with a bound on at least one edge in the cycle.

### 3.2 Task states

The tracker remains the authoritative record of the Issue; Factory is authoritative for the Task ([`CONTEXT.md`](../../CONTEXT.md)). Intake and Triage are tracked before the Task exists — the triage Run, its gates, the `TriageDecision`, and the checkpoint, all keyed by the Issue; **approval creates the Task** (ticket 008). A triage Run failure is recorded against the Issue and returns it to the Owner's inbox or the triage queue; it never creates a Task.

Task state is generic; `currentNode` says where the Task is:

| Task state | Meaning | Issue |
| --- | --- | --- |
| Ready | approved; the Task exists and is queued | open; labeled `ready-for-agent` |
| Active | a node is executing (agent, gate, action, route) | open |
| Waiting | waiting at a trigger or checkpoint | open |
| Blocked | needs the Owner; evidence attached | open; the routed failure may also change Issue state |
| Abandoned | the Owner abandoned the Task | open or closed, per the recorded decision |
| Merged | squash-merged | closed through Factory |
| Failed | a terminal failure routed by the graph | open or closed, per the terminal node |

No Issue transition happens before the Triage Checkpoint (ADR-0004).

**Post-v1 note.** The clarification branch's `NeedsInfo` state (§3.4, §7.5) is a Factory-side state that Factory records against the Issue, not a tracker transition: the tracker still sees no label or state change before the Triage Checkpoint (ADR-0004). It is not a Task state and leaves this table unchanged.

### 3.3 Intake

The daemon polls the Managed Project's tracker on a configurable interval; webhooks are post-v1 (ADR-0005). The `intake` trigger matches new Issues carrying the intake label and routes them to the `triage` agent node. The existing backlog is **not** swept: it stays out until labeled (ticket 008). Admission is by the Workflow's intake label; the `defaults/` artifact names it (`needs-triage`), and it is distinct from the post-approval `ready-for-agent` label. Those two are the v1 label set: renaming or adding labels is post-v1, when the tracker projection becomes data (ADR-0008).

Intake is idempotent: an Issue is admitted once, keyed by provider reference. A re-poll, a daemon restart, or a duplicate webhook (post-v1) cannot admit it twice; **approval** is what creates the Task.

### 3.4 Triage

A triager session in the `triage` agent node produces a typed **`TriageDecision`**: suggested labels and priority, acceptance criteria, plan sketch, size estimate, confidence, and open questions (ticket 008). Two gate nodes guard it: `decision-shape` validates the artifact against the schema in `.factory/schema/`, and `scope-declared` requires declared acceptance criteria; a missing criterion is a failure routed by its edge, not a warning.

The Owner approves or edits at the **`triage-approval` checkpoint node**. Edits are recorded as part of the decision. Approval applies `ready-for-agent` and creates the Task; rejection records the reason, comments on the Issue, and creates no Task.

The triager proposes transitions; it cannot apply them. Every transition after approval goes through Factory tools (ADR-0004).

**Post-v1 clarification branch.** Post-v1, the triager's outcome may instead be `NeedsInfo` — a `ClarificationRequest` naming the questions, the missing fields, and the context it needs — and the Issue enters a pre-Task `NeedsInfo` state (§3.2) while the exchange runs under §7.5. The answers inform a later `TriageDecision`; they do not stand in for one, and the Issue stays authoritative. v1 is decision-only: the `TriageDecision` schema, the `decision-shape` and `scope-declared` gate nodes, and the generic Task state are unchanged.

### 3.5 Agent nodes: implement, review, rework, and feedback

The default graph's agent nodes are `implement`, `review`, and `rework`. They are ordinary `agent` nodes; the engine does not know those names.

An `agent` node declares:

- a wave of one or more Roster Entries;
- required outputs, checked for presence before the node can be `Completed`;
- a deadline, idle timeout, and heartbeat;
- event edges for `stalled` and `no_progress`;
- success and failure edges.

**Implement.** One implementer session in the Task's worktree inside the Project VM. The agent has full agency over the clone: read, write, install, run. It must produce a branch with a commit and diff and may propose the PR title and body. It cannot push or merge: Factory fetches the branch from the VM clone and pushes it with the host identity in the `push` action (ADR-0010, §5.3). The VM token is read-only.

**Review.** A wave of two reviewers — spec-fidelity (does the diff do what the approved `TriageDecision` says) and adversarial (what breaks, what is missing, what is unsafe) (ticket 008) — produces typed findings: severity (blocking or not), location (path/line or artifact), claim, and evidence references, plus a verdict of approve or request changes (its schema ships in `.factory/schema/`, §4.1). Findings tagged as misunderstanding feed the Agent Confusion metric (§6.4). The `review-verdict` gate aggregates them deterministically; a failing edge carries the findings as `Feedback` to the `rework` agent node within the D14 budget. Reviewers do not merge, transition the Issue, or advance the graph.

**Rework.** An agent node selecting the implementer entry (or another roster entry in a project's graph) with a typed `Feedback` input. It handles gate failures, review findings, PR feedback, and conflict resolution. It is not a harness node kind; it is a graph node.

Gates run as Factory-issued checks, not agent claims:

- `build` / `tests` — commands executed in the Project VM; the gate reads the exit status.
- `diff-present` — a deterministic predicate over the changed-file set.

A gate never accepts "tests pass" as an agent statement. If a command cannot run, the gate fails closed with the reason.

**Agent outcomes and liveness.** The engine classifies every session as `Completed`, `Incomplete`, `Stalled`, `Crashed`, `Exhausted`, `Blocked`, or `Refused` (§2.4). Liveness is declared by the adapter:

- `heartbeat` — a session-liveness signal independent of model/tool events;
- `idle-timeout-only` — event silence plus the deadline;
- `none` — liveness is `unobserved`, never assumed.

**⟨default D13⟩** The liveness defaults are a heartbeat every 15 seconds with 3 consecutive misses allowed, an idle timeout of 5 minutes, and a deadline of 30 minutes; a workflow may override them, and the adapter declares whether a heartbeat exists.

A heartbeat proves the session is reachable, not that it is progressing. Idle timeout catches a live but stuck agent; the Agent Confusion proxies catch one that is busy but thrashing. A missing heartbeat beyond the threshold, an exceeded deadline, or a lost session produces `Stalled`/`Crashed`; the engine interrupts and records the last event, transcript reference, and liveness evidence.

**Feedback loop.** A failure or stall edge can carry a typed `Feedback` artifact into the next agent Run: a Gate report, review findings, PR feedback, an Agent Outcome, or an Owner note on resume. The next Run starts with exactly the evidence of what failed. **⟨default D14⟩** The default budget is the initial attempt plus two automatic feedback rounds; after the last round the Task is recorded `Blocked` for the Owner. Model fallback inside one entry is separate: the adapter tries the ordered model list within a Run, while an agent retry is a new Run with feedback.

### 3.6 Gates

A **Gate** is a harness-enforced condition that must pass before a Task advances; its verdict is deterministic and never an agent's judgment ([`CONTEXT.md`](../../CONTEXT.md), ADR-0003).

Three rules define it:

1. **Harness-owned.** The Gate is IR the Go engine evaluates. It is never a prompt, a skill, or a plugin assertion. Ticket 014's rule is binding: *a skill proposes, a harness-enforced rule disposes.*
2. **Deterministic.** The verdict is computed from durable facts — transition state, command exit status, provider state, file-set predicates — or from **typed artifacts aggregated by a deterministic rule**. Reviewers' judgments are content; the aggregation is the Gate.
3. **Fail-closed.** Missing evidence, an unreachable provider, a timeout, or an unknown result is a failure with a reason, never a pass.

A Gate report is a first-class record: gate node id, check, input references with digests (including the PR head where the check reads the PR), result, reason, attempt count, and the outgoing edge taken.

**Check classes the default graph needs** (drawn from the prototype's IR; the spec requires the classes, the IR names them). The IR names a gate node's primitive a `check`; the gate is the condition it enforces.

| Check class | Input | Passes when |
| --- | --- | --- |
| schema | artifact | the artifact validates against its schema |
| required-field | artifact | the named field is present and non-empty |
| command | Project VM | the command exits zero within its timeout |
| changed-files | Task branch | the predicate holds (e.g. more than zero changed files) |
| review-aggregate | typed review artifacts | the Workflow's predicate holds (default: every reviewer approves and no blocking finding is unresolved) |
| pr-state | provider | the PR is in the expected state |
| pr-checks | provider | required checks are green |

**Failure edges and bounds.** A gate's fail outcome is an edge, not a harness policy. The edge may retry the same node, route to an earlier node, open a follow-up Issue through an action, change Issue state, or wait at a checkpoint for the Owner. Every cycle carries a traversal bound; an unbounded cycle is invalid IR (the prototype's validator caught exactly this on its first run — [`prototype/workflow-authoring/`](../../prototype/workflow-authoring/README.md)). The default graph applies the D14 feedback budget; when it is spent the Task is recorded `Blocked` for the Owner. Before a Task exists, the same bound parks the **Issue** in the Owner's inbox; it does not create a Task. A failure outside a gate — model exhaustion, a crashed Run, a stall, a missing output — is an edge from the agent node with the same actions and bounds (§3.10). A node with multiple outgoing edges needs a fallback or a reviewed dead-end; the engine blocks with `no_transition` rather than guessing.

**Gate integrity.** An agent may edit `.factory/` on its branch, but it cannot loosen the gates it is running under: each Task pins the IR it was created with, including its Agent Roster (§4.8, D3). A change to the artifact takes effect for later Tasks, after review and merge.

### 3.7 PR

A PR is always required; it is the durable, protected merge surface in v1 (ADR-0003). The `push` action fetches the Task's branch from the VM clone and pushes it with the host identity; the `pr-create` action opens or updates the same PR. The agent may propose the title and body but never pushes or merges. Branch protection on the remote guards the target branch.

An in-thread review with no PR (DeltaDB's model) was considered and not adopted for v1: the pattern of review evidence and verdicts in the work thread is kept, but the PR remains the merge surface (ticket 008, ADR-0003).

**PR feedback.** After `pr-create`, the `pr-watch` trigger polls the Task's open PR and normalizes typed events: `review_changes_requested` from a human, a top-level PR comment from the Owner or a configured reviewer, `base_moved`, `merge_conflict`, and `checks_failed`. Events are deduped by provider id and reconciled on restart. **⟨default D15⟩** The poll interval is configurable, actionable actors are the Owner and a configured reviewer allowlist, bots and Factory's own comments are ignored, and inline replies are deferred. The actor filter and routes are Workflow data.

- A human `CHANGES_REQUESTED` or Owner/reviewer comment routes to the `rework` agent node with a typed `Feedback` artifact carrying the review state, comment bodies, inline path/line context, and the PR head.
- `base_moved` routes to the `sync` action; a clean sync reruns the affected gates, and a conflict routes to `rework` with the conflict evidence.
- `checks_failed` routes to `rework` or the gate's failure edge, per the graph.
- `ready_to_merge` routes to the `merge-checkpoint` node.

The VM has no issue-write token, so the agent does not reply in the PR. Factory may post a summary (“addressed in `<sha>`”) with the host identity; inline agent replies are the post-v1 comment plugin. A waiting `merge-checkpoint` also accepts PR events, so new feedback interrupts it instead of leaving a stale approval pending.

**Evidence is bound to the head.** Every Gate report and the merge Checkpoint reference the PR head commit. A push after the gates pass, or after the Owner approves, invalidates both: the Task routes back to the affected gates and, if the approval is stale, to a fresh merge Checkpoint. A merge is refused unless the PR head still equals the approved head, and the merge request itself is conditioned on that SHA rather than merely checked before it. The merge Checkpoint's `expect` also pins a feedback digest, so a new actionable review/comment invalidates the approval even when the head has not moved.

### 3.8 Merge

The merge is an Owner checkpoint node followed by a merge action:

1. Every gate in Implement and Review has passed; the `push`/`pr-create` actions have opened the PR.
2. The merge group's gate nodes (`pr-open`, `checks-green`) pass; the Owner receives the PR and the Gate report at the **`merge-checkpoint` node**.
3. Factory serializes merges per Managed Project. Before merging it verifies that the PR head still equals the head the gates and the checkpoint approved, and that the feedback digest has not changed; a mismatch refuses the merge and routes the Task to the affected gates or `rework`.
4. If the base moved and the branch must be updated, the `sync` action applies it. A clean sync that changes the head invalidates the approval and routes to a fresh checkpoint; a conflict routes to `rework`.
5. On approval and a matching head, **Factory** executes a **squash merge via `gh`** on the daemon host, using the host's identity, **conditioned on the approved head** (`--match-head-commit`), including on retries after reconciliation; a provider that cannot express the condition blocks the Task instead of merging. Factory records the merge commit.
6. Factory closes the Issue through the tracker adapter and marks the Task Merged.

Agents never run the merge: the capability is Factory's, and the remote's branch protection must make it unreachable from the Project VM's read-only token (ADR-0003, ADR-0010, ticket 008).

**⟨default D2⟩** A denied merge routes to `rework` with the Owner's reason attached as input; the Owner may instead abandon the Task through a separate recorded decision. The Workflow declares which edge a denial takes.

Post-merge monitoring is post-v1; the Managed Project's own CI takes over from the merged commit (ticket 008, ticket 018).

### 3.9 Concurrency and scheduling

Concurrency is a Workflow setting per Managed Project: the maximum number of in-flight Tasks; v1 defaults to **1** and supports values above it **⟨default D17⟩** (ticket 008, ADR-0010).

**⟨default D1⟩** Admission order is Issue creation time ascending, then Issue number; the chosen Task is recorded in the transition log so the schedule is auditable. A Task enters the queue at `Ready` and leaves it at Merged, Abandoned, or Failed. A Task waiting at a trigger or checkpoint remains in flight, holds its worktree, and counts against the cap.

At concurrency 1, a single working copy in the Project VM is sufficient. Above 1, each Task gets its own `git worktree` on a unique branch inside the same Project VM (D4); a separate clone is the fallback when a worktree cannot be used. The VM boundary stays per Managed Project (§2.5, §5.8).

**Merge queue.** **⟨default D16⟩** Merges are serialized per Managed Project. The merge action re-checks the approved head, the base, and the feedback digest inside its transaction. A base update that changes the head invalidates the approval and routes to a fresh checkpoint; a conflict routes to `rework`. Two approved Tasks never merge concurrently.

**Abandon and cancellation.** `task.abandon` on an in-flight Task interrupts the active agent or action, stops its processes, records the evidence, and removes the worktree after the branch is no longer needed. The Issue disposition is the recorded decision. A Task cannot be abandoned and dispatched in the same window; the transition is serialized.

**Resource contention.** Worktrees isolate files and branches, not build caches, ports, databases, or CPU. A project whose test suite needs exclusive services keeps `concurrency` at 1; optional per-node exclusivity is post-v1. The daemon records queue wait, active count, and VM resource pressure so the Owner can see when concurrency is hurting.

### 3.10 Blocked, failures, abandonment

Blocked is a Task state with evidence: what failed, which node and edge, what was tried, the feedback history, and what the Owner must decide. It appears in the Owner's inbox. Resuming a Blocked Task is an Owner action recorded as a transition; `task.resume` may carry an Owner note that becomes input to the resumed Run.

| Failure | Handling |
| --- | --- |
| Gate failure | The failing edge routes with the Gate report as `Feedback`; the D14 budget applies, then the Task is recorded `Blocked` |
| Agent `Incomplete` | Required outputs missing; automatic retry with the missing-output evidence as `Feedback` |
| Agent `Stalled` / `Crashed` | Heartbeat/idle/deadline or session failure; interrupt, record last event and transcript ref, automatic retry with the stall evidence as `Feedback` |
| Agent `Exhausted` | The adapter tried every model in the entry's ordered list; the edge decides retry, a different roster entry, follow-up, Issue state, or the Task is recorded `Blocked` |
| Agent `Blocked` / `Refused` | Self-reported blocker or model refusal; route to a checkpoint/blocker or retry with feedback, never silently continue |
| No-progress | Agent Confusion proxies crossed their threshold; the event edge routes to rework, or the Task is recorded `Blocked` |
| PR feedback | Human `CHANGES_REQUESTED` or Owner/reviewer comment; route to rework with the feedback artifact, bounded |
| Base moved / merge conflict | `sync` action; clean sync reruns gates, conflict routes to rework |
| Pre-Task triage failure | Recorded against the Issue; retry within the triage node or wait for the Owner; no Task is created |
| Project VM lost | Task Blocked with evidence; no silent recreation (ADR-0005) |
| Tracker/PR divergence | Reconcile from provider state; record the correction; block if the two cannot be reconciled safely |
| Egress block needing a decision | Egress Request to the Owner (§5.6); on a decision the rule is applied locally and recorded, and the Task resumes per the routed edge |
| Secret denial | Recorded with host and reason; the Task blocks or retries per policy; never bypassed |

Abandonment is an Owner decision with a reason; the Issue is left open with a comment or closed, per that decision. Abandoning an in-flight Task interrupts the active agent or action and removes its worktree (§3.9).

### 3.11 Reconcile-and-resume

On start, the daemon loads the latest snapshot, replays the log suffix, and reconciles with the world before resuming anything (ADR-0005):

1. **Tracker**: labels, state, and comments for every non-terminal Task; adopt provider truth where Factory's projection is stale.
2. **PRs**: open/closed/merged state, checks, head and base commits, review state, and feedback ids for every Task with an open PR or a `pr-watch` trigger.
3. **Project VMs**: presence, tier, and bindings per Managed Project; the local allowlist and secret scopes are reported from devvm and compared with the recorded local rules, not treated as contract drift. Worktrees are checked against their Tasks. A Task whose VM state vanished goes Blocked with evidence.
4. **In-flight Runs**: a Run whose session is gone is marked `Crashed`/`Stalled` with evidence; the Task resumes from its current node only if that node can be safely re-entered, otherwise the edge routes to a retry or Blocked. A pre-Task triage Run is retried within the triage node or waits on the Issue.
5. **Waiting nodes**: pending checkpoints and trigger cursors are restored; a new PR review/comment is delivered once, not replayed as a fresh decision.

No silent re-dispatch. Before retrying any external effect, read the provider state (PR exists? merge already applied? comment posted?) and record what was found. Reconciliation itself is logged as transitions.

---

## 4. Workflow Artifact

### 4.1 Directory

A Managed Project carries its Workflow Artifact as a committed directory, added by Project Init (ADR-0006):

```
.factory/
  workflow.dhall   # nodes, edges, triggers, actions, checkpoints, concurrency, measures
  roster.dhall     # Agent Roster: entries, model lists from bindings, policy references, declared requirements
  bindings.dhall   # init data: models per seat, build/test commands, provider/secret names, provenance
  envelope.dhall   # clone mode, network tier and preset, optional extra_allow, secret names
  schema/          # the Dhall types the files import
```

**⟨default D8⟩** `schema/` also carries the artifact schemas the Gates validate (`TriageDecision`, review findings), so the artifact is self-contained. ADR-0006 requires `schema/` for the Dhall types; artifact schemas share it rather than becoming a second configuration surface.

**Rendered from `defaults/`.** The project's `.factory/` is rendered from the Default Workflow Artifact (ADR-0008); the default itself is not part of the project artifact and does not propagate. `bindings.dhall` is the Project Init surface.

**Agent Roster.** `.factory/roster.dhall` is part of the artifact (ADR-0007): a project-scoped, typed list of Roster Entries that agent nodes select by id. Provider authentication, tokens, and host credentials are not part of the artifact: the harness (OpenCode in v1) is configured host-side, the Envelope names the secrets, and Factory stores no values (§5.5).

Reviewed as one PR at init; deviation — including a roster, model-list, or bindings change — is a PR against the Managed Project's copy.

### 4.2 Compilation

Dhall is the only frontend (ADR-0006). The compilation chain:

```
workflow.dhall + roster.dhall + envelope.dhall + bindings.dhall + schema/
        │  dhall-golang: parse, typecheck, normalize
        ▼
   typed Dhall value
        │  decode into the closed IR
        ▼
   IR validation (node ids, edges, triggers, actions, bounds, schemas)
        ▼
   versioned IR  ── the engine's contract
```

Rules:

- **No effects in Dhall.** A Dhall expression may build the graph; it may never call a host effect (ticket 011, ADR-0010).
- **Finite graphs.** Dhall has no general recursion. Runtime iteration is an explicit bounded edge cycle, with a declared bound and an engine-persisted cursor (ticket 011, ADR-0010). A cycle without a bound is invalid IR.
- **CEL for guards only.** Guards are typed, side-effect-free, terminating expressions evaluated by the engine (ticket 011).
- **IR is the contract.** The engine executes the node/edge IR, not Dhall. The IR is versioned independently of the Dhall standard (ticket 011, ADR-0006, ADR-0010).
- **Roster is compiled, not looked up.** Roster Entries and their ordered model lists compile into the IR; the engine never reads a separate roster or model-selection configuration beside the artifact, and the operational local devvm config (ADR-0009) is applied at the VM boundary, not read as workflow configuration. Each entry's ordered list lives in `bindings.dhall` (ADR-0007, ADR-0008); Project Init writes it, the roster entry that consumes it compiles it into the IR, so the list the engine selects from is the roster's. Model-list validity is a compile check; model availability is a dispatch-time fact.
- **Default is a seed.** `defaults/` is compiled in CI against fixture bindings; a project compiles its own `.factory/` with its own `bindings.dhall`. The project never reads `defaults/` at runtime.
- **Fail closed.** An IR version the engine does not know, or an artifact that fails validation, refuses to start a Task; it never runs a best-effort interpretation.

### 4.3 IR shape

Top-level fields the IR must express (ADR-0010; the prototype is evidence only — [`default-loop.ir.json`](../../prototype/workflow-authoring/default-loop.ir.json)):

| Field | Content |
| --- | --- |
| IR version | engine contract version |
| Workflow identity | `workflowId`, name, description, Managed Project reference |
| Entry | exactly one entry node id |
| Envelope | compiled Project Envelope (§4.4) |
| Roster | entries: id, role, persona, instructions (content-addressed), ordered model list, tool and permission policy reference (the post-v1 profile ref; the Project Envelope in v1), adapter options, declared requirements (secret names, tool classes, modality); one adapter kind per Managed Project |
| Concurrency | max in-flight Tasks |
| Nodes | id, kind (`agent`, `gate`, `checkpoint`, `action`, `trigger`, `route`, `terminal`), typed config, optional `group`, optional `measures`, optional `maxVisits` |
| Agent contract | wave of roster entry ids, required outputs, deadline, idle timeout, heartbeat, optional event edges |
| Gate contract | check class + parameters, pass/fail edges |
| Checkpoint contract | asked artifacts, optional `expect` (approved head SHA + feedback digest), decision and event edges |
| Action contract | action type from the closed registry, parameters, success/failure/conflict edges |
| Trigger contract | event source and match, actor guard, target edges, optional timeout |
| Route contract | pure CEL expression, decision edges |
| Terminal contract | disposition (`merged`, `abandoned`, `failed`), terminal edges |
| Edges | id, `from`, `to`, `on` (`success`, `failure`, `event`, `decision`, `timeout`, `always`), optional CEL `guard`, optional `maxTraversals` |
| Node identity | every node has a stable id; its path is `workflowId + nodeId`; `group` is display metadata, not identity |
| Termination | every cycle has at least one bounded edge; every terminal is reachable; every non-terminal has a route or a reviewed dead-end |
| Measures | default set reference plus optional per-node additions; every measure id is a built-in semantic key (§6.4) |

The roster is part of the IR; a Task pin therefore covers the models, tools, and permissions that execute it (ADR-0007, D3). The full network allowlist, provider endpoints, and secret scopes are local devvm config, not IR fields (ADR-0009). The default's golden IR asserts the node ids, edges, groups, and metric keys; a project's IR is compiled at Task creation and pinned.

v1 carries one Workflow definition per Managed Project. The `workflowId` and workflow-addressed API remain so a later multi-workflow release is additive.

### 4.4 Project Envelope

The Envelope is the containment contract Factory compiles into the Project VM ([`CONTEXT.md`](../../CONTEXT.md), ADR-0004):

| Field | v1 meaning | Compiles to |
| --- | --- | --- |
| `clone` | the VM holds its own copy; the host working tree is never mounted | `devvm --clone` |
| `network.tier` | `allowlist` | devvm tier |
| `network.preset` | a named adapter/devvm preset; `developer` starts with GitHub, common package registries, and the model-provider endpoints configured in local devvm config | preset expansion at VM create |
| `network.extra_allow` | optional stable project hosts, version-controlled; empty by default | local allow rules |
| `secrets` | secret **names** only (e.g. `github`, `model-provider`); scopes are local | `devvm secret use` bindings per Project VM |

Roster entries declare their requirements: secret names, checked against the Envelope's grants; tool classes and modality, checked against the Model Catalog for every model in the entry's list (ADR-0007). Network hosts are runtime egress, not entry requirements (ADR-0009). The Envelope grants; it never selects a model.

The envelope declares clone mode, and v1 enforces `true` (ADR-0004, ticket 009). The `developer` preset is a named adapter/devvm set; its exact host list is build-time data seeded from the prototype (`github.com`, `api.github.com`, npm, PyPI, Go proxy, crates.io). **⟨default D7⟩** The Owner may add stable project hosts to `extra_allow` by PR; per-request egress additions stay in local devvm config.

The artifact is the source of truth for the containment contract — clone, tier, preset, `extra_allow`, secret names. It is not the source of truth for the full allowlist or secret scopes: those are local devvm config, owned by the Owner and recorded in Factory's local database (ADR-0009). The VM is never hand-configured differently for the contract fields.

### 4.5 Secrets by name only

The artifact is committed, so it never contains a secret value. It names secrets; the harness or devvm host-side store holds the values, and Factory never stores or prints them; the Project VM sees placeholders and per-VM bindings (§5.5). A Workflow Artifact is therefore safe to publish in a public repository (ADR-0006).

### 4.6 Copy-on-init and deviation

Project Init renders the Default Workflow Artifact in [`defaults/`](../../defaults/README.md) into the Managed Project's `.factory/` through a PR: the typed workflow graph, roster, envelope, and schema are copied, and `bindings.dhall` carries the selected primary models, build/test commands, provider and secret names, and provenance (`irVersion` + content digest); provider endpoints are applied to local devvm config, not the artifact. There is no inheritance, `extends`, or override machinery: a Managed Project that wants a different wave, an extra node or edge, a different model list, or different bindings edits its own copy in a PR. This keeps one authoritative artifact per Managed Project and needs no merge semantics (ADR-0006, ADR-0007, ADR-0008, ADR-0010).

An upstream content change to `defaults/` does not propagate; the digest records what the project started from. A shape change is an IR major bump and a migration PR against the project's copy. Fallback models are added to an entry's ordered list by a roster or bindings PR.

The content digest covers the default's source set — `workflow.dhall`, `roster.dhall`, `envelope.dhall`, `bindings.example.dhall`, and every file under `schema/`; `fixtures/` is test-only and excluded. It is SHA-256 over the covered files sorted by repository path, each contributing its path, a NUL byte, and its LF-normalized bytes, and it is written as `sha256:<hex>` **⟨default D12⟩**. A checkout on another platform therefore yields the same digest, and the golden-IR diff shows what a content change moved.

### 4.7 Measurement declarations

A default metric set applies to every Run; per-node declarations are optional additions, and declaring none is valid (ADR-0006, ticket 016). A node with no explicit measures is measured by the default set; a node that declares measures adds built-in metric keys from §6.4. A new semantic key is post-v1. The default artifact declares the default set; the prototype's stage-group ids are not carried. The prototype's validator **failed** an unmeasured stage group (mandatory measures were the earlier requirement); ADR-0006 later made declarations optional, so that strictness is not carried into v1 — the check remains an authoring aid only.

### 4.8 Validation rules

The compiler and IR validator reject:

- an unknown IR version;
- a missing or duplicate node id, or a missing/multiple entry node;
- an edge whose `from` or `to` names no node, or whose `on` condition is incompatible with the source node kind;
- an unknown node kind, gate check class, action type, trigger event type, or decision value;
- a node with no route when its outcome is reachable, unless the node is a terminal or the dead-end is explicitly reviewed;
- a cycle with no bounded edge;
- a graph with no terminal node, or a terminal unreachable from the entry node;
- a checkpoint `expect` naming an unknown head or an unknown feedback digest;
- an agent wave naming no Roster Entry, or an entry missing its role or persona;
- an agent node with an empty or unknown required output, or a liveness contract that cannot hold (`heartbeat` not below `idleTimeout`, `idleTimeout` not below `deadline`, or a claimed heartbeat from an adapter that does not declare it);
- a checkpoint asking for an artifact no upstream node produces;
- a gate check referencing malformed parameters;
- an action whose type or parameters are unknown, or whose required capability is not declared;
- a trigger whose event source, match, or actor guard is unknown;
- a route whose CEL does not typecheck or is not side-effect-free;
- a Roster Entry whose compiled model list is empty, or a model-list member that is not a Model Catalog ID or whose declared tool classes or modality the static descriptor does not support;
- an entry whose declared secret names are not granted by the Envelope;
- an entry whose policy reference does not resolve to the project policy (the Project Envelope in v1; a Capability Profile post-v1);
- a measure id that is not a built-in semantic key (§6.4);
- a `bindings.dhall` with missing or malformed provenance: an `irVersion` the engine does not know, or a value that is not a well-formed `sha256:<hex>` content digest (§4.6);
- concurrency below 1;
- a second Workflow definition in v1.

**⟨default D3⟩** A Task pins the `workflowId`, IR version, and digest it was created with, including its Agent Roster. Mid-Task artifact edits — including a roster or model-list change — never alter the running nodes, gates, or edges; the next Task uses the new IR.

---

## 5. Containment and secrets

### 5.1 Envelope compilation

At Project VM creation or reconfiguration, Factory applies the Envelope in one pass:

| Step | devvm surface | Failure |
| --- | --- | --- |
| Create or adopt the Managed Project's VM (clone mode) | `--clone`, folder identity | refuse to run; Task blocked with evidence |
| Set the tier and expand the preset; apply `extra_allow` and the local allowlist | `allowlist` + preset + local rules | broken rule fails closed (all denied) until fixed |
| Bind each named secret | `devvm secret use NAME` | missing secret value → Task blocked; never a fallback |
| Apply local secret scopes and provider endpoints | `devvm secret set … --method --path`; local config | failure leaves the placeholder; requests fail closed |
| Record the contract digest | Factory transition log | drift in clone/tier/preset/`extra_allow`/secret names blocks new work; local allowlist differences are recorded, not drift |

The full allowlist, provider endpoints, and secret scopes come from local devvm config, not the artifact (ADR-0009). The contract digest covers only the artifact-owned fields.

### 5.2 Full agency inside the Project VM

Agents get filesystem, tools, installs, and the copied repository. OpenCode runs unrestricted inside the Project VM. v1 has no per-tool allowlists and no role profiles; the VM is the control (ADR-0004). A Roster Entry's policy reference exists for post-v1 Capability Profiles; in v1 it resolves to the project-wide policy, the Project Envelope.

### 5.3 What leaves the Project VM

| Egress | Path |
| --- | --- |
| Tracker reads | direct, `gh` inside the VM with the Managed Project's **read-only** token |
| Tracker comments | Factory-mediated in v1; the post-v1 comment plugin lets the agent request a reply |
| Tracker label/state/close transitions | Factory tools only, after the Triage Checkpoint |
| Git reads/fetch | direct, HTTPS from inside the VM with the read-only token |
| Git pushes | host-side: Factory fetches the Task branch and pushes with the host identity (no git-over-SSH injection; §5.5) |
| PR creation and merge | Factory on the daemon host |
| PR comments/reviews | read direct; replies Factory-mediated (post-v1 comment plugin) |
| Network requests | devvm proxy: allowlist, secret injection, logs |
| Blocked hosts | Egress Request to the Owner |

**Transition enforcement.** The Project VM's GitHub token is **read-only** for the Managed Project's repositories: contents read, issues read, pull requests read, metadata read, and optional checks/actions read. It has no contents write, no issue write, no merge, and no admin. Factory performs every write — push, PR creation, merge, label/state/close, and comments — with the host identity. Because the token cannot mutate, the old method/path denial layer is a defense-in-depth check rather than the primary control; devvm still logs every request and Factory reconciles out-of-band changes. The base rules are adapter/tracker-owned and applied locally; the artifact does not carry them (ADR-0009, ADR-0010).

Nothing else is an "always-ask" prompt: v1 has no approval beyond the two Checkpoints (ticket 009).

### 5.4 PR and merge ownership

Factory owns push, PR creation, and merge; the agent commits locally and may propose PR text (ADR-0004, ADR-0010). Enforcement is layered:

- branch protection on the Managed Project's repository restricts merges to Factory's host identity;
- the Project VM's token is read-only for the Managed Project's repositories; it cannot push, comment, or merge;
- the host identity is the only writer, and every write is a typed `action` with a receipt and audit record.

### 5.5 Secrets

The model is devvm's: values live on the host, the VM sees placeholders, and a proxy injects the real value only for the bound hosts (ticket 017). Secret scopes and values are local devvm config; the artifact names secrets only. Provider authentication is configured in the harness host-side; Factory stores no secret values.

| Property | Behavior |
| --- | --- |
| Storage | OS keychain or devvm's host-side store; no command prints a value |
| Placeholders | per-VM random suffix; a placeholder copied out of the VM is worthless elsewhere |
| Binding | per Project VM (`devvm secret use`); a bound secret's hosts join that VM's allowlist on 443 |
| Scope | host + header/env + optional method/path; up to 16 exact hosts per custom secret; wildcards refused; configured in the local devvm store, not the artifact |
| Coverage | HTTPS tunnels (TLS re-terminated with a VM-only CA) and plain HTTP forwards; model APIs, `gh`, git over HTTPS, custom-header APIs |
| Not covered | git over SSH, raw TCP to arbitrary ports, tools that bypass the proxy |
| Failure | a placeholder in an un-injected shape stays a placeholder and the server rejects it — fail-closed, logged without the value |
| Rotation | one read-only project token per Managed Project; the credential-minting guard refuses key/runner/webhook creation but cannot stop OAuth grants, so distrust means rotate |

Consequences the spec carries: remotes are HTTPS; the VM token is read-only (contents/issues/PRs/metadata reads, optional checks/actions reads); pushes are host-side; a secret name in the artifact that has no host-side value blocks the Task; the CA's 30-day expiry is an operational check, not an agent concern. The token is entered host-side and bound by name; the API never carries it. One read-only token per project is stored as a devvm secret bound to that Project VM; when per-project values are required, use a project-named custom secret rather than a machine-global entry.

### 5.6 Egress Requests

A devvm-blocked host — with method, path, and reason from `devvm network log --json` — becomes an **Egress Request** for the Owner ([`CONTEXT.md`](../../CONTEXT.md), ticket 009). The Owner allows or denies; Factory applies the rule to the local devvm config and records the decision and applied rule in its local SQLite DB. Both outcomes are measured; a denial is visible, not silent.

An approval does not persist as a Workflow Artifact change and has no provisional state. The local config is the applied truth; the SQLite record is the audit and recovery source. A stable project host may be added to `extra_allow` by a separate PR, but that is a deliberate policy change, not the record of the request (ADR-0009).

### 5.7 Cost

Cost is tracked when the Adapter reports usage, as the `run.tokens` and `run.cost` metrics; missing usage is recorded as unavailable, not estimated. There is no `budget` field and no cap in v1. Runaways are visible in the Owner's metrics, not prevented (ADR-0004, ADR-0009).

### 5.8 Boundary honesty

| Protected | Not protected | Mitigation |
| --- | --- | --- |
| Host filesystem and credentials: the repo is a clone, secrets are placeholders | Per-agent separation inside a Project VM | Waves share the VM by decision; Capability Profiles post-v1 |
| Network: proxy-mediated, allowlist, DNS in the proxy | Git-over-SSH secret injection | HTTPS remotes |
| Host mutation through the repo | Linux `.git` hooks/config written inside the VM | `--clone` (the host repo is never mounted); set-id files are scanned by devvm on stop |
| Tracker/PR authority | Out-of-band changes made outside Factory while the read-only token is in the VM | The VM token cannot write; Factory records out-of-band transitions as violations and reconciles provider state |
| Audit of network attempts | File and shell coverage beyond instrumented hooks | Marked partial/unobserved in the activity log (ticket 004) |

### 5.9 Post-v1 direction

Capability Profiles are narrower Envelopes — network subset, secret subset, Factory-reach subset — compiled through the same path and enforced by the same Project VM boundary; the artifact remains the source of truth for the contract, and profiles never become a second configuration surface (ticket 009, ADR-0004). A profile attaches to a Roster Entry's policy reference; the roster remains the single place that selects models and tools (ADR-0007). Profiles narrow the contract and the local config; they do not reintroduce a budget (ADR-0009).

---

## 6. Observability and measurement

Map note #15 is binding: *if it is not measured, it is not improved.* Every Run, Gate, Checkpoint, and merge emits measurable events; improvement activity is driven by those events, not by recollection.

### 6.1 Three stores, three jobs

| Store | Job | Authority |
| --- | --- | --- |
| Transition log (§2.3) | What the harness decided and did: workflow state, Gates, Checkpoints, effects | Authoritative for Task state |
| Activity event log (ticket 004 envelope) | What happened in a session and when: steers, tool calls, file access, network requests, approvals | Index and evidence; content-free by default |
| Runtime transcript | What was said: exact messages and tool payloads | Canonical for content; Factory keeps references, not copies |

The activity log links to the transcript through `evidence` (message/part IDs) and to workflow state through `run_id`/`operation_id`. Traces (OTel) are for live timing only; sampled traces are never the audit record (ticket 004).

### 6.2 Event envelope

The envelope's field names are fixed by ticket 004; its allowed-value enums, indexing, retention windows, and the queries mining runs over remain fog (§9.1).

| Field | Meaning |
| --- | --- |
| `schema_version` | pinned envelope version |
| `event_id`, `sequence` | stable id; monotonic per session |
| `occurred_at` | RFC3339 UTC |
| `session_id`, `run_id`, `parent_session_id` | runtime session, Factory Run, delegated/forked parent |
| `trace_id`, `span_id` | optional W3C/OTel correlation |
| `actor` | `human`, `agent`, `system`, or `tool`, with a stable local id |
| `kind` | closed category set (§6.3) |
| `operation_id`, `operation` | correlation id; normalized operation name |
| `outcome` | `started`, `succeeded`, `failed`, `denied`, `cancelled` |
| `duration_ms` | where applicable |
| `target` | repo-relative path or hostname, never both |
| `details` | bounded safe fields only |
| `evidence` | transcript references |
| `completeness` | `complete`, `partial`, or `unobserved` |

### 6.3 Categories

The activity log's closed set is ticket 004's: `steer`, `skill_invoked`, `context_changed`, `model_call`, `tool_call`, `file_access`, `network_request`, `approval`, `run_state`.

Workflow facts — Gate verdicts, node transitions, Checkpoint decisions, Agent Outcomes, feedback rounds, PR review/comment events, tracker and PR effects, reconciliation — live in the transition log and are correlated into the Owner timeline by `run_id` and `operation_id`. Whether they surface as additional activity kinds is part of the field-schema fog, not decided here; liveness signals are recorded as state changes, never one row per beat.

Steers keep the human message in the transcript; the event carries the subtype (`correction`, `preference`, `scope_change`, `approval`, `rejection`), whether it was explicit or inferred, and its confidence. Inferred intent is never presented as ground truth (ticket 004).

### 6.4 Default metric set

Applies to every Run; nodes may add, never subtract (ADR-0006, ticket 008, ADR-0010). Each metric has one stable key, and that key is the id used in the artifact. The default artifact declares the set; a node may add built-in keys, but v1 allows no new semantic key.

| Key | Metric | Definition |
| --- | --- | --- |
| `node.cycle_time` | Node cycle time | Node entry → exit transition, per Task; p50/p95 |
| `gate.verdict` | Gate verdicts | pass / deny / timeout counts and rates per Gate node id |
| `review.findings` | Review findings | count and severity per wave, per reviewer persona |
| `run.retries` | Retries | per node and per Task |
| `run.tokens` | Tokens | per Run, Task, Roster Entry, resolved model, Managed Project; only when the adapter reports usage |
| `run.cost` | Cost | same dimensions; only when reported; missing usage is unavailable, never estimated |
| `model.resolution` | Model resolution | fallback attempts and exhausted lists per Run and Roster Entry; provider error classes; fallback rate |
| `agent.outcomes` | Agent outcomes | counts and rates of Completed / Incomplete / Stalled / Crashed / Exhausted / Blocked / Refused |
| `agent.liveness` | Session liveness | heartbeat misses, idle-timeout and deadline stalls, recovery time; liveness mode |
| `agent.feedback_rounds` | Feedback rounds | feedback attempts per agent node and Task, split by source (gate, review, PR, agent outcome) |
| `pr.feedback_rounds` | PR feedback rounds | human review/comment events routed to rework, and time to address |
| `pr.merge_latency` | PR merge latency | PR opened → merge transition |
| `merge.queue_wait` | Merge queue wait | approved → merge action start, per Task |
| `tool.error_rate` | Tool error rate | failed or denied tool calls per Run, normalized by operation |
| `agent.confusion_proxies` | Agent Confusion proxies | six proxies below |

The default artifact's `measures` list is exactly this key set; the golden IR asserts it.

**Agent Confusion** is a measured property, expressed through proxies, never a subjective score ([`CONTEXT.md`](../../CONTEXT.md)):

| Proxy | Operational definition |
| --- | --- |
| Repeated identical tool calls | the same normalized operation, target, and argument digest repeated within a Run above a configured threshold |
| File thrash | the same path written and reverted repeatedly, or a net-zero edit set across a Run |
| Plan revisions | plan artifacts superseded within one Task |
| Abandonment / retry | Tasks abandoned by the Owner per N Tasks; Runs ending without an Outcome; node retries per Task |
| Reviewer-flagged misunderstanding | review findings tagged `misunderstanding` |
| Self-reported uncertainty | agent-declared uncertainty events in a Run |

Thresholds are build-time configuration recorded alongside the metric so a metric definition cannot drift silently. **⟨default D5⟩**

### 6.5 Containment measures

From ticket 017, recorded per Project VM:

| Measure | Why |
| --- | --- |
| VM start time p50/p95 (cold vs image-cached) | Task start cost; idle-stop tuning |
| Image/toolchain build time and refresh frequency | the warm state |
| Secret denials by host | a role or Task tried a secret it was not bound to |
| Egress blocks per host/reason, and allow suggestions | workflow friction; Egress Request demand |
| Tier violations and `unenforced` sightings | containment regressions |
| Task isolation failures | self-check stops, folder-identity refusals, set-id files named, cross-Task port contention |
| Concurrent VMs vs the 17 cap; per-VM memory/disk | resource headroom |

### 6.6 devvm network log ingestion

The daemon tails or polls `devvm network log --json` per Project VM and normalizes each event into a `network_request` activity event: `target.host`, method, path, outcome (`succeeded` or `denied`), and `details` carrying the rule, the secrets injected, and the block reason. devvm's event kinds `tunnel`, `intercept`, `forward`, `blocked`, and `nix-cache` map onto that event.

Rules:

- **Ingest before removal.** `devvm rm` deletes the VM's logs; Factory ingests first. Retention is Factory's, not devvm's rolling ~10 MiB (ticket 017).
- **Content-free.** Host, method, path, rule, secrets-by-name, reason. No query strings, headers, or bodies.
- **Enforcement-level coverage.** This closes the network axis of ticket 004's "partial/unobserved" warning for Runs in a Project VM; file and shell axes keep their caveats and are marked accordingly.
- **Downtime is visible.** A gap in ingestion is recorded as an unobserved interval, never smoothed over.

### 6.7 Privacy and retention

Activity details stay local by default, with explicit retention, deletion, and export controls. Content digests are for correlation and integrity, not a claim that content is recoverable or secret-proof. Remote telemetry is opt-in and content-free. Shell events capture executable category and exit status by default, not raw arguments, environment, stdin, or output. Full payloads stay in the protected transcript or Run detail (ticket 004).

### 6.8 Mining

Mining is a deliberate, reviewable batch over a date/project/session scope, not a background rewrite. It prioritizes explicit corrections and rejections, repeated clarifications, failed or denied operations, reruns, and changed context. It produces evidence-linked candidate learnings — pattern, supporting event and message references, counterexamples, confidence, proposed destination — never direct edits (ticket 004).

Ticket 012's upgrade is adopted in form: a candidate carries a `cue`, a `lesson`, and `evidence`; admission requires an execution contrast; a candidate bundles the source run or skill bundle it came from; retrieval is an index, not a summary dump. The governance stays Factory's: the Owner approves changes to shared skills or Workflows **and any creation or promotion of tracker work**, and repeated actionable gaps become deduplicated Issues on the tracker after that approval. Mining-generated Issues are distinct from the feedback convention in §7.2. Cross-run persistence and consolidation are Factory's own addition (ticket 012).

### 6.9 Owner timeline

One timeline per Run or Task, built from activity events, transition records, and trace spans: steers and context changes, model calls, tool calls, approvals, file and network operations, node transitions, Gate verdicts, Agent Outcomes, feedback rounds, PR review/comment/base events, outcome and latency, plus links to the transcript, the diff, and the PR. Filterable by Managed Project, Task, Run, node, actor, operation, outcome, and time (ticket 004).

### 6.10 Metrics carried from research, not mandated

Ticket 014's candidates are useful but were not adopted as the v1 set: traceability coverage (merged changes with a complete session→Gate→diff→outcome chain), log health (growth, frontier query latency), review capacity (arrivals vs reviewer capacity), mining yield (accepted learnings per N sessions). Ticket 012 adds a candidate of the same kind: admitted-lesson count and re-use. They belong on the dashboard when the mining loop exists.

---

## 7. Adoption, init, and self-hosting

### 7.1 Project Init

Adopting a repository as a Managed Project is a PR, not a console wizard ([`CONTEXT.md`](../../CONTEXT.md), ticket 008):

1. The Owner registers the repository and its tracker with Factory.
2. The Owner configures the harness host-side (OpenCode in v1): adds provider authentication and verifies the models Factory may offer. Factory stores no secret values.
3. `factory init` — interactive by default, fully flag-driven for automation — validates the configured harness live, and asks for a primary model for each default agent node's roster entry (triager, implementer, reviewer (spec-fidelity), reviewer (adversarial)) and for build/test commands, defaulting to `make build` / `make test` **⟨default D11⟩**. It renders `defaults/` into the project's `.factory/`, writes `bindings.dhall` with the selected models, commands, provider and secret names, and provenance (`irVersion` + content digest), applies provider endpoints to local devvm config, and proposes the init PR. If no provider is configured or live validation fails, init blocks and opens no PR. **⟨default D10⟩**
4. The Owner reviews and merges the init PR. The repository is now a Managed Project.
5. Secret **values** and scopes are entered in the harness or devvm host-side store under the names the artifact declares; no value enters Factory, the repository, the VM, or a log, and the scope stays local.
6. Branch protection is verified: merges restricted to Factory's identity; the project token cannot merge.
7. The Project VM is created on first work, with the Envelope compiled.

Fallback models are added to an entry's ordered list by a later roster or bindings PR, not during init. Until step 4 merges, Factory may report on the project but creates no Tasks: the artifact is the contract.

### 7.2 Factory as Subproject one

Factory's own repository is the first Managed Project ([`CONTEXT.md`](../../CONTEXT.md), ticket 008):

- **Bootstrap period.** The initial build is manual: a human writes the daemon, the adapter, and the Default Workflow Artifact in `defaults/` (workflow, roster, envelope, bindings, schema, golden IR), and merges them without the Loop.
- **Handover.** Once the artifact is merged and the daemon can run the Loop, Factory drives changes to itself. From then on, work on Factory arrives as Issues and leaves as merged PRs like any other project.
- **Roster changes.** Factory's own Agent Roster is an artifact like any other; a self-merged roster or model-list change takes effect for later Tasks (D3).
- **Feedback routing.** Work done in another Managed Project files feedback about Factory as an Issue on Factory's tracker (map note #5). In v1 that is a convention, not a graph node.
- **Upgrade step.** A self-merged change to the daemon takes effect only when the daemon is rebuilt or restarted. **⟨default D6⟩** The Owner performs that restart; automating self-upgrade is not v1.

### 7.3 Operating surfaces

Ticket 010 names `factory inbox`, `factory approve …`, and `factory egress allow …`; ADR-0005 fixes the architecture. The spec expects at least the following surface; the verb and command names are **⟨default D9⟩**:

| Surface | Purpose |
| --- | --- |
| `factory inbox` | Checkpoints, Blocked Tasks, Egress Requests |
| `factory approve <checkpoint>` | Record a Checkpoint decision, with edits or reason |
| `factory egress allow` / `factory egress deny` | Decide an Egress Request; both outcomes recorded |
| `factory init` | Validate the configured harness, select a primary model per default seat and build/test commands, render `defaults/` into `.factory/`, and open the init PR (interactive or flags) |
| `factory models` | List the adapter's Model Catalog and current availability |
| `factory status` | Task state, current node, attempts, PR/feedback state, Gate reports, metrics |
| `factory timeline` | The Owner timeline for a Task or Run, filtered by node/actor/outcome |
| `factory task abandon` | Abandon a Task with a reason and Issue disposition; cancels an in-flight Run |
| `factory task resume` | Resume a Blocked Task, optionally with an Owner note/feedback |
| `factory workflow validate` | Compile and validate the node/edge graph before a PR |

All are clients of the same API; none reads the database.

### 7.4 Post-v1: Project Console and Project Assistant

v1 ships the CLI only. Three post-v1 Factory clients consume the same API and do not change the control plane: the **Project Console** (a per-project browser client for Tasks, Runs, Gate reports, and metrics), the **Node View**, and the **Project Assistant**. They are scoped per Managed Project first; a Factory-wide overview is later.

- **Node View.** One node at a time — any node in the graph: agent, gate, checkpoint, action, trigger, route, or terminal. It groups the node's Runs, model attempts, activity events, artifacts, Gate reports, and transcript references, and can follow the Run's normalized event stream live. The node path is stable in the IR (v1); the run/event path columns and the view itself are post-v1. A rich view depends on the observability schema fog (§9.1).
- **Project Assistant.** A per-project client, not a Workflow node and not a Roster Entry. It reads project state and a node's work; it may create an Issue (recorded, with the intake label), propose a `.factory/` change as a PR, and send a message to a waiting Run — each with Owner confirmation. Its answer to a question is a transient artifact the Owner can view and discard; there is no separate report capability. It never merges, transitions the tracker, advances Workflow state, holds the Project VM's credentials, or records a Checkpoint decision on the Owner's behalf.
- **Waiting-agent conversation.** When an agent waits for a human, its Run enters `waiting_for_human`; the Task may be Blocked or still at its current node. The Owner's message is a recorded command; the adapter steers or resumes the session, and the conversation lands in the transcript and activity log. A conversation can unblock or inform the agent, but it cannot advance the Workflow; a Checkpoint decision remains a separate harness record. If the session is gone, the conversation is not possible: the Task is Blocked with evidence and resumes per policy with a fresh session and handoff summary. A waiting-agent exchange and a triage clarification are both Conversations (§7.5), the same record the post-v1 API exposes as a resource.

### 7.5 Post-v1: Clarification conversations and handoff

Post-v1 adds an alternative triage outcome — `NeedsInfo` — and a richer surface for the conversation that resolves it. This is a direction, not a v1 behavior: no v1 schema, gate node, graph, or generic Task state changes (§3.4).

**Flow.**

1. The triager returns `NeedsInfo` with a `ClarificationRequest`: the questions, the missing fields, and the context behind each. The Issue enters the pre-Task `NeedsInfo` state (§3.2).
2. The triager hands the Conversation to the richest surface available: preferably a T3 Code thread, then an OpenCode session, with GitHub Issue comments as the fallback.
3. Answers arrive as messages. Factory posts a summary and a link on the Issue; the Issue stays authoritative.
4. Triage re-runs over the summary and the Issue's current state and produces the `TriageDecision` it could not produce before. The normal Gates and triage-approval Checkpoint follow, and only approval creates the Task.

**Conversation record.** A Conversation is a Factory record linked to an Issue or a Run ([`CONTEXT.md`](../../CONTEXT.md)). It carries the hosting surface and its provider reference (thread or session id), the opening request or trigger, participant identities, references to the messages (transcript references, not copies, §6.1), the summary posted to the Issue, and its lifecycle. Messages are evidence: they inform a decision, they are not Workflow state, and a Conversation never appears in a node's transition history as an outcome. Human messages in a session-hosted Conversation are steers in the activity log (§6.3); a tracker-hosted exchange lands on the Issue as comments. Repeated clarifications remain a mining priority (§6.8).

**Summary back to the Issue.** The Issue gets a summary and a link, not a transcript of the exchange. The Issue is the durable record the Owner and the next agent read; a raw transcript is long, surface-specific, and may carry content that does not belong on the tracker. The summary is the artifact of the Conversation and is linked from both sides. On the GitHub-comments fallback the exchange already lives on the Issue: the summary is its own comment and the link points at the thread.

**Security boundary.** The agent in a Conversation has a scoped tool set: it may read the Issue, ask and answer questions, and write messages to the Conversation record. It cannot merge, transition the tracker, advance Workflow state, or use Project VM credentials. Only the `TriageDecision` and its Checkpoint advance the Loop; a Conversation cannot. Who else may join a Conversation — guests, a second Owner — is fog (§9.1).

**T3 Code: surface or adapter.** Two post-v1 options are recorded; neither is chosen here.

- **Surface/client.** Factory launches a T3 thread through the T3 API, stores the link on the Conversation record, and the agent inside the thread uses Factory's tools, including reading the Issue, reporting answers, and attaching artifacts. T3 hosts the thread; Factory owns the record and the boundary.
- **`RuntimeAdapter`.** T3 is a future execution adapter through ADR-0002's seam, a peer of OpenCode, not a conversation host.

They are compatible but distinct; choosing either is a future ADR.

**Forward-looking API note.** The post-v1 API exposes Conversation as a resource — query, open/handoff, message, close, subscribe — for the Project Assistant, the Node View (§7.4), and a T3 surface. It reads and writes Conversation records and streams messages; it does not advance Workflow state, which still comes only from a committed transition. The full contract belongs to the future client API design, not this spec.

---

## 8. Build prerequisites and risks

### 8.1 Hard prerequisites

| Prerequisite | Why it is required (source) |
| --- | --- |
| Go toolchain and a single daemon binary | ADR-0001; static distribution, goroutines, official MCP/provider SDKs if needed |
| SQLite with WAL | ADR-0005; one writer, one backup file |
| `dhall-golang` **conformance gate** | ADR-0006: the build fails if the binding cannot evaluate the artifact schema (workflow, roster, envelope, bindings) or the default's canonical compile differs from its golden IR (§8.2). There is no second frontend |
| `cel-go` | guards (ticket 011) |
| OpenCode, **pinned version** | ADR-0002; contract tests against the pinned API surface, not "latest" (ticket 002) |
| Configured harness provider (OpenCode in v1) with access to the selected models | Project Init validates it live; Factory stores no secret values (ADR-0007) |
| Adapter Model Catalog (static descriptor + live availability) | Compile-time roster validation and `factory init` model selection (ADR-0007) |
| Adapter liveness declaration (`heartbeat`, `idle-timeout-only`, or `none`) | Agent completion and stall detection; a missing heartbeat is never assumed alive (ADR-0010) |
| Default Workflow Artifact at `defaults/` with its golden IR | Project Init renders it; the conformance gate compiles it (ADR-0008) |
| devvm **≥ 0.1.1**, CLI only | ticket 017; 0.1.0 predates custom secrets, the 17-VM cap, and the split proxy |
| Linux host with Lima + QEMU/KVM | devvm's only backend (ticket 017) |
| `gh` authenticated on the daemon host | tracker polling, host-side push, PR creation, squash merge |
| Branch protection on each Managed Project's repository | merge authority is Factory's; the Managed Project's read-only token cannot push or merge |
| systemd user unit | ADR-0005 |
| HTTPS git remotes | devvm does not inject secrets into git-over-SSH |

### 8.2 The Dhall conformance gate

A CI job, not a runtime hope:

1. Evaluate `defaults/schema/` and `defaults/workflow.dhall` + `defaults/roster.dhall` + `defaults/envelope.dhall` with `defaults/fixtures/bindings.dhall`, using the pinned `dhall-golang`.
2. Decode the result into the Go IR.
3. Validate roster references against the adapter's pinned Model Catalog descriptor, then run the IR validator (§4.8).
4. Canonicalize the IR and compare it to `defaults/fixtures/golden.ir.json`; fail on any difference.
5. Fail the build on any error, with the Dhall diagnostics attached.

The static descriptor declares model IDs, providers, capabilities (including session liveness), and tool classes, and is pinned with the adapter; live availability is an init-time overlay, not a CI input, so a provider rotation cannot fail the build. The golden IR is a fixture compile of the default, not a project's IR; a project compiles its own `.factory/` with its own `bindings.dhall`.

The gate failing stops the build. It does not trigger a fallback frontend: the Owner took the Dhall decision with this risk in view (ADR-0006), and ticket 011's fallback order is a re-decision, not a quiet switch.

### 8.3 Version pins

| Dependency | Pin | Compatibility policy |
| --- | --- | --- |
| devvm | ≥ 0.1.1 | CLI + `--json` version 1 (additive); re-pin only after a contract run |
| OpenCode | one pinned release | contract tests for sessions, events, permissions, questions, model fallback order and exhaustion; capability descriptor records the version |
| Model Catalog | adapter descriptor version | additive; unknown model IDs fail compile; live availability is not pinned |
| Default artifact | `defaults/` + content digest | content changes update the digest; shape changes bump the IR major and migrate by PR |
| IR | its own major version | engine refuses unknown versions |
| Dhall standard | the subset `dhall-golang` supports | conformance gate proves the schema, not the standard |
| Event envelope | `schema_version` 1 | additive changes bump the version |

The 0.1.1 line was at `0.1.1-rc.3` when researched; the pin is to 0.1.1 or later, and the contract run — not the version string — decides whether a given build is usable (ticket 017).

### 8.4 Risk register

| # | Risk | Exposure | Mitigation |
| --- | --- | --- | --- |
| R1 | `dhall-golang` tracks standard v19 while the standard is 23.1 | Authoring path blocked at the worst time | Conformance spike is the first build task; Go decodes and validates the IR before execution; build gate fails loudly; no fallback frontend by decision (ADR-0006, ticket 011) |
| R2 | OpenCode API churn; some route families are experimental; provider model rotation removes a model mid-flight | Adapter breaks on upgrade; a Run fails on exhaustion | Pinned version; contract tests; capability descriptor including liveness; test double exercises the seam; ordered model lists with typed exhaustion to the agent node; model-resolution metrics; upgrades only with a green suite (ADR-0002, ADR-0007, ADR-0010, ticket 002) |
| R3 | devvm is young (0.1.x), CLI-only, breaking changes on main, 17-VM cap | Lifecycle automation and capacity | Pin ≥ 0.1.1; treat `--json` version as the contract; wrap the CLI behind Factory's adapter; one VM per Managed Project keeps the count low (ticket 017) |
| R4 | Linux has no `.git` protection | VM-written hooks/config could run on the host | `--clone` always; the host repo is never mounted; devvm scans set-id files on stop (ticket 017) |
| R5 | Secret injection does not cover git-over-SSH; CA expiry; minting gaps | VM git-over-SSH reads fail; requests fail closed; credential grants | HTTPS remotes; host-side push uses the host identity; read-only project token in the VM; CA expiry is an operational check; rotate after distrust (ticket 017, ADR-0010) |
| R6 | Runaway spend; no budget or cap in v1 | Cost, not correctness | Cost tracked when the adapter reports usage; visible in metrics; no `budget` field; the allowlist bounds egress; a cap is post-v1 (ADR-0004, ADR-0009) |
| R7 | Self-hosting bootstrap is circular | Factory cannot build itself without itself | Manual initial build; Subproject one after handover; feedback as Issues (ticket 008) |
| R8 | Gate integrity: an agent edits the artifact or claims a verdict; evidence outlives its head | Ungated advancement; merging unreviewed content | IR (including the Agent Roster) pinned per Task; gate nodes read durable facts; head- and feedback-bound evidence, compare-and-merge, serialized merge queue (§3.7–3.9); artifact edits are PRs (ticket 014, ADR-0003, ADR-0007, ADR-0010) |
| R9 | One daemon, one Owner, no multi-user auth | Local compromise; no team use | Unix socket with a scoped Owner session; one writer; one credential owner; multi-client auth deferred (ADR-0005) |
| R10 | Evidence loss when a Project VM is removed | Forensics and mining gaps | Ingest network logs and export transcripts before `devvm rm`; refs and digests live in Factory (ticket 004, ticket 017) |
| R11 | Polling intake latency and provider rate limits | Slow admission; throttling | Configurable interval; idempotent intake; webhooks post-v1 (ADR-0005) |
| R12 | DeltaDB / Harness² / Swamp tempt adoption | License, account gate, or substrate lock-in | Patterns only, no dependency (§8.5) |
| R13 | Deploy creep | Scope and credential risk | Out of scope by owner ruling; each project owns its CI; no deploy credentials in a Project VM (ticket 018) |
| R14 | 17-VM cap / per-VM memory if usage grows | Queueing at scale | Per-Run VMs stay an escalation; capacity is measured (§2.5, R3; ticket 017) |
| R15 | Transcript/runtime state inside the VM is the only copy | Loss on VM replacement; runtime lock-in | Factory keeps Task context, artifacts, diffs, and handoff summaries outside the runtime so a Task can resume with a fresh session (ticket 002) |
| R16 | Node/edge graph is more expressive than a stage table | Authoring complexity; a validator that misses a dead end or unbounded cycle | Small closed primitive set; bounded cycles; entry/terminal/edge validation; default graph as the proof; prototype/golden IR tests (ADR-0010) |
| R17 | Agents stall, stop silently, or return incomplete work | Tasks hang or "finish" without the work | Typed Agent Outcomes; declared liveness with idle/deadline fallback; required outputs; Gate/review feedback edges; the D14 feedback budget then `Blocked` (ADR-0010) |
| R18 | Concurrent Tasks share one Project VM | Build/test port, cache, CPU, and database contention | Per-Task worktrees; concurrency 1 for projects with exclusive services; queue and resource metrics; per-Run VM remains an escalation (ADR-0010, ticket 017) |
| R19 | PR polling rate limits and feedback storms | Missed or duplicated feedback; rework loops | Provider-id dedupe, actor allowlist, ETag/since cursors, bounded rework rounds, bots ignored by default (ADR-0010) |
| R20 | Merge queue and base movement invalidate approvals | Stale merges or repeated Owner approvals | Serialized merge queue; head + base + feedback digest checks inside the merge transaction; base update routes to sync/rework and a fresh checkpoint (ADR-0010) |

### 8.5 Patterns studied, not adopted

| Source | Taken | Not taken |
| --- | --- | --- |
| DeltaDB (ticket 014) | stable operation identity, append-only history, materialized frontier, evidence→conversation links | the store itself (no SDK/source, hosted, no permission model); review-without-PR for v1 |
| Harness² (ticket 012) | eight-component harness vocabulary, contrast-gated lessons (`cue`/`lesson`/`evidence`), artifact-bundled candidates, index-on-demand | automated lesson adoption; the substrate |
| Swamp Club (ticket 013) | typed DAG + CEL, default-deny grant vocabulary, YAML+Schema as the road not taken, skills+CLI neutrality | building on it (AGPL, closed registry, mandatory account); public registry; remote worker fleet |
| Code mode (ticket 015) | the composition pattern as a future adapter capability; Pi's sandbox reference | scripts as Workflow, scripts as Gates; classifier-based checking |

### 8.6 Suggested build order

Dependency-ordered, each step ending in a verifiable state:

1. Dhall conformance spike + node/edge IR validator + Default Workflow Artifact in `defaults/` (workflow graph, roster, envelope, bindings, schema, golden IR) (the earliest failure is the cheapest).
2. Transition log, projections, snapshots, graph executor primitives (agent, gate, checkpoint, action, trigger, route, terminal; edges; bounds), API skeleton, CLI client.
3. Fake `RuntimeAdapter` runs the default graph end to end with no real agent, including model fallback, typed outcomes, liveness/stall detection, feedback edges, and exhaustion.
4. devvm lifecycle + Envelope compilation + read-only project token + secret bindings.
5. OpenCode adapter inside the Project VM; Model Catalog; liveness capability; contract tests.
6. Tracker adapter, gate nodes, checkpoints, host-side push, PR creation, serialized squash merge.
7. Concurrency: per-Task worktrees, queue, cancel/cleanup, merge queue, PR watch trigger, `sync` action, `rework` agent node.
8. Activity log, metric set (including agent outcomes, liveness, feedback rounds, merge queue), network-log ingestion.
9. Project Init (guided provider validation, seat model and build/test command selection, `defaults/` rendering); Factory registers itself; handover to self-driven.

---

## 9. Open questions (fog)

### 9.1 Fog

Six questions remain unspecified in the record. This spec does not answer them.

1. **Observability schema detail.** The envelope's field names are decided (ticket 004, §6.2); its allowed-value enums, indexing, retention windows, and the queries mining runs over are not. Until they are, the log is a schema without an operational contract: implementers will otherwise invent value names and indexes that mining then depends on. Related detail: whether workflow facts (Gate verdicts, Checkpoints, effects) surface as additional activity kinds or stay transition-log-only.
2. **Path-to-other-users surface.** Packaging, onboarding, the configuration surface a second Owner would need, multi-user auth, and how a second Owner's projects are isolated. The map defers design until the Owner's needs are fully specified; the four seams in §1.2 are what keeps the door open.
3. **Project Assistant capability set.** Beyond the boundaries §7.4 records — never merge, never transition the tracker, never advance Workflow state, no Project VM credentials, no Checkpoint decision on the Owner's behalf — the assistant's tool surface, confirmation rules, and transient-artifact behavior are not specified.
4. **Clarification conversation access and shape.** Guest or multi-user access to a Conversation, whether T3 is a surface or a `RuntimeAdapter` (§7.5), retention of conversation transcripts, and whether clarification needs a dedicated agent beyond the triager are unspecified.
5. **Multiple Workflow routing.** If a project later carries more than one Workflow definition, how an Issue selects one before triage — label mapping, issue type, or a project-level intake graph — is unspecified. v1 keeps one definition per project and a `workflowId` in the IR (ADR-0010).
6. **Full PR conversation surface.** Inline reply threads, resolving conversations, bot feedback, reactions, and arbitrary `gh` comment operations are post-v1. v1 covers human review state, top-level comments from the Owner/reviewer allowlist, base movement, and conflicts; Factory posts summaries (ADR-0010).

Everything else is deferred by decision; §1.4 is the authoritative list, and none of it is fog. Per-Run VMs are not a deferral: they remain an escalation option, unused by v1 (ticket 017).

### 9.2 Spec defaults introduced here

Every **⟨default Dn⟩** in the body is listed here; the D-id is the stable key, the section reference is convenience:

| # | Default | Where |
| --- | --- | --- |
| D1 | Admission order: Issue creation time, then number | §3.9 |
| D2 | A denied merge routes to `rework` with the reason; the Workflow declares the denial/abandon split | §3.8 |
| D3 | Each Task pins its `workflowId`, IR version, and digest at creation, including the Agent Roster | §4.8 |
| D4 | Concurrency above 1 gives each Task its own `git worktree` in the VM, with a separate clone as fallback | §2.5, §3.9 |
| D5 | Metric thresholds are recorded configuration | §6.4 |
| D6 | The Owner restarts the daemon after a self-merged change | §7.2 |
| D7 | The `developer` preset is a named adapter/devvm set; its host list is build-time data seeded from the prototype | §4.4 |
| D8 | Artifact schemas share `.factory/schema/` with the Dhall types | §4.1 |
| D9 | CLI verb and command names beyond the three ticket-010 names | §7.3 |
| D10 | Init blocks and opens no PR when no provider is configured or live validation fails | §7.1 |
| D11 | Build/test commands default to `make build` / `make test` | §7.1 |
| D12 | Content digest: SHA-256 over the default's source set, sorted by path, LF-normalized | §4.6 |
| D13 | Agent liveness defaults: heartbeat every 15s with 3 misses, idle timeout 5m, deadline 30m; the workflow may override, and the adapter declares whether heartbeat exists | §2.4, §3.5 |
| D14 | Feedback budget: the initial attempt plus two automatic feedback rounds, then Blocked; model fallback inside one entry is separate | §3.5, §3.6 |
| D15 | PR feedback defaults: poll interval configurable; actionable actors are the Owner and a configured reviewer allowlist; bots and Factory comments ignored; inline replies deferred | §3.7 |
| D16 | Merge queue: one merge at a time per Managed Project; a base update that changes the head requires a fresh merge Checkpoint | §3.8, §3.9 |
| D17 | Concurrency defaults to 1 and is configurable per Managed Project; a waiting Task counts against the cap | §3.9 |

---

## 10. Reconciliations

The spec's first version recorded nine conflicts between the map, the glossary, the tickets, and the ADRs. This table is the reconciliation record — history, not normative text; the body is normative. I10 records a later Owner decision that reverses I9's split; I11 records the default artifact's ownership; I12 records the containment contract/local-config split and the `budget` removal; I13–I15 record ADR-0010's node/edge core and the v1 concurrency, PR feedback, and agent-access changes. I7's amendment replaced ticket 009's runtime-only allowlist with artifact persistence, recorded in ADR-0004 and ticket 009; I12 supersedes that persistence and I11's provider-endpoints-in-bindings part. No other decision was reversed.

| # | Was | Resolution | Artifact changed |
| --- | --- | --- | --- |
| I1 | The map's Notes #12 called daemon-vs-CLI "decide later" | The note records ADR-0005's decision: resident daemon, thin CLI | [`map.md`](../wayfinding/map.md) |
| I2 | The map destination, Notes #3/#14, and the glossary called Workflows "code-defined" with the language open; ticket 001 still recommended Starlark | A Workflow is typed declarative data (Dhall → IR), not code running in the Go process; the wording matches ADR-0006 and a superseded-in-part note now heads 001 | [`map.md`](../wayfinding/map.md), [`CONTEXT.md`](../../CONTEXT.md), [`closed/001`](../wayfinding/closed/001-research-harness-language.md) |
| I3 | Ticket 002 recommended the embedded OpenCode SDK | Superseded by ticket 006/ADR-0002 (managed server over its API); a superseded-in-part note now heads 002 | [`closed/002`](../wayfinding/closed/002-research-build-vs-opencode-plugins.md) |
| I4 | The map destination promised "per-agent capability control" | v1 controls per Managed Project (ADR-0004); per-role profiles are post-v1 | [`map.md`](../wayfinding/map.md) |
| I5 | Ticket 006's Task-in named a "capability-profile ref" while v1 ships no profiles | The field resolves to the Project Envelope in v1 and is reserved for post-v1 profiles | [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md) |
| I6 | ADR-0006's `budget` field read like a cap | It was a spend-measurement declaration; removed by I12 (cost is tracked when reported) | [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md) |
| I7 | Ticket 009 had an egress approval adding a host to the allowlist outside the artifact | Superseded by I12: an approval applies to local devvm config and is recorded with the applied rule in SQLite; an `extra_allow` PR is optional for stable hosts | [`ADR-0004`](../adr/0004-containment-first-capability-model.md), [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md) |
| I8 | The map's fog still listed the permission model as unspecified | v1's model is decided (ADR-0004); only post-v1 profiles remain open | [`map.md`](../wayfinding/map.md) |
| I9 | The glossary defined the Workflow Artifact as the Workflow plus runtime configuration; ADR-0006 defines it as the `.factory/` directory | The artifact is `.factory/`; runtime configuration is a separate Factory-managed, versioned artifact per Managed Project (ADR-0002), and the glossary now says so. This split is superseded by I10 | [`CONTEXT.md`](../../CONTEXT.md), [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md) |
| I10 | I9 and ADR-0002 placed runtime configuration in a separate Factory-managed artifact outside `.factory/` | The Agent Roster is project-owned, lives in `.factory/roster.dhall`, and compiles into the IR; Factory validates it against the Model Catalog and stores no secret values (ADR-0007) | [`CONTEXT.md`](../../CONTEXT.md), [`ADR-0002`](../adr/0002-opencode-as-first-runtime-adapter.md), [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md), [`ADR-0007`](../adr/0007-agent-roster-in-workflow-artifact.md) |
| I11 | The default Workflow Artifact was referenced nine times with no address; §1.5 #6 had no subject | The default is a versioned deliverable in `defaults/`, rendered into a project by Project Init, with a fixture golden IR and content-digest provenance (ADR-0008). Init's write of provider names and endpoints moves from `envelope.dhall` to `bindings.dhall`, superseding ADR-0007's clause. Superseded in part by I12: provider endpoints are local config, not bindings | [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md), [`ADR-0007`](../adr/0007-agent-roster-in-workflow-artifact.md), [`ADR-0008`](../adr/0008-default-artifact-deliverable.md), [`defaults/README.md`](../../defaults/README.md), [`CONTEXT.md`](../../CONTEXT.md) |
| I12 | I7 persisted egress approvals as artifact PRs; the Envelope carried the allowlist, secret scopes, and `budget` | The artifact carries the containment contract (tier, preset, `extra_allow`, secret names); local devvm config carries the full allowlist, provider endpoints, and secret scopes; Egress decisions are recorded in SQLite; `budget` is removed (ADR-0009) | [`ADR-0004`](../adr/0004-containment-first-capability-model.md), [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md), [`ADR-0007`](../adr/0007-agent-roster-in-workflow-artifact.md), [`ADR-0008`](../adr/0008-default-artifact-deliverable.md), [`ADR-0009`](../adr/0009-containment-contract-local-config.md), [`CONTEXT.md`](../../CONTEXT.md), [`defaults/README.md`](../../defaults/README.md) |
| I13 | The IR was stage-centric: a Stage bundled a wave, gates, a checkpoint, and an action, and the engine implicitly advanced | The core primitive is Node + Edge; the engine executes nodes and evaluates edges; Stage is a display group. `Rework` and `sync` are ordinary graph nodes/actions, not harness node kinds (ADR-0010) | [`ADR-0003`](../adr/0003-v1-issue-driven-loop.md), [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md), [`ADR-0007`](../adr/0007-agent-roster-in-workflow-artifact.md), [`ADR-0010`](../adr/0010-node-edge-workflow-core.md), [`CONTEXT.md`](../../CONTEXT.md), [`defaults/README.md`](../../defaults/README.md), [`prototype/workflow-authoring/README.md`](../../prototype/workflow-authoring/README.md) |
| I14 | The spec gave agents direct reads, comments, and pushes with a project-scoped token | The Project VM token is read-only (contents/issues/PRs/metadata reads); pushes, PR creation, merge, tracker transitions, and comments use the host identity. Comments are Factory-mediated in v1 and the agent comment plugin is post-v1 (ADR-0010) | [`ADR-0010`](../adr/0010-node-edge-workflow-core.md), [`CONTEXT.md`](../../CONTEXT.md), [`map.md`](../wayfinding/map.md), [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md) |
| I15 | Concurrency and human PR feedback were not v1 behaviors | v1 supports configurable concurrency with per-Task worktrees and a serialized merge queue, and a `pr-watch` trigger routes human review/comments, base movement, and conflicts to `sync`/`rework` (ADR-0010) | [`ADR-0010`](../adr/0010-node-edge-workflow-core.md), [`CONTEXT.md`](../../CONTEXT.md), [`closed/008`](../wayfinding/closed/008-shape-the-issue-driven-loop.md) |

One wording distinction, not a conflict: ADR-0003 lists PR among the Loop's steps; the spec treats PR creation as a typed `action` node after Review, with gate evaluation inside gate nodes (§3.1).

I10 also annotates the superseded wording in [`map.md`](../wayfinding/map.md) and [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md), [`closed/008`](../wayfinding/closed/008-shape-the-issue-driven-loop.md), and [`closed/016`](../wayfinding/closed/016-shape-workflow-authoring-ergonomics.md). I12 also annotates the superseded wording in [`map.md`](../wayfinding/map.md) and [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md), [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md), [`closed/016`](../wayfinding/closed/016-shape-workflow-authoring-ergonomics.md), and [`closed/017`](../wayfinding/closed/017-research-devvm-sandboxing.md). I13–I15 annotate the superseded wording in [`map.md`](../wayfinding/map.md), [`closed/008`](../wayfinding/closed/008-shape-the-issue-driven-loop.md), [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md), and [`closed/016`](../wayfinding/closed/016-shape-workflow-authoring-ergonomics.md); the same revision amends [`ADR-0002`](../adr/0002-opencode-as-first-runtime-adapter.md) (exhaustion to the agent node, adapter liveness) and [`ADR-0007`](../adr/0007-agent-roster-in-workflow-artifact.md) (agent nodes select entries; failures route on edges).

---

## 11. Source index

| Artifact | Supplies |
| --- | --- |
| [`docs/adr/0001`](../adr/0001-harness-core-language-go.md) | Go core; workflow layer separate |
| [`docs/adr/0002`](../adr/0002-opencode-as-first-runtime-adapter.md) | Hybrid substrate; managed OpenCode server; adapter contract; durable state |
| [`docs/adr/0003`](../adr/0003-v1-issue-driven-loop.md) | Loop shape; two Checkpoints; gates in the harness; Waves as data |
| [`docs/adr/0004`](../adr/0004-containment-first-capability-model.md) | Containment-first; Project Envelope; Egress Requests; no profiles in v1 |
| [`docs/adr/0005`](../adr/0005-resident-daemon-thin-clients.md) | Daemon, CLI, SQLite, polling, reconcile-and-resume, VM idle stop |
| [`docs/adr/0006`](../adr/0006-dhall-authoring-factory-directory.md) | `.factory/`, Dhall → IR, secrets by name, copy-on-init, optional measures |
| [`docs/adr/0007`](../adr/0007-agent-roster-in-workflow-artifact.md) | Agent Roster in `.factory/`, selection by id, ordered model lists, typed failure to the agent node |
| [`docs/adr/0008`](../adr/0008-default-artifact-deliverable.md) | Default artifact in `defaults/`; bindings; golden IR; content digest; migrations |
| [`docs/adr/0009`](../adr/0009-containment-contract-local-config.md) | Containment contract vs local devvm config; local Egress record; budget removed |
| [`docs/adr/0010`](../adr/0010-node-edge-workflow-core.md) | Node/edge workflow core; Stage as display group; agent outcomes/liveness/feedback; concurrency; PR feedback |
| [`closed/001`](../wayfinding/closed/001-research-harness-language.md) | Go core recommendation; workflow-authoring question deferred (superseded in part) |
| [`closed/002`](../wayfinding/closed/002-research-build-vs-opencode-plugins.md) | Control-plane/runtime boundary; effect-runner discipline |
| [`closed/003`](../wayfinding/closed/003-research-tracker-adapters-and-permissions.md) | Tracker adapter contract; harness-gated mutations |
| [`closed/004`](../wayfinding/closed/004-research-steer-capture-observability.md) | Event envelope; categories; privacy; mining |
| [`closed/005`](../wayfinding/closed/005-research-software-factory-landscape.md) | Landscape anti-patterns; what no prior system combined |
| [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md) | Adapter contract detail; plugin scope; composition reserved |
| [`closed/007`](../wayfinding/closed/007-decide-harness-language.md) | Go core decision; workflow-type constraint |
| [`closed/008`](../wayfinding/closed/008-shape-the-issue-driven-loop.md) | Default graph shape; default Wave; failure edges; metrics; init |
| [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md) | Envelope fields; tracker authority split; PR/merge ownership |
| [`closed/010`](../wayfinding/closed/010-decide-daemon-or-cli.md) | Process model; state; API; restart; VM lifecycle |
| [`closed/011`](../wayfinding/closed/011-research-typed-functional-workflow-language.md) | Typed graph; CEL; Dhall risk; IR independence |
| [`closed/012`](../wayfinding/closed/012-research-harness2-recursive-harnessing.md) | Harness vocabulary; improvement-library contract |
| [`closed/013`](../wayfinding/closed/013-research-swamp-club-behavior-centric.md) | Typed DAG corroboration; grant vocabulary; patterns not substrate |
| [`closed/014`](../wayfinding/closed/014-research-deltadb-operation-level-vcs.md) | Operation-log pattern; gate-not-skill rule |
| [`closed/015`](../wayfinding/closed/015-research-code-mode-claude-pi.md) | Code-mode boundary; sandbox reference; promotion only |
| [`closed/016`](../wayfinding/closed/016-shape-workflow-authoring-ergonomics.md) | Dhall decision detail; copy-on-init; measures optional |
| [`closed/017`](../wayfinding/closed/017-research-devvm-sandboxing.md) | Project VM granularity; secrets; network log; Linux gaps; 17-VM cap |
| [`closed/018`](../wayfinding/closed/018-shape-deploy-pipeline.md) | Deploy ruled out; researched mechanics preserved |
| [`prototype/workflow-authoring/`](../../prototype/workflow-authoring/README.md) | Evidence for authoring ergonomics, IR shape, and the unbounded-`returnTo` catch |
| [`defaults/README.md`](../../defaults/README.md) | Default artifact contract: layout, bindings, golden IR, metric keys, labels, node ids |
| [`docs/wayfinding/map.md`](../wayfinding/map.md) | Destination, Owner inputs, decisions, fog, out of scope |
| [`CONTEXT.md`](../../CONTEXT.md) | Glossary: the binding vocabulary |
