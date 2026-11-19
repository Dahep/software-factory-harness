# Factory — Specification (v1)

**Status:** build-ready planning artifact · 2026-11-18

**Relationship to the record.** This spec is the destination of the wayfinder map at [`docs/wayfinding/map.md`](../wayfinding/map.md). It restates decisions; it does not make them. Decisions live in [`docs/adr/`](../adr/) and in the resolutions of the closed tickets under [`docs/wayfinding/closed/`](../wayfinding/closed/); the glossary is [`CONTEXT.md`](../../CONTEXT.md). Where this spec is silent, the ADR and ticket win. The conflicts found while writing it were reconciled against the ADRs and are recorded, with the artifacts changed, in §10.

**Spec defaults.** Sentences marked **⟨default⟩** are choices this spec makes where the source artifacts are silent — scheduler ordering, denial paths, timeouts, and similar build-time detail. They are review targets, not recorded decisions, and are collected in §9.3 so a reviewer can audit them in one place.

**Building is out of scope here.** This is a planning artifact: no production code, no scaffolding. A later effort implements it.

---

## 1. Purpose, audience, scope

### 1.1 What Factory is

Factory is a user-defined agent harness: a resident control plane that runs deterministic, project-defined workflows which orchestrate agent teams across Managed Projects. Factory owns workflow state, gates, and audit, and delegates agent execution to a runtime through a `RuntimeAdapter` ([`CONTEXT.md`](../../CONTEXT.md), ADR-0002).

The v1 milestone is the issue-driven Loop: an Issue enters, an agent triages it, the Owner approves a `TriageDecision`, an implementer Wave produces a branch, harness-owned Gates and a reviewer Wave pass judgment, Factory opens a PR, and the Owner approves a squash merge. Nothing between the two Checkpoints needs the Owner (ADR-0003).

### 1.2 Audience and the path to other users

The Owner is the audience: the author of Workflows and the authority at Checkpoints. v1 is sized to one Owner on one machine (ADR-0005).

The path to other users is preserved by four seams, not by designing for them now: a tracker adapter boundary (§2.6), a Workflow Artifact that lives in each Managed Project's own repository (§4), a `RuntimeAdapter` that keeps the runtime swappable (§2.4), and a local API that a future TUI or web UI can consume without touching the database (ADR-0005). Packaging, onboarding, and a configuration UI are fog (§9.1); designing them now is out of scope.

### 1.3 v1 scope

| Capability | v1 shape | Source |
| --- | --- | --- |
| Process model | Resident Go daemon + thin CLI over a local JSON API on a Unix socket | ADR-0005 |
| Durable state | One SQLite (WAL) database: append-only transition log, projections, snapshots | ADR-0002, ADR-0005 |
| Runtime | `RuntimeAdapter` seam; OpenCode as the one real adapter; a test double proves the seam | ADR-0002 |
| Containment | One Project VM (devvm) per Managed Project; Project Envelope compiled from the artifact | ADR-0004, ticket 017 |
| Tracker | GitHub Issues via `gh`; adapter interface designed for others | ticket 003, ticket 008 |
| Loop | intake → triage → implement → gates → review → PR → merge, Owner at two Checkpoints | ADR-0003 |
| Default Wave | one implementer, two reviewers (spec-fidelity + adversarial), as Workflow data | ticket 008 |
| Gates | deterministic, harness-enforced, each with a Workflow-defined Failure Policy | ADR-0003 |
| Adoption | Project Init PR adds `.factory/`; copy-on-init; deviation by PR | ADR-0006 |
| Measurement | append-only log, default metric set, Agent Confusion proxies | ticket 004, ticket 008 |
| Self-hosting | Factory's repository is Subproject one; manual first build, then self-driven | ticket 008 |

v1 validates the Loop on **one Managed Project plus Factory-as-Subproject**. The architecture is per-project throughout (rows, VMs, runtime configuration), but a multi-project fleet is not a v1 goal (ticket 008).

### 1.4 Non-goals

Out of scope by decision, not by omission:

- **Deploy.** Each Managed Project owns its deploy path (its own CI, e.g. GitHub Actions). Factory's Loop ends at merge; no deploy Stage, no host inventory, no deploy credentials in a Project VM (ticket 018, map note #7).
- **Capability Profiles.** No per-role profiles in v1; containment is per project (ADR-0004). Profiles return post-v1 as narrower envelopes on the same path.
- **PR-format validators.** Reserved in the model, not built (ADR-0004).
- **Other trackers.** GitHub Issues only; Fizzy/Linear follow the adapter interface later (ticket 003, ticket 008).
- **Runtime plurality.** One real adapter plus a test double; harness neutrality is a property of the seam, not of the shipping surface (ADR-0002).
- **Webhooks and public ingress.** Intake polls; webhooks are post-v1 (ADR-0005).
- **UI.** The CLI is the surface; TUI/web arrive on the same API (ADR-0005).
- **Spend caps.** Spend is measured per Task, not capped (ADR-0004).
- **Post-merge monitoring and fix cycles**, and **sub-Issue decomposition in Triage** (ticket 008).
- **Code-mode / sandboxed composition** as a Workflow layer. The pattern is reserved as a future adapter capability; an LLM-authored script is never the Workflow and never a Gate (ADR-0002, ticket 015).
- **Remote/worker mode and multi-machine fleets.** Local daemon only (ADR-0005).
- **A public registry of reusable Workflows** (ticket 013; path-to-other-users fog).

### 1.5 Definition of done for v1

v1 is done when, on Factory's own repository as a Managed Project, all of the following hold:

1. A new Issue reaches a merged squash commit through the Loop with Owner action only at the triage and merge Checkpoints.
2. Every Gate verdict is recorded with its inputs; no agent judgment, plugin, or skill file decides advancement.
3. A daemon restart mid-Task either resumes from the last transition or parks the Task Blocked with evidence; no Task is silently re-dispatched (ADR-0005).
4. Every Run carries the default metric set, including the six Agent Confusion proxies.
5. Each blocked egress attempt that needed a decision has a recorded Egress Request outcome.
6. The Dhall conformance gate is green in CI, and the default Workflow Artifact compiles to the IR the engine executes.
7. A Workflow Artifact change lands only through a PR against the Managed Project's copy.

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
                                        ├─ repo clone (--clone)
                                        ├─ OpenCode server ── sessions (Waves)
                                        └─ egress proxy ── allowlist + secret injection
```

Two GitHub paths exist by design: the daemon host holds the tracker/PR/merge identity, and the Project VM holds a project-scoped token for direct reads, comments, and pushes (ADR-0004, ticket 009). Merge is host-side only.

### 2.2 The daemon

One long-running Go process on the daemon host, installed as a **systemd user unit** (ADR-0005). It owns the queue, scheduling, Project VM lifecycle, Gate evaluation, Checkpoint delivery, tracker polling, PR and merge execution, egress decisions, and the audit log. It is the only writer to the database.

The daemon's responsibilities are deliberately narrow in one direction: it decides *which work is eligible, who owns it, when it runs, what Gates it must pass, and how outcomes are recorded*. It never decides *how* an agent solves its Task (ticket 002).

The CLI is a client. Commands are idempotent and carry persisted receipts; even locally the client uses a scoped Owner session; no client opens the database (ADR-0005). ADR-0005 names `factory inbox`, `factory approve`, and `factory egress allow`; §7.3 lists the surface this spec expects.

### 2.3 Durable state

One SQLite database in WAL mode, daemon-only writer, project-scoped rows (ADR-0005).

| Store | Role | Guarantees |
| --- | --- | --- |
| Transition log | Audit truth: every command, state change, Gate verdict, Checkpoint decision, tracker/PR effect, and reconciliation | Append-only; monotonic sequence per database; actor, time, cause, and evidence on every row; long retention (directive #15) |
| Projections | Current state per Managed Project, Task, Run, Stage, Gate | Derived from the log; safe to rebuild; never authoritative over the log |
| Snapshots | Bounded replay | Taken at a log sequence; a snapshot plus its suffix reproduces state |

The write discipline follows the effect-runner shape (ticket 002): **commit a valid transition and its effect intent first; perform the external effect outside that decision; record the result as a new transition.** External effects are reconciled before retry — read provider state, then act (§3.12).

Logical records the log must carry (fields, not DDL):

| Record | Required content |
| --- | --- |
| Command | idempotency key, actor, target, receipt reference |
| Transition | sequence, Managed Project, Task, Run, Stage, before/after state, cause (Gate, Checkpoint, Failure Policy, reconciliation), IR digest |
| Gate verdict | Gate id, check, input references with digests, result, reason, attempts, policy applied |
| Checkpoint | asks (artifact references), decision, edits or reason, actor, time |
| Run | adapter instance, Task input digest, Outcome, usage, transcript reference, completeness |
| Effect | tracker/PR/merge/VM action, idempotency key, result, provider reference |

Backups are one file (ADR-0005). Retention of transcripts and activity events is governed by §6.7.

### 2.4 RuntimeAdapter

The seam is T3-shaped (ticket 006, ADR-0002). Four parts:

| Part | Contract |
| --- | --- |
| Task in | typed: prompt, workspace reference, envelope reference, budget |
| Outcome out | typed: status, artifacts, diff reference, transcript reference, usage |
| Events | normalized stream for session / message / tool / permission. Telemetry only — never Workflow state |
| Capabilities | an explicit descriptor per driver: streaming, steer/interrupt, checkpoints, rollback, sandboxed composition, native option IDs |

Rules that keep the seam honest:

- **Declared, not assumed.** Factory must not use a capability the adapter did not declare. A Workflow step that requires an undeclared capability is rejected at validation or blocks the Task with evidence; it never degrades silently.
- **Driver kind vs instance.** Two configurations or accounts never share mutable session or catalog state. The adapter records which instance produced an Outcome.
- **Native option IDs survive normalization.** Display labels are not valid replies for permission or question prompts.
- **No setup as a health-check side effect.** Opening a session must not trigger MCP servers, hooks, or logins (ticket 006).
- **Runtime events are not state.** Only a committed transition advances a Task (ticket 002).

The Task's **envelope reference** is the field ticket 006 calls a *capability-profile ref*; v1 resolves it to the Managed Project's Project Envelope, and the field stays reserved for post-v1 profiles (ticket 006 amendment, ADR-0004).

**OpenCode as the v1 adapter.** Factory starts, version-probes, idles out, and speaks to an OpenCode server over its API; external-server mode is post-v1. One server per Project VM — the instance is the Managed Project's runtime configuration — with many sessions (one per agent in a Wave). The server runs inside the Project VM; the daemon reaches it through `devvm host` + SSH (ticket 006, ticket 017).

**Runtime configuration** (agents, models, tools, policies) is a Factory-managed, version-reviewed artifact per Managed Project. Secret *values* stay in the host's devvm store and reach the VM only as placeholders (§5.5). Host authentication stays host-level; correctness never depends on the host's global OpenCode config (ADR-0002, ticket 006).

**The minimal Factory plugin** exposes only: report a blocker, attach an artifact, read Gate status, inject Task context, and enforce permission rules. It never advances Workflow state (ticket 002, ticket 006).

**The test double.** A fake adapter proves the seam and runs the Loop's contract tests in CI. No second real adapter ships in v1 (ADR-0002).

### 2.5 Project VM

A **Project VM** is the devvm instance backing a Managed Project: the sandbox, network, and secret boundary for every agent session and for the runtime server of that project ([`CONTEXT.md`](../../CONTEXT.md)).

The Owner's decision is **one Project VM per Managed Project**, reused across Tasks and Waves ([ticket 017](../wayfinding/closed/017-research-devvm-sandboxing.md#owner-decision-2026-11-18)). Consequences this spec carries:

- The boundary is the project, not the Task, the agent, or the Wave. Every session of a Wave shares the Task's Project VM.
- A per-Run VM is an escalation option (untrusted input, destructive work), not a default; v1 does not need it. The 17-concurrent-VM cap is therefore not a v1 constraint.
- When concurrency is greater than one (§3.10), each Task needs its own workspace inside the Project VM — a separate clone or worktree per Task — because agents write files. **⟨default⟩**
- The VM starts on first work and stops after an idle period (default ~30 minutes, configurable); starting a Task pays a VM start cost (ADR-0005).
- `devvm rm` deletes the VM's network logs and state; Factory ingests what it needs before any removal (§6.6).

**Lifecycle and control.** Factory drives devvm as a CLI: `--no-input`, versioned `--json` output (version 1, additive-only), and folder-scoped commands resolved by the working directory plus folder identity (path + device + inode + birth time). The daemon either `chdir`s into the project's run directory or uses `devvm adopt`. The headless command path is `devvm host --no-input` followed by plain `ssh` to the VM; there is no devvm API or SDK (ticket 017).

**Clone mode.** The envelope's clone mode compiles to `devvm --clone`: the VM holds its own copy of the repository, and the host working tree is never mounted. On Linux this is also the mitigation for the missing `.git` protection (§8.4, R4).

**Inside the VM:** the repository clone, toolchains, the OpenCode server, and every agent session of the project. The Go control plane never runs inside it.

### 2.6 TrackerAdapter

The adapter is a translation and authorization boundary, not a lowest-common-denominator schema (ticket 003). v1 implements GitHub Issues via `gh`; the interface is designed so another tracker is one adapter, not a rewrite.

| Capability | v1 use |
| --- | --- |
| `capabilities()` | Report read/write fidelity per operation; Factory refuses what the provider cannot do instead of emulating it |
| `listIssues`, `getIssue` | Intake polling and reconciliation |
| `updateIssue`, `transitionIssue` | Labels, workflow state, close — **through Factory only** |
| `assign` / `unassign` | Available; the v1 Loop does not assign agents to Issues |
| `listComments`, `addComment` | Agents may read and comment directly via `gh` inside the Project VM |
| `listActivity` | Provider activity for reconciliation; never treated as an immutable audit log |
| `listDependencies`, `addDependency`, `removeDependency` | Available; the v1 Loop does not consume blocking relations |
| `authorize` | Early UX only; the harness re-checks every mutation immediately before the call |

Rules: provider IDs stay opaque; provider-specific fields and events are preserved; unsupported operations are reported, never faked with tags or comments; important writes are verified by reading back (ticket 003).

**Authority split** (ADR-0004):

- Reads and comments: the agent may use `gh` directly inside the Project VM.
- Label, state, and close transitions: **Factory tools only**, after the Triage Checkpoint. The agent proposes; Factory records and applies.
- Merge: not a tracker operation, and not an agent operation (§3.9).

There are two principals throughout: the provider credential and the harness agent principal. The harness gates every mutation even when the provider credential could perform it (ticket 003).

---

## 3. The v1 Loop

### 3.1 Stages

The Loop has six steps: three Wave-bearing Stages (Triage, Implement, Review), Intake, Merge, and the PR action the harness performs between Review and Merge. Gates live inside Stages; ADR-0003's "gates" and "PR" are activities, not extra Stages.

| Stage | Wave (default artifact) | Gates (default artifact) | Checkpoint | Advances to |
| --- | --- | --- | --- | --- |
| Intake | none | admission rules | — | Triage |
| Triage | triager | `decision-shape`, `scope-declared` | triage-approval | Implement |
| Implement | implementer | `build`, `tests`, `diff-present` | — | Review |
| Review | reviewer (spec-fidelity), reviewer (adversarial) | `review-verdict` | — | PR |
| PR | none — harness action | — | — | Merge |
| Merge | none | `pr-open`, `checks-green` | merge-approval | Merged |

Gate ids are the default artifact's; the names are IR-level, not harness constants.

### 3.2 Task states

The tracker remains the authoritative record of the Issue; Factory is authoritative for the Task ([`CONTEXT.md`](../../CONTEXT.md)).

| Task state | Meaning | Issue |
| --- | --- | --- |
| Triaging | triage Wave running or a `TriageDecision` awaiting the Checkpoint | open; no transition yet |
| Ready | approved; the Task exists | open; labeled `ready-for-agent` |
| Implementing | implementer Wave active | open |
| InReview | review Wave active | open |
| AwaitingMerge | PR open, Gates green, merge Checkpoint pending | open |
| Blocked | needs the Owner; evidence attached | open; the Failure Policy may also change Issue state |
| Abandoned | the Owner abandoned the Task | open or closed, per the recorded decision |
| Merged | squash-merged | closed through Factory |

No Issue transition happens before the Triage Checkpoint (ADR-0004).

### 3.3 Intake

The daemon polls the Managed Project's tracker on a configurable interval; webhooks are post-v1 (ADR-0005). New Issues enter Triage. The existing backlog is **not** swept: it stays out until the Owner admits an Issue (ticket 008).

**⟨default⟩** Backlog admission is an explicit Owner command (`factory triage <issue-ref>`), not a label convention; this keeps the post-approval label `ready-for-agent` unambiguous.

Intake is idempotent: an Issue is admitted once per Task, keyed by provider reference. A re-poll, a daemon restart, or a duplicate webhook (post-v1) cannot create a second Task.

Measured: issues admitted, intake-to-triage latency.

### 3.4 Triage

A triager session produces a typed **`TriageDecision`**: suggested labels and priority, acceptance criteria, plan sketch, size estimate, confidence, and open questions (ticket 008). The Gate validates its shape against the schema in `.factory/schema/`; a missing acceptance criterion is a Gate failure with its own policy, not a warning.

The Owner approves or edits at the **triage-approval Checkpoint**. Edits are recorded as part of the decision. Approval applies `ready-for-agent` and creates the Task; rejection records the reason, comments on the Issue, and creates no Task.

The triager proposes transitions; it cannot apply them. Every transition after approval goes through Factory tools (ADR-0004).

Measured: decision time, Owner edits, rejection rate.

### 3.5 Implement

One implementer session in the Task's workspace inside the Project VM. The agent has full agency over the clone: read, write, install, run. It must produce a branch with a diff and may propose the PR title and body; it cannot merge (ADR-0004).

Gates run as Factory-issued checks, not agent claims:

- `build` / `tests` — commands executed in the Project VM; the Gate reads the exit status.
- `diff-present` — a deterministic predicate over the changed-file set.

A Gate never accepts "tests pass" as an agent statement. If a command cannot run, the Gate fails closed with the reason.

Measured: Stage cycle time, retries, diff size, tool error rate.

### 3.6 Gates

A **Gate** is a harness-enforced condition that must pass before a Task advances; its verdict is deterministic and never an agent's judgment ([`CONTEXT.md`](../../CONTEXT.md), ADR-0003).

Three rules define it:

1. **Harness-owned.** The Gate is IR the Go engine evaluates. It is never a prompt, a skill, or a plugin assertion. Ticket 014's rule is binding: *a skill proposes, a harness-enforced rule disposes.*
2. **Deterministic.** The verdict is computed from durable facts — transition state, command exit status, provider state, file-set predicates — or from **typed artifacts aggregated by a deterministic rule**. Reviewers' judgments are content; the aggregation is the Gate.
3. **Fail-closed.** Missing evidence, an unreachable provider, a timeout, or an unknown result is a failure with a reason, never a pass.

A Gate report is a first-class record: Gate id, Stage, check, input references with digests, result, reason, attempt count, and the Failure Policy applied.

**Check classes the default Loop needs** (drawn from the prototype's IR; the spec requires the classes, the IR names them):

| Check class | Input | Passes when |
| --- | --- | --- |
| schema | artifact | the artifact validates against its schema |
| required-field | artifact | the named field is present and non-empty |
| command | Project VM | the command exits zero within its timeout |
| changed-files | Task branch | the predicate holds (e.g. more than zero changed files) |
| review-aggregate | typed review artifacts | the Workflow's predicate holds (default: every reviewer approves and no blocking finding is unresolved) |
| pr-state | provider | the PR is in the expected state |
| pr-checks | provider | required checks are green |

**Failure Policy.** Each Gate carries one, defined in the Workflow: retry within the Stage, return the Task to an earlier Stage, open a follow-up Issue, change Issue state, or wait for the Owner ([`CONTEXT.md`](../../CONTEXT.md), ticket 008). Retry and return-to counts are bounded; an unbounded `returnTo` is invalid IR (the prototype's validator caught exactly this on its first run — [`prototype/workflow-authoring/`](../../prototype/workflow-authoring/README.md)). The default policy bounds fix rounds at two, then parks the Task Blocked for the Owner.

**Gate integrity.** An agent may edit `.factory/` on its branch, but it cannot loosen the Gates it is running under: each Task pins the IR it was created with **⟨default⟩** (§4.8). A change to the artifact takes effect for later Tasks, after review and merge.

### 3.7 Review

The default workflow's agent set is one implementer and two reviewers (ticket 008); the reviewers form the Review Stage's Wave: **spec-fidelity** (does the diff do what the approved `TriageDecision` says) and **adversarial** (what breaks, what is missing, what is unsafe). Wave composition is Workflow data.

Reviewers produce typed artifacts: findings with severity (blocking or not), location (path/line or artifact), claim, and evidence references; plus a verdict of approve or request changes (field schema: §9.1). Findings tagged as misunderstanding feed the Agent Confusion metric (§6.4).

The `review-verdict` Gate aggregates the artifacts deterministically. Reviewers do not merge, do not transition the Issue, and do not advance the Task.

Measured: findings per Wave, turnaround, blocking-finding rate, reviewer-flagged misunderstanding.

### 3.8 PR

A PR is always required; it is the durable, protected merge surface in v1 (ADR-0003). Factory opens it from the pushed branch and owns it; the agent may propose the title and body. Re-pushing updates the same PR. Branch protection on the remote guards the target branch.

An in-thread review with no PR (DeltaDB's model) was considered and not adopted for v1: the pattern of review evidence and verdicts in the work thread is kept, but the PR remains the merge surface (ticket 008, ADR-0003).

Measured: PR open latency, PR size, review round trips.

### 3.9 Merge

The merge is an Owner Checkpoint followed by a harness action:

1. Every Gate in Implement and Review has passed; Factory has opened the PR.
2. The Merge Stage's Gates (`pr-open`, `checks-green`) pass; the Owner receives the PR and the Gate report at the **merge-approval Checkpoint**.
3. On approval, **Factory** executes a **squash merge via `gh`** on the daemon host, using the host's identity, and records the merge commit.
4. Factory closes the Issue through the tracker adapter and marks the Task Merged.

Agents never run the merge: the capability is Factory's, and the remote's branch protection must make it unreachable from the Project VM's token (ADR-0003, ticket 008).

**⟨default⟩** A denied merge returns the Task to Implement with the Owner's reason attached as input; the Owner may instead abandon the Task through a separate recorded decision. The Workflow declares which.

Post-merge monitoring is post-v1; the project's own CI takes over from the merged commit (ticket 008, ticket 018).

### 3.10 Concurrency and scheduling

Concurrency is a Workflow setting per Managed Project: the maximum number of in-flight Tasks; v1 defaults to **1** (ticket 008).

**⟨default⟩** Admission order is Issue creation time ascending, then Issue number; the chosen Task is recorded in the transition log so the schedule is auditable. A Task enters the queue at `Ready` and leaves it at Merged or Abandoned.

At concurrency 1, a single workspace in the Project VM is sufficient. Above 1, each Task gets its own workspace inside the same Project VM; the VM boundary stays per project (§2.5, §5.8).

### 3.11 Blocked, failures, abandonment

Blocked is a Task state with evidence: what failed, which Gate or effect, what was tried, and what the Owner must decide. It appears in the Owner's inbox. Resuming a Blocked Task is an Owner action recorded as a transition.

| Failure | Handling |
| --- | --- |
| Gate failure | The Gate's Failure Policy: bounded retry, return to an earlier Stage, follow-up Issue, Issue state change, or wait for the Owner |
| Run crash or vanished session | Outcome unknown → the Run is recorded failed with evidence; re-dispatch only per the Failure Policy |
| Project VM lost | Task Blocked with evidence; no silent recreation (ADR-0005) |
| Tracker/PR divergence | Reconcile from provider state; record the correction; block if the two cannot be reconciled safely |
| Egress block needing a decision | Egress Request to the Owner (§5.6); the Task waits |
| Secret denial | Recorded with host and reason; the Task blocks or retries per policy; never bypassed |

Abandonment is an Owner decision with a reason; the Issue is left open with a comment or closed, per that decision.

### 3.12 Reconcile-and-resume

On start, the daemon loads the latest snapshot, replays the log suffix, and reconciles with the world before resuming anything (ADR-0005):

1. **Tracker**: labels, state, and comments for every non-terminal Task; adopt provider truth where Factory's projection is stale.
2. **PRs**: open/closed/merged state, checks, and head commit for every Task in PR or AwaitingMerge.
3. **Project VMs**: presence, tier, and bindings per Managed Project; a Task whose VM state vanished goes Blocked with evidence.
4. **In-flight Runs**: a Run whose session is gone is marked failed with evidence; the Task resumes from its last transition only if the Stage can be safely re-entered.

No silent re-dispatch. Before retrying any external effect, read the provider state (PR exists? merge already applied? comment posted?) and record what was found. Reconciliation itself is logged as transitions.

---

## 4. Workflow Artifact

### 4.1 Directory

A Managed Project carries its Workflow Artifact as a committed directory, added by Project Init (ADR-0006):

```
.factory/
  workflow.dhall   # stages, waves, gates and failure policies, checkpoints, concurrency, measures
  envelope.dhall   # clone mode, network tier and allowlist, secret names, spend measurement
  schema/          # the Dhall types the two files import
```

**⟨default⟩** `schema/` also carries the artifact schemas the Gates validate (`TriageDecision`, review findings), so the artifact is self-contained. ADR-0006 requires `schema/` for the Dhall types; artifact schemas share it rather than becoming a second configuration surface.

Reviewed as one PR at init; deviation is a PR against the project's copy.

### 4.2 Compilation

Dhall is the only frontend (ADR-0006). The pipeline:

```
workflow.dhall + envelope.dhall + schema/
        │  dhall-golang: parse, typecheck, normalize
        ▼
   typed Dhall value
        │  decode into the closed IR
        ▼
   IR validation (ids, references, variants, bounds, schemas)
        ▼
   versioned IR  ── the engine's contract
```

Rules:

- **No effects in Dhall.** A Dhall expression may build the graph; it may never call a host effect (ticket 011).
- **Finite graphs.** Dhall has no general recursion. Runtime iteration is an explicit `ForEach` node over a prior typed output, with a declared bound and an engine-persisted cursor (ticket 011).
- **CEL for guards only.** Guards are typed, side-effect-free, terminating expressions evaluated by the engine (ticket 011).
- **IR is the contract.** The engine executes the IR, not Dhall. The IR is versioned independently of the Dhall standard (ticket 011, ADR-0006).
- **Fail closed.** An IR version the engine does not know, or an artifact that fails validation, refuses to start a Task; it never runs a best-effort interpretation.

### 4.3 IR shape

Top-level fields the IR must express (names follow the prototype's compiled sketch, which is evidence, not a contract — [`default-loop.ir.json`](../../prototype/workflow-authoring/default-loop.ir.json)):

| Field | Content |
| --- | --- |
| IR version | engine contract version |
| Workflow identity | name, description, Managed Project reference |
| Envelope | compiled Project Envelope (§4.4) |
| Concurrency | max in-flight Tasks |
| Checkpoints | id → Stage, the artifacts asked for |
| Stages | id, entry condition, Wave, Gates, Checkpoint, action, measures |
| Waves | agent entries: role, persona (runtime-specific config resolved per project) |
| Gates | id, check (class + parameters), Failure Policy with bounds |
| Measures | default set reference plus optional per-Stage additions |

### 4.4 Project Envelope

The Envelope is the containment declaration Factory compiles into the Project VM ([`CONTEXT.md`](../../CONTEXT.md), ADR-0004):

| Field | v1 meaning | Compiles to |
| --- | --- | --- |
| `clone` | the VM holds its own copy; the host working tree is never mounted | `devvm --clone` |
| `network.tier` | `allowlist` | devvm tier |
| `network.allow` | human-editable hosts; the **developer preset** starts with GitHub, the configured model-provider endpoints, and common package registries | `devvm network allow` rules |
| `secrets` | secret **names** only (e.g. `github`, `model-provider`) | `devvm secret use` bindings per Project VM |
| `budget` | spend **measurement** declaration; no cap in v1 | usage recording per Task |

**⟨default⟩** `clone` is fixed to true in v1; the field exists so the IR can express it. The developer preset's exact host list is build-time data seeded from the prototype (`github.com`, `api.github.com`, npm, PyPI, Go proxy, crates.io).

The artifact is the single source of truth: the Project VM is never hand-configured differently (ADR-0004).

### 4.5 Secrets by name only

The artifact is committed, so it never contains a secret value. It names secrets; the Owner's host holds the values; the Project VM sees placeholders and per-VM bindings (§5.5). A Workflow Artifact is therefore safe to publish in a public repository (ADR-0006).

### 4.6 Copy-on-init and deviation

Project Init copies the default artifact into the project through a PR. There is no inheritance, `extends`, or override machinery: a project that wants a different Wave, an extra Gate, or different tracker state names edits its own copy in a PR. This keeps one authoritative artifact per Managed Project and needs no merge semantics (ADR-0006).

An upstream change to the default does not propagate. A project adopts it by PR against its own copy.

### 4.7 Measurement declarations

A default metric set applies to every Run; per-Stage declarations are optional additions, and declaring none is valid (ADR-0006, ticket 016). A Stage with no explicit measures is measured by the default set; a Stage that declares measures adds to it. The prototype's validator warned on an unmeasured Stage; that warning is an authoring aid, not a Gate.

### 4.8 Validation rules

The compiler and IR validator reject:

- a `returnTo` naming no earlier Stage, or carrying no bound;
- a Gate with no Failure Policy, or a policy with an unbounded retry/return;
- a Checkpoint naming no Stage, or asking for an artifact no Stage produces;
- a Wave entry whose role or persona does not resolve in the project's runtime configuration;
- a Gate check referencing an unknown check class or malformed parameters;
- a `ForEach` without a bound;
- concurrency below 1;
- an unknown IR version.

**⟨default⟩** A Task pins the IR version and digest it was created with. Mid-Task artifact edits never alter the running Gates; the next Task uses the new IR.

---

## 5. Containment and secrets

### 5.1 Envelope compilation

At Project VM creation or reconfiguration, Factory applies the Envelope in one pass:

| Step | devvm surface | Failure |
| --- | --- | --- |
| Create or adopt the project's VM (clone mode) | `--clone`, folder identity | refuse to run; Task blocked with evidence |
| Set the network tier and allowlist | `allowlist` + rules | broken rule fails closed (all denied) until fixed |
| Bind each named secret | `devvm secret use NAME` | missing secret value → Task blocked; never a fallback |
| Apply method/path scopes for custom secrets | `devvm secret set … --method --path` | failure leaves the placeholder; requests fail closed |
| Record the compiled envelope digest | Factory transition log | drift between artifact and VM blocks new work |

### 5.2 Full agency inside the Project VM

Agents get filesystem, tools, installs, and the copied repository. OpenCode runs unrestricted inside the sandbox. v1 has no per-tool allowlists and no role profiles; the VM is the control (ADR-0004).

### 5.3 What leaves the Project VM

| Egress | Path |
| --- | --- |
| Tracker reads and comments | direct, `gh` inside the VM with the project's scoped token |
| Tracker label/state/close transitions | Factory tools only, after the Triage Checkpoint |
| Git pushes | HTTPS from inside the VM with the scoped token (no git-over-SSH injection; §5.5) |
| PR creation and merge | Factory on the daemon host |
| Network requests | devvm proxy: allowlist, secret injection, logs |
| Blocked hosts | Egress Request to the Owner |

Nothing else is an "always-ask" prompt: v1 has no approval beyond the two Checkpoints (ticket 009).

### 5.4 PR and merge ownership

Factory owns PR creation and holds the merge capability; the agent pushes a branch and may propose PR text (ADR-0004). Enforcement is layered:

- branch protection on the managed repository restricts merges to Factory's host identity;
- the Project VM's token is scoped to the project's repositories and must not carry merge rights;
- optionally, the VM's allowlist can additionally deny `POST` on the PR-creation path, so PR ownership is enforced at the network boundary rather than by policy alone (devvm supports method+path rules; ticket 017). This is an available lever, not a v1 requirement.

### 5.5 Secrets

The model is devvm's: values live on the host, the VM sees placeholders, and a proxy injects the real value only for the bound hosts (ticket 017).

| Property | Behavior |
| --- | --- |
| Storage | OS keychain or devvm's host-side store; no command prints a value |
| Placeholders | per-VM random suffix; a placeholder copied out of the VM is worthless elsewhere |
| Binding | per Project VM (`devvm secret use`); a bound secret's hosts join that VM's allowlist on 443 |
| Scope | host + header/env + optional method/path; up to 16 exact hosts per custom secret; wildcards refused |
| Coverage | HTTPS tunnels (TLS re-terminated with a VM-only CA) and plain HTTP forwards; model APIs, `gh`, git over HTTPS, custom-header APIs |
| Not covered | git over SSH, raw TCP to arbitrary ports, tools that bypass the proxy |
| Failure | a placeholder in an un-injected shape stays a placeholder and the server rejects it — fail-closed, logged without the value |
| Rotation | fine-grained tokens per project; the credential-minting guard refuses key/runner/webhook creation but cannot stop OAuth grants, so distrust means rotate |

Consequences the spec carries: remotes are HTTPS; a secret name in the artifact that has no host-side value blocks the Task; the CA's 30-day expiry is an operational check, not an agent concern.

### 5.6 Egress Requests

A devvm-blocked host — with method, path, and reason from `devvm network log --json` — becomes an **Egress Request** for the Owner ([`CONTEXT.md`](../../CONTEXT.md), ticket 009). The Owner allows or denies; the decision is recorded with its outcome, and both are measured. A denial is visible, not silent.

An approval is persisted as a Workflow Artifact change: Factory proposes a PR against `envelope.dhall`, applies the approved rule to the running Project VM immediately, and records it as provisional until the PR merges; a rejected PR revokes it at the next compile (ADR-0004, ticket 009 amendment). This keeps an unblock from waiting on review without creating a second configuration surface.

### 5.7 Spend

Spend is measured per Task from the Adapter's usage and recorded in the log; there is no hard cap in v1. Runaways are visible in the Owner's metrics, not prevented (ADR-0004). A cap is post-v1 and would compile through the same Envelope.

### 5.8 Boundary honesty

| Protected | Not protected | Mitigation |
| --- | --- | --- |
| Host filesystem and credentials: the repo is a clone, secrets are placeholders | Per-agent separation inside a Project VM | Waves share the VM by decision; Capability Profiles post-v1 |
| Network: proxy-mediated, allowlist, DNS in the proxy | Git-over-SSH secret injection | HTTPS remotes |
| Host mutation through the repo | Linux `.git` hooks/config written inside the VM | `--clone` (the host repo is never mounted); set-id files are scanned by devvm on stop |
| Tracker/PR authority | Agent shell processes bypassing the proxy on the `open` tier | v1 uses the allowlist tier; `open` is not a project tier |
| Audit of network attempts | File and shell coverage beyond instrumented hooks | Marked partial/unobserved in the activity log (ticket 004) |

### 5.9 Post-v1 direction

Capability Profiles are narrower Envelopes — network subset, secret subset, Factory-reach subset, budget — compiled through the same path and enforced by the same sandbox; the artifact remains the single source of truth, and profiles never become a second configuration surface (ticket 009, ADR-0004).

---

## 6. Observability and measurement

Directive #15 is binding: *if it is not measured, it is not improved.* Every Run, Gate, Checkpoint, and merge emits measurable events; improvement activity is driven by those events, not by recollection.

### 6.1 Three records, three jobs

| Record | Job | Authority |
| --- | --- | --- |
| Transition log (§2.3) | What the harness decided and did: workflow state, Gates, Checkpoints, effects | Authoritative for Task state |
| Activity event log (ticket 004 envelope) | What happened in a session and when: steers, tool calls, file access, network requests, approvals | Index and evidence; content-free by default |
| Runtime transcript | What was said: exact messages and tool payloads | Canonical for content; Factory keeps references, not copies |

The activity log links to the transcript through `evidence` (message/part IDs) and to workflow state through `run_id`/`operation_id`. Traces (OTel) are for live timing only; sampled traces are never the audit record (ticket 004).

### 6.2 Event envelope

The envelope shape is fixed by ticket 004; the field schema remains fog (§9.1).

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

Workflow facts — Gate verdicts, Stage transitions, Checkpoint decisions, tracker and PR effects, reconciliation — live in the transition log and are correlated into the Owner timeline by `run_id` and `operation_id`. Whether they surface as additional activity kinds is part of the field-schema fog, not decided here.

Steers keep the human message in the transcript; the event carries the subtype (`correction`, `preference`, `scope_change`, `approval`, `rejection`), whether it was explicit or inferred, and its confidence. Inferred intent is never presented as ground truth (ticket 004).

### 6.4 Default metric set

Applies to every Run; Stages may add, never subtract (ADR-0006, ticket 008).

| Metric | Definition |
| --- | --- |
| Stage cycle time | Stage entry → exit transition, per Task; p50/p95 |
| Gate verdicts | pass / deny / timeout counts and rates per Gate id |
| Review findings | count and severity per Wave, per reviewer persona |
| Retries | per Stage and per Task |
| Tokens and cost | per Run, per Task, per Managed Project |
| PR merge latency | PR opened → merge transition |
| Tool error rate | failed or denied tool calls per Run, normalized by operation |
| Agent Confusion proxies | six proxies below |

**Agent Confusion** is a measured property, expressed through proxies, never a subjective score ([`CONTEXT.md`](../../CONTEXT.md)):

| Proxy | Operational definition |
| --- | --- |
| Repeated identical tool calls | the same normalized operation, target, and argument digest repeated within a Run above a configured threshold |
| File thrash | the same path written and reverted repeatedly, or a net-zero edit set across a Run |
| Plan revisions | plan artifacts superseded within one Task |
| Abandonment / retry | Runs ending without an Outcome; Stage retries per Task |
| Reviewer-flagged misunderstanding | review findings tagged `misunderstanding` |
| Self-reported uncertainty | agent-declared uncertainty events in a Run |

Thresholds are build-time configuration recorded alongside the metric so a metric definition cannot drift silently. **⟨default⟩**

### 6.5 Containment measures

From ticket 017, recorded per Project VM:

| Measure | Why |
| --- | --- |
| VM start time p50/p95 (cold vs image-cached) | Task start cost; idle-stop tuning |
| Image/toolchain build time and refresh frequency | the warm state |
| Secret denials by host | a role or Task tried a secret it was not bound to |
| Egress blocks per host/reason, and allow suggestions | workflow friction; Egress Request demand |
| Tier violations and `unenforced` sightings | containment regressions |
| Task isolation failures | self-check stops, folder-identity refusals, set-id files named, workspace contention |
| Concurrent VMs vs the 17 cap; per-VM memory/disk | resource headroom |

### 6.6 devvm network log ingestion

The daemon tails or polls `devvm network log --json` per Project VM and normalizes each event into a `network_request` activity event: `target.host`, method, path, outcome (`succeeded` or `denied`), and `details` carrying the rule, the secrets injected, and the block reason. devvm's event kinds `tunnel`, `intercept`, `forward`, `blocked`, and `nix-cache` map onto that event.

Rules:

- **Ingest before removal.** `devvm rm` deletes the VM's logs; Factory ingests first. Retention is Factory's, not devvm's rolling ~10 MiB (ticket 017).
- **Content-free.** Host, method, path, rule, secrets-by-name, reason. No query strings, headers, or bodies.
- **Enforcement-level coverage.** This closes the network axis of ticket 004's "partial/unobserved" warning for sandboxed Runs; file and shell axes keep their caveats and are marked accordingly.
- **Downtime is visible.** A gap in ingestion is recorded as an unobserved interval, never smoothed over.

### 6.7 Privacy and retention

Activity details stay local by default, with explicit retention, deletion, and export controls. Content digests are for correlation and integrity, not a claim that content is recoverable or secret-proof. Remote telemetry is opt-in and content-free. Shell events capture executable category and exit status by default, not raw arguments, environment, stdin, or output. Full payloads stay in the protected transcript or Run detail (ticket 004).

### 6.8 Mining

Mining is a deliberate, reviewable batch over a date/project/session scope, not a background rewrite. It prioritizes explicit corrections and rejections, repeated clarifications, failed or denied operations, reruns, and changed context. It produces evidence-linked candidate learnings — pattern, supporting event and message references, counterexamples, confidence, proposed destination — never direct edits (ticket 004).

Ticket 012's upgrade is adopted in form: a candidate carries a `cue`, a `lesson`, and `evidence`; admission requires an execution contrast; a candidate bundles the exact artifact it came from; retrieval is an index, not a summary dump. The governance stays Factory's: the Owner approves changes to shared skills or Workflows, and repeated actionable gaps become deduplicated Issues on the tracker. Cross-run persistence and consolidation are Factory's own addition (ticket 012).

### 6.9 Owner timeline

One timeline per Run or Task, built from activity events, transition records, and trace spans: steers and context changes, model calls, tool calls, approvals, file and network operations, Gate verdicts, outcome and latency, plus links to the transcript, the diff, and the PR. Filterable by Managed Project, Task, Run, actor, operation, outcome, and time (ticket 004).

### 6.10 Metrics carried from research, not mandated

Ticket 014's candidates are useful but were not adopted as the v1 set: traceability coverage (merged changes with a complete session→Gate→diff→outcome chain), log health (growth, frontier query latency), review capacity (arrivals vs reviewer capacity), mining yield (accepted learnings per N sessions). Ticket 012 adds a candidate of the same kind: admitted-lesson count and re-use. They belong on the dashboard when the mining loop exists.

---

## 7. Adoption, init, and self-hosting

### 7.1 Project Init

Adopting a repository as a Managed Project is a PR, not a console wizard ([`CONTEXT.md`](../../CONTEXT.md), ticket 008):

1. The Owner registers the repository, its tracker, and its runtime configuration with Factory.
2. Factory proposes a PR adding `.factory/` with the default Workflow Artifact.
3. The Owner merges the init PR. The project is now manageable.
4. Secret **values** are entered host-side under the names the artifact declares; no value enters the repository, the VM, or a log.
5. Branch protection is verified: merges restricted to Factory's identity; the project token cannot merge.
6. The Project VM is created on first work, with the Envelope compiled.

Until step 3 merges, Factory may report on the project but creates no Tasks: the artifact is the contract.

### 7.2 Factory as Subproject one

Factory's own repository is the first Managed Project ([`CONTEXT.md`](../../CONTEXT.md), ticket 008):

- **Bootstrap phase.** The initial build is manual: a human writes the daemon, the adapter, and the default artifact, and merges them without the Loop.
- **Handover.** Once the artifact is merged and the daemon can run the Loop, Factory drives changes to itself. From then on, work on Factory arrives as Issues and leaves as merged PRs like any other project.
- **Feedback routing.** Work done in another Managed Project files feedback about Factory as an Issue on Factory's tracker (map note #5). In v1 that is a convention, not a workflow Stage.
- **Upgrade step.** A self-merged change to the daemon takes effect only when the daemon is rebuilt or restarted. **⟨default⟩** The Owner performs that restart; automating self-upgrade is not v1.

### 7.3 Operating surfaces

ADR-0005 names `factory inbox`, `factory approve …`, and `factory egress allow …`. The spec expects at least the following surface; the verb and command names are **⟨default⟩**:

| Surface | Purpose |
| --- | --- |
| `factory inbox` | Checkpoints, Blocked Tasks, Egress Requests |
| `factory approve <checkpoint>` | Record a Checkpoint decision, with edits or reason |
| `factory egress allow` / `factory egress deny` | Decide an Egress Request; both outcomes recorded |
| `factory triage <issue-ref>` | Admit an existing backlog Issue into Triage |
| `factory status` | Task/Run state, Gate reports, metrics |
| `factory workflow validate` | Compile and validate the artifact before a PR |

All are clients of the same API; none reads the database.

---

## 8. Build prerequisites and risks

### 8.1 Hard prerequisites

| Prerequisite | Why it is hard |
| --- | --- |
| Go toolchain and a single daemon binary | ADR-0001; static distribution, goroutines, official MCP/provider SDKs if needed |
| SQLite with WAL | ADR-0005; one writer, one backup file |
| `dhall-golang` **conformance gate** | ADR-0006: the build fails if the binding cannot evaluate the workflow schema. There is no second frontend |
| `cel-go` | guards (ticket 011) |
| OpenCode, **pinned version** | ADR-0002; contract tests against the pinned API surface, not "latest" (ticket 002) |
| devvm **≥ 0.1.1**, CLI only | ticket 017; 0.1.0 predates custom secrets, the 17-VM cap, and the split proxy |
| Linux host with QEMU/KVM (Lima) | devvm's only backend |
| `gh` authenticated on the daemon host | tracker polling, PR creation, squash merge |
| Branch protection on managed repositories | merge authority is Factory's; the project token must not merge |
| systemd user unit | ADR-0005 |
| HTTPS git remotes | devvm does not inject secrets into git-over-SSH |

### 8.2 The Dhall conformance gate

A CI job, not a runtime hope:

1. Evaluate the `schema/` types and the default `workflow.dhall` + `envelope.dhall` with the pinned `dhall-golang`.
2. Decode the result into the Go IR.
3. Run the IR validator (§4.8).
4. Fail the build on any error, with the Dhall diagnostics attached.

The gate failing stops the build. It does not trigger a fallback frontend: the Owner took the Dhall decision with this risk in view (ADR-0006), and ticket 011's fallback order is a re-decision, not a quiet switch.

### 8.3 Version pins

| Dependency | Pin | Compatibility policy |
| --- | --- | --- |
| devvm | ≥ 0.1.1 | CLI + `--json` version 1 (additive); re-pin only after a contract run |
| OpenCode | one pinned release | contract tests for sessions, events, permissions, questions; capability descriptor records the version |
| IR | its own major version | engine refuses unknown versions |
| Dhall standard | the subset `dhall-golang` supports | conformance gate proves the schema, not the standard |
| Event envelope | `schema_version` 1 | additive changes bump the version |

The 0.1.1 line was at `0.1.1-rc.3` when researched; the pin is to 0.1.1 or later, and the contract run — not the version string — decides whether a given build is usable (ticket 017).

### 8.4 Risk register

| # | Risk | Exposure | Mitigation |
| --- | --- | --- | --- |
| R1 | `dhall-golang` tracks standard v19 while the standard is 23.1 | Authoring path blocked at the worst time | Conformance spike is the first build task; Go decodes and validates the IR before execution; build gate fails loudly; no fallback frontend by decision (ADR-0006, ticket 011) |
| R2 | OpenCode API churn; some route families are experimental | Adapter breaks on upgrade | Pinned version; contract tests; capability descriptor; test double exercises the seam; upgrades only with a green suite (ADR-0002, ticket 002) |
| R3 | devvm is young (0.1.x), CLI-only, breaking changes on main, 17-VM cap | Lifecycle automation and capacity | Pin ≥ 0.1.1; treat `--json` version as the contract; wrap the CLI behind Factory's adapter; one VM per Managed Project keeps the count low (ticket 017) |
| R4 | Linux has no `.git` protection | VM-written hooks/config could run on the host | `--clone` always; the host repo is never mounted; devvm scans set-id files on stop (ticket 017) |
| R5 | Secret injection does not cover git-over-SSH; CA expiry; minting gaps | Push fails; requests fail closed; credential grants | HTTPS remotes; CA expiry is an operational check; fine-grained tokens per project; rotate after distrust (ticket 017) |
| R6 | Runaway spend; no cap in v1 | Cost, not correctness | Measured per Task; visible in metrics; the allowlist bounds egress; a cap is post-v1 (ADR-0004) |
| R7 | Self-hosting bootstrap is circular | Factory cannot build itself without itself | Manual initial build; Subproject one after handover; feedback as Issues (ticket 008) |
| R8 | Gate integrity: an agent edits the artifact or claims a verdict | Ungated advancement | IR pinned per Task; Gates read durable facts; review verdicts are typed artifacts aggregated deterministically; artifact edits are PRs (ticket 014, ADR-0003) |
| R9 | One daemon, one Owner, no multi-user auth | Local compromise; no team use | Unix socket with a scoped Owner session; one writer; one credential owner; multi-client auth deferred (ADR-0005) |
| R10 | Evidence loss when a Project VM is removed | Forensics and mining gaps | Ingest network logs and export transcripts before `devvm rm`; refs and digests live in Factory (ticket 004, ticket 017) |
| R11 | Polling intake latency and provider rate limits | Slow admission; throttling | Configurable interval; idempotent intake; webhooks post-v1 (ADR-0005) |
| R12 | DeltaDB / Harness² / Swamp tempt adoption | License, account gate, or substrate lock-in | Patterns only: operation-log vocabulary, evidence-gated lessons, typed DAG + CEL. No dependency (tickets 012–014) |
| R13 | Deploy creep | Scope and credential risk | Out of scope by owner ruling; each project owns its CI; no deploy credentials in a Project VM (ticket 018) |
| R14 | 17-VM cap / per-VM memory if usage grows | Queueing at scale | One VM per Managed Project; per-Run VMs stay an escalation; capacity is measured (ticket 017) |
| R15 | Transcript/runtime state inside the VM is the only copy | Loss on VM replacement; runtime lock-in | Factory keeps Task context, artifacts, diffs, and handoff summaries outside the runtime so a Task can resume with a fresh session (ticket 002) |

### 8.5 Patterns studied, not adopted

| Source | Taken | Not taken |
| --- | --- | --- |
| DeltaDB (ticket 014) | stable operation identity, append-only history, materialized frontier, evidence→conversation links | the store itself (no SDK/source, hosted, no permission model); review-without-PR for v1 |
| Harness² (ticket 012) | eight-component harness vocabulary, contrast-gated lessons (`cue`/`lesson`/`evidence`), artifact-bundled candidates, index-on-demand | automated lesson adoption; the substrate |
| Swamp Club (ticket 013) | typed DAG + CEL, default-deny grant vocabulary, YAML+Schema as the road not taken, skills+CLI neutrality | building on it (AGPL, closed registry, mandatory account); public registry; remote worker fleet |
| Code mode (ticket 015) | the composition pattern as a future adapter capability; Pi's sandbox reference | scripts as Workflow, scripts as Gates; classifier-based checking |

### 8.6 Suggested build order

Dependency-ordered, each step ending in a verifiable state:

1. Dhall conformance spike + IR validator + default artifact (the earliest failure is the cheapest).
2. Transition log, projections, snapshots, API skeleton, CLI client.
3. Fake `RuntimeAdapter` runs the Loop's state machine end to end with no real agent.
4. devvm lifecycle + Envelope compilation + secret bindings.
5. OpenCode adapter inside the Project VM; contract tests.
6. Tracker adapter, Gates, Checkpoints, PR, squash merge.
7. Activity log, metric set, network-log ingestion.
8. Project Init; Factory registers itself; handover to self-driven.

---

## 9. Open questions (fog)

### 9.1 Fog

Two questions remain unspecified in the record. This spec does not answer them.

1. **Observability field schema.** The envelope shape is decided (ticket 004), but the exact field set, allowed values, indexing, retention windows, and the queries mining runs over are not. Until they are, the activity log is a shape without a contract: implementers will otherwise invent field names that mining then depends on. Related detail: whether workflow facts (Gate verdicts, Checkpoints, effects) surface as additional activity kinds or stay transition-log-only.
2. **Path-to-other-users surface.** Packaging, onboarding, configuration UI, multi-user auth, and how a second Owner's projects are isolated. The map defers design until the Owner's needs are fully specified; the four seams in §1.2 are what keeps the door open.

### 9.2 Deferred by decision, not fog

These have an answer — "not in v1" — and a recorded direction: Capability Profiles (ticket 009), PR-format validators (ADR-0004), the composition surface (ADR-0002, ticket 015), external-server mode (ticket 006), webhooks (ADR-0005), remote/worker mode (ADR-0005), other trackers (ticket 003), runtime plurality (ADR-0002), post-merge monitoring and sub-Issue decomposition (ticket 008), spend caps (ADR-0004), deploy (ticket 018), workflow packs / public registry (ticket 013). Per-Run VMs are not in this list: they remain a recorded escalation option, unused by v1 (ticket 017).

### 9.3 Spec defaults introduced here

Every **⟨default⟩** in one place, for review:

| # | Default | Where |
| --- | --- | --- |
| D1 | Backlog admission by explicit Owner command, not a label | §3.3 |
| D2 | Admission order: Issue creation time, then number | §3.10 |
| D3 | A denied merge returns the Task to Implement with the reason; the Workflow declares the denial/abandon split | §3.9 |
| D4 | Each Task pins its IR version and digest at creation | §4.8 |
| D5 | `clone` fixed true in v1 | §4.4 |
| D6 | Concurrency above 1 gives each Task its own workspace in the VM | §2.5, §3.10 |
| D7 | Metric thresholds are recorded configuration | §6.4 |
| D8 | The Owner restarts the daemon after a self-merged change | §7.2 |
| D9 | Developer preset host list seeded from the prototype | §4.4 |
| D10 | Artifact schemas share `.factory/schema/` with the Dhall types | §4.1 |
| D11 | CLI verb and command names beyond the three ADR-0005 names | §7.3 |

---

## 10. Reconciliations (formerly inconsistencies)

The first draft found eight conflicts between the map, the glossary, the tickets, and the ADRs. Each is now fixed with the ADR as the authority; the table records what changed so the history stays legible. No decision was reversed; the two ADR amendments record mechanisms already implied by those ADRs' authority rules.

| # | Was | Resolution | Artifact changed |
| --- | --- | --- | --- |
| I1 | The map's Notes #12 called daemon-vs-CLI "decide later" | The note records ADR-0005's decision: resident daemon, thin CLI | [`map.md`](../wayfinding/map.md) |
| I2 | The map destination, Notes #3/#14, and the glossary called Workflows "code-defined" with the language open; ticket 001 still recommended Starlark | A Workflow is typed declarative data (Dhall → IR), not code running in the Go process; the wording matches ADR-0006 and a superseded-in-part note now heads 001 | [`map.md`](../wayfinding/map.md), [`CONTEXT.md`](../../CONTEXT.md), [`closed/001`](../wayfinding/closed/001-research-harness-language.md) |
| I3 | Ticket 002 recommended the embedded OpenCode SDK | Superseded by ticket 006/ADR-0002 (managed server over its API); a superseded-in-part note now heads 002 | [`closed/002`](../wayfinding/closed/002-research-build-vs-opencode-plugins.md) |
| I4 | The map destination promised "per-agent capability control" | v1 controls per Managed Project (ADR-0004); per-role profiles are post-v1 | [`map.md`](../wayfinding/map.md) |
| I5 | Ticket 006's Task-in named a "capability-profile ref" while v1 ships no profiles | The field resolves to the Project Envelope in v1 and is reserved for post-v1 profiles | [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md) |
| I6 | ADR-0006's `budget` field read like a cap | It is a spend-measurement declaration: measured, not capped (ADR-0004) | [`ADR-0006`](../adr/0006-dhall-authoring-factory-directory.md) |
| I7 | Ticket 009 had an egress approval adding a host to the allowlist outside the artifact | An approval persists as a PR against `envelope.dhall`; provisional application is recorded until merge | [`ADR-0004`](../adr/0004-containment-first-capability-model.md), [`closed/009`](../wayfinding/closed/009-decide-capability-control-model.md) |
| I8 | The map's fog still listed the permission model as unspecified | v1's model is decided (ADR-0004); only post-v1 profiles remain open | [`map.md`](../wayfinding/map.md) |

One wording note that is not a conflict: ADR-0003 writes the Loop as "intake → triage → implement → gates → review → PR → merge", while CONTEXT.md names five Stages. Gates and PR are activities inside Stages, not extra Stages (§3.1).

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
| [`closed/002`](../wayfinding/closed/002-research-build-vs-opencode-plugins.md) | Control-plane/runtime boundary; effect-runner discipline |
| [`closed/003`](../wayfinding/closed/003-research-tracker-adapters-and-permissions.md) | Tracker adapter contract; harness-gated mutations |
| [`closed/004`](../wayfinding/closed/004-research-steer-capture-observability.md) | Event envelope; categories; privacy; mining |
| [`closed/006`](../wayfinding/closed/006-decide-harness-substrate.md) | Adapter contract detail; plugin scope; composition reserved |
| [`closed/008`](../wayfinding/closed/008-shape-the-issue-driven-loop.md) | Loop stages; default Wave; failure policies; metrics; init |
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
