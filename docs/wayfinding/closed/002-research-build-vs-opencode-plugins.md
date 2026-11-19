---
title: Build on OpenCode + plugins, or implement our own harness?
type: wayfinder:research
blocked-by: []
assignee: done
status: resolved
---

> **Superseded in part (2026-11-18).** The embedded-SDK recommendation in the Resolution below was superseded by [ticket 006](006-decide-harness-substrate.md) and ADR-0002: Factory runs OpenCode as a Factory-managed server and speaks to it over its API. The control-plane/runtime boundary, the "what Factory still needs to build" list, and the switching-cost analysis stand.

## Question

Should Factory run its agents through **OpenCode + plugins** (reusing its agent runtime, session model, permissions, skill system) or implement its own agent execution layer? Study T3 Code's orchestration (delegation, worktrees, scheduling, pull-request linking), pi.dev's approach, and https://github.com/paperclipai/paperclip for what each teaches about structure without spaghetti: how they draw the boundary between deterministic orchestration and agent autonomy. Verdict: concrete integration surface (what OpenCode would have to expose via plugins/SDK), what must still be built, and a recommendation with the switching cost if the choice later reverses.

## Resolution

### Verdict

Build a **hybrid**: Factory owns the deterministic workflow/control plane; OpenCode is the first agent-runtime adapter. Use OpenCode's embedded SDK (`@opencode/sdk`) to host agent sessions in-process, with a narrow Factory plugin for runtime-specific tools and policy. Do not make the workflow itself a plugin, and do not build a second model/tool/session runtime.

The boundary is: Factory decides *which work is eligible, who owns it, when it runs, what gates it must pass, and how outcomes/retries are recorded*. The agent decides *how to solve its assigned task*. Agents can propose decomposition or report blockers; Factory validates and records resulting state transitions rather than trusting an agent's narrative as a state change. This combines T3 Code's durable intent/effects split with Paperclip's task ownership and governance, while keeping Pi's useful lesson that the harness should be extensible rather than hardcoding every workflow into the runtime.

### OpenCode integration surface

The current V2 documentation already exposes enough surface for an initial local runner:

- **Host and lifecycle:** `OpenCode.create()` creates an explicitly owned embedded host; it exposes the generated client plus `sessions` and `events` aliases, and closes with `opencode.close()`. This avoids managing a separate HTTP listener for an in-process Factory.
- **Run a task:** create a session at a task worktree/location, choose an agent/model, submit a prompt, then wait for, interrupt, or inspect the session. Read session context/messages, diffs, and status to collect evidence and outcomes.
- **Observe:** subscribe to OpenCode's async event stream for session, message, tool, and permission activity. Treat events as telemetry/notifications; Factory's own durable run record remains authoritative.
- **Workspace:** use project worktree create/list/refresh/remove and VCS status/diff APIs for isolated local checkouts. Keep a task-to-project/worktree/session correlation in Factory.
- **Extend selectively:** register a plugin at host creation. Plugin transforms can define agents/models/tools/skills; runtime hooks can inspect/modify prompt admission, model context, tool execution, retries, and permission behavior. A Factory plugin can provide a small explicit tool surface (for example, report a blocker or request a review) and inject task context. Keep these hooks local to agent behavior, not the workflow state machine.
- **Policy:** OpenCode exposes session-scoped permission rules and pending-permission inspection/replies. Use explicit allow/ask/deny rules, but do not treat these rules as an OS sandbox: OpenCode documents shell as running with the host user's filesystem, process, and network authority, with best-effort directory inference.

Prefer the embedded SDK for the first implementation. The HTTP API is also usable if Factory later runs OpenCode as a separate service, but V2 documents label the HTTP API and multiple route families experimental. Pin a supported OpenCode version and hide it behind a `RuntimeAdapter`; add contract tests before depending on less stable endpoints. V1 plugin APIs differ from V2, so do not mix their contracts.

### What Factory still needs to build

OpenCode supplies agent execution, not Factory's product/workflow semantics. Factory still owns:

1. A durable task/run state machine, transactional claims/leases, idempotency keys, bounded retries, cancellation, crash recovery, and a scheduler/webhook trigger path.
2. Tracker adapters and normalized issue/task state; explicit human approval and review gates; durable audit history and attribution.
3. The end-to-end issue → triage → approved implementation → verification/review → PR → merge loop. OpenCode provides local workspace/VCS operations, but Factory needs hosting-provider PR create/link/status/check operations and merge policy.
4. Execution environment lifecycle and isolation. A Git worktree is useful workspace separation, not a security sandbox; use a separate OS/container/remote sandbox when tasks are untrusted or need stronger isolation.
5. Runtime adapter contract and persisted task context so an agent can be restarted or replaced. Persist task instructions, artifacts, session correlation, concise handoff summaries, and normalized outcomes outside the runtime transcript.

Keep the orchestration core as a small state machine plus effect runner: commit a valid transition and its effect intent first; perform runtime/provider/filesystem work outside that decision; feed its result back as a new event. Avoid a cross-cutting chain of plugins that each secretly advances workflow state.

### What the comparisons teach

- **T3 Code:** Its architecture separates deterministic command-to-event decisions from post-commit provider/filesystem effects, then records results back into orchestration. Its user-facing system also makes worktree-per-task, scheduling/webhooks, thread/PR links, PR watches, and settlement server-owned. It is a strong model for Factory's workflow boundary—not evidence that OpenCode should own Factory's state machine.
- **Pi:** Pi calls itself a minimal, extensible harness and intentionally leaves capabilities such as subagents and plan mode to extensions/packages. Extensions run inside Pi with the process's OS permissions. This supports a small runtime plus purpose-built extensions, but also shows why extensibility alone does not give Factory durable scheduling, isolation, or governance.
- **Paperclip:** Its adapter boundary launches a runtime and passes task/wakeup context, captures results/session state/usage, validates environment, and optionally parses transcripts or syncs skills. Its control plane separately owns issues, atomic checkout/run locks, routines, workspaces, approval gates, activity, budgets, and delegation. It currently has an OpenCode adapter that invokes `opencode run` and resumes via `--session`, proving the process/CLI adapter path works; Factory can use the richer embedded SDK while preserving the same control-plane/runtime boundary.

### Switching cost

**Moderate, manageable if the seam is kept now.** Switching *away* from OpenCode means implementing one replacement `RuntimeAdapter` and translating agent/model/permission/tool/skill configuration; OpenCode conversation transcripts and runtime-specific tool behavior will not automatically transfer. Factory should keep normalized task inputs, decisions, artifacts, diffs, and handoff summaries in its own records so work can resume with a fresh runtime session. Git branches/worktrees and PRs remain portable. The cost becomes high only if Factory stores workflow state in OpenCode plugin storage/transcripts, lets OpenCode own task claims/scheduling, or depends on undocumented internals. Switching *to* a custom runtime later has the symmetric runtime-build cost, but avoids rewriting the control plane.

### Sources

Primary sources reviewed (accessed 2026-10-14):

- OpenCode V2 [embedded SDK](https://opencode.ai/v2/docs/build/sdk), [plugins](https://opencode.ai/v2/docs/build/plugins), [HTTP API](https://opencode.ai/v2/docs/api), and [permissions](https://opencode.ai/v2/docs/permissions).
- T3 Code [architecture](https://github.com/pingdotgg/t3code/blob/main/docs/internals/overview.md), [working with threads/worktrees](https://github.com/pingdotgg/t3code/blob/main/docs/user/thread-sidebar.md), [project settings and scheduled tasks](https://github.com/pingdotgg/t3code/blob/main/docs/user/project-settings.md), and [source control/PR linking](https://github.com/pingdotgg/t3code/blob/main/docs/user/source-control.md).
- Pi [README](https://github.com/earendil-works/pi/blob/main/README.md) and [extensions guide](https://pi.dev/docs/latest/extensions).
- Paperclip [repository](https://github.com/paperclipai/paperclip), [issue API and checkout semantics](https://docs.paperclip.ing/reference/api/issues/), [heartbeats and routines](https://docs.paperclip.ing/guides/projects-workflow/routines/), [delegation](https://docs.paperclip.ing/guides/org/delegation/), [approvals](https://docs.paperclip.ing/guides/day-to-day/approvals/), [adapter boundary](https://docs.paperclip.ing/reference/adapters/overview/), and [OpenCode adapter](https://docs.paperclip.ing/reference/adapters/opencode/).
