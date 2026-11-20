# Factory runs as a resident daemon with thin clients

Factory's process model is a single resident Go daemon on the owner's machine (systemd user unit) that owns the queue, scheduling, Project VMs, gates, checkpoints, and the audit log; the CLI is a client of a typed local JSON API over a Unix socket, with idempotent commands and persisted receipts. Durable state is one SQLite database holding the append-only transition log, projections, and snapshots, and the daemon is its only writer. Intake polls the tracker on an interval; webhooks come later. On restart the daemon reconciles with tracker and PR state and resumes tasks from their last transition, blocking any task whose VM state vanished.

## Considered Options

- **Pure CLI/cron with no resident process** — rejected: it cannot hold approvals, watch the tracker, or keep the runtime server/VM warm, and it fragments credentials across invocations.
- **Daemon with API only (no CLI)** — rejected: the owner would have no surface until a UI exists.
- **CLI reading SQLite directly** — rejected: multiple writers, no receipts, no path to future UIs.
- **Webhook-first intake** — deferred: requires public ingress on the owner's machine before the loop exists.
- **Full T3-style scoped multi-client auth** — deferred: one owner on one machine needs a scoped owner session, not pairing/DPoP machinery.

## Consequences

- One writer and one credential owner; backups are one SQLite file.
- The API boundary is stable enough that a TUI/web UI is additive, and remote/worker mode becomes an extraction rather than a rewrite.
- Idle Project VMs stop; task start pays a VM start cost.
- Deploy-pipeline design becomes specifiable (its last dependency was this decision).

**Amendment (2026-11-20, ADR-0010).** No decision here is reversed; the client surface is specified. "Typed local JSON API" is the **Client Contract** (`factory-api/v1`): commands, queries, and subscriptions, with the operation id as the identity and JSON Schema as the field-level contract. "Persisted receipts" are rows in this SQLite database, inserted with the intent transition and updated with the effect's outcome. "Snapshots + subscriptions" is two feeds with different guarantees — the durable feed (gapless, replayable after a snapshot, cursor-resumed) and the live telemetry feed (lossy, reporting its loss). "Scoped owner session" is a per-start bearer token file at `0600` with a Linux `SO_PEERCRED` check and declared operation scopes whose v1 grants are broad. The contract itself is [`docs/spec/API.md`](../spec/API.md).

Status: accepted 2026-11-18 (wayfinder ticket: resident daemon vs CLI/cron). Amended 2026-11-20: the client surface is specified as the Client Contract, two feeds, receipts co-committed with their intent transitions (ADR-0010); no decision reversed.
