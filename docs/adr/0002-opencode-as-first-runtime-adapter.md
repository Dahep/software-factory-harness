# Factory runs on OpenCode as the first RuntimeAdapter (hybrid substrate)

Factory's harness is a hybrid: a Go-owned deterministic control plane (workflow state, gates, approvals, tracker adapters, audit, scheduling, isolation) with each agent runtime behind a `RuntimeAdapter`. OpenCode is the v1 adapter, run as a Factory-managed server per instance and spoken to over its API; a T3 Code–shaped contract (typed Task in / Outcome out, normalized telemetry events, declared capabilities, driver-vs-instance separation) keeps the seam honest, and a test double — not a second real runtime — proves it in v1. Factory owns the agent-flow state; the runtime owns only execution. Durable state is an append-only transition log with projections and snapshots, retained long under the measure-everything directive.

## Considered Options

- **Own runtime from scratch (Go + MCP SDK)** — rejected: re-implements model/tool/session runtime, which the build-vs-buy research explicitly warned against.
- **OpenCode-only (plugin/workflow layer, no independent control plane)** — rejected: no durable state ownership, and the Swamp `@swamp/software-factory` prior art demonstrates the ceiling of a pack with zero control over the driving agent.
- **Harness-neutral v1 (OpenCode + Pi + Claude Code simultaneously)** — deferred: adapter-matrix upkeep before the issue loop exists; neutrality stays a property of the seam, not of v1's shipping surface.

## Consequences

- Runtime configuration is the Managed Project's Agent Roster in `.factory/roster.dhall` (ADR-0007): project-owned, compiled into the IR, and validated by Factory against the adapter's Model Catalog. Host and provider auth stay host-level; Factory stores no secret values.
- A model exhaustion is a typed failed Outcome returned to the agent node that dispatched the session, whose failure edge decides the next step; the adapter never substitutes outside the entry's declared model list (ADR-0007).
- Capability enforcement lives in the adapter + a minimal Factory plugin; an optional sandboxed composition surface is reserved as a capability, never conflated with the typed workflow graph.
- Architectural lock-in is bounded: swapping runtimes means one adapter replacement plus translating agent/model/permission/tool config; Factory's durable records and artifacts stay portable.

Status: accepted 2026-11-18 (wayfinder ticket: harness substrate). Amended 2026-11-19: runtime configuration is the project-owned Agent Roster (ADR-0007); adapter Outcomes carry failure reasons and attempt trails. Amended 2026-11-22: a model exhaustion is returned to the agent node, and the adapter declares session liveness (`heartbeat`, `idle-timeout-only`, or `none`) (ADR-0010).
