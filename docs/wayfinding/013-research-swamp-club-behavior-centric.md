---
title: Study Swamp Club's behavior-centric design as a Factory design input
type: wayfinder:research
blocked-by: []
---

## Question

Swamp Club ([site](https://swamp-club.com/), [source](https://git.swamp-club.com/swamp-club/swamp/src/branch/main), manual at swamp-club.com/manual) argues AI systems should be built from **repeatable behaviors** — deterministic, named, reusable operations composed into workflows — rather than token-hungry agent-centric designs. This overlaps Factory's ambition almost point for point and may change Factory's design. Study it deeply and extract what Factory should adopt, adapt, or avoid:

1. **The behavior model**: what a "behavior" actually is — its definition format, typing (they show zod schemas), invocation surfaces (harness tool, CLI, Slack, API, webhook), and how behaviors compose into workflows. Compare directly with closed/011's decided **typed workflow graph + CEL guards in Go** — same idea? Where does their authoring/ergonomics beat or lose to that shape?
2. **Extensions registry** (1,850+ behaviors incl. `@swamp/software-factory` — study that one especially, it is a prior art close to Factory itself): packaging, versioning, distribution, trust model. What does a mature behavior ecosystem teach Factory about its (still fogged) path-to-other-users and reusable workflow-like primitives?
3. **The seams with any harness** (Claude Code, OpenCode, Pi…): how they inject behaviors as tools into arbitrary harnesses. Does this strengthen or threaten the hybrid substrate decision space around ticket 006 (Factory could itself be a Swamp behavior pack vs a Swamp competitor)?
4. **Platform mechanics**: secret vaults, structured datastore with lifetimes/query, OTel/SIEM observability, `swamp serve` with grants & groups, remote workers/fleet (build-7f3a…), scale-out story. Which of these map onto Factory's open decisions (009 capability control, 010 daemon-vs-CLI, deploy pipeline fog) — and confirm against primary docs, not marketing copy.
5. **License, self-hosting, and independence**: source availability and license terms at git.swamp-club.com, extension registry terms, and what "building on Swamp" would cost Factory in dependence vs learning-for-free.

Verdict must state: per-concept adopt/adapt/avoid recommendations with reasons, which map tickets the findings touch, and whether any open decision (006, 009, 010) or recent closure (011) has reason to re-open or reshape. Date claims 2026-10-27; prefer primary docs, the repo, and third-party field reports (reset.dev, dieter.plaetinck.be, mcginniscommawill.com, stack72.dev) over the homepage's marketing.
