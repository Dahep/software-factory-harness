---
title: Decide — resident daemon vs CLI/cron invocation model
type: wayfinder:grilling
blocked-by:
- closed/002-research-build-vs-opencode-plugins.md
- closed/005-research-software-factory-landscape.md
---

## Question

Sketch both consumer models in the spec, then decide: a resident daemon owning scheduling, workflow runs, monitoring loops, and an API for agents/UI; or pure CLI/cron invocation with no resident process. Constraints to weigh: recurring monitors and deploys want a resident process; sandboxing and credentials want one owner; the owner's tolerance for running services; and what the chosen substrate makes cheap.
