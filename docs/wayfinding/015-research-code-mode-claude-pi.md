---
title: Study Claude Code Code Mode and Pi Codemode as Factory design inputs (Swamp companion)
type: wayfinder:research
blocked-by: []
---

## Question

Two major harnesses now expose **code mode** — the model writes a program that composes tool calls, instead of calling tools one round trip at a time. Companion to [Study Swamp Club's behavior-centric design](closed/013-research-swamp-club-behavior-centric.md): Swamp packages *durable, registry-backed behaviors*; code mode composes *ephemeral, per-step* calls in code. Study both implementations and extract what Factory should adopt, adapt, or avoid:

1. **Exact mechanics.** (a) **Claude Code Code Mode** — experimental since 2.1.323 (Nov 2026), off by default, enabled via env var, cannot be enabled per-project; model writes JavaScript "that makes the tool calls," runs "in your session"; documented provider restrictions (not on Bedrock/Vertex/Foundry/custom gateways); the "who checks the calls" question. (b) **Pi Codemode** — Pi 1.0 (Oct 1, 2026): embedded QuickJS-in-WASM sandbox, tools as code APIs with deferred exposure (`searchTools()`, `describeTool()`, inline token budget), scripts can call non-LLM models directly, state in session transcript; the design decision that the sandbox lives in the harness not the server (composition across vendors); Armin Ronacher's writeup. Get primary sources for both (Claude docs, Pi docs, release notes) before third-party commentary.
2. **The three-way comparison** — Swamp behaviors vs code mode vs closed/011's Go-owned typed workflow graph. Where does each sit on the durability/determinism spectrum? Is "workflow code" in Factory really the same object as code-mode scripts (LLM-authored, ephemeral, unverified) — or the opposite (typed graph, engine-owned, replayable)? Name the boundary precisely; a conflation would poison the spec.
3. **Factory implications.** Should Factory expose its primitives (issue/task/agent/gate/tracker ops) as **code APIs inside agent sessions** — i.e. code mode *inside* the RuntimeAdapter, so agents can compose Factory calls cheaply — while the typed graph stays the durable orchestration layer? What does that mean for the RuntimeAdapter contract (ticket 006), the loop's implementer/reviewer wave (008), and capability control (009 — a sandboxed JS surface is a permission boundary, per Pi's no-filesystem/no-network constraints)?
4. **Measurement (directive #15).** Code mode's pitch is fewer round trips and less context; what published evidence is there (token savings, latency, filtering examples), what is unmeasured hand-waving, and what metrics would Factory track if it adopted the pattern? Note Ronacher's own caution that composition gains depend on the API shape.
5. **Maturity and risk.** Experimental vs shipped, model/plan restrictions, community pushback (Pi's MCP reversal and codemode criticism), security model (sandbox limits, what the caller can see) as of 2026-11-18.

Verdict must state: per-concept adopt/adapt/avoid with reasons, the precise boundary between code-mode composition and Factory's typed graph, which map tickets (006, 008, 009, closed/011, closed/013) are touched and whether any should re-open or reshape, and what Factory measures first. Date claims 2026-11-18; primary docs and release notes over aggregators.
