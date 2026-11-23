# Workflows are node/edge graphs; Stage is a display group

A Workflow's core primitive is the **Node**, connected by **Edges**. The engine executes nodes and evaluates edges; it does not execute Stages. The default issue-driven Loop is one graph in `defaults/`, not engine logic. A **Stage** survives only as a `group` label on nodes for display, metrics, and the later Node View.

A Node has a stable `id`, a `kind`, typed `config`, an optional `group`, optional `measures`, and an optional visit bound. An Edge has `from`, `to`, an `on` condition (`success`, `failure`, `event`, `decision`, `timeout`, or `always`), an optional CEL `guard`, and an optional traversal bound. Only one outgoing edge is taken; edges are evaluated in declaration order and the first match wins. A Task starts at exactly one designated entry node and ends at a terminal node.

The primitive node kinds are `agent`, `gate`, `checkpoint`, `action`, `trigger`, `route`, and `terminal`.

- An `agent` node dispatches a wave of one or more Roster Entries, declares its required outputs, deadline, idle timeout, heartbeat, and event edges, and follows an edge on completion or failure. Agent outcomes are a closed set: `Completed`, `Incomplete`, `Stalled`, `Crashed`, `Exhausted`, `Blocked`, and `Refused`. A failure or stall edge can carry a typed `Feedback` artifact (a Gate report, review findings, PR feedback, or the agent outcome) into the next Run.
- A `gate` node evaluates one deterministic check from a closed registry and follows pass or fail. A Gate report is a first-class record; a failure edge can carry it as feedback to an agent node.
- A `checkpoint` node waits for an Owner decision, with asked artifacts, and follows the decision.
- An `action` node performs one typed effect from a closed registry — for example `git.push`, `git.sync`, `pr.create`, `pr.merge`, `tracker.comment`, `tracker.transition` — and follows success, failure, or a typed conflict/stale outcome.
- A `trigger` node waits for typed external events. The engine owns polling, dedupe, and restart reconciliation; the Workflow owns the event match, actor guard, and target edge. Waiting nodes (triggers and checkpoints) can carry event edges, so a human PR review or a moved base can interrupt a pending merge checkpoint and route the Task to rework.
- A `route` node evaluates a pure CEL expression and chooses an edge.
- A `terminal` node records `merged`, `abandoned`, or `failed`.

The harness owns the alphabet — node-kind semantics, event sources, gate evaluators, action effects, scheduling, bounds enforcement, receipts, and audit. The Workflow owns the sentences — every node, edge, trigger match, guard, bound, roster selection, checkpoint ask, measure, and route. A new process shape must not require harness code. A genuinely new node kind or effect is a reviewed harness extension, not an arbitrary Dhall expression; Dhall still builds data and never calls a host effect.

Task state becomes generic: `Ready`, `Active`, `Waiting`, `Blocked`, `Merged`, `Abandoned`, and `Failed`, with `currentNode` identifying the node. `Implementing`, `InReview`, and `AwaitingMerge` are no longer engine states; they are nodes or groups in the default graph.

Cycles are allowed only when at least one edge in the cycle declares a bound. The validator rejects unbounded cycles, unresolved edges, unknown node kinds/checks/actions/events, missing entry or terminal nodes, unreachable terminals, duplicate node ids, and agent nodes whose outputs or liveness contract is incomplete.

Concurrency and PR feedback are graph features, not harness special cases. The default graph sets `concurrency` per Managed Project, gives each Task its own working copy inside the Project VM, serializes merges, and uses a `pr-watch` trigger plus `sync` action and `rework` agent node to react to base movement, conflicts, and human feedback. The default feedback budget is the initial attempt plus two automatic feedback rounds, then `Blocked`.

Agent access is **read-only** in v1: the Project VM gets one project-scoped token with contents/issues/PRs/metadata reads (and optional checks/actions reads), no write. Factory pushes the agent's branch and performs PR creation, merge, tracker transitions, and comments with the host identity. Agents do not comment directly in v1; Factory may post summaries, and inline replies are the post-v1 comment plugin. The token is entered host-side and bound by name; the Client API never carries it.

v1 remains one Workflow definition per Managed Project. The IR carries a `workflowId` and the API is workflow-addressed so a later multi-workflow release is additive, but validation still rejects a second Workflow in v1.

## Considered Options

- **Keep the stage-centric IR** — rejected. A Stage bundles a wave, gates, a checkpoint, and an action, and the engine implicitly advances. Adding `Rework` and `sync` would become new hardcoded Stage behavior; every new process shape would need engine code.
- **Add `Rework` and `sync` as special node kinds** — rejected for the same reason. They are ordinary `agent` and `action` nodes in the default artifact.
- **Let Dhall define node kinds or effects** — rejected. Dhall may build the graph but may not call a host effect (ADR-0006); arbitrary effects would lose determinism, audit, and containment.
- **A plugin runtime for new node kinds in v1** — deferred. A new kind or effect is a reviewed harness extension, not a project-local script.
- **`parallel`/`join` nodes in v1** — deferred. An agent node's wave covers parallel agent sessions; cross-Task concurrency is a scheduler setting, not a graph primitive.
- **Multiple Workflow definitions per Managed Project in v1** — deferred. The IR and API keep the workflow identity so the change is additive, but v1 routes every Task through one Workflow.

## Consequences

- `docs/spec/SPEC.md` §3 and §4 are rewritten around nodes and edges; the default Loop is a graph; Task states are generic; Gate failure policies become bounded edges.
- The IR shape changes: `entry`, `nodes`, `edges`, `workflowId`, and edge bounds replace stage-scoped Waves, Gates, checkpoints, and failure policies.
- `defaults/`'s Dhall and golden IR are authored as a graph in build step 1; the prototype's stage-centric IR stays as evidence and is not rewritten.
- Agent completion and liveness become part of the RuntimeAdapter and agent-node contract: a declared `liveness` capability, typed outcomes, heartbeat/idle/deadline detection, and typed feedback into retries.
- Concurrency above one and PR feedback become v1 features of the default graph; the merge queue and stale-approval rule are specified.
- The future Client API decision inherits this shape: `workflow.get` returns the graph, `task.get` returns `currentNode` and generic state, and no `rework` or `sync` operation exists.
- ADR-0006 is amended: the typed declarative graph is now a node/edge graph, and Stage is a display group.

Status: accepted 2026-11-22 (Owner design decision; review record: PR #7).
