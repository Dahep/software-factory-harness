# Workflow authoring — throwaway prototype (ticket 016)

**Question:** what does writing Factory's default Loop actually feel like? Is the artifact YAML + JSON-Schema, Dhall, or raw JSON IR?

This directory is a prototype. Nothing here ships.

## What to look at

| File | What it is |
| --- | --- |
| `default-loop.yaml` | The v1 Loop from ADR-0003, written as YAML with a schema |
| `default-loop.schema.json` | The JSON-Schema the YAML is validated against |
| `default-loop.dhall` | The same Loop in Dhall (illustrative; no `dhall` binary on this machine — `dhall type/dhall format` would be the real workflow) |
| `default-loop.ir.json` | What the Go engine would consume — the compiled form |
| `validate.py` | Runs the structural checks the harness would run; edit the YAML and re-run |

## Try it

```sh
cd prototype/workflow-authoring
python3 validate.py default-loop.yaml     # passes
# now break something:
#   - delete a gate's onFail      → should fail with the gate named
#   - point a checkpoint at a missing stage → should fail
#   - remove a stage's measure     → warns (directive #15: unmeasured stage)
```

## Side-by-side, roughly

YAML:
```yaml
stages:
  - id: review
    wave:
      agents:
        - { role: reviewer, persona: spec-fidelity }
        - { role: reviewer, persona: adversarial }
    gates:
      - id: review-verdict
        check: all-reviewers-agree
        onFail: { retry: 2, then: block }
```

Dhall:
```dhall
review =
  Stage::{
  , id = "review"
  , wave = Some Wave::{ agents = [ reviewer "spec-fidelity", reviewer "adversarial" ] }
  , gates = [ Gate::{ check = ReviewVerdict, onFail = Retry 2 Block } ]
  }
```

JSON IR (compiled):
```json
{ "id": "review", "wave": { "agents": [...] }, "gates": [{ "check": {...}, "onFail": {...} }] }
```

## What this prototype is testing

1. **Verbosity** — does the loop read as a loop, or as config soup?
2. **Gate + failure policy legibility** — `onFail` is the newest concept; can you see what a failing gate does without opening a schema?
3. **Waves** — does "one implementer, two reviewers" read clearly?
4. **Envelope adjacency** — does the Project Envelope belong in the same file?
5. **Reuse** — how would a project deviate without forking the default? (Dhall functions/imports vs YAML `extends`/anchors — prototype only sketches the YAML side.)
6. **Measurement** — is declaring metrics per stage a burden or a useful forcing function?

## Known gaps in this prototype

- Dhall file is unchecked (no binary); it is syntax-shaped, not compiled.
- No real schema evolution/versioning story shown.
- The YAML `extends`/override mechanism is described, not implemented.
