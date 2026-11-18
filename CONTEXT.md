# Factory

A user-defined agent harness: deterministic, code-defined workflows that orchestrate agent teams across managed projects, each with its own tracker. This glossary fixes the vocabulary the spec and workflows share.

## Language

**Factory**:
The harness itself: it owns workflow state, gates, and audit, and delegates agent execution to a runtime.
_Avoid_: platform, framework, orchestrator

**Managed Project**:
A repository plus its tracker that Factory operates on, with its own workflow definitions, runtime configuration, and Project VM.
_Avoid_: project, repo, workspace

**Project VM**:
The devvm instance that backs a Managed Project: the sandbox, network, and secret boundary for every agent session and runtime server of that project.
_Avoid_: sandbox, container, environment

**Subproject**:
A managed project served by Factory where the work being done belongs to Factory itself (the first subproject is Factory).
_Avoid_: self-hosting target, self-managed repo

**Workflow**:
The code-defined, typed graph of stages a Task moves through in a Managed Project; the unit of project-defined behavior, not harness code.
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

**Gate**:
A harness-enforced condition that must pass before a Task advances; its verdict is deterministic and never an agent's judgment. Each Gate carries its own failure policy, defined in the Workflow.
_Avoid_: check, criteria, approval

**Failure Policy**:
The Workflow-defined action a failed Gate triggers: retry within the Stage, return the Task to an earlier Stage, open a follow-up Issue, change Issue state, or wait for the Owner.
_Avoid_: error handling, fallback, retry

**TriageDecision**:
The typed result of the Triage Stage: suggested labels and priority, acceptance criteria, plan sketch, size estimate, confidence, and open questions — approved or edited by the Owner before a Task exists.
_Avoid_: assessment, analysis

**Workflow Artifact**:
The version-controlled artifact a Managed Project carries in its own repository: its Workflow plus runtime configuration, added by Project Init.
_Avoid_: config file, pipeline definition

**Project Init**:
The act of adopting a repository as a Managed Project: Factory proposes a PR adding the Workflow Artifact, the Owner merges it, and the project becomes manageable.
_Avoid_: onboarding, setup

**Checkpoint**:
A point in the Loop where the Owner must decide; the Owner's decision is recorded as part of the Task's history.
_Avoid_: approval, sign-off

**Agent Confusion**:
A measured property of a Run, expressed through proxies (repeated identical tool calls, file thrash, plan revisions, abandonment or retry, reviewer-flagged misunderstanding, self-reported uncertainty) rather than a subjective score.
_Avoid_: hallucination, error

**Owner**:
The person Factory serves: the author of workflows and the authority at Checkpoints.
_Avoid_: user, admin, operator

**Run**:
One execution of a Task (or of a Stage's Wave) recorded in Factory's durable history.
_Avoid_: attempt, execution, session

**RuntimeAdapter**:
The seam through which Factory delegates agent execution to a runtime; it normalizes runtime behavior into Factory's task/outcome vocabulary.
_Avoid_: provider, integration, driver
