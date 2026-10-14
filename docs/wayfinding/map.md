---
label: wayfinder:map
title: Chart the Factory — a user-defined agent harness for deterministic workflows
---

# Map: Factory

## Destination

A **written spec of "Factory"**: a meta-harness that lets the owner define deterministic workflows (code-defined, language TBD) which orchestrate agent teams — implement, review, triage, monitor, log, deploy — across multiple managed projects, each with its own tracker adapter, with per-agent capability control and SSH-based machine deployment. The spec is ready to hand off for planning/building in a later effort. Scope note: it serves the owner first with a path to other users; it ships a first milestone (the issue-driven loop) and is designed-for self-hosting (Factory manages Factory) in the short term.

## Notes

- **Domain**: agent orchestration / software factory. Skills: `grilling` + `domain-modeling` for any decision conversation; `research` for research tickets; `prototype` for shape questions.
- **Tracker convention** (no git remote yet, local-markdown tracker): open tickets are files in `docs/wayfinding/`; claim by adding `Assignee: <you>`; blocking via `Blocked-by:` lines naming sibling files; resolution goes into the ticket file before moving it to `docs/wayfinding/closed/`.
- **Settled before charting** (user decisions, treat as standing inputs):
  1. Destination = spec, not code (map is planning).
  2. Audience = the owner, with a deliberate path to other users later.
  3. Workflows are **code-defined** (users write code calling agent primitives); workflow language is undecided.
  4. Underlying harness is undecided: OpenCode + plugins vs own implementation — research topic.
  5. Factory should **self-track in the short term**; when working on other projects, agents report feedback as issues back to Factory's tracker.
  6. Steering/interaction data serves **mining into skills & workflow updates + observability** (tool calls, file access, network monitoring, debugging).
  7. Deployment = SSH to the owner's machines, cloud optional.
  8. First milestone = the **issue-driven loop** (issues → triage → implement → review → merge).
  9. Tracker adapters: pluggable interface; GitHub Issues (`gh`) as first implementation; Fizzy/Linear/others follow; permissions across trackers are a concern.
  10. Language comparison must include functional/memory-managed leaning: Roc, Mojo; also Go, TypeScript, others.
  11. Capability control: role profiles (a), leaning toward "profiles + always-ask for high-risk" (c) pending research.
  12. Daemon vs CLI: fetch both consumer models — sketch both in the spec, decide later.
  13. Project name: "Factory" for now.
- Inspirations to study: mattpocock/skills, T3 Code, paperclip, pi.dev.
- All research agents dispatched at charting time are working in parallel; their results land in their ticket files.

## Decisions so far

<!-- one line per closed ticket: title (URL/path) — gist -->

- [Which implementation language for the Factory harness](closed/001-research-harness-language.md): Go recommended for the harness core; owners write workflow code in Starlark or via a subprocess/JSON interface; OCaml and TypeScript stay as escape hatches.
- [Build on OpenCode + plugins, or own harness?](closed/002-research-build-vs-opencode-plugins.md): hybrid — Factory owns deterministic orchestration and uses OpenCode's embedded SDK as its first runtime behind a narrow adapter; Factory still builds durable run state, scheduling, approvals, tracker/PR integration, audit, recovery, execution isolation. Switching cost moderate if runtime state stays behind the adapter.
- [Tracker adapter interface & permissions](closed/003-research-tracker-adapters-and-permissions.md): draft capability adapter with a GitHub/Fizzy/Linear support+permission matrix; a list of per-agent permissions (incl. merge-adjacent) the harness must enforce itself.
- [Steer capture & observability](closed/004-research-steer-capture-observability.md): append-only, transcript-linked event log; OTel spans for timing/correlation only; privacy boundaries defined; evidence-linked mining with human approval; owner-facing run timeline.
- [Software-factory landscape survey](closed/005-research-software-factory-landscape.md): comparison of MetaGPT, ChatDev, AutoGen/AG2, OpenAI/Anthropic writes, Devin, Cursor, Copilot, Jules, OpenHands, SWE-agent; recurring spaghetti-agents anti-patterns cataloged with adopt/avoid recommendations. Amended 2026-10-14 (owner request): [Tessl](https://tessl.io) — the closed-source "context-driven factory" platform whose skills→loops→factory thesis challenges the code-defined-workflow premise, plus a five-system open-source factory sweep (AI Workflow, Open SWE, Vercel Foreman, gh-aw, agent-orchestrator; detail in `docs/research/oss-agent-factories-2026-10-14.md`) — no system yet combines multi-project scope, tracker neutrality, enforced capability control, and an authoritative issue→merge loop.

## Not yet specified

- **Permission model for agents**: how profiles + always-ask interact with tracker permissions; exact autonomy levels. Hangs on harness decision (research-driven) and tracker research.
- **Where agents run**: local, remote worktrees, per-machine executors, sandboxing. Fog: depends on harness choice.
- **Observability schema**: what is recorded about every steer/tool call/file/network action, and how mining consumes it. Depends on harness decision.
- **The deploy pipeline**: how a workflow declares "deploy to machines over SSH", multi-machine updates. Depends on language + daemon decision.
- **Factory self-hosting loop**: how Factory manages itself (its own repo + tracker) and short-term self-tracking story. Fog until the first milestone's shape is firm.
- **Workflow language ergonomics**: what writing a workflow actually looks like (libraries, primitives, composition). Depends heavily on language decision.
- **Path-to-other-users surface**: packaging, onboarding, config UI. Later.

## Out of scope

- Building the harness or an MVP inside this map — execution follows the spec in a later effort.
- Product/UI design for other users — audience path is noted, but design starts after the owner's needs are fully specified.
- Specific cloud-provider deploy integrations — v1 is SSH to the owner's machines, cloud is optional and unspecified.
