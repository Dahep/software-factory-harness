# Default Workflow Artifact — contract

This directory is Factory's **Default Workflow Artifact**: the seed Project Init renders into a Managed Project's `.factory/`. It is not a dependency and it does not propagate. A project owns its copy; a change here reaches the project only through a PR against that copy.

The Dhall files and `fixtures/golden.ir.json` are authored in build step 1. This README is the contract they must satisfy.

## Layout

```
defaults/
  workflow.dhall           # node/edge graph: agent, gate, checkpoint, action, trigger, route, terminal; bounds, measures
  roster.dhall             # Agent Roster: four entries; model lists come from bindings
  envelope.dhall           # clone mode, network tier and preset, optional extra_allow, secret names
  bindings.example.dhall   # the init surface, with placeholder values
  schema/                  # the Dhall types plus TriageDecision and review schemas
  fixtures/
    bindings.dhall         # fixture values used only to produce the golden IR
    model-catalog.dhall    # pinned catalog descriptor, validated against the adapter
    golden.ir.json         # canonical compile of the default with the fixtures
```

## Project Init

`factory init` validates the configured harness live, selects a primary model for each default seat (`triager`, `implementer`, `reviewer-spec-fidelity`, `reviewer-adversarial`), and asks for build/test commands, defaulting to `make build` / `make test`. It then copies the typed files and schema into the project's `.factory/` and writes `bindings.dhall`:

```
{ from = { irVersion = "factory-ir/v1", contentDigest = "..." }
, models = { triager = ["..."], implementer = ["..."],
             reviewerSpecFidelity = ["..."], reviewerAdversarial = ["..."] }
, commands = { build = ["make", "build"], tests = ["make", "test"] }
, providers = { github = { secret = "github" },
                model = { secret = "model-provider" } }
}
```

The default roster entries are `triager`, `implementer`, `reviewer-spec-fidelity`, and `reviewer-adversarial`; the binding keys above map to them. Each entry's ordered model list lives in `bindings.dhall`, so the roster entry stays the selector the IR compiles. Fallback models are added to a seat's list by a later roster or `bindings.dhall` PR. Secret values never appear here; the Envelope names secrets, and the harness or devvm host-side store holds them.

## Containment

The Envelope carries the containment **contract**: clone mode, network tier, a named network preset, an optional stable `extra_allow` list, and secret names. The full network allowlist, provider endpoints, and secret scopes and values are **local devvm config**: the Owner manages them, and nothing there is version-controlled. `extra_allow` is empty by default; add a host only when it is a stable project need, never for every egress request. Project Init writes provider endpoints to local config, not to `bindings.dhall` or the Envelope.

## Versioning

- **Shape** is the IR major (`factory-ir/v1`). A shape change is a new IR major; a project adopts it through a migration PR against its `.factory/` copy.
- **Content** is the default's digest: SHA-256 over `workflow.dhall`, `roster.dhall`, `envelope.dhall`, `bindings.example.dhall`, and every file under `schema/`, sorted by repository path, each contributing its path, a NUL byte, and its LF-normalized bytes, written as `sha256:<hex>` (the spec's §4.6). `fixtures/` is excluded. Prompts, gate commands, default labels, and model defaults can change in place; the digest changes and the golden-IR diff shows what moved.
- There is one live `defaults/` directory. Old defaults stay in git history; tag them if a human-readable reference is wanted. Do not create `defaults/v1/` and `defaults/v2/` unless two shapes must be served at once.

## Golden IR

`fixtures/golden.ir.json` is the canonical compile of `defaults/` with `fixtures/bindings.dhall` and `fixtures/model-catalog.dhall`. CI recompiles, canonicalizes the JSON, and fails on any difference. It is a fixture, not any project's IR and not the prototype's IR.

## Vocabulary owned here

- **Metric keys.** Every measure id is one of the spec's §6.4 built-in semantic keys: `node.cycle_time`, `gate.verdict`, `review.findings`, `run.retries`, `run.tokens`, `run.cost`, `model.resolution`, `agent.outcomes`, `agent.liveness`, `agent.feedback_rounds`, `pr.feedback_rounds`, `pr.merge_latency`, `merge.queue_wait`, `tool.error_rate`, `agent.confusion_proxies`. v1 adds no custom semantic keys.
- **Labels.** The default label set is the only set in v1: the intake label `needs-triage` and the post-approval `ready-for-agent` label. Renaming and additions are post-v1.
- **Node ids.** Every node has a stable id and kind; its path is `workflowId + nodeId`. `Stage` is a display group, not an execution unit. The golden IR asserts node ids, edges, groups, and the entry/terminal nodes. The post-v1 Node View groups Runs, events, artifacts, and Gate reports under them.
- **Graph.** Every cycle has a bounded edge; the default graph includes the two-round feedback bound, the merge queue, the `pr-watch` trigger, and the `sync`/`rework` nodes. v1 carries one Workflow definition per Managed Project.

## Not here

The prototype under `prototype/workflow-authoring/` is evidence for authoring ergonomics, not a source for this directory. Do not lift its YAML, schema, or IR: its schema requires measures on every stage group, contradicting the spec's §4.7, its IR is stage-centric rather than node/edge (ADR-0010), and its Dhall was never compiled.
