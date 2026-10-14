---
title: What should the tracker adapter interface support (Fizzy, Linear, GitHub…) and how do permissions map?
type: wayfinder:research
blocked-by: []
assignee: research-dispatch
---

## Question

Factory manages multiple projects, each with its own issue tracker. Define the **abstract capabilities and data model** a tracker adapter must expose (issues, labels/states like needs-triage → ready, assignments, dependencies/blocking, comments, history/audit) by studying GitHub Issues (via `gh`), https://github.com/basecamp/fizzy, and Linear's data model and permission systems. Verdict: a draft adapter interface (capability list), what each target tracker can/can't support, and the **permission concern**: how per-agent tracker permissions (read, comment, create, assign, close, merge-adjacent actions) map onto each tracker's own permission model, and what the harness must gate itself.
