# Factory

A user-defined agent harness: deterministic, typed workflows defined as data that orchestrate agent teams across managed projects, each with its own tracker. This glossary fixes the vocabulary the spec and workflows share.

## Language

**Factory**:
The harness itself: it owns workflow state, gates, and audit, and delegates agent execution to a runtime.
_Avoid_: platform, framework, orchestrator

**Managed Project**:
A repository plus its tracker that Factory operates on, with its own workflow definitions, Agent Roster, and Project VM.
_Avoid_: project, repo, workspace

**Project VM**:
The devvm instance that backs a Managed Project: the sandbox, network, and secret boundary for every agent session and runtime server of that project.
_Avoid_: sandbox, container, environment

**Project Envelope**:
The containment contract in a Workflow Artifact — clone mode, network tier and named network preset, an optional stable `extra_allow` list, and secret names — that Factory compiles into the Project VM. The full allowlist, provider endpoints, and secret scopes are local devvm config, not part of the artifact.
_Avoid_: config, settings, policy

**Local devvm config**:
The operational devvm configuration the Owner manages: the full network allowlist, provider endpoints, and secret scopes and values. It is not version-controlled and not part of the Workflow Artifact.
_Avoid_: runtime config, settings

**Capability Profile**:
A post-v1 refinement of the Project Envelope: a narrower set of network, secret, and Factory-reach permissions for one role, compiled through the same path.
_Avoid_: role, permission set

**Egress Request**:
A blocked network access attempt that devvm surfaces to the Owner for an allow-or-deny decision; the decision and the applied local rule are recorded in Factory's local database, and the rule is applied to local devvm config.
_Avoid_: block, exception

**Subproject**:
A managed project served by Factory where the work being done belongs to Factory itself (the first subproject is Factory).
_Avoid_: self-hosting target, self-managed repo

**Workflow**:
The typed, declarative graph of nodes and edges a Task moves through in a Managed Project, authored in the Workflow Artifact (ADR-0006, ADR-0010); the unit of project-defined behavior, not harness code.
_Avoid_: pipeline, script, automation

**Task**:
A unit of work admitted into a Workflow graph, derived from a tracker Issue and owned by Factory until it is merged, abandoned, or failed.
_Avoid_: ticket, job, item

**Issue**:
The tracker artifact a Task is derived from; the tracker remains its authoritative record.
_Avoid_: ticket, task

**Loop**:
The recurring path a Task takes through the default Workflow graph: intake → triage → implement → review → merge.
_Avoid_: cycle, flow

**Node**:
The core primitive of a Workflow: a stable, addressable execution element with a kind, typed config, optional display group, and outgoing edges. The primitive kinds are agent, gate, checkpoint, action, trigger, route, and terminal.
_Avoid_: step, task, stage

**Edge**:
A guarded transition between two nodes: what activates it (`success`, `failure`, `event`, `decision`, `timeout`, or `always`), an optional CEL guard, and an optional traversal bound. A cycle is valid only when at least one edge in it is bounded.
_Avoid_: link, arrow, transition

**Trigger**:
A node that waits for typed external events. The harness owns polling, dedupe, and reconciliation; the Workflow owns the event match, actor guard, and target edge. A trigger and a checkpoint can accept events while waiting.
_Avoid_: webhook, listener, watcher

**Action**:
A node that performs one typed effect from the harness's closed action registry — for example git push, git sync, PR creation, merge, or a tracker effect. The Workflow selects and parameterizes the action; it never runs arbitrary host code.
_Avoid_: step, task, script

**Terminal**:
A node that ends a Task as merged, abandoned, or failed.
_Avoid_: end, finish

**Stage**:
A display grouping of nodes in a Workflow (for example Triage, Implement, Review, Merge), used for readability, metrics, and the later Node View. It is not an execution unit and cannot dispatch or gate anything by itself.
_Avoid_: phase, step, execution stage

**Wave**:
The set of agent sessions dispatched together by one agent node for one Task, defined by the Workflow (e.g. one implementer with two reviewers).
_Avoid_: team, swarm, fan-out

**Agent Outcome**:
The typed result of an agent session: Completed, Incomplete, Stalled, Crashed, Exhausted, Blocked, or Refused. The harness classifies it; the Workflow routes on its edges.
_Avoid_: status, result

**Feedback**:
A typed artifact carried on an edge into an agent node, or on a resume — a Gate report, review findings, PR feedback, an Agent Outcome, or an Owner note — so the next Run starts with the evidence of what failed.
_Avoid_: advice, retry prompt

**Session Liveness**:
The harness's evidence that an agent session is alive: an adapter heartbeat, idle timeout, and deadline. The adapter declares whether it can provide a heartbeat; otherwise liveness is idle-timeout-only or unobserved, never assumed.
_Avoid_: health check, keepalive

**Agent Roster**:
The project-scoped, typed set of Roster Entries in `.factory/roster.dhall`; agent nodes select from it by id. It is part of the Workflow Artifact and compiles into the IR.
_Avoid_: runtime configuration, agent config, team

**Roster Entry**:
One agent definition in the Agent Roster: id, role, persona, instructions, ordered model list (which lives in `bindings.dhall`, ADR-0008), tool and permission policy reference, adapter options, and declared requirements (secret names, tool classes, modality). An agent node selects an entry by id; a node cannot override its model, tools, or parameters. Informally, a seat.
_Avoid_: agent config, worker

**Model Catalog**:
The adapter's declaration of available model IDs, providers, capabilities (including modality), tool classes, and current availability; its static descriptor validates at compile time and its live overlay informs Project Init.
_Avoid_: model list, allowlist, provider config

**Gate**:
A harness-enforced condition evaluated by a gate node; its verdict is deterministic and never an agent's judgment. A Gate report is a first-class record, and a failing edge can carry it as Feedback to an agent node.
_Avoid_: check, criteria, approval

**Failure Policy**:
The Workflow-defined edge a failure takes, with a guard and a bound: retry the node, return to an earlier node, open a follow-up Issue, change Issue state, or wait for the Owner. A failure policy is graph data, not a harness behavior; a cycle without a bound is invalid IR.
_Avoid_: error handling, fallback, retry

**TriageDecision**:
The typed result of the triage agent node: suggested labels and priority, acceptance criteria, plan sketch, size estimate, confidence, and open questions — approved or edited by the Owner before a Task exists. Post-v1, triage may instead return `NeedsInfo` with a `ClarificationRequest` (questions, missing fields, context); that is a direction, not a v1 outcome.
_Avoid_: assessment, analysis

**Workflow Artifact**:
The version-controlled artifact a Managed Project carries in its own repository: its Workflow graph, Agent Roster, bindings, and Project Envelope, rendered from the Default Workflow Artifact by Project Init (ADR-0006, ADR-0007, ADR-0008, ADR-0010). v1 carries one Workflow definition per Managed Project. Provider authentication is not part of the artifact; it stays harness- and host-side.
_Avoid_: config file, pipeline definition

**Default Workflow Artifact**:
The versioned seed Factory ships in `defaults/` and Project Init renders into a Managed Project's `.factory/`; a project's copy is independent and adopts changes by PR.
_Avoid_: template, scaffold, boilerplate

**Project Init**:
The act of adopting a repository as a Managed Project: Factory validates the configured harness, renders the Workflow Artifact (including the Agent Roster's primary models), proposes one init PR, the Owner merges it, and the project becomes manageable.
_Avoid_: onboarding, setup

**Checkpoint**:
A checkpoint node where the Owner must decide; the Owner's decision is recorded as part of the Task's history. A pending checkpoint can accept event edges, so moved evidence or new PR feedback can interrupt it rather than silently approving stale work.
_Avoid_: approval, sign-off

**Conversation**:
A durable human-agent exchange linked to an Issue or a Run, hosted by a tracker, a runtime thread, or an external client; its messages are evidence, not Workflow state. A triage clarification and a waiting-agent conversation are both Conversations; a "thread" is the external surface, not the Factory record.
_Avoid_: chat

**Agent Confusion**:
A measured property of a Run, expressed through proxies (repeated identical tool calls, file thrash, plan revisions, abandonment or retry, reviewer-flagged misunderstanding, self-reported uncertainty) rather than a subjective score.
_Avoid_: hallucination, error

**Owner**:
The person Factory serves: the author of workflows and the authority at Checkpoints.
_Avoid_: user, admin, operator

**Project Assistant**:
The post-v1 per-project client that answers questions, creates Issues and proposes Workflow Artifact PRs on the Owner's confirmation, and talks to a waiting Run; not a Workflow node and not a Roster Entry.
_Avoid_: chatbot, console agent

**Run**:
One execution of a Task's node recorded in Factory's durable history. An agent node's wave records each session's Outcome and model attempt trail under that Run.
_Avoid_: attempt, execution, session

**RuntimeAdapter**:
The seam through which Factory delegates agent execution to a runtime; it normalizes runtime behavior, agent outcomes, and session liveness into Factory's vocabulary.
_Avoid_: provider, integration, driver
