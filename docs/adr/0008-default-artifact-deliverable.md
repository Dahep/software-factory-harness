# The default Workflow Artifact is a versioned deliverable

Factory ships one **Default Workflow Artifact** in `defaults/`: the typed workflow, Agent Roster, envelope, schema, a bindings example, and a golden IR compiled from fixture bindings. Project Init renders it into a Managed Project's `.factory/` and writes the project's `bindings.dhall` — primary models per seat, build/test commands, provider names and endpoints, and provenance (`irVersion` + content digest). The IR major is the shape version; the content digest is the exact default. Content changes update `defaults/` in place; a shape change bumps the IR major and is adopted by a migration PR against each project. The default is a seed, not a dependency: no inheritance, no propagation, no automatic upgrades. The golden IR is a fixture compile for CI drift checks, never a production artifact.

## Considered Options

- **Per-project default with no Factory source** — rejected: copy-on-init has no source, and every project reinvents the Loop's ids, labels, and measures.
- **A separate defaults repository** — rejected for v1: distribution, versioning, and authentication overhead for one Owner; a candidate for the post-v1 registry.
- **Immutable `defaults/v1/`, `defaults/v2/` directories** — rejected: copy-on-init means each project keeps its own copy, so old shapes can live in git history; a live old-shape directory is only needed if two shapes must be served at once.
- **Render concrete files at init** — rejected for v1: it needs a Dhall value-to-source renderer. A typed generator plus `bindings.dhall` is a smaller, reviewable init surface; a project can flatten its copy later.
- **Inheritance (`extends` + overrides)** — rejected: ADR-0006 already chose copy-on-init with PR-only deviation and no merge semantics.
- **Promote the prototype as the default** — rejected: its schema mandates measures against §4.7, its IR drops the poll trigger, and its Dhall was never compiled. It remains evidence.

## Consequences

- `defaults/` is the conformance gate's subject; §1.5 #6 is falsifiable against `defaults/fixtures/golden.ir.json`.
- `bindings.dhall` is the init surface and carries provenance; there is no separate provenance file.
- Metric ids are the built-in semantic keys of §6.4; the default declares the set, and v1 allows no custom semantic key.
- The default label set is the v1 set; renaming and additions are post-v1, when the tracker projection becomes data.
- Every Workflow element gets a stable node id in the IR and the golden IR; grouping Runs and events under a node is the post-v1 Node View (candidate 4b).
- A shape migration is a PR against the project's copy; a content change never propagates.
- Project Init writes `bindings.dhall`; it does not copy an old default or upgrade one silently.

Status: accepted 2026-11-20 (architecture review, candidate 2: default artifact).
