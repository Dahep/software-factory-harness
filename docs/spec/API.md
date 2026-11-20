# Factory Client Contract — `factory-api/v1`

**Status:** build-ready planning artifact · 2026-11-20 · companion to [`SPEC.md`](SPEC.md); the shape is [ADR-0010](../adr/0010-client-contract.md).

**What this is.** Every Factory client speaks this contract and nothing else: the CLI, the post-v1 Project Console, the Node View, the Project Assistant, and whatever surface comes after them. It defines the transport, the envelopes, the operations v1 ships, the operations v1 reserves, the guarantees of the two feeds, and what a client may never do. It is the answer to the question ADR-0005 and ticket 010 answered only in outline: *what exactly goes over the socket?*

**Relationship to the record.** ADR-0005 fixes the architecture (resident daemon, thin clients, one SQLite writer, idempotent commands, persisted receipts, a scoped Owner session, no client opens the database); ticket 010 fixes the client surface's class (typed JSON over a Unix socket, loopback TCP later) and names T3 Code's shape as the reference. [ADR-0010](../adr/0010-client-contract.md) decides the shape below and records the rejected alternatives. This document is normative for the contract; ADR-0010 records the decision, so a divergence between the two is an ADR amendment, not a silent choice by either. Where this document is silent, the ADR and the closed tickets win. Bare `ADR-000N` and `ticket NNN` references resolve through [`SPEC.md` §11](SPEC.md#11-source-index), and the glossary is [`CONTEXT.md`](../../CONTEXT.md).

**⟨default Dn⟩ markers** are spec defaults introduced here and collected in [`SPEC.md` §9.2](SPEC.md#92-spec-defaults-introduced-here); today that is D13 (runtime paths) and D14 (initial limits and timings).

**Spec and ADR only.** This is a planning artifact: no server, no client, no schema files. A later effort implements it.

**Contents.** [1 Purpose, scope, non-goals](#1-purpose-scope-non-goals) · [2 The model](#2-the-model-commands-queries-subscriptions) · [3 Transport and session](#3-transport-and-session) · [4 Envelopes and frames](#4-envelopes-and-frames) · [5 Errors](#5-errors) · [6 Receipts, idempotency, stale targets](#6-receipts-idempotency-and-stale-targets) · [7 The two feeds](#7-the-two-feeds) · [8 v1 operations](#8-v1-operations-and-the-projections-they-read) · [9 Reserved post-v1 resources](#9-reserved-post-v1-resources) · [10 Clients](#10-clients-the-cli-and-the-fake-second-client) · [11 Fog](#11-fog-and-deferred) · [12 Candidate-4 review](#12-candidate-4-review-record) · [13 Sources](#13-sources)

---

## 1. Purpose, scope, non-goals

### 1.1 Purpose

The daemon owns all durable state; the contract is the only way in or out for a client. Two things follow, and they are the whole point of writing it down:

1. **The seam is the deliverable.** A future TUI, web UI, assistant, or remote worker is an extraction on this contract, not a rewrite of it (ADR-0005's consequence). The next surface is cheap only if this contract is complete enough for a surface that does not exist yet.
2. **The boundary is testable.** A fake second client — not the CLI, not sharing its code — proves the contract carries a real surface's work: read the inbox, decide a checkpoint, follow a run live, reconnect across a restart (§10.2). Without that test, "the boundary is stable" is an assertion, not a property.

### 1.2 Scope

In scope: the client boundary of the v1 daemon on one machine for one Owner — transport, session, envelopes, operations, receipts, feeds, errors, versioning, capability discovery, the v1 operation set, and the named post-v1 reservations.

Workflow semantics, Gate behaviour, containment, and the tracker adapter are not restated here; they are [`SPEC.md`](SPEC.md) §§2–6. This document says only what a client can ask for and what it is promised back.

### 1.3 Non-goals

Out of scope by decision:

- **A public or remote surface.** No TLS, no reverse proxy, no third-party authentication, no deprecation policy for strangers. Loopback TCP for a same-host non-CLI client is the only named step beyond the socket (ticket 010), and it is fog (§11).
- **Multi-user access.** One Owner, one principal, one session (ADR-0005). Operation *scopes* exist so a narrower surface is possible later; *grants* do not narrow in v1.
- **An agent-facing surface.** Agents talk to the runtime inside the Project VM. The minimal Factory plugin's tool channel (`SPEC.md` §2.4) is a separate, narrower surface, out of scope here, and it must never carry the Owner session (§11).
- **Tracker or webhook ingress.** Intake polls; nothing inbound is exposed (ADR-0005).
- **Workflow writes.** No operation sets Task state, records a Gate verdict, or advances a Stage. Checkpoint decisions and Egress decisions are *recorded commands*, not state writes: Factory translates them into transitions (§8.4).
- **Secret values.** No operation carries, returns, or stores one (`SPEC.md` §5.5).
- **A resource-shaped REST surface.** Nothing here is designed for caches, intermediaries, or browsers-first clients (§12, rejected alternatives).

---

## 2. The model: commands, queries, subscriptions

Three kinds of client operation. The kind is a property of the operation in the **operation index** (§8.2, plus §9's reserved rows), not of the URL, and it fixes the shape of the guarantee: a command's at-most-once application, a query's read point, a subscription's stream. One refinement: a subscription's *delivery* guarantees are fixed by the feed it names (§7), not by the kind — the kind says "stream of frames", the feed says whether that stream is gapless or lossy.

| Kind | Semantics | Idempotency | Returns |
| --- | --- | --- | --- |
| **Command** | Asks Factory to record a decision or perform an effect | Required key; at most one application per key; a retry returns the recorded receipt | A **receipt** plus result refs |
| **Query** | Reads a projection at a point in the log | None needed: side-effect free | State plus the `asOf` log sequence |
| **Subscription** | Opens a feed and streams frames until closed | Resume by cursor, not by key | A stream of frames |

Rules that hold across all three:

- **The operation id is the identity.** `checkpoint.decide` means the same thing in every client, every version, and every doc. Ids are `<resource>.<action>`; both halves are stable strings in the operation index, and no client derives an id it was not given.
- **Nothing in the request is trusted that the session can supply.** The actor is the session's principal, the time is the daemon's clock, the sequence is the daemon's. A client may describe *what it wants*; it may not claim *who it was* or *when* (audit integrity, `SPEC.md` §2.3).
- **Targets are refs, artifact content travels in the request.** No operation takes a host filesystem path (§3.6). This is what keeps remote/worker mode an extraction (ADR-0005) and closes a path-traversal class before it exists.
- **Artifacts, never secrets.** A request may carry Workflow Artifact file content (relative paths only) because a client validates before it pushes; it may never carry a secret value, and no response ever contains one.

### 2.1 What a client may not do

| Never | Because |
| --- | --- |
| Open the SQLite database, read or write | One writer; receipts and scopes are unenforceable otherwise (ADR-0005) |
| Claim an actor, timestamp, or sequence | The audit record's integrity (`SPEC.md` §2.3) |
| Pass a filesystem path as a target | Host-agnostic contract; traversal; remote mode (§3.6) |
| Record a Gate verdict or set a Task state | Gates are harness-evaluated; only a committed transition advances a Task (`SPEC.md` §2.4) |
| Mutate the tracker or open a PR directly | Those are Factory effects, not client effects (`SPEC.md` §3.9, §5.3) |
| Carry, log, or echo a secret value | Secrets are host-side by name only (`SPEC.md` §5.5) |
| Treat a subscription as state | Feeds report; the transition log decides (§7) |

---

## 3. Transport and session

### 3.1 Two endpoints: HTTP/1.1, JSON, a Unix socket

Requests are `POST /v1/rpc` on an HTTP/1.1 server listening on a Unix domain socket. The body is one JSON object; the `operation` field selects the operation. The response framing is decided by the operation's kind, not by the URL: one JSON object for a command or query, newline-delimited JSON frames for a subscription (`Content-Type: application/x-ndjson`, §4.3).

**The envelope carries the outcome, not the HTTP status.** Every response the daemon produces is HTTP `200`; `status` and `error.code` in the envelope are authoritative, including for `unauthenticated` and `forbidden_scope`, so a client has one place to look. HTTP status codes appear only where no envelope can be produced — a malformed HTTP request, an unknown method or path, or a `/v2/` path this daemon does not serve — and those responses carry no envelope.

`GET /v1/health` is the only other endpoint: unauthenticated, carrying no project state, `200` with `{status, apiVersion, serverVersion}`. It exists so a client can tell "daemon down" from "daemon refusing" and so systemd and the seam test have a liveness probe with nothing behind it.

**Paths ⟨default D13⟩.** Socket `$XDG_RUNTIME_DIR/factory/d.sock`, directory mode `0700`, socket mode `0600`; session token `$XDG_RUNTIME_DIR/factory/session.token`, mode `0600`; falling back to `~/.local/state/factory/` when `XDG_RUNTIME_DIR` is unset. The CLI takes an override flag; nothing else reads these paths.

### 3.2 Why HTTP/JSON over the socket

- **Stdlib only.** Go serves and dials a Unix socket with `net/http` and a `DialContext`; no protocol library, no codegen, no schema runtime in the request path.
- **Inspectable by hand.** `curl --unix-socket … -d '{"operation":"inbox.query",…}'` plus `jq` is a complete client, which is both the debugging story and half the seam test (§10.2). The Owner can read the boundary without writing code.
- **Framing is solved.** Status codes, `Content-Type`, chunked streaming bodies, timeouts, and half-close are HTTP's problems, not ours. A hand-rolled NDJSON socket protocol re-earns nothing and loses all of it.
- **Loopback TCP later is a listener change.** Same envelopes, same operations, same client code with a different dialer (ticket 010's "optional later").

The rejected alternatives are recorded once, in [ADR-0010](../adr/0010-client-contract.md)'s *Considered Options*; the load-bearing one is gRPC/protobuf, which would add a toolchain, a codegen step, and a second encoding to a boundary that is already JSON everywhere — the compiled IR is JSON (`SPEC.md` §4.3), the activity envelope is JSON (§6.2), and ticket 013's recommendation is JSON Schema as the interchange and validation format. The workflow artifact itself is Dhall-typed with Dhall its only frontend (`SPEC.md` §4.1–4.2); nothing in the artifact layer would be served by protobuf.

### 3.3 The session

One principal, one token.

- At start the daemon writes a random session token to the token path and a client sends `Authorization: Bearer <token>` on every request. A missing or wrong token is `unauthenticated`, never a degraded mode.
- On Linux the daemon additionally checks `SO_PEERCRED` against its own uid and refuses a mismatched peer. Belt and braces on a socket that is already `0600`, and the check costs one `getsockopt`.
- The token is regenerated at every daemon start; a client re-reads it. There is no long-lived credential to leak, rotate, or expire.
- The principal is the **Owner**, and the session is the only place the actor comes from (§2).

**Scopes are declared now and granted broadly now.** Every operation declares the scope it requires:

| Scope | Covers |
| --- | --- |
| `owner:read` | Queries, subscriptions, capability discovery |
| `owner:decide` | Checkpoint decisions, Egress decisions, task abandon/resume |
| `owner:admin` | Project registration and init |

The v1 token carries all three, because the Owner is the only user (ADR-0005). The scopes exist so that a future read-only console or a Project Assistant on its own token is a grant change, not an operation redesign — and so a violation is a typed `forbidden_scope` rather than an emergent behaviour. A reserved operation's scope (§9) is provisional until its contract lands. Narrowing grants is fog (§11).

### 3.4 Versioning

One version, `factory-api/v1`, carried two ways: the `/v1/` path prefix and an `apiVersion` field in every request, response, and frame. Redundant on purpose — a proxy-rewritten path or a hand-written request cannot silently cross a major.

Within v1 the rules are additive only:

- a new **operation** may appear (the count is not part of the contract);
- a new **optional request field** may appear;
- a new **response field** may appear;
- a field may become optional only if every v1 client already tolerates its absence — in practice, never.

A client must ignore unknown fields and must not infer meaning from absent ones. Four value sets are **closed** — response statuses (§4.2), frame kinds (§4.3), error codes (§5), and decision values (§8.3) — and are never extended within v1; a client may switch on them exhaustively. Everything else is **open**: an unknown value is data, not an error. The activity event's `kind` is the one set that is closed in the spec (`SPEC.md` §6.2–6.3) while its enumeration is fog (§9.1 #1), so this contract passes the envelope through unchanged and a client treats an unknown `kind` as unknown data rather than an error until that fog lands.

Removal, rename, or a changed meaning of an existing field is `factory-api/v2`. A daemon serves exactly one major. A v2 daemon refuses a v1 client with `unsupported_api` and the server's version, rather than half-serving it; the CLI and daemon ship from one release train, and a self-hosted upgrade restarts the daemon (⟨default D6⟩, `SPEC.md` §7.2), so skew is a version check, not a compatibility library.

**Client side.** A client declares the minimum `apiVersion` and the operations it requires at startup, reads them from `meta.capabilities`, and refuses to run if either is missing — with the server's version in the error. No client probes an operation to see whether it works.

### 3.5 Capability discovery

`meta.capabilities` is the first call of every client, and the answer is a descriptor:

```json
{
  "apiVersion": "factory-api/v1",
  "serverVersion": "0.1.0",
  "schemaDigest": "sha256:…",
  "operations": [
    { "id": "inbox.query",   "kind": "query",        "status": "v1",       "scopes": ["owner:read"] },
    { "id": "conversation.open", "kind": "command",  "status": "reserved", "scopes": ["owner:decide"] }
  ],
  "feeds": { "durable": { "cursor": "logSequence" },
             "telemetry": { "cursor": "sessionSequence", "lossy": true } },
  "irVersions": ["factory-ir/v1"],
  "adapterKinds": ["opencode"],
  "limits": { "pageSize": 200, "responseBytes": 1048576,
              "durableBuffer": 256, "telemetryBuffer": 4096,
              "requestTimeoutMs": 30000, "heartbeatMs": 15000 }
}
```

The `limits` values above are initial build defaults (**⟨default D14⟩**, `SPEC.md` §9.2): they are reported so a client never guesses and never hard-codes them, and the contract fixes only that they exist and are reported.

`schemaDigest` identifies the exact JSON Schema set the daemon validates against. That set lives at `internal/api/schema/` beside the daemon and the CLI it describes: it is the contract's field-level half, so a change there is a contract change — same review, same additive-only rule — and the digest moves with it. The digest is **diagnostic, not a compatibility gate**: an additive change moves it, and a client that refused on mismatch would break on every release. The gate is `apiVersion` plus the required-operation set.

### 3.6 Targets and content

Every operation names its target as a **ref**: `project`, `task`, `run`, `checkpoint`, `egressRequest`, and — reserved, never returned in v1 — `conversation` (§9). Refs are opaque strings; a client never constructs one and never derives meaning from its shape.

Artifact content — the `.factory/` file set a client wants validated — travels as a list of `{path, content}` with repository-relative paths. The daemon rejects absolute paths, `..`, and anything outside the declared artifact root. The daemon's own checkouts are derived from the registered project (`project.register`), never supplied by a client.

---

## 4. Envelopes and frames

### 4.1 Unary request

```json
{
  "apiVersion": "factory-api/v1",
  "requestId": "01J…",
  "operation": "checkpoint.decide",
  "idempotencyKey": "01J…",
  "client": { "name": "factory-cli", "version": "0.1.0" },
  "input": { }
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `apiVersion` | yes | Must be a served major |
| `requestId` | yes | Client-generated; echoed; correlates client and daemon logs |
| `operation` | yes | An id from the operation index (§8.2, §9); unknown → `invalid_request` |
| `idempotencyKey` | commands | Absent on a command → `invalid_request`. Absent on a query → ignored |
| `client` | recommended | `name` and `version`, recorded on the transition so the audit says which surface acted |
| `input` | yes | The operation's schema; validated before anything else happens |

`client` is why a second surface is auditable from day one: a decision made by the fake client, the CLI, or a future console is distinguishable in the log without the client being able to *claim* an actor — it reports its software identity, the session reports the principal.

### 4.2 Unary response

```json
{
  "apiVersion": "factory-api/v1",
  "requestId": "01J…",
  "status": "ok",
  "asOf": { "logSequence": 4100 },
  "receipt": { "id": "rcp_…", "recordedAt": "2026-11-20T10:00:00Z", "logSequence": 4101, "inProgress": false },
  "result": { },
  "error": null
}
```

`asOf.logSequence` is present on every response and names the log sequence the response is true at: the read point for a query, the sequence of the transition the command produced (or, for `accepted`, the sequence at which its intent was committed). One number, one name across envelopes, and the wrapper says what it means: `asOf` is the read point, `cursor` is a resume point (§4.3), `at` is a pinned read (§8.3).

`status` is a closed set of three:

| Status | Meaning | `result` | `receipt` |
| --- | --- | --- | --- |
| `ok` | The command's effect is recorded, or the query answered | Present | Commands only |
| `accepted` | The command's intent is committed and its effect is in flight; `receipt.inProgress` is true | May be a partial acknowledgement | Present |
| `error` | Nothing took effect (§5) | null | Absent, except `precondition_failed` and `idempotency_conflict`, which return the receipt that explains them |

`accepted` exists because some commands are slow by nature — opening an init PR, applying an egress rule, executing a merge — and holding a socket for them would make every client's timeout a correctness question. The intent is durable before the response, the effect completes under the daemon's own reconciliation (§3.12 of `SPEC.md`), and the client learns the outcome from the receipt's later state or from the durable feed. A retry with the same key converges on the same receipt (§6).

### 4.3 Subscription request and frames

A subscription is the same unary request with `"operation": "feed.subscribe"`; the response is a stream of NDJSON frames, one JSON object per line.

```json
{"apiVersion":"factory-api/v1","requestId":"01J…","operation":"feed.subscribe",
 "input":{"feed":"durable","cursor":{"logSequence":4100},"project":"prj_…","includeSnapshot":true}}
```

```json
{"kind":"snapshot","feed":"durable","logSequence":4100,"state":{ }}
{"kind":"transition","feed":"durable","logSequence":4101,"transition":{ }}
{"kind":"heartbeat","sentAt":"2026-11-20T10:00:15Z"}
```

| Frame | Feeds | Meaning |
| --- | --- | --- |
| `snapshot` | durable | State for the requested scope at `logSequence`; always followed by transitions from `logSequence + 1` |
| `transition` | durable | One committed transition record |
| `event` | telemetry | One activity event in the ticket-004 envelope |
| `gap` | telemetry | The source lost or never observed events in an interval (`completeness` is `partial` or `unobserved`) |
| `drop` | telemetry | This subscriber fell behind and the server dropped frames for it (§7.4) |
| `resync` | both | The cursor cannot be honoured; the client must re-query and resubscribe |
| `heartbeat` | both | Liveness with no state; `sentAt` on the `heartbeatMs` interval |
| `error` | both | Terminal for the stream; the envelope of §5 |

Frame kinds and statuses are closed sets within v1 (§3.4).

### 4.4 Timeouts, cancellation, limits

- Unary requests have a declared timeout (`limits.requestTimeoutMs`, default 30 s). Hitting it is a client-visible `unavailable` with `retryable: true`, not a silent hang.
- A client disconnect cancels the server-side work it started (context cancellation); a committed command is not rolled back by a disconnect — the receipt is the record.
- Queries over collections take `limit` and `cursor` and return `nextCursor` (null on the last page). `limit` is bounded by `limits.pageSize`; a larger request is refused rather than silently clamped, so a client never believes it saw everything.
- A response larger than `limits.responseBytes` is refused with `response_too_large` naming the limit. Truncation would make "I read it all" untestable, and the client's move is to page.
- Subscriptions have bounded per-subscriber buffers (`limits.durableBuffer`, `limits.telemetryBuffer`); behaviour on overflow differs by feed and is specified in §7.4.

---

## 5. Errors

One error shape, one closed code set.

```json
{ "code": "stale_target",
  "message": "merge approval expected head 4f2a1c9; the PR head is now 9b31e07",
  "retryable": false,
  "details": { "kind": "approval",
               "expected": {"artifactDigests": ["sha256:…"], "prHead": "4f2a1c9"},
               "current":  {"artifactDigests": ["sha256:…"], "prHead": "9b31e07"} } }
```

| Code | Meaning | Retryable |
| --- | --- | --- |
| `unauthenticated` | No token, wrong token, or peer uid mismatch | No — re-read the token |
| `forbidden_scope` | The session lacks the operation's scope | No |
| `invalid_request` | Malformed envelope, unknown operation, unknown field set, a request limit exceeded (page size above `limits.pageSize`) | No |
| `schema_violation` | `input` does not validate against the operation's schema | No |
| `not_found` | A named ref does not exist or is not visible to this session | No |
| `not_implemented` | The operation is reserved (or absent) in this build | No |
| `unsupported_api` | The requested major is not served | No |
| `idempotency_conflict` | The key was used before with a different request digest | No |
| `stale_target` | The refs the client decided against are no longer current | No — re-read, re-present |
| `precondition_failed` | The target's state does not allow the operation (already decided, not Blocked, not the last decision) | No |
| `conflict` | A concurrent command won the target | Usually — re-read first |
| `unavailable` | The daemon is starting, stopping, or overloaded | Yes, after the heartbeat interval |
| `response_too_large` | The answer does not fit `limits.responseBytes`; page it or narrow it | Yes, with a smaller request |
| `dependency_failed` | A required external thing failed: Project VM, tracker, provider, `gh` | Yes, per the Failure Policy — never blindly |
| `internal` | A bug | Yes once, then report |

Rules:

- **An error means nothing took effect.** A command that returned `error` is not applied, and a retry with a new key is safe only after re-reading state. The one honest exception is `conflict`/`stale_target` where a *different* command won: the client's intent did not land, and the state moved.
- **`stale_target` is `SPEC.md` §3.8's stale-approval rule, generalized.** Evidence is bound to the head it was gathered against, so a decision carries the refs it was decided on and the daemon compares them inside the deciding transaction (§6.3). The error returns `current` so a client can re-present the decision without a second round trip to read.
- **Never a bare status.** A machine code and a human message on every error; a client never has to parse prose and a human never has to read a code.
- **Dependency failures name the dependency** in `details.dependency` (`vm`, `tracker`, `provider`, `gh`) so the CLI can say which one and the timeline can correlate it.

---

## 6. Receipts, idempotency, and stale targets

### 6.1 What a receipt is

A **receipt** is the durable record of a command: its idempotency key, the operation, the request digest, the principal and client identity, the recorded response, and the transition it produced. It is a row in the same SQLite database, and **one row takes two writes**:

1. **Intent, co-committed.** The row is inserted in the **same transaction** as the transition that records the command's intent. Its idempotency key, request digest, and recorded response are written here and never change — they are what makes a replay return the same answer.
2. **Outcome, after the effect.** When the effect completes or fails, the same row is updated in the transaction that records the outcome: `inProgress` turns false and the terminal status and its error (or result refs) are set. Only those outcome fields move. `SPEC.md` §2.3's effect-runner discipline is what puts this write in its own transaction — the effect happens outside the deciding transaction, and its result is a new transition.

That is the whole mechanism. `SPEC.md` §2.3 requires "commit a valid transition and its effect intent first; perform the external effect outside that decision; record the result as a new transition". The receipt rides the first commit: after it, the intent exists and a retry cannot duplicate it; before it, nothing happened and a retry is the first attempt. There is no window where a client retried and the daemon both did and did not act, and no window where a client saw a recorded response that the daemon had not committed.

### 6.2 Idempotency-key scope and lifecycle

- The key is client-generated, opaque, and unique per `(operation, idempotencyKey)` in the database. Reusing a key across operations is legal; reusing it with a different request digest is `idempotency_conflict` — the client changed its mind under the same name, and the daemon will not guess which it meant.
- A retry returns the **recorded receipt and the recorded response**, not a re-execution. `accepted` receipts return `accepted` again with the current `inProgress` flag, so a client's retry loop converges on the effect's completion or failure.
- **The retry is the read.** An `accepted` command has no separate status operation in v1: a client observes completion by re-issuing the same command with the same key, which returns the receipt and its current state. That is what `factory … --wait` does (§10.1). A client that lost its key has lost its read path, which is why the key is stored with the pending action rather than held in memory.
- A command whose effect later fails records a new transition with the failure and updates the receipt. The command's *application* stays exactly-once; its *success* is not guaranteed, and the receipt says which.
- Receipts are retained with the transition log (`SPEC.md` §2.3's long retention) and are backed up with the database. There is no short receipt TTL: a key that could still be retried must resolve to its receipt, and the log's retention is the only honest bound. Deletion is an administrative control under `SPEC.md` §6.7's privacy rules — an explicit export, then delete — and not a v1 operation; there is no background sweep, because the retention rule above is the guarantee a client relies on.
- Receipts hold the response, so commands are specified to return **compact acknowledgements and typed refs**, never large documents, and the operation index declares a per-operation maximum response size the daemon enforces (`response_too_large` on a body that would exceed it).

### 6.3 Natural decisions and stale targets

Every decision-taking command carries an `expect` block. It has **one shape**:

```json
{ "logSequence": 4100, "refs": { } }
```

`logSequence` is the log position the client read before deciding (absent only where the operation creates rather than reads state, as `project.init` may). `refs` is the operation's own set of version refs, and the error reuses the same names:

| Command | `expect.refs` |
| --- | --- |
| `checkpoint.decide` | `{ artifactDigests: [<sha256>], prHead?: <sha> }` — the artifacts the Owner read, and the PR head where the checkpoint reads the PR |
| `egress.decide` | `{ requestDigest: <sha256> }` — the Egress Request as the Owner saw it |
| `task.abandon`, `task.resume` | `{ taskState: <state> }` |
| `project.init` | `{ irVersion: <version>, contentDigest: <sha256> }` — the artifact it validated |

The daemon compares `refs` inside the deciding transaction. A mismatch is `stale_target`, whose `details` are `{ kind, expected, current }`: `expected` is the `refs` object the client sent, byte for byte, and `current` is the same object as it is now. `details.kind` says what moved — `approval`, `rule`, `state`, or `artifact`. This is not defensive programming: it is `SPEC.md` §3.8–3.9 — a merge is refused unless the PR head still equals the approved head, and the merge request itself is conditioned on that SHA. The contract carries the same discipline for every decision, so no surface can approve a head it did not see, and a client never has to guess a second name for the same value.

A checkpoint is decided once. A second decision on the same checkpoint — even a different one — is `precondition_failed` with the recorded receipt. Changing one's mind is a new checkpoint the Workflow produces, not an edit of a recorded decision; the contract reflects the engine rather than inventing an amend path.

---

## 7. The two feeds

### 7.1 Two feeds, different guarantees

| | **Durable feed** | **Live telemetry feed** |
| --- | --- | --- |
| Source | The transition log — the audit truth (`SPEC.md` §2.3) | The activity event log and normalized runtime events (`SPEC.md` §6.1) |
| Cursor | `logSequence`, monotonic | `(sessionId, sequence)` per session |
| Ordering | Total, gapless, per database | Per session; interleaving across sessions is unspecified |
| Replay | Yes, from any retained sequence, after a snapshot | No; a gap is reported, not filled |
| Loss | Never while retained; a falling-behind subscriber is disconnected (`resync`) | Yes; loss is always reported (`gap` or `drop`) |
| Authority | Authoritative for Task state | Evidence and index; never Workflow state |
| Survives restart | Yes — replay from the log | Only what was persisted; downtime is an unobserved interval |

One mixed feed was rejected (§12.4): it would either make telemetry look authoritative or weaken state guarantees to telemetry's. The split is already in the record — three stores with three jobs (`SPEC.md` §6.1) — and the contract's job is to expose it honestly, not to hide it behind one socket.

### 7.2 Durable subscription

- `includeSnapshot: true` sends `snapshot` **at the requested cursor** for the requested scope, then `transition` frames from `cursor.logSequence + 1`. Snapshot plus suffix reproduces state (`SPEC.md` §2.3), and "replay from any retained sequence" (§7.1) stays true. With no cursor the snapshot is taken at the current sequence and the stream continues from there.
- The cursor is a sequence, so reconnect is exact: no duplicate and no hole.
- Filters are scope filters (`project`, and optionally `task`/`run`), never semantic transformations — a filtered feed must not require the client to trust the server's reading of a state machine.
- If the cursor is older than the earliest retained sequence (or a snapshot generation was pruned), the server sends `resync` and the client re-queries `status.query` and resubscribes. This is why snapshots exist: bounded replay, with an explicit bound.
- A durable subscriber that cannot keep up is disconnected with `resync` rather than silently skipped. State guarantees are too important to degrade quietly.

### 7.3 Telemetry subscription

- Frames are activity events in the ticket-004 envelope, unchanged (`SPEC.md` §6.2) — the contract does not invent a second event schema. Correlation to Workflow state stays `run_id`/`operation_id`.
- Subscribing to a run whose session is gone is legal: the client gets persisted events and then `gap` frames for unobserved intervals, which is the honest representation of a lost session.
- Telemetry never advances a Task, and no client may treat an event as a transition. `SPEC.md` §2.4's rule is the contract's rule: runtime events are not state.

### 7.4 Backpressure and loss reporting

- Telemetry: on buffer overflow the oldest frames are dropped and a `drop` frame names the dropped sequence range. The client treats `drop` and `gap` identically for its purposes (state unknown over that interval) and differently for its honesty (one is transport pressure, one is source completeness). A dropped interval is never replayed from memory; a client that needs it re-queries the persisted activity log through `timeline.query`.
- Durable: on buffer overflow the subscription is closed with `resync`. There is no partial durable stream.
- Heartbeats keep an idle subscription provably alive on both feeds; a client that sees no frame for two `heartbeatMs` intervals reconnects and resumes by cursor.

---

## 8. v1 operations and the projections they read

### 8.1 Projections

Projections are the read models over the transition log (`SPEC.md` §2.3). Every **query** reads a named projection — no query touches the log or a table directly, and no projection is authoritative over the log. The durable **subscription** is the exception by design: it streams the log's own records (§7.2), and `meta.capabilities` and `workflow.validate` read no projection at all.

| Projection | Serves |
| --- | --- |
| `inbox` | Checkpoints awaiting decision, Blocked Tasks, Egress Requests (`SPEC.md` §3.11, §5.6) |
| `project` | Registered Managed Projects, their status, artifact digest, VM state |
| `task` | Task state, Stage, pinned IR digest, Issue ref |
| `run` | Run records, model attempt trails, Outcomes, transcript refs |
| `gate_report` | Gate verdicts with inputs and digests (`SPEC.md` §3.6) |
| `checkpoint` | Open and decided checkpoints with their asked artifacts |
| `egress_request` | Open and decided Egress Requests with the applied rule |
| `model_catalog` | Static descriptor plus live availability overlay (`SPEC.md` §2.4) |
| `metrics` | The default metric set slices (`SPEC.md` §6.4): cycle time, verdicts, findings, retries, tokens, cost, model resolution, merge latency, tool errors, confusion proxies |
| `timeline` | The Owner timeline: activity events, transitions, and trace spans joined by `run_id`/`operation_id` (`SPEC.md` §6.9) |

### 8.2 The v1 operation set

Fourteen operations, two of which are the transport's own (`meta.capabilities`, `feed.subscribe`). Every one traces to a spec need; none is speculative. `scope` is the required scope from §3.3; every command is `keyed` (idempotency key required, §6).

| Operation | Kind | Scope | Purpose | Reads |
| --- | --- | --- | --- | --- |
| `meta.capabilities` | query | `owner:read` | Version, operation index, feeds, limits (§3.5) | — |
| `feed.subscribe` | subscription | `owner:read` | Durable or telemetry feed (§7) | transitions, activity events |
| `project.query` | query | `owner:read` | List or get registered projects | `project` |
| `project.register` | command | `owner:admin` | Register a repository and its tracker (`SPEC.md` §7.1 step 1) | `project` |
| `project.init` | command | `owner:admin` | Validate the harness live, render `defaults/`, open the init PR (`SPEC.md` §7.1, §7.3) | `project`, `model_catalog` |
| `inbox.query` | query | `owner:read` | The Owner's inbox, paged (`SPEC.md` §3.11, §7.3) | `inbox` |
| `checkpoint.decide` | command | `owner:decide` | Record a Checkpoint decision, with edits or reason (`SPEC.md` §3.4, §3.9) | `checkpoint`, `task` |
| `egress.decide` | command | `owner:decide` | Allow or deny an Egress Request; applies the local rule and records it (`SPEC.md` §5.6) | `egress_request` |
| `status.query` | query | `owner:read` | Task/Run state, Gate reports, metrics (`SPEC.md` §7.3) | `task`, `run`, `gate_report`, `metrics` |
| `timeline.query` | query | `owner:read` | The Owner timeline, filtered and paged (`SPEC.md` §6.9) | `timeline` |
| `task.abandon` | command | `owner:decide` | Abandon a Task with a reason and an Issue disposition (`SPEC.md` §3.11) | `task` |
| `task.resume` | command | `owner:decide` | Resume a Blocked Task (`SPEC.md` §3.11) | `task` |
| `model.catalog` | query | `owner:read` | The adapter's Model Catalog and current availability (`SPEC.md` §7.3) | `model_catalog` |
| `workflow.validate` | query | `owner:read` | Compile and validate an artifact file set before a PR (`SPEC.md` §7.3) | — |

The CLI's mapping to them is `SPEC.md` §7.3; the two transport operations are used by every client and have no verb of their own. The set is additive inside v1 (§3.4), so this table — not the count — is the list.

### 8.3 Shapes worth fixing

Full field-level schemas belong to the implementation; the shapes that carry decisions are fixed here.

- **`inbox.query`** — `{project?, kind?, limit, cursor}` → `{items: [{kind: "checkpoint"|"blocked"|"egress", ref, since, summary, artifacts?}], counts, nextCursor, asOf}`. `artifacts` carries the **content** of the typed artifacts the decision is taken on — a `TriageDecision`, a review finding set — with their digests, because Factory holds them anyway as Gate inputs and the Owner cannot decide on a ref alone. They are small JSON documents, bounded by `responseBytes` (§4.4). Transcripts are different: Factory keeps references, not copies (`SPEC.md` §6.1), so a transcript ref is not resolvable through this contract (§11). One inbox, three kinds, one ordering (oldest first, **⟨default D14⟩**) so a client never sorts; `kind` is a filter because a surface may want one kind without paging the rest.
- **`checkpoint.decide`** — `{checkpoint, decision: "approve"|"reject", edits?, reason?, expect}`. `edits` is the typed edit set the checkpoint's asked artifacts allow; a rejection requires a reason; approval of a merge checkpoint requires the PR head in `expect.refs`.
- **`egress.decide`** — `{request, decision: "allow"|"deny", rule?, expect}`. `rule` optionally narrows the applied rule (method and path scope) below the observed target; the default applies the observed target. Both outcomes are recorded (`SPEC.md` §5.6).
- **`project.init`** — `{project, models: {<seat>: [<catalog id>…]}, commands: {build, tests}, expect: {refs: {irVersion, contentDigest}}}`, returning `accepted`. Init is interactive in the CLI and flag-driven here; the contract takes the resolved answers, not a wizard, and its `expect.refs` is the artifact it validated (§6.3).
- **`workflow.validate`** — `{project?, files: [{path, content}], irVersion?}` → `{irVersion, contentDigest, nodes, diagnostics}`. A read-only computation: it opens no PR, records no transition, and returns the artifact's node ids so a client can show what would be added.
- **`status.query`** — `{project, task?, run?, include: ["state","gates","metrics","runs"], at?: {logSequence}}` → the projection slices plus `asOf`. `at.logSequence` pins a read to the sequence a subscription just reported, which is how a client joins feed and query without a gap or a duplicate.

### 8.4 What the contract does not decide

The contract records an Owner decision; it does not implement the decision's workflow semantics. `checkpoint.decide` produces a Checkpoint transition (or a typed `precondition_failed` when the Workflow has not asked for that checkpoint); `egress.decide` produces an Egress Request transition and applies the rule to local devvm config through the normal devvm application path, not artifact compilation (ADR-0009); `task.abandon` produces an abandonment transition and the tracker effect the decision names. Nothing here is a second state machine, and no client can reach a state the IR would not.

---

## 9. Reserved post-v1 resources

v1 reserves **operation ids** for the surfaces `SPEC.md` §7.4–7.5 already names, and implements none of them. A reserved operation answers `not_implemented` and appears in `meta.capabilities` as `"status": "reserved"`. One resource name is reserved with them: the `conversation` ref kind (§3.6).

Why reserve at all: `SPEC.md` §7.5 already commits to the name **Conversation** and its five verbs, and §7.4 commits to the Project Assistant, the Node View, and a message to a waiting Run. Leaving those ids unclaimed invites a second vocabulary that later has to be churned out of the CLI. Reserving an id costs one line and binds only the name and kind — never the shape, which stays open until a follow-up spec change. A reserved operation is explicitly *not* a promise about fields, and no v1 client may depend on one.

| Reserved operation | Kind | One line | Source |
| --- | --- | --- | --- |
| `conversation.query` | query | Read Conversation records and their state | `SPEC.md` §7.5 |
| `conversation.open` | command | Open or hand off a Conversation to a hosting surface | `SPEC.md` §7.5 |
| `conversation.message` | command | Append a message to a Conversation | `SPEC.md` §7.5 |
| `conversation.close` | command | Close a Conversation and record its summary | `SPEC.md` §7.5 |
| `conversation.subscribe` | subscription | Stream messages for one Conversation | `SPEC.md` §7.5 |
| `node.view` | query | One Workflow node's grouped history | `SPEC.md` §7.4 |
| `assistant.ask` | command | Ask the Project Assistant; answer is a transient artifact | `SPEC.md` §7.4 |
| `assistant.createIssue` | command | Create an Issue, on Owner confirmation | `SPEC.md` §7.4 |
| `assistant.proposeArtifact` | command | Propose a `.factory/` change as a PR, on Owner confirmation | `SPEC.md` §7.4 |
| `run.message` | command | Send an Owner message to a waiting Run | `SPEC.md` §7.4 |

**Conversation's contract depth.** `SPEC.md` §7.5 already fixes the record's fields — hosting surface and provider reference, opening request or trigger, participants, message references (refs, not copies), the summary posted to the Issue, and lifecycle — plus three binding rules: no Conversation operation advances Workflow state, message content stays in the transcript and the record holds references, and the summary is Factory's only content. Those are inherited, not decided here, and they are all the shape a reserved id needs. Factory's own contribution is the summary **and its link** on the Issue (`SPEC.md` §7.5). Access control, retention, the T3-surface-vs-adapter question, and whether a dedicated clarifier agent exists remain fog (`SPEC.md` §9.1 #4); message fetching is excluded rather than fog, because the record holds references and never copies.

**Node View.** The *name* is reserved; the *query* is deferred to the follow-up spec change. Its response depends on the observability schema (`SPEC.md` §9.1 #1) and on the run/event path columns that `SPEC.md` §7.4 defers, so specifying a shape now would either invent that schema or be rewritten. This is the conservative default, and the alternative — no reservation at all — would let a client call it something else first.

---

## 10. Clients: the CLI and the fake second client

### 10.1 The CLI is the first client, and nothing more

`cmd/factory` speaks this contract and holds no privileged access. It reads the token, calls operations, renders results, and exits. It does not import the daemon's storage, does not know the schema beyond the types every client shares, and cannot do anything a script with `curl` could not do (that is the test of §3.2).

Three CLI conveniences are allowed because they are presentation only: `--json` (the raw envelope, for scripts), `--follow` (wraps `feed.subscribe`), and `--wait` (polls a receipt on its own key). None adds an operation.

**Version skew.** The CLI checks `meta.capabilities` at startup and refuses to run against a daemon whose `apiVersion` or required operations differ, printing both versions. During self-hosting the Owner restarts the daemon after a self-merged change (⟨default D6⟩); until then an upgraded CLI meets an older daemon, and the honest behaviour is to say so rather than to half-work.

### 10.2 The fake second client is the seam test

ADR-0002 proves the runtime seam with a fake adapter. This contract gets the same treatment, and it needs two levels because they prove different things:

1. **A script client** — `curl --unix-socket` and `jq` in a shell script, in CI, no shared code. It proves the contract is complete enough to use *without* our types, that the errors are readable, and that the docs are not lying about the wire. It is also the sample a future client author copies.
2. **A Go second client in its own package** — imports only the schema types, never the CLI or the daemon's internals. It proves the typed contract, the feeds, and resume.

Its acceptance test is the four flows that any real surface must do, in the order a surface does them:

| Flow | Operations | What it proves |
| --- | --- | --- |
| Open the inbox | `meta.capabilities` → `inbox.query` | Discovery works; the Owner's queue is one query |
| Decide | `checkpoint.decide`, retried with the same key | Receipts: one application, identical response |
| Follow a run | `feed.subscribe` durable + telemetry, `status.query` | Ordering, frames, `asOf` join, `gap` honesty |
| Reconnect | restart the daemon mid-stream; retry across the restart | Durable cursor resumes exactly; a retried command applies once |

A flow that cannot be expressed is a contract defect, and the test fails. It runs from build step 2 (`SPEC.md` §8.6) beside the transition log, so the contract is exercised before any surface depends on it.

### 10.3 What a second surface does not need

The contract carries no rendering, no layout, no polling interval, no local cache semantics, no per-client state. A client that needs a cache builds one from `cursor` and `asOf`; a client that needs a widget decides which query to call. This is why the post-v1 Project Console can be built without a control-plane change.

---

## 11. Fog and deferred

Named, not answered here:

- **Loopback TCP and browser clients.** §3.1 names the socket; ticket 010 allows loopback TCP later. What a browser client needs — token delivery without a file the browser cannot read, `Origin` checks, CSRF-shaped defences, cookie-vs-header — is unspecified. It joins `SPEC.md` §9.1 #2's path-to-other-users fog and its #5.
- **Multi-user access and narrower grants.** Operation scopes exist; grants do not narrow. Guests, a second Owner, a read-only console token, and per-project scoping of a session are fog (`SPEC.md` §9.1 #2, #4).
- **Remote/worker mode.** The contract is host-agnostic by design (refs, no paths, §3.6), which is what makes an extraction cheap. The authenticated transport, worker identity, per-worker scopes, and the reconciliation split are post-v1 (ADR-0005).
- **T3 as surface or adapter.** If T3 becomes a surface, the Conversation operations carry it and the thread is a hosting surface like any other; if it becomes a `RuntimeAdapter`, it never touches this contract. `SPEC.md` §7.5 records both; neither is chosen.
- **The plugin's tool channel.** The minimal Factory plugin's tools are not operations here. An agent inside a Project VM must never hold the Owner session, so that channel needs its own scoped principal; its transport and scopes are unspecified.
- **Observability schema.** `timeline.query` filters and the telemetry event enums inherit `SPEC.md` §9.1 #1 fog; the contract fixes only the envelope's shape, not its value sets.
- **Transcript content.** A transcript reference is not resolvable through this contract in v1: Factory keeps references, not copies (`SPEC.md` §6.1), and the runtime owns the content. Whether a client reads transcripts through Factory, through the runtime's own surface, or not at all is unspecified — and it is the gap a Node View would hit first.

---

## 12. Candidate-4 review record

This section is the dossier's review record: what the candidate got right, what it missed, the decisions taken, and where the rejected alternatives live. It is history, not contract — the body above is normative, and §12.3's rows point at the sections that carry each decision.

### 12.1 What the candidate got right

- **The seam claim is correct.** Every future surface rides this boundary, so an unstated boundary is a decision made by the first client's convenience. Writing it down before `cmd/factory` exists is the cheapest moment.
- **The inherited pieces are sound and do not need re-litigating.** One writer, no client DB access, idempotent commands with receipts, snapshots plus subscriptions, a scoped Owner session, JSON over a socket, T3 Code's shape. ADR-0005 and ticket 010 settled them; this document specifies rather than redesigns.
- **The acceptance test is the right one.** "The CLI is the first client" and "a fake second client proves the seam" are the right acceptance tests, and they are the same pattern ADR-0002 already applied to the runtime seam — one idiom, two seams.

### 12.2 What the candidate missed

Each gap is closed by a section above:

| Gap | Closed by |
| --- | --- |
| No envelope or operation identity: "the API" was a class, not an interface | §2, §4 — operations, kinds, request/response identity |
| Idempotency asserted, never defined | §6 — receipts, key scope, co-commit, retention |
| Subscriptions with no cursor and no loss semantics | §7 — cursor per feed, `gap`/`drop`/`resync`, restart behaviour |
| No error taxonomy, so "stale approval" and "daemon down" looked alike | §5 — closed codes plus `retryable` |
| No stale-decision rule at the API layer, though `SPEC.md` §3.8 requires one | §6.3 — `expect`, `stale_target`, `current` |
| Owner actions the spec already requires had no surface (`register`, `abandon`, `resume`, timeline) | §8.2 |
| `SPEC.md` §7.5's Conversation named with no reserved vocabulary, inviting a second naming | §9 |
| No versioning, though CLI/daemon skew is guaranteed during self-hosting | §3.4, §3.5, §10.1 |
| No seam test that could fail | §10.2 |
| Paths in requests would have blocked remote mode and opened traversal | §3.6 |

### 12.3 Decisions taken

| Decision | Call | Basis |
| --- | --- | --- |
| Envelope: commands/queries/subscriptions vs REST resources vs JSON-RPC | Commands, queries, subscriptions, with the operation id as identity | **Decided here**, on ADR-0005's and ticket 010's direction |
| Wire: HTTP/JSON over UDS vs NDJSON-only vs gRPC | HTTP/1.1 + JSON on one `POST /v1/rpc`, NDJSON only where streaming is intrinsic | **Decided here** |
| Feeds: two vs one mixed | Two, with different guarantees stated | **Decided here**, on `SPEC.md` §6.1's three stores |
| Contract format: JSON Schema vs OpenAPI vs protobuf | JSON Schema 2020-12 as the field-level source of truth, at `internal/api/schema/`, plus a hand-written operation index; a schema change is a contract change | **Decided here** |
| Receipts, key scope, retention | Same SQLite; the intent half co-committed with its transition, the outcome written with the effect's; key per `(operation, key)`; retained with the log; response digest guarded | **Decided here**; storage inherited from ADR-0005 |
| Auth | Bearer token file at `0600` from a per-start random token, `SO_PEERCRED` check, declared operation scopes, broad v1 grants | **Inherited** (ADR-0005, ticket 010), specified here |
| Versioning | `factory-api/v1`, additive inside the major, one major per daemon, capability descriptor for discovery | **Decided here** |
| Reserve post-v1 operation ids | Reserve names and kinds for `SPEC.md` §7.4–7.5's surfaces; no shapes | **Decided here** |
| Node View query now or later | Name reserved now, query deferred to the follow-up change | **Decided here** |
| Conversation contract depth | Record fields and the three rules inherited from `SPEC.md` §7.5; five verbs reserved; shapes deferred with the Node View query | **Inherited + decided here** |
| Targets as refs, artifact content in requests, no host paths | Adopted | **Decided here** |
| Query consistency | Every response carries `asOf.logSequence`; a query may pin a read with `at.logSequence`; feeds resume from it | **Decided here**, specified in §4.2 |

### 12.4 Rejected alternatives (recorded once, in the ADR)

Recorded once, in [ADR-0010](../adr/0010-client-contract.md)'s *Considered Options* — do not restate them here, or the two copies will disagree. The load-bearing rejections, in one line each: REST-shaped resources (no caches, intermediaries, or browser-first client; the id would become a URL), JSON-RPC 2.0 as the wire standard (no slot for `apiVersion`, `accepted`, or receipts), NDJSON as the whole protocol (re-earns framing and loses `curl`), gRPC/protobuf (a second encoding for one consumer), one mixed feed (telemetry would look authoritative, or state would inherit its loss), OpenAPI as the contract document (it describes a surface we do not serve), codegen-first stubs (more machinery than a conformance test), multi-user auth now (ADR-0005), host paths as targets (traversal; remote mode), an amend-decision operation (a decided checkpoint is a fact), and specifying the Conversation or Node View contracts now (they depend on fog).

---

## 13. Sources

| Artifact | Supplies |
| --- | --- |
| [`docs/adr/0005`](../adr/0005-resident-daemon-thin-clients.md) | Daemon, thin clients, typed local JSON API, receipts, scoped Owner session, no client DB |
| [`docs/adr/0010`](../adr/0010-client-contract.md) | This contract's shape and its rejected alternatives |
| [`docs/wayfinding/closed/010`](../wayfinding/closed/010-decide-daemon-or-cli.md) | Client-surface decision: UDS, loopback TCP later, commands/receipts/snapshots+subscriptions, T3-shaped RPC |
| [`docs/wayfinding/closed/004`](../wayfinding/closed/004-research-steer-capture-observability.md) | Activity event envelope, transcript linkage, Owner timeline, completeness reporting |
| [`docs/wayfinding/closed/006`](../wayfinding/closed/006-decide-harness-substrate.md) | T3 Code as the reference shape for a daemon boundary and multi-client RPC |
| [`SPEC.md`](SPEC.md) §1.2, §1.3, §2.1–§2.3, §3.8, §3.11, §5.6, §6.1–§6.9, §7.1, §7.3–§7.5, §8.6, §9.1 | The behaviour this contract exposes |
| [`CONTEXT.md`](../../CONTEXT.md) | Conversation, Project Assistant, Run, Owner, Client Contract and its vocabulary |
