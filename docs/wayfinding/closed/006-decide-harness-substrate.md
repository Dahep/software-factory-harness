---
title: Decide — build on OpenCode + plugins or implement our own harness?
type: wayfinder:grilling
assignee: done
status: resolved
blocked-by:
- closed/002-research-build-vs-opencode-plugins.md
- closed/005-research-software-factory-landscape.md
---

## Question

Which execution substrate does the spec commit to: OpenCode + plugins, an own agent runtime, or a hybrid (own orchestration layer calling OpenCode as the agent runtime for session work)? Weigh the 002 findings (integration surface, switching cost) against the 005 landscape findings (what structures the industry proved). HITL: the owner makes this call with the research in view.

## Resolution

**Decided 2026-11-18 (HITL with the owner), after research tickets 002, 005, 012, 013, 014, 015.**

**Decision: hybrid substrate, OpenCode-first.** Factory's Go control plane owns the deterministic plane (run state, scheduling, claims/leases, gates, tracker adapters, audit, execution isolation, workspace mediation); the agent runtime sits behind a `RuntimeAdapter`; OpenCode is the v1 adapter; a test double proves the seam, no second real adapter ships in v1. Rejected: own runtime from scratch (re-implements a session runtime — what 002 forbade), OpenCode-only/plugin-layer (no independent control plane — contradicted 002's state-ownership findings and 013's zero-control ceiling), harness-neutral v1 across three runtimes (adapter-matrix upkeep before the loop exists; neutrality is preserved by the seam instead).

### The seam (T3 Code's provider architecture as the reference)

T3 Code's own docs (`docs/internals/providers.md`, `overview.md`) were studied on 2026-11-18; its multi-provider pattern (opencode/pi/codex/claude/grok/antigravity) is the model:

1. **Factory-managed OpenCode server per instance.** Factory starts, version-probes, idles-out, and talks to an OpenCode server over its API (T3's 2.x per-instance server model). Plugin and permission wiring live in the adapter. External-server mode is post-v1.
2. **Adapter contract, T3-shaped:**
   - typed **Task in** (prompt, workspace ref, capability-profile ref, budget) → typed **Outcome out** (status, artifacts, diff ref, transcript ref, usage);
   - a **normalized event stream** for telemetry (session/message/tool/permission) — telemetry, never workflow state;
   - an explicit **capability descriptor** per driver (streaming, steer/interrupt, checkpoints, rollback, sandboxed composition, native option IDs) — adapters must declare what they can actually do, and Factory must not assume more;
   - **driver kind vs instance** split so two configurations/accounts never share mutable session or catalog state;
   - native permission/question option IDs survive normalization (display labels are not valid replies);
   - no setup as a health-check side effect (session opens can trigger MCP servers/hooks/logins).
3. **Minimal Factory plugin in v1.** One narrow plugin exposing Factory tools (report blocker, attach artifact, read gate status), injecting task context, and enforcing permission rules. No workflow state advances inside the plugin (002's rule).
4. **Factory-managed project runtime config.** A versioned OpenCode config per managed project (agents, models, tools, policies) stored and reviewed like any artifact; host credentials/auth stay host-level. No dependence on the host's global config for correctness.
5. **Composition surface reserved, not built.** An optional sandboxed script-composition capability (Pi Codemode's harness-side QuickJS/WASM reference design, per ticket 015) is named as a future adapter capability. v1 does not depend on it; code-mode scripts never become the typed workflow graph — only promotion through typing and review bridges them.

**Durable state:** append-only transition log as audit truth with long retention (measure-everything directive #15, ticket 004), read projections for speed, snapshots to bound replay. DeltaDB's operation-log pattern (ticket 014) was adopted as vocabulary/simplification input, not as a store.

**Consequences:** ticket 007's deferred OpenCode-seam question is answered (managed server + API, not embedded SDK). Ticket 009 inherits: permission enforcement happens in the adapter/plugin layer plus sandbox-as-capability; exposure modes belong in capability profiles. Ticket 008 inherits: composition happens inside agent steps; gates remain graph-owned; a gate is never a plugin/script. Ticket 010 inherits: Factory-managed runtime servers are a resident-process argument.

**Amendment (2026-11-18, with the spec).** The Task-in `capability-profile ref` is the **Project Envelope reference** in v1: ADR-0004 ships no role profiles, so there is nothing narrower to point at. The field stays in the contract for post-v1 Capability Profiles; Factory validates it against the project's compiled envelope.

**Amendment (2026-11-19).** Item 4's Factory-managed project runtime config is superseded by ADR-0007: each Managed Project owns an Agent Roster in `.factory/roster.dhall`, compiled into the IR. Host credentials and provider auth stay host-level, and Factory stores no secret values.

**Amendment (2026-11-20, ADR-0009).** Item 2's Task-in drops `budget`: v1 has no budget field and no cap, and cost is tracked only when the adapter reports usage.
