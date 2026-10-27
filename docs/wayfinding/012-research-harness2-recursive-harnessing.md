---
title: Study Harness² (recursive agent harnessing) as a Factory design input
type: wayfinder:research
blocked-by: []
---

## Question

Factory's agent layer currently treats the harness around each agent as runtime-provided (OpenCode's prompts, tools, skills, plugins via the RuntimeAdapter), and its mining-to-skills story (closed/004) assumes mining upgrades skills & workflows with human approval. Google Research's **Harness²** ("Recursive Agent Harnessing for an Open World", [arXiv:2610.14224](https://arxiv.org/abs/2610.14224), [code](https://github.com/google-research/harness2), [project page](https://harness2.github.io), Apache-2.0, includes an **OpenCode executor**) makes the harness itself a first-class, self-improving artifact. Study it and extract what Factory should adopt, adapt, or avoid:

1. **The eight editable harness components** (system prompt, guardrails, memory, tool guidance, subagents, skills, scripts, plugins): is this taxonomy a good vocabulary for Factory's per-agent capability profiles (ticket 009's open decision) and for what "harness" means behind the RuntimeAdapter?
2. **Task-level recursion — Propose→Probe→Compose** without ground-truth verifiers: does this belong in Factory as an optional agent-team pattern (a "harness improver" role alongside implementer/reviewer), and how does it reconcile with Factory's deterministic-graph stance (closed/011) where the Go engine owns effects?
3. **Harnessing-level recursion — the improvement library + evidence-backed lessons / EXPERIENCE.md**: how does this compare to closed/004's mining-into-skills-with-approval design? Do its automated lesson adoption and evidence-linking patterns strengthen or conflict with that closed decision?
4. **Practical fit**: paper claims and their caveats (benchmarks, k-scaling gains; proportional token cost per recursion step), code maturity (3 commits, 20.5k stars), what running it against an OpenCode executor actually requires.

Verdict must state: concrete adopt/adapt/avoid recommendations per concept, which map tickets (006, 009, closed 004, closed 011) the findings touch, and whether any of them has a reason to re-open. Date every claim 2026-10-27 with sources.
