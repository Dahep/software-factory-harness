---
title: Shape workflow authoring ergonomics (what writing a Loop actually looks like)
type: wayfinder:prototype
assignee: done
status: resolved
blocked-by:
- closed/008-shape-the-issue-driven-loop.md
- closed/011-research-typed-functional-workflow-language.md
---

## Question

The map now knows what a Workflow *is* (typed graph, CEL guards, gates with failure policies, waves as data) and where it lives (a Workflow Artifact inside each Managed Project, added by Project Init). It does not know what **authoring one feels like**. The fog held this until the milestone's shape was firm (008, resolved); it is now the remaining spec-level uncertainty on the workflow layer.

Shape the authoring experience with the owner, using a concrete artifact to react to (the `prototype` skill):

1. **Surface**: Dhall frontend (gated in 011 on a `dhall-golang` conformance spike), a YAML + JSON-Schema frontend (Swamp's model, 013), or handwritten JSON IR with tooling. Requirement: typesafe, functional where possible (map note #14) — evaluate each against the *actual* loop from 008, not toy steps.
2. **The author's chair**: write the default loop (intake → triage → implement → gates → review → PR → squash merge, 1 implementer + 2 reviewers, gate failure policies) in each candidate and compare honestly: verbosity, error messages, how gates and their failure policies read, how waves/agents are referenced, how runtime config and capability profiles attach.
3. **Reuse and composition**: project init copies/parameterises the default; how does a project deviate (different wave, extra gate, different tracker state names) without fork-and-drift? What does a "library" of workflow fragments look like?
4. **Validation and measurement hooks**: how does authoring enforce the measurement directive (#15) — does every stage/gate need a declared metric, or are metrics inferred? Where does the schema live so the harness can validate pre-run?
5. **Migration**: Workflow Artifact versioning — how does a project's stored Workflow evolve when the default loop changes upstream?

Deliverable: a prototype artifact (rough loop definitions in the top two candidates + a recommendation) plus a decision on the frontend, so the spec can commit. HITL: the owner reacts to the artifact.

## Resolution

**Decided 2026-11-18 (HITL with the owner), after the prototype at `prototype/workflow-authoring/`.**

1. **Frontend: Dhall — no fallback.** Workflows are authored in Dhall and compiled by `dhall-golang` to the versioned IR (closed/011's contract). The conformance spike is a **build prerequisite**: the build gate fails if the Go binding cannot evaluate the workflow schema. The owner took this with the risk in view; the YAML+JSON-Schema prototype stays in the repo as documentation of the alternative, but no second frontend ships.
2. **Artifact: committed directory `.factory/`** in each Managed Project: `workflow.dhall` (loop), `envelope.dhall` (configuration: clone mode, network tier/allowlist, budget, secret names), `schema/` (Dhall types). Reviewed as one PR at init.
3. **Secrets by name only.** The artifact is committed, so it never holds secret values: the envelope names secrets (`github`, `model-provider`); values live host-side in devvm's store and bind per Project VM (closed/017).
4. **Reuse: copy-on-init.** Project Init opens a PR adding the default artifact; merging it makes the project manageable. Deviation from the default is PRs against the project's copy — no inheritance or override machinery.
5. **Measurement: optional per stage.** A default metric set applies to every Run (stage cycle time, gate verdicts, review findings, retries, tokens/cost, PR latency, tool errors, agent-confusion proxies); stages may add metrics; declaring none is valid.
6. **Prototype capture.** `prototype/workflow-authoring/` holds the YAML+Schema version, the Dhall sketch, the compiled IR, and `validate.py`; its first run caught an unbounded `returnTo` — the case for schema-checked authoring, now native in Dhall.

**Amendment (2026-11-19).** Item 2's `.factory/` directory gains `roster.dhall` (ADR-0007); the Agent Roster compiles with the workflow and envelope into the IR.

**Amendment (2026-11-20).** Item 2's `.factory/` also carries `bindings.dhall` and is rendered from the Default Workflow Artifact in `defaults/`, which ships a fixture golden IR and a content digest (ADR-0008). Item 4's copy-on-init answer stands, with one boundary that decision fixed: the two lifecycle labels (`needs-triage`, `ready-for-agent`) are the whole v1 label set, so renaming label or workflow-state names is post-v1 rather than a copy deviation.
