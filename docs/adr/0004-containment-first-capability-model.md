# Capability control is containment: one Project Envelope, full agency inside the VM

Factory's v1 controls agency through the sandbox boundary rather than tool-level allowlists. Each Managed Project declares one **Project Envelope** in its Workflow Artifact — clone mode (`devvm --clone`), network tier and allowlist (developer preset), secret bindings (GitHub + model providers), and spend measurement — which Factory compiles into the project's devvm instance. Inside that VM, agents run with full permissions over their own copy of the repo. Everything leaving the VM is Factory-mediated: tracker label/state/close transitions run through Factory tools after the Triage Checkpoint, Factory owns PR creation and the merge capability, and devvm-blocked hosts surface as Egress Requests for the Owner to allow or deny. Role profiles are deferred to post-v1 as narrower envelopes compiled into the same surface.

## Considered Options

- **Fine-grained tool allowlists per role in v1** — rejected: duplicates what the VM already enforces, and every allowlist entry becomes a maintenance surface before the loop has proven itself.
- **No containment (agents on the host with worktrees)** — rejected: 002 established worktrees are workspace separation, not a security boundary; prompt-injected agents on the host can reach real credentials and files.
- **Owner-managed VM configuration outside the artifact** — rejected: two sources of truth drift; the Workflow Artifact must remain authoritative.

## Consequences

- Blocked egress becomes an Owner workflow (request → allow/deny → recorded), not a log entry discovered later. An **approval is persisted as a Workflow Artifact change** (a PR against the project's `envelope.dhall`); Factory may apply the approved rule to the running Project VM immediately, recorded as provisional until the change merges. A denied Egress Request is recorded as a decision, not as an artifact change.
- Spend is measured per Task but not capped in v1; runaways are visible, not prevented.
- The Project Envelope is the v1 tuning surface; capability profiles arrive post-v1 as stricter envelopes over the same compilation path.
- PR-format validators are reserved in the model but not built in v1; when they land they are deterministic Factory checks, never LLM judgments.

Status: accepted 2026-11-18 (wayfinder ticket: capability control model). Amended 2026-11-18: egress approvals persist as Workflow Artifact changes, with provisional application until merge.
