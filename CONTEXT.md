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
The typed, declarative graph of stages a Task moves through in a Managed Project, authored in the Workflow Artifact (ADR-0006); the unit of project-defined behavior, not harness code.
_Avoid_: pipeline, script, automation

**Task**:
A unit of work admitted into a Workflow, derived from a tracker Issue and owned by Factory until it is merged or abandoned.
_Avoid_: ticket, job, item

**Issue**:
The tracker artifact a Task is derived from; the tracker remains its authoritative record.
_Avoid_: ticket, task

**Loop**:
The recurring path a Task takes through a Workflow: intake → triage → implement → review → merge.
_Avoid_: cycle, flow

**Stage**:
One named step of a Loop (Triage, Implement, Review, Merge) that can dispatch a Wave and must pass its Gates to advance.
_Avoid_: phase, step

**Wave**:
The set of agent sessions dispatched together within a Stage for one Task, defined by the Workflow (e.g. one implementer with two reviewers).
_Avoid_: team, swarm, fan-out

**Node**:
A stable, addressable element of a Workflow — a Stage, Gate, Checkpoint, action, or agent entry — under which Runs, events, artifacts, and Gate reports are grouped.
_Avoid_: step, task

**Agent Roster**:
The project-scoped, typed set of Roster Entries in `.factory/roster.dhall`; Wave entries select from it by id. It is part of the Workflow Artifact and compiles into the IR.
_Avoid_: runtime configuration, agent config, team

**Roster Entry**:
One agent definition in the Agent Roster: id, role, persona, instructions, ordered model list (which lives in `bindings.dhall`, ADR-0008), tool and permission policy reference, adapter options, and declared requirements (secret names, tool classes, modality). A Wave entry selects an entry by id; a Stage cannot override its model, tools, or parameters. Informally, a seat.
_Avoid_: agent config, worker

**Model Catalog**:
The adapter's declaration of available model IDs, providers, capabilities (including modality), tool classes, and current availability; its static descriptor validates at compile time and its live overlay informs Project Init.
_Avoid_: model list, allowlist, provider config

**Gate**:
A harness-enforced condition that must pass before a Task advances; its verdict is deterministic and never an agent's judgment. Each Gate carries its own failure policy, defined in the Workflow.
_Avoid_: check, criteria, approval

**Failure Policy**:
The Workflow-defined action a failure triggers: retry within the Stage, return the Task to an earlier Stage, open a follow-up Issue, change Issue state, or wait for the Owner. A Gate carries one for its verdict; a Stage carries one for Run-level failures outside a Gate (model exhaustion, a crashed Run), with the same actions and bounds.
_Avoid_: error handling, fallback, retry

**TriageDecision**:
The typed result of the Triage Stage: suggested labels and priority, acceptance criteria, plan sketch, size estimate, confidence, and open questions — approved or edited by the Owner before a Task exists. Post-v1, triage may instead return `NeedsInfo` with a `ClarificationRequest` (questions, missing fields, context); that is a direction, not a v1 outcome.
_Avoid_: assessment, analysis

**Workflow Artifact**:
The version-controlled artifact a Managed Project carries in its own repository: its Workflow, Agent Roster, bindings, and Project Envelope, rendered from the Default Workflow Artifact by Project Init (ADR-0006, ADR-0007, ADR-0008). Provider authentication is not part of the artifact; it stays harness- and host-side.
_Avoid_: config file, pipeline definition

**Default Workflow Artifact**:
The versioned seed Factory ships in `defaults/` and Project Init renders into a Managed Project's `.factory/`; a project's copy is independent and adopts changes by PR.
_Avoid_: template, scaffold, boilerplate

**Project Init**:
The act of adopting a repository as a Managed Project: Factory validates the configured harness, renders the Workflow Artifact (including the Agent Roster's primary models), proposes one init PR, the Owner merges it, and the project becomes manageable.
_Avoid_: onboarding, setup

**Checkpoint**:
A point in the Loop where the Owner must decide; the Owner's decision is recorded as part of the Task's history.
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
The post-v1 per-project client that answers questions, creates Issues and proposes Workflow Artifact PRs on the Owner's confirmation, and talks to a waiting Run; not a Workflow Stage and not a Roster Entry.
_Avoid_: chatbot, console agent

**Run**:
One execution of a Task (or of a Stage's Wave) recorded in Factory's durable history.
_Avoid_: attempt, execution, session

**RuntimeAdapter**:
The seam through which Factory delegates agent execution to a runtime; it normalizes runtime behavior into Factory's task/outcome vocabulary.
_Avoid_: provider, integration, driver
