# The Agent Roster lives in the Workflow Artifact

Each Managed Project's Workflow Artifact carries an **Agent Roster**: `.factory/roster.dhall`, a project-owned, typed list of Roster Entries that Wave entries select by id. An entry declares one agent's identity, role, persona, instructions, tool and permission policy reference, adapter options, and declared requirements (secret names, tool classes, modality). Its ordered model list is supplied by the project's `bindings.dhall` (ADR-0008): the entry stays the selector the IR compiles, and the list lives with the init data where Project Init writes it. A Stage cannot override an entry's model, tools, or parameters. The roster compiles with `workflow.dhall` and `envelope.dhall` into the same IR, so the existing Task pin covers the models, tools, and permissions that execute a Task — there is no second configuration digest to forget. Factory validates the roster against the adapter's Model Catalog at compile time: model IDs are catalog IDs, never host-resolved aliases. One adapter kind serves each Managed Project. The adapter tries an entry's model list in order and records every attempt; if every model fails it returns a typed failure Outcome to the Stage that dispatched the agent, whose own Failure Policy decides, with the same actions and bounds as a Gate's policy. The adapter never substitutes a model the roster did not name. Provider authentication stays harness- and host-side; Factory stores no secret values.

## Considered Options

- **Factory-managed runtime configuration outside `.factory/`** (ADR-0002's original consequence) — rejected: two sources of truth for how a Task executes, a Task pin that misses the model and tools, and no project review path.
- **A sibling directory in the Managed Project's repo** (`.factory-runtime/`) — rejected: a second artifact surface and a second review path for something the Workflow already selects.
- **A Factory store, content-addressed** — rejected for v1: no Git review or history; still a candidate for remote mode later.
- **Roster embedded in `workflow.dhall`** — rejected: the roster is a project-scoped artifact that reviews and diffs better as its own file.
- **Role + persona as the key** — rejected: the implicit matrix breaks silently when a persona is renamed; an explicit id is also the object a profile attaches to later.
- **Host-resolved model alias, or substitution outside the list** — rejected: the project would not know which model ran; declared lists keep substitution explicit and auditable.
- **Per-entry adapter kind** — deferred post-v1; v1 keeps one adapter kind per Managed Project.

## Consequences

- `.factory/roster.dhall` joins the artifact; ADR-0006's directory and copy-on-init gain it, and the conformance gate compiles it with the workflow and envelope. The compiler checks each entry's declared requirements: secret names against the Envelope's grants, tool classes and modality against the Model Catalog for every model in the entry's list. Network hosts are runtime egress, not entry requirements (ADR-0009).
- Project Init becomes a guided bind → render → PR flow: validate the configured harness, choose a primary model for each default seat (triager, implementer, reviewer (spec-fidelity), reviewer (adversarial)), render `defaults/` into the project's `roster.dhall`, `envelope.dhall`, and `schema/`, and write the selected models, build/test commands, provider and secret names, and provenance into `bindings.dhall` in one PR; provider endpoints are applied to local devvm config, not the artifact (ADR-0009). Fallbacks are added later by a roster or bindings PR.
- The IR carries the roster and its instructions content-addressed, so a roster change affects later Tasks only.
- The adapter Outcome contract gains a failure-reason taxonomy and an attempt trail, delivered with every Outcome; the default metric set gains model resolution.
- A Stage gains a mandatory Failure Policy for Run-level failures outside its Gates (model exhaustion, a crashed Run); the Workflow cannot compile without handling them, so a typed adapter failure has a defined disposition rather than failing the Workflow.
- Capability Profiles attach to a Roster Entry's policy reference post-v1; in v1 every entry resolves to the project-wide policy (ADR-0004).
- Factory stores no secret values: the Envelope names them, and the harness or devvm host-side store holds them.

Status: accepted 2026-11-19 (architecture review, candidate 1: runtime configuration; review record: PR #1). Amended 2026-11-20: each entry's ordered model list, and the provider names and endpoints Project Init writes, live in `bindings.dhall` (ADR-0008); the compiled entry still carries the list into the IR. Amended 2026-11-20: the entry's `budget` and network-host requirements are removed; provider endpoints are local devvm config (ADR-0009).
