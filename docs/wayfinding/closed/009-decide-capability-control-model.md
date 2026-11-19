---
title: Decide — capability control model (profiles vs profiles + always-ask)
type: wayfinder:grilling
assignee: done
status: resolved
blocked-by:
- closed/002-research-build-vs-opencode-plugins.md
- closed/003-research-tracker-adapters-and-permissions.md
---

## Question

Owner leans toward named role profiles (implementer, reviewer, deployer…) with per-workflow overrides, optionally plus always-ask prompts for high-risk actions (deploy, secrets, destructive ops) pending research. Settle the exact model: what a profile can express (tools, machines, trackers, autonomy, spend limits), how always-ask fits, and how it maps onto the chosen harness's permission primitives.

## Resolution

**Decided 2026-11-18 (HITL with the owner), after 012, 013, 015, 017 and the Project-VM decision.**

**v1 is containment-first: no role-profile system.** Agency lives inside the Project VM, not in per-tool allowlists.

1. **One Project Envelope per Managed Project**, declared in the Workflow Artifact and compiled into devvm by Factory (the artifact is the single source of truth; the VM is never hand-configured differently):
   - **clone mode** — `devvm --clone`, so the VM holds its own copy and the real local repo is never mounted;
   - **network tier + allowlist** — `allowlist` tier with a **developer preset** (github.com/api.github.com, configured model-provider endpoints, common package registries), human-editable;
   - **secret bindings** — the project's GitHub token and the model-provider credentials the runtime needs (devvm placeholders + host-scoped injection);
   - **spend measurement** — recorded per Task; **no hard cap in v1**.
2. **Agents run with full permissions inside the VM** — filesystem, tools, installs, and the copied repo are theirs. OpenCode runs unrestricted inside the sandbox.
3. **Tracker authority is split:** comments/reads via `gh` directly; **label/state/close transitions go through Factory tools** (Triage proposes → Owner approves → Factory applies), so every transition is recorded and gate-checked.
4. **PRs and merge:** the agent pushes its branch from inside the VM with the scoped token; **Factory opens and owns the PR and holds the merge capability** (v1 merge Checkpoint from ticket 008 unchanged). Agent may propose PR title/body; **workflow-defined PR validators** (deterministic, run by Factory on the PR; not LLM judgment) are reserved for post-v1, not built in v1.
5. **Always-ask:** nothing beyond the merge Checkpoint. The VM bounds network, secrets, and clone; stage permissions bound Factory-mediated actions; every action is logged.
6. **Egress requests surface to the Owner:** a devvm-blocked host (with method, path, reason from `devvm network log --json`) becomes an **Egress Request**; approval adds the host to the project's allowlist, denial is recorded, and both decisions are measured.
7. **Post-v1 direction (recorded, not built):** per-role **Capability Profiles** as narrower envelopes (network subset, secret subset, Factory-reach subset, budget) compiled into the same devvm config and OpenCode permission refinements. The artifact remains the single source of truth; profiles never become a second configuration surface.

Glossary: added **Project Envelope**, **Egress Request**, **Capability Profile** (post-v1) to `CONTEXT.md`.

**Amendment (2026-11-18, with the spec).** An approved Egress Request is persisted as a **Workflow Artifact change** — a PR against the project's `envelope.dhall` — because ADR-0004/ADR-0006 make the artifact the single source of truth. Factory may apply the approved rule to the running Project VM immediately, recorded as provisional until the PR merges; a rejected PR revokes it at the next compile. Denials are recorded as decisions, not artifact changes.
