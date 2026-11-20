# Capability control is containment: one Project Envelope, full agency inside the VM

Factory's v1 controls agency through the sandbox boundary rather than tool-level allowlists. Each Managed Project declares one **Project Envelope** in its Workflow Artifact — clone mode (`devvm --clone`), network tier and a named preset, an optional stable `extra_allow` list, and secret names — which Factory compiles into the project's devvm instance. The full network allowlist, provider endpoints, secret scopes, and secret values are local devvm configuration, not artifact fields (ADR-0009). Inside that VM, agents run with full permissions over their own copy of the repo. Everything leaving the VM is Factory-mediated: tracker label/state/close transitions run through Factory tools after the Triage Checkpoint, Factory owns PR creation and the merge capability, and devvm-blocked hosts surface as Egress Requests for the Owner to allow or deny. Role profiles are deferred to post-v1 as narrower envelopes compiled into the same surface.

## Considered Options

- **Fine-grained tool allowlists per role in v1** — rejected: duplicates what the VM already enforces, and every allowlist entry becomes a maintenance surface before the loop has proven itself.
- **No containment (agents on the host with worktrees)** — rejected: 002 established worktrees are workspace separation, not a security boundary; prompt-injected agents on the host can reach real credentials and files.
- **Full owner-managed VM configuration outside the artifact** — rejected: the containment contract stays in the Workflow Artifact; only the operational allowlist, provider endpoints, and secret scopes are local devvm config (ADR-0009).

## Consequences

- Blocked egress becomes an Owner workflow (request → allow/deny → applied locally and recorded), not a log entry discovered later. An approval is applied to the local devvm config and recorded with the applied rule in Factory's local SQLite; no artifact PR is required. A stable project host may be added to `extra_allow` by a separate PR, but that is a policy change, not the request record. A denial is recorded as a decision.
- Cost is tracked when the adapter reports usage; there is no `budget` field and no cap in v1. Runaways are visible, not prevented.
- The Project Envelope is the v1 tuning surface; capability profiles arrive post-v1 as stricter envelopes over the same compilation path.
- PR-format validators are reserved in the model but not built in v1; when they land they are deterministic Factory checks, never LLM judgments.

Status: accepted 2026-11-18 (wayfinder ticket: capability control model). Amended 2026-11-18: egress approvals persist as Workflow Artifact changes, with provisional application until merge. Amended 2026-11-20: that persistence is reversed — the artifact carries the containment contract (tier, preset, `extra_allow`, secret names), local devvm config carries the full allowlist and secret scopes, and egress decisions are recorded in SQLite (ADR-0009); the `budget` field is removed.
