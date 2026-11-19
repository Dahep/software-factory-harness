---
title: Shape the deploy pipeline (SSH to the Owner's machines)
type: wayfinder:grilling
blocked-by:
- closed/010-decide-daemon-or-cli.md
---

## Question

The map's standing input says deployment is **SSH to the owner's machines, cloud optional** (map note #7), and the deploy fog was held back by the language and daemon decisions — both now settled (Go core, resident daemon, Project VMs). Make it specifiable: how does a Workflow's deploy stage reach the owner's machines, and what does it declare?

Open questions to settle with the Owner:

1. **Deploy stage shape.** A Stage in the Workflow Artifact, or a separate post-merge Workflow? What does it declare — target machines/hosts (how are they named and discovered — static list, inventory file, SSH config?), the artifact (built binary? container image? repo checkout?), the commands, and idempotency.
2. **Mechanism.** Plain SSH from the daemon host (with the owner's `ssh` config/keys), SSH from inside the Project VM (requiring forwarded agent or bound secret; note devvm SSH-agent modes and the "git-over-SSH is not proxied" limitation from ticket 017), or a hybrid. Who holds deploy credentials, and does the Project VM ever get them?
3. **Gates and approvals.** Is a deploy gated by the merge Checkpoint, a separate Owner Checkpoint, or workflow-defined gates (health check, smoke test)? What does failure do — rollback, halt, Egress Request?
4. **Multi-machine updates.** Sequential per-host vs parallel; staging vs production hosts; drain/restart semantics; health verification and rollback story.
5. **Measurement.** What every deploy records (per-host outcome, duration, version), consistent with directive #15, and where it lives (daemon host vs project log).

Research tickets worth loading: closed/017 (devvm secrets/SSH), closed/006 (runtime adapter), closed/010 (daemon). If the Owner's machines are the desktop (omarchy) and the VPS (hersan), the grilling should ground itself in those two real hosts.
