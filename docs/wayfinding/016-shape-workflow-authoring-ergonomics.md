---
title: Shape workflow authoring ergonomics (what writing a Loop actually looks like)
type: wayfinder:prototype
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
