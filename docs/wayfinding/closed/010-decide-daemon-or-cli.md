---
title: Decide — resident daemon vs CLI/cron invocation model
type: wayfinder:grilling
assignee: done
status: resolved
blocked-by:
- closed/002-research-build-vs-opencode-plugins.md
- closed/005-research-software-factory-landscape.md
---

## Question

Sketch both consumer models in the spec, then decide: a resident daemon owning scheduling, workflow runs, monitoring loops, and an API for agents/UI; or pure CLI/cron invocation with no resident process. Constraints to weigh: recurring monitors and deploys want a resident process; sandboxing and credentials want one owner; the owner's tolerance for running services; and what the chosen substrate makes cheap.

## Resolution

**Decided 2026-11-18 (HITL with the owner).**

1. **Resident daemon + thin CLI client.** One Go daemon owns queue, scheduling, workflow runs, VM lifecycle, gates, checkpoint delivery, and the audit log. The CLI is a client (`factory inbox`, `factory approve …`, `factory egress allow …`); a TUI/web UI comes later on the same API. This concentrates credentials and state in one owner, as the constraints require.
2. **Placement:** the owner's machine, run as a **systemd user unit**; Project VMs are devvm instances beneath it. Remote/worker mode is post-v1 (extraction on the same API).
3. **Intake:** **polling** the project's tracker on a configurable interval (webhook endpoints post-v1, when Factory is reachable). No public ingress required for v1.
4. **State:** a single **SQLite** database (WAL) on the daemon host: append-only transition log (audit truth), projections, snapshots, project-scoped rows. The daemon is the only writer.
5. **Client surface:** a typed **local JSON API over a Unix socket** (loopback TCP optional later). Commands are idempotent with persisted receipts; snapshots + subscriptions serve future UIs; even locally the client uses a scoped owner session — no client opens the database directly. T3 Code's shape (daemon owns the boundary, clients over authenticated RPC), sized to a single owner.
6. **Restart behavior:** on start the daemon reconciles tracker and PR state and resumes tasks idempotently from their last transition; a task whose VM state is gone goes **Blocked with evidence** for the Owner. No silent re-dispatch.
7. **VM lifecycle:** start a project's VM on first work; stop after a configurable idle period (default ~30 minutes). Keeps idle cost near zero and stays under devvm's concurrency cap.
8. **Consequences for other tickets:** deploy pipeline fog graduates (ticket 018); post-merge monitoring stays out of v1 (008); the runtime server (006) lives in the Project VM while the control plane stays on the host via `devvm host` + SSH.
