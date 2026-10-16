---
title: Decide — harness implementation language
type: wayfinder:grilling
assignee: done
status: resolved
blocked-by:
- closed/001-research-harness-language.md
- closed/002-research-build-vs-opencode-plugins.md
---

## Question

Which language does the spec commit the harness to? The owner leans functional / memory-managed (Roc, Mojo) and is skeptical of TypeScript unless its ecosystem argument is overwhelming. Decide with 001's comparison in view, cross-checked against 002's findings about what glue must exist (MCP, SDKs, process/SSH supervision) and against the workflow user-code story (separate decision on workflow ergonomics follows).

## Resolution

**Decided 2026-10-16 (HITL with the owner).**

1. **Harness core = Go.** The owner accepted the 001 verdict: the operational/ecosystem case (Tier-1 MCP SDK, official provider clients, hardened daemon runtime, static distribution) outweighs the functional/memory-managed preference *for the core*. Recorded as ADR: `docs/adr/0001-harness-core-language-go.md`, with reopening triggers (OCaml standing alternative; Mojo Phase-2; Roc 0.1 stability; TS only if in-process embedding becomes the defining requirement).
2. **OpenCode seam cross-check deferred to ticket 006 (substrate).** Going Go means OpenCode sits behind a process/network boundary (CLI adapter proven by Paperclip; HTTP API V2-experimental; TS sidecar possible; Go-native runtime possible via the official Go MCP SDK). The owner chose to leave this cost unknown until 006 decides; the `RuntimeAdapter` seam from closed/002 stays mandatory either way.
3. **Workflow user-code constraint tightened:** code must be **typesafe, and functional where possible**. This demotes Starlark's untyped-Python shape from default and graduates the map fog into research ticket *Survey typed functional workflow languages for a Go Factory core* (Dhall, cel-go guards, WASM-hosted Haskell/OCaml, external Roc/Gleam/OCaml binaries). The coarse shape (embedded DSL vs subprocess/JSON contract) follows that survey; full ergonomics remain fog.
4. **ADR-grade recording confirmed by the owner** — see the ADR above; the language decision is documented as an ADR (not just a spec line), with the family of rejected candidates and reopen triggers.
