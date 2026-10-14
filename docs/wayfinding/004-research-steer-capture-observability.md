---
title: How should user steers and agent activity (tool/file/network calls) be captured for mining and observability?
type: wayfinder:research
blocked-by: []
assignee: research-dispatch
---

## Question

Factory records how the owner steers agents (corrections, invocations, context changes) plus agent activity (tool calls, file access, network requests) to (a) mine into skill/workflow improvements and promoted issues, and (b) give the owner observability/debuggability. Research what prior art exists — OpenCode/T3Code session storage (sqlite transcripts), OpenTelemetry-style traces, agent-audit standards, mattpocock/skills' reflect-mining loop, and paperclip/pi.dev approaches. Verdict: a proposed capture schema (what is stored, granularity, where: transcript store vs structured event log), what a mining step consumes, and existing patterns to adopt rather than invent.
