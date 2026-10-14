---
title: Which implementation language for the Factory harness (and why)
type: wayfinder:research
blocked-by: []
assignee: research-dispatch
---

## Question

Which memory-managed (or opt-in-memory-managed) language should the Factory harness itself be implemented in — weighing the owner's preference for functional languages, agent-ecosystem glue (LLM SDKs, MCP, subprocess/process supervision, git, SSH ops), single-binary distribution, long-running daemon reliability, and extension story? Candidates to compare honestly: **Roc**, **Mojo**, **Go**, **OCaml**, **TypeScript** (baseline for ecosystem fit), and any the research surfaces. Verdict must state: maturity/stability risk, ecosystem fit for LLM/tooling glue, ergonomics for user-defined workflow code interoperability, and a recommendation with escape hatches.

## Question (owner's crux)

No TypeScript unless the ecosystem argument is overwhelming; the owner leans functional (Roc-like) or memory-managed-with-optional-control (Mojo-like).
