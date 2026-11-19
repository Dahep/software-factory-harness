# Workflows are authored in Dhall inside a committed `.factory/` directory

Factory's Workflow Artifact is a `.factory/` directory committed in each Managed Project: `workflow.dhall` (stages, waves, gates and their failure policies, checkpoints), `envelope.dhall` (clone mode, network tier and allowlist, budget, secret names), and `schema/` (the Dhall types). The Go engine evaluates Dhall with `dhall-golang` and compiles it to a versioned IR; the IR — not Dhall — is the contract the engine executes. `devvm` secret values never appear in the artifact: the envelope names secrets, the host holds the values, bindings are per Project VM. Project Init copies the default artifact through a PR; later deviations are PRs against the project's copy. Per-stage metric declarations are optional because a default metric set applies to every run.

## Considered Options

- **YAML + JSON-Schema frontend** — prototyped (`prototype/workflow-authoring/`) and readable, with a working validator; rejected for v1 because the owner chose Dhall's author-time typing, with the YAML sketch kept as documentation of the road not taken.
- **Raw JSON IR authoring** — rejected: worst review and edit ergonomics.
- **Inheritance (`extends` + overrides)** — rejected: copy-on-init with PR-only deviation keeps one authoritative artifact per project and needs no merge semantics.
- **Mandatory per-stage metrics** — rejected: the default metric set plus optional extras keeps the directive without validation friction.

## Consequences

- `dhall-golang` conformance with the workflow schema is a build prerequisite, not a runtime gamble: if the binding cannot evaluate the schema, the build gate fails. There is no second frontend in v1 (owner's call, taken with the risk in view).
- Secrets by name only means a Workflow Artifact is safe to publish in a public repo.
- The prototype (`prototype/workflow-authoring/`) remains as evidence; its validator caught an unbounded `returnTo` on first run.

Status: accepted 2026-11-18 (wayfinder ticket: shape workflow authoring ergonomics).
