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
  14. Workflow code must be **typesafe, and functional where possible** (owner, 2026-10-16, via ticket 007); Starlark's untyped-Python shape is demoted from default. The workflow-language survey runs as ticket 011.
- Inspirations to study: mattpocock/skills, T3 Code, paperclip, pi.dev, [Harness²](https://arxiv.org/abs/2610.14224) (recursive agent harnessing — ticket 012), [Swamp Club](https://swamp-club.com/) (behavior-centric AI — ticket 013; owner request 2026-10-27).
- All research agents dispatched at charting time are working in parallel; their results land in their ticket files.

## Decisions so far

<!-- one line per closed ticket: title (URL/path) — gist -->

- [Which implementation language for the Factory harness](closed/001-research-harness-language.md): Go recommended for the harness core; owners write workflow code in Starlark or via a subprocess/JSON interface; OCaml and TypeScript stay as escape hatches.
- [Build on OpenCode + plugins, or own harness?](closed/002-research-build-vs-opencode-plugins.md): hybrid — Factory owns deterministic orchestration and uses OpenCode's embedded SDK as its first runtime behind a narrow adapter; Factory still builds durable run state, scheduling, approvals, tracker/PR integration, audit, recovery, execution isolation. Switching cost moderate if runtime state stays behind the adapter.
- [Tracker adapter interface & permissions](closed/003-research-tracker-adapters-and-permissions.md): draft capability adapter with a GitHub/Fizzy/Linear support+permission matrix; a list of per-agent permissions (incl. merge-adjacent) the harness must enforce itself.
- [Steer capture & observability](closed/004-research-steer-capture-observability.md): append-only, transcript-linked event log; OTel spans for timing/correlation only; privacy boundaries defined; evidence-linked mining with human approval; owner-facing run timeline.
- [Software-factory landscape survey](closed/005-research-software-factory-landscape.md): comparison of MetaGPT, ChatDev, AutoGen/AG2, OpenAI/Anthropic writes, Devin, Cursor, Copilot, Jules, OpenHands, SWE-agent; recurring spaghetti-agents anti-patterns cataloged with adopt/avoid recommendations. Amended 2026-10-14 (owner request): [Tessl](https://tessl.io) — the closed-source "context-driven factory" platform whose skills→loops→factory thesis challenges the code-defined-workflow premise, plus a five-system open-source factory sweep (AI Workflow, Open SWE, Vercel Foreman, gh-aw, agent-orchestrator; detail in `docs/research/oss-agent-factories-2026-10-14.md`) — no system yet combines multi-project scope, tracker neutrality, enforced capability control, and an authoritative issue→merge loop.
- [Which language does the spec commit the harness to?](closed/007-decide-harness-language.md): **Go** for the harness core (ADR-0001 with reopen triggers); OpenCode-seam cost deferred to ticket 006; workflow-code constraint tightened to **typesafe + functional where possible**, Starlark demoted — survey runs as ticket 011.
- [Survey typed functional workflow languages for a Go Factory core](closed/011-research-typed-functional-workflow-language.md): **typed, declarative workflow graph owned and interpreted by Go, with CEL for guards**; Dhall is the best-fit authoring syntax but `dhall-golang`'s v19-vs-standard-23.1 lag is an adoption gate — version the IR independently until a conformance spike passes. Fallbacks: versioned subprocess/JSON worker (native OCaml first, then Gleam/F#), then WASM/via-wazero when ABI+startup proven, Roc only post-0.1.
- [Study Harness² (recursive agent harnessing) as a Factory design input](closed/012-research-harness2-recursive-harnessing.md): adapt the **eight-component harness taxonomy** as the capability-profile vocabulary (with an enforcement axis — OpenCode freezes context assembly; only plugins+permissions enforce); **Harness²'s PPC recursion confirms 011's engine-owns-effects** (its scheduler is itself deterministic); its **improvement-library contract (cue/lesson/evidence, gated admission) upgrades closed/004** without re-opening it — keep human approval, add cross-run persistence. 006 and 009 gain reshape criteria, not re-openings.
- [Study Swamp Club's behavior-centric design as a Factory design input](closed/013-research-swamp-club-behavior-centric.md): **copy Swamp's patterns, don't build on it** (AGPLv3 core + closed registry + mandatory swamp-club.com account even for local runs). Swamp **corroborates 011** — its engine is independently a typed declarative workflow DAG with CEL guards. Adopt: YAML+JSON-Schema authoring frontend candidate beside Dhall, default-deny grant model (reshapes 009), skills+CLI harness-neutral seam across nine harnesses (lowers 002's switching-cost stakes), vaults / versioned data with lifetimes / OTel-audit split (reshape material for 010's daemon model); avoid v1: public registry, remote-worker fleet (SSH deploy stands). `@swamp/software-factory` = the issue-driven loop as data with **zero control over the driving agent** — considered for Factory's core, rejected.

## Not yet specified

- **Permission model for agents**: how profiles + always-ask interact with tracker permissions; exact autonomy levels. Hangs on harness decision (research-driven) and tracker research.
- **Where agents run**: local, remote worktrees, per-machine executors, sandboxing. Fog: depends on harness choice.
- **Observability schema**: what is recorded about every steer/tool call/file/network action, and how mining consumes it. Depends on harness decision.
- **The deploy pipeline**: how a workflow declares "deploy to machines over SSH", multi-machine updates. Depends on language + daemon decision.
- **Factory self-hosting loop**: how Factory manages itself (its own repo + tracker) and short-term self-tracking story. Fog until the first milestone's shape is firm.
- **Workflow language ergonomics**: what writing a workflow actually feels like (primitives, composition, whether pure typed graphs suffice vs authors expecting imperative code). The candidate survey (closed/011) chose the shape — typed graph + CEL guards, Dhall frontend pending a conformance spike — but the ergonomics detail stays fog until the first milestone's shape is firm (ticket 008); it then graduates as an ergonomics/prototype decision blocked by 008.
- **Path-to-other-users surface**: packaging, onboarding, config UI. Later.

## Out of scope

- Building the harness or an MVP inside this map — execution follows the spec in a later effort.
- Product/UI design for other users — audience path is noted, but design starts after the owner's needs are fully specified.
- Specific cloud-provider deploy integrations — v1 is SSH to the owner's machines, cloud is optional and unspecified.
