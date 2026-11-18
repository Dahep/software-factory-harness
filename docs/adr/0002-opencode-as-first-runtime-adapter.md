# Factory runs on OpenCode as the first RuntimeAdapter (hybrid substrate)

Factory's harness is a hybrid: a Go-owned deterministic control plane (workflow state, gates, approvals, tracker adapters, audit, scheduling, isolation) with each agent runtime behind a `RuntimeAdapter`. OpenCode is the v1 adapter, run as a Factory-managed server per instance and spoken to over its API; a T3 Code–shaped contract (typed Task in / Outcome out, normalized telemetry events, declared capabilities, driver-vs-instance separation) keeps the seam honest, and a test double — not a second real runtime — proves it in v1. Factory owns the agent-flow state; the runtime owns only execution. Durable state is an append-only transition log with projections and snapshots, retained long under the measure-everything directive.

## Considered Options

- **Own runtime from scratch (Go + MCP SDK)** — rejected: re-implements model/tool/session runtime, which the build-vs-buy research explicitly warned against.
- **OpenCode-only (plugin/workflow layer, no independent control plane)** — rejected: no durable state ownership, and the Swamp `@swamp/software-factory` prior art demonstrates the ceiling of a pack with zero control over the driving agent.
- **Harness-neutral v1 (OpenCode + Pi + Claude Code simultaneously)** — deferred: adapter-matrix upkeep before the issue loop exists; neutrality stays a property of the seam, not of v1's shipping surface.

## Consequences

- Runtime configurations are Factory-managed artifacts per managed project; host auth stays host-level.
- Capability enforcement lives in the adapter + a minimal Factory plugin; an optional sandboxed composition surface is reserved as a capability, never conflated with the typed workflow graph.
- Architectural lock-in is bounded: swapping runtimes means one adapter replacement plus translating agent/model/permission/tool config; Factory's durable records and artifacts stay portable.

Status: accepted 2026-11-18 (wayfinder ticket: harness substrate).
