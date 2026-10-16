---
title: Survey typed functional workflow languages for a Go Factory core
type: wayfinder:research
blocked-by:
- closed/001-research-harness-language.md
- closed/007-decide-harness-language.md
---

## Question

The owner requires workflow code to be **typesafe, and functional where possible** (standing input recorded on the map, 2026-10-16). Starlark — the Go-embeddable Python dialect from closed/001's default path — is untyped and fails this constraint, so the default is demoted. Survey the candidates as Factory's workflow-authoring language over the decided Go core, across the embedding strategies:

1. **Typed declarative config languages embeddable in Go** — Dhall via `dhall-golang`: how do loops, retries, human-approval gates, and step composition fit "orchestration-as-data" (workflow as a typed value the core interprets)? Evaluate ergonomics honestly, not just type soundness.
2. **Typed expression languages as guards** — cel-go (Google, official Go library): its scope and limits; whether a Dhall/CEL-style joint DSL (typed declarative definitions + typed guards) is coherent.
3. **Functional languages compiled to WASM, hosted in-process via wazero** (pure-Go runtime, no CGo) — GHC 9.6+ `wasm32-wasi` target, OCaml's WASM backend: maturity, binary size/startup, the host-import ABI for calling Factory primitives, and whether the wasm sandbox buys a real security story.
4. **External functional binaries over the versioned subprocess/JSON contract** — Roc, Gleam, F#/OCaml native: viability as first-class workflow authoring; what the contract must support (streaming, partial progress, inputs/outputs typing).

Weigh against the decided facts: harness core = Go (closed/007 ADR), RuntimeAdapter seam mandatory (closed/002). Note any untyped option that still deserves consideration despite the constraint, and say why.

Verdict must state: a recommended primary shape, the fallback order, maturity risks per candidate, and what a "hello world" workflow would look like **from the author's chair** — the ergonomics ticket that follows will build on this.
