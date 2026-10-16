# Factory harness core is implemented in Go

The Factory harness core is a long-running systems-and-integration service (process/network glue, SSH deploys, tracker adapters, agent-runtime supervision) rather than a compute kernel. We commit the core to **Go**: Tier-1 official MCP SDK plus official OpenAI/Anthropic clients, hardened goroutine/cancellation runtime daemon fit, and the simplest static-binary distribution. The owner's functional/memory-managed preference (Roc-like, Mojo-like) is honored by moving it to the **workflow-authoring layer**, not the core: workflow code must be typesafe and functional where possible, surveyed separately (see `docs/wayfinding/` research ticket on typed functional workflow languages). The untyped Starlark shape is demoted from default. The OpenCode/agent-runtime seam stays behind a `RuntimeAdapter` (hybrid substrate), so the core language does not lock the runtime choice.

## Considered Options

- **OCaml 5 + Eio** — the strongest functional alternative: mature language, effect-based Eio; rejected today for the core because Eio's I/O stack is young relative to Go's standard server stack and MCP/provider SDKs are community-only. Stands as the standing alternative.
- **TypeScript** — flips the owner's no-TS crux; only justified if in-process OpenCode SDK embedding becomes the defining requirement.
- **Mojo / Roc** — not production-ready as a harness foundation (Phase-2 roadmap incomplete; Roc pre-0.1 with RC platforms). Reassess on triggers above.

## Consequences

- Reopening triggers (any of these re-runs the language decision): Go integration work proving materially heavier than expected; Mojo's Phase-2 roadmap (async, package management, memory safety) landing; Roc reaching a stable 0.1 with platform stability; churn in the official Go MCP/provider SDK surface.
- Workflow user-code design lives on its own layer and ticket — core language choice does not dictate workflow ergonomics beyond the host contract (embedded typed-functional DSL vs versioned subprocess/JSON).

Status: accepted 2026-10-16 (wayfinder ticket: harness implementation language).
