---
title: Build on OpenCode + plugins, or implement our own harness?
type: wayfinder:research
blocked-by: []
assignee: research-dispatch
---

## Question

Should Factory run its agents through **OpenCode + plugins** (reusing its agent runtime, session model, permissions, skill system) or implement its own agent execution layer? Study T3 Code's orchestration (delegation, worktrees, scheduling, pull-request linking), pi.dev's approach, and https://github.com/paperclipai/paperclip for what each teaches about structure without spaghetti: how they draw the boundary between deterministic orchestration and agent autonomy. Verdict: concrete integration surface (what OpenCode would have to expose via plugins/SDK), what must still be built, and a recommendation with the switching cost if the choice later reverses.
