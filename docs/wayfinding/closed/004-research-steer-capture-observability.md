---
title: How should user steers and agent activity (tool/file/network calls) be captured for mining and observability?
type: wayfinder:research
blocked-by: []
assignee: done
status: resolved
---

## Question

Factory records how the owner steers agents (corrections, invocations, context changes) plus agent activity (tool calls, file access, network requests) to (a) mine into skill/workflow improvements and promoted issues, and (b) give the owner observability/debuggability. Research what prior art exists — OpenCode/T3Code session storage (sqlite transcripts), OpenTelemetry-style traces, agent-audit standards, mattpocock/skills' reflect-mining loop, and paperclip/pi.dev approaches. Verdict: a proposed capture schema (what is stored, granularity, where: transcript store vs structured event log), what a mining step consumes, and existing patterns to adopt rather than invent.

## Resolution

### Verdict

Use two linked local records with different jobs: the existing conversation/session store remains the canonical content-bearing transcript; a small append-only **session activity event log** indexes what happened and when. Add OpenTelemetry-compatible spans for live timing/correlation and optional export, but do not treat sampled/exported traces as the durable audit record. This gives the owner a chronological, attributable run timeline and gives mining deterministic session/event references without copying prompts, tool payloads, or file contents into another database.

### Proposed capture schema

One event per meaningful transition, not per token or UI repaint. Preserve exact user/assistant/tool message granularity in the transcript; record lifecycle activity as discrete events, with tool start and finish as separate events or one start/end pair keyed by `operation_id`.

```json
{
  "schema_version": 1,
  "event_id": "uuid",
  "sequence": 42,
  "occurred_at": "RFC3339 UTC",
  "session_id": "stable session id",
  "run_id": "optional run/turn id",
  "parent_session_id": "optional delegated/forked session",
  "trace_id": "optional W3C trace id",
  "span_id": "optional OTel span id",
  "actor": {"kind": "human|agent|system|tool", "id": "optional stable local id"},
  "kind": "steer|skill_invoked|context_changed|model_call|tool_call|file_access|network_request|approval|run_state",
  "operation_id": "optional correlation id",
  "operation": "closed/normalized name, e.g. read_file or http_request",
  "outcome": "started|succeeded|failed|denied|cancelled",
  "duration_ms": 123,
  "target": {"path": "repo-relative path or null", "host": "hostname only or null"},
  "details": {"bounded safe fields only"},
  "evidence": [{"message_id": "...", "part_id": "..."}],
  "completeness": "complete|partial|unobserved"
}
```

* **Steers:** retain the actual human message in the transcript and point to it from a `steer` event with a subtype such as `correction`, `preference`, `scope_change`, `approval`, or `rejection`. Record whether the subtype was explicit or inferred and its confidence/evidence; never present an inferred intent as ground truth. Slash-command/skill invocations are explicit events with the skill/command identifier and version or content digest. Do not save duplicate prompt text in the event row.
* **Context:** record each effective context/loadout change as a delta: skill and instruction/resource identifiers, versions/content digests, added/removed tools, model/provider selection, working directory/repo identity, and parent/fork/branch boundary. Keep context bodies and secrets out of this event log. Preserve the full provider/session transcript according to its existing policy; compaction summaries do not replace the original evidence.
* **Agent activity:** record tool operation name, call identity, start/end, status, duration, approval/denial, and safe bounded result metadata. File events record operation and repo-relative path (plus optional size/hash), not file contents. Network events record destination hostname, method/protocol, status/error class and timing, not URL query, headers, credentials, or request/response bodies. Shell commands need a separate policy: by default capture executable/category and exit status, not raw args, environment, stdin, or output. Raw values may be kept only in the protected transcript/run detail when needed for debugging and subject to redaction/retention controls.
* **Scope and integrity:** identify project/repository and runtime/harness version, use monotonically increasing per-session sequence numbers and stable event IDs, and mark gaps or unsupported instrumentation. Keep activity details local by default with explicit retention/deletion and export controls. Use content digests only for correlation/integrity, not as a claim that the underlying content can be recovered or is secret-proof. Remote telemetry is opt-in and content-free.

The capture boundary must report its limits. Tool hooks can observe tool calls; filesystem and network activity performed by arbitrary child processes cannot be claimed complete without OS/sandbox instrumentation (for example, filesystem audit hooks and an egress proxy). Mark that coverage as partial/unobserved rather than silently implying a complete audit. A filesystem read event proves an attempted/observed access by the instrumented layer, not that all bytes were consumed by the model.

### Mining and owner observability

Mining runs as a deliberate, reviewable batch over a selected date/project/session scope. It loads transcript messages and referenced event slices for completed sessions, preferably prioritizing explicit corrections/rejections, repeated user clarifications, failed/denied operations, reruns, and changed context. It produces evidence-linked candidate learnings (pattern, supporting message/event references, counterexamples, confidence, proposed skill/workflow destination), not direct skill edits. A reviewer wave can independently assess judgment, tooling/environment, and contrarian patterns; a synthesis step sorts candidates into accepted, rejected, and backlog. Accepted items are proposed for the responsible skill/workflow; repeated actionable gaps become deduplicated tracker issues with evidence links. Require owner approval before changing shared skills or creating/promoting tracker work. This follows the local `reflect` workflow's transcript extraction → multi-lens review → synthesis → human approval, and Matt Pocock's `retro` emphasis on actionable environment improvements rather than generic session summaries.

For the owner, render a single run timeline from activity events, transcript references, and trace spans: user steer/context changes; model calls; tool calls; approvals; file/network operations; outcome and latency; plus links to the exact transcript/run and resulting diff. Filter by project, session/run, actor, operation, outcome and time. Local audit/activity records answer “what happened and who did it”; traces answer “where was time spent and what failed”; transcript references answer “what was said.” Alert/query on repeated failure or long-running spans without exporting content.

### Patterns to adopt, not invent

* **OpenCode/T3Code:** the local OpenCode SQLite store already separates session metadata (`session_v2`) from ordered, typed `session_message` records (with sequence, timestamp and JSON data), and its legacy schema separates message and part rows. This is a useful transcript source and correlation model, not a sufficient audit feed: there is no generalized semantic event covering every external filesystem/network side effect. T3Code threads backed by these sessions can retain that stable session reference. Read-only inspection of the local database confirmed these table shapes; the local schema is version-dependent, so consume supported APIs/extractors rather than coupling Factory to undocumented SQL columns. [OpenCode docs](https://opencode.ai/docs/) · [local reflect extractor contract](~/.agents/skills/reflect/SKILL.md#L24-L36).
* **OpenTelemetry GenAI conventions:** reuse W3C trace/span parentage, semantic operation names (`invoke_agent`, `execute_tool`, `plan`), provider/model/agent attributes, status/error conventions and duration. These conventions are explicitly marked **Development**; their input/output/instruction/tool-definition content fields are opt-in and warn of sensitive data. Keep Factory's durable audit/event log separate, use a conservative content-free attribute allowlist, and pin a schema version. [Agent spans](https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-agent-spans.md) · [model/tool spans and content capture guidance](https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-spans.md) · [GenAI events](https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-events.md).
* **Paperclip:** its operator model distinguishes durable activity/audit history and per-run transcripts/logs from opt-in OTel traces and anonymous, content-minimized product telemetry. Activity records are actor/action/entity/time oriented; the UI links agent actions to runs. Adopt that separation, attribution and run-linked debugging, not its full control plane. [Activity log](https://docs.paperclip.ing/guides/day-to-day/activity-log/) · [observability contract](https://github.com/paperclipai/paperclip/blob/master/doc/observability.md) · [telemetry data contract](https://github.com/paperclipai/paperclip/blob/master/packages/shared/src/telemetry/README.md).
* **Pi:** its session format is append-only JSONL with typed entries, stable IDs, parent links for branches, explicit model/thinking changes, and prompt/tool-loadout deltas. Its extension lifecycle exposes input, tool-call/result, session and agent events, while its docs warn that exported sessions may contain prompts, tool arguments, command output and file contents. Adopt typed append-only records, branch-aware evidence and lifecycle hooks; do not mistake a harness hook for OS-level coverage or share exports without review. [Session format](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/session-format.md) · [extensions/events](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) · [session privacy/export guidance](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sessions.md).
* **Skills mining:** the checked-in `~/.agents/skills/reflect/SKILL.md` is a concrete mining workflow: extract the transcript from SQLite, review from distinct lenses, synthesize accepted/rejected/backlog, and wait for approval before applying skill edits. Matt Pocock's public `skills/engineering/retro` is adjacent prior art focused on mining a session for navigation, checks, standards, tool economy, no-ops and information-access improvements; it does not define a cross-session telemetry/audit schema. Adopt the evidence-first, categorized retrospective and keep promotion gated. [Matt Pocock retro skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/retro/SKILL.md) · [skills repository overview](https://github.com/mattpocock/skills).

No mature, cross-harness standard was found that defines a complete, privacy-safe audit log for human steering plus tool, filesystem and network actions. OTel GenAI is the closest shared tracing vocabulary, but remains in development and is observability rather than an audit-retention guarantee. Keep a small Factory event envelope and adapter-specific capture contracts; do not build a second transcript format or claim complete host activity without enforcement-level instrumentation.
