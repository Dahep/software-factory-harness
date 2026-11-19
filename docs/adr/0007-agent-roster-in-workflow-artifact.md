# The Agent Roster lives in the Workflow Artifact

Each Managed Project's Workflow Artifact carries an **Agent Roster**: `.factory/roster.dhall`, a project-owned, typed list of Roster Entries that Workflow Stages select by id. An entry declares one agent's identity, role, persona, instructions, ordered model list, tool and permission policy reference, adapter options, declared requirements, and budget. The roster compiles with `workflow.dhall` and `envelope.dhall` into the same IR, so the existing Task pin covers the models, tools, and permissions that execute a Task — there is no second configuration digest to forget. The adapter tries an entry's model list in order and records every attempt; if every model fails it returns a typed failure Outcome to the Stage that dispatched the agent, whose Failure Policy decides. The adapter never substitutes a model the roster did not name. Provider authentication stays harness- and host-side; Factory stores no secret values.

## Considered Options

- **Factory-managed runtime configuration outside `.factory/`** (ADR-0002's original consequence) — rejected: two sources of truth for how a Task executes, a Task pin that misses the model and tools, and no project review path.
- **A sibling directory in the Managed Project's repo** (`.factory-runtime/`) — rejected: a second artifact surface and a second review path for something the Workflow already selects.
- **A Factory store, content-addressed** — rejected for v1: no Git review or history; still a candidate for remote mode later.
- **Roster embedded in `workflow.dhall`** — rejected: the roster is project-scoped and shared across Workflows, and a separate file reviews and diffs better.
- **Role + persona as the key** — rejected: the implicit matrix breaks silently when a persona is renamed; an explicit id is also the object a profile attaches to later.
- **Host-resolved model alias, or substitution outside the list** — rejected: the project would not know which model ran; declared lists keep substitution explicit and auditable.
- **Per-entry adapter kind** — deferred post-v1; v1 keeps one adapter kind per Managed Project.

## Consequences

- `.factory/roster.dhall` joins the artifact; ADR-0006's directory and copy-on-init gain it, and the conformance gate compiles it.
- Project Init becomes a guided bind → render → PR flow: validate the configured harness, choose a primary model for each default seat (triager, implementer, reviewer/spec-fidelity, reviewer/adversarial), render the roster, and write the configured providers' secret names and endpoints into the envelope in one PR. Fallbacks are added later by a roster PR.
- The IR carries the roster and its instructions content-addressed, so a roster change affects later Tasks only.
- The adapter Outcome contract gains a failure-reason taxonomy and an attempt trail; the default metric set gains model resolution.
- Capability Profiles attach to a Roster Entry's policy reference post-v1; in v1 every entry resolves to the project-wide policy (ADR-0004).
- Factory stores no secret values: the Envelope names them, and the harness or devvm host-side store holds them.

Status: accepted 2026-11-19 (architecture review, candidate 1: runtime configuration).
