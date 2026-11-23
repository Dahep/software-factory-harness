# How workflow code inside the Project VM reaches daemon infrastructure

**Research date: 2026-11-23.** Ticket: [software-factory-harness#11](https://github.com/Dahep/software-factory-harness/issues/11). Feeds the engine-boundary tickets (#13), the program contract (#18), the activation envelope (#20) and Owner checkpoints (#21).

Every devvm claim below is cited to a primary source: devvm's docs at [devvm.dev](https://devvm.dev) (pages last updated **2026-11-06**), devvm's source at `github.com/devvmhq/devvm` **main `06f7221` (2026-11-21), `VERSION` 0.2.0-rc.1**, Lima's source and docs, OpenSSH 10.6's own manual pages, and the locally installed `devvm` **0.1.0** CLI. Where the installed binary (0.1.0) is older than main, the citation says which one.

## Verdict

**Carry mediated calls on the SSH exec session the daemon already opens to invoke the activation, over an inherited file descriptor — not over any listener in the VM.** Concretely:

1. The daemon invokes the handler the way it already must: `devvm host --no-input` (ensure the VM is up and get its alias), then `ssh <alias> -- factory-activate …`. That one SSH connection is the whole transport.
2. `factory-activate`, a small supervisor in the Project VM image, creates a socketpair, starts the handler with **fd 3** as its control channel, and speaks **JSON-RPC 2.0 in length-prefixed frames** with the daemon on the SSH channel. The handler's stdout/stderr remain logs; the daemon captures them for the activation envelope.
3. **Nothing in the VM listens.** No Unix socket, no TCP port, no proxy rule, no vsock device. There is therefore no ambient endpoint for an agent session to `curl`: the capability is an inherited descriptor in the activation's process tree, the same shape as the "explicit Task workdir capability" the rewrite already gives a handler.
4. The channel is **not** an authentication boundary between handler and agent, and must not be sold as one. The VM user has passwordless sudo, so any code in the Project VM is root and can reach any in-VM credential, file or descriptor. The honest statement is: *the channel identifies the activation, not the process*. Security therefore comes from the daemon side: a closed, state-scoped operation set, parameters derived from the activation record, and host-side re-verification for the dangerous operations (push, merge, tracker).
5. Keep two things impossible from inside the VM regardless of who calls: **host identity** (no credential to push or merge ever enters the VM) and **merge without a live Owner approval** (approval is minted host-side, bound to the head SHA and the feedback digest, and re-checked inside the merge transaction).

Secondary, allowed but not recommended for v1: a per-activation TCP remote forward in devvm's link range `127.77.0.0/16` to a host-side Unix socket (devvm already uses exactly this primitive for VM links). It is a fine *ergonomic adapter* for tools that need an address; it is a worse security posture (a VM-visible listener) and it squats a range devvm allocates.

A proxy allow rule naming `127.0.0.1:<port>` (the "HTTP through the devvm proxy" option) is technically possible on the `allowlist` tier, but it opens a persistent, VM-wide hole in the one boundary devvm exists to maintain, and its credential would be readable by the same root-capable agent. Do not adopt it.

## 1. What the channel must carry, and what it must never carry

From the rewrite's decisions (issue #8): one re-entrant handler per state, invoked by the daemon, receiving a workdir capability and typed state, performing direct effects inside the Project VM; the daemon owns admission, queueing, worktrees, activation invocation and recording, checkpoints, push/PR/merge, and tracker transitions.

**Mediated set** (each a typed op with an idempotency key, a receipt, and an audit row):

| Op | Returns | Notes |
| --- | --- | --- |
| `dispatchAgent(rosterEntry, input, outputs, deadline)` | typed Outcome, artifacts, transcript ref, usage | ticket #14 owns the shape; the handler blocks or receives progress notifications |
| `push()` | remote branch + SHA | no arguments: the daemon derives remote, ref, worktree and expected base from the activation record, reads the tip from the VM itself, never force-pushes, never pushes the base branch |
| `openOrUpdatePR(title, body)` | PR number/URL + head SHA | one PR per Task branch; repository and base fixed by project config |
| `requestMerge(pr)` | merged SHA or typed refusal | the daemon uses its own gate records, the PR's live state, the head SHA, the feedback digest and the live Owner approval; the caller supplies no evidence; executes with `--match-head-commit` (§3.8 of the current spec) |
| `trackerTransition(state)`, `trackerComment(body)` | provider ids | only the Task's issue, only transitions legal from the recorded state |
| `requestCheckpoint(ask, artifacts)` | pending checkpoint id (or the decision, if the design blocks) | ticket #21 decides park-vs-block; the call can never approve itself |
| `newWorktree()`, `discardWorktree()` | worktree path + branch, or confirmation | paths chosen by the daemon under the project root; bounded by the concurrency setting; discard refuses a dirty worktree unless the workflow says otherwise and the daemon records it |

Reads of the tracker stay direct inside the VM with the read-only token (§5.3); they need no op.

**Never exposed** (this list is the threat model, not a stylistic preference): any secret value or host-side secret inventory; any host shell, process, file read or path outside the project's own run artifacts; any raw `git`/`gh` command; any caller-chosen repository, remote, ref, base branch or force flag; any merge that is not backed by a live Owner approval for the current head; any tracker write outside the Task's issue and legal transitions; Owner impersonation or approval minting; VM lifecycle or devvm config (`devvm network allow`, `devvm secret set/use`); another Project's or Task's data; a "record this gate as passed" call (gate verdicts come from the activation's returned state and the pinned definition digest, never from a caller assertion).

## 2. The environment facts that decide the design

These are the constraints every option must fit. They are stronger than a generic VM: devvm deliberately closes the VM→host direction.

- **No devvm API, daemon, or SDK.** The CLI is the automation surface; `--no-input` and versioned `--json` are the contract; the headless path is `devvm host --no-input` then plain `ssh <alias>` (ticket 017; [command line](https://devvm.dev/docs/using/command-line/)). devvm's `internal/daemon` package only supervises its own proxies/forwarders — it is not a service API (`internal/daemon/daemon.go:1-20`).
- **The VM's only network egress is its proxy.** On Linux, QEMU runs through a devvm wrapper that adds `restrict=on` and a single `guestfwd` to the VM's proxy `192.168.5.4:3128`; the wrapper refuses any other `-netdev` shape (`internal/backend/lima/qemu.go:21-42,93-138`). DNS resolves only in the proxy. "Direct connections, DNS, UDP and connections to the host's own services fail at once, while forwarded ports, mounts and ssh keep working" ([Lima](https://devvm.dev/docs/internals/lima/); [Security model](https://devvm.dev/docs/internals/security/)).
- **The guest sshd deliberately refuses the reverse direction.** The image writes `/etc/ssh/sshd_config.d/00-devvm.conf`: `AllowTcpForwarding all`, **`AllowStreamLocalForwarding local`**, `GatewayPorts clientspecified`, **`PermitListen 127.77.*:*`**, `PermitTunnel no`, `X11Forwarding no` (`assets/layers/base.sh:185-196`). The source comment states the intent: "no remote socket forwards, tunnels or X11 … the boundary is the host's ssh, which asks for no other remote forward and accepts a channel only for a forward it asked for." So `ssh -R /vm/path.sock:…` — the obvious "expose the daemon's Unix socket into the VM" move — is **refused by the shipped image**; only a guest root could change that.
- **The host's ssh entries pin everything else.** devvm's Host block sets `StrictHostKeyChecking yes`, a per-start `UserKnownHostsFile`, `ControlMaster no`, `ControlPath none`, `PermitRemoteOpen none`, `ProxyCommand none`, `Hostname 127.0.0.1`, a recorded port, the VM login key (`internal/sshconfig/sshconfig.go:183-224`). `PermitRemoteOpen` only constrains SOCKS-style remote forwards (OpenSSH `ssh_config(5)`), so it does not block a streamlocal or a destination-specific `-R`; the sshd policy above does.
- **There is no host mount to abuse.** Without `--clone` the project folder is mounted read-write; with `--clone` the VM mounts only shared tools and agent config folders, and work returns through `devvm clone fetch` ([Security model](https://devvm.dev/docs/internals/security/); [clone](https://devvm.dev/docs/using/clone/)). Factory uses `--clone` (§2.5).
- **Everything in a VM is untrusted, and the VM user is root.** "devvm treats everything in a VM as untrusted, including a coding agent with root, because the VM's user has passwordless sudo" ([Security model](https://devvm.dev/docs/internals/security/)). This single sentence decides the authentication question in §4.
- **Precedent for a channel credential:** the per-VM proxy requires the VM's own random password in `Proxy-Authorization` because "other programs on the host can also reach that port, so the port alone doesn't identify the VM" ([Network tiers](https://devvm.dev/docs/internals/network/)). devvm's per-VM placeholder suffix is the same pattern. It authenticates the *VM*, never a process inside it.

## 3. Transport options

### T0 — Direct HTTP over the VM bridge (`192.168.5.2`, `host.lima.internal`)

**Not available on a confined tier.** On Linux the wrapper runs QEMU with `restrict=on` and a single `guestfwd`; the guest has no route to the host except the proxy (`internal/backend/lima/qemu.go:21-42`; [Lima](https://devvm.dev/docs/internals/lima/)). The bridge address is reachable only on the `open` tier, whose proxy "reaches every host and address … this machine's `localhost` and your LAN included" ([Network tiers](https://devvm.dev/docs/internals/network/)). Using it would mean running the Project VM unconfined, which contradicts the containment contract (§5.1). Reject.

### T1 — SSH exec channel + inherited control fd (recommended)

**What it is.** The daemon's activation invocation *is* the transport. `ssh` starts `factory-activate` in the VM; the supervisor creates a `socketpair`, spawns the handler with one end on **fd 3** and the activation envelope on stdin, and multiplexes framed JSON-RPC between fd 3 and its own stdout. The handler never dials anything; it writes to a descriptor it was born with.

**Requirements.** `devvm host --no-input` + the pinned ssh entry (both exist); a supervisor binary plus a per-language client shim shipped in the Project VM image (a devvm user layer can install both — [Customizing images](https://devvm.dev/docs/using/customizing/)); a frame format (4-byte big-endian length + JSON is enough).

**Costs.** Build the supervisor and the SDK; a frame protocol to version; handler subprocesses inherit fd 3 unless it is `CLOEXEC` by default (see §4.4); SSH connection lifetime equals activation lifetime, so a dropped connection is an activation with an unknown outcome (record it; direct effects persist).

**Tier interaction.** None. The bytes ride an SSH channel the host opened; the VM never makes a connection. Mediated calls therefore work on tier `none`, and **a workflow can push and merge with no network egress at all** — a clean separation of "infra capability" from "internet capability". No `devvm network` rule, no proxy, no `network log` entry (the daemon's own transition log is the audit).

**Why it wins.** It is the only option with **no ambient authority**: there is no address, path or port in the VM that another process can discover and call. It needs zero devvm changes and does not touch devvm's reserved link range, its sshd policy, its proxy, or its tiers.

### T2 — SSH remote TCP forward in `127.77.0.0/16` to a host Unix socket

**What it is.** `ssh -R 127.77.0.1:<port>:/run/factory/act-<id>.sock <alias> -- factory-activate …`: the guest sshd listens on a `127.77.x.y` address inside the VM; each connection is tunneled to a per-activation Unix socket on the host. The handler (or any tool) connects with a normal TCP client. This is **exactly the primitive devvm uses for links**: a link master connection plus `-O forward -R <127.77.x.y:port>:<host unix socket>` (`internal/vmssh/links.go:34-38,835-847`), and the sshd policy exists to permit it (`base.sh:185-196`).

**Requirements.** SSH as in T1; a per-activation host Unix socket; a free port on the VM's loopback (allocate and retry; whether `PermitListen` accepts a dynamic port `0` is unverified). No devvm change.

**Costs.** The VM now has a listener for the activation's duration, reachable by every process in the VM; the 127.77 range is devvm's link address space, so a collision with a real link is possible (detectable: the bind fails); the SSH connection must stay up for the activation (or use a control master). Audit is again the daemon's log, not `devvm network log` (ssh channels bypass the proxy).

**Verdict.** Keep as a **shim** behind the same JSON-RPC protocol if the chosen workflow language's tooling cannot use an fd, or for debugging with `curl`. Not the primary. Do not let its existence redefine the auth model: a port is ambient.

### T3 — HTTP to the host through the devvm proxy with an address rule

**What it is.** Add a local rule such as `devvm network allow 127.0.0.1:7100` (devvm's own docs use `devvm network allow 127.0.0.1:5432` as the example) so the proxy's internal-address floor lets the VM reach a daemon HTTP listener on the host loopback. Confirmed in source: an explicit address rule passes the floor (`internal/proxy/policy.go:756-774`, `internal/proxy/dial.go:91-100`) and applies from the next connection ([Network tiers](https://devvm.dev/docs/internals/network/)).

**Requirements.** Tier `allowlist` — on `internet` and `none` only denies apply, so an allow cannot be added there; a host-side TCP listener; a per-activation bearer token (readable by any agent, so it is hygiene, not auth); an Owner-applied local rule (outside the artifact, ADR-0009).

**Costs.** A **persistent** hole for the VM's whole lifetime, not just the activation; any process in the VM can reach it; it contradicts the "the VM reaches nothing but its proxy on the host" sentence in devvm's own model; the local rule drifts per machine and is invisible to the artifact digest; the daemon must add a second, TCP-facing API surface beside ADR-0005's Unix socket. Its one genuine advantage is `devvm network log --json` coverage of every request.

**Verdict.** Reject for v1. If an HTTP-ish surface is ever wanted, T2 gives it without the proxy hole and without the tier restriction.

### T4 — Unix socket remote-forward of the daemon socket (`ssh -R /vm/path`)

**Impossible on the shipped image.** `AllowStreamLocalForwarding local` permits only host→VM streamlocal forwards (what VS Code and Lima use), and devvm's comment says "no remote socket forwards" (`base.sh:185-196`; `sshd_config(5)`). Only a guest root could flip it — i.e. the agent could, which is not a security argument. Reject.

The direction devvm *does* allow is the one Factory needs for the runtime server: `ssh -L /host/path.sock:/run/opencode.sock <alias>` (local, host→VM) is permitted and is how the daemon reaches the OpenCode server inside the VM. It cannot carry a VM-initiated call, because the VM never dials; the daemon would have to poll a socket the VM writes to, which is a mailbox with extra steps.

### T5 — vsock

**Unavailable on this host.** devvm configures no virtio-vsock device (`internal/backend/lima/` has none); Lima's QEMU driver carries the guest agent on a virtio-serial port, and its SSH-over-`AF_VSOCK` support exists only for VZ/krunkit VMs on macOS with newer systemd ([Lima port forwarding docs](https://lima-vm.io/docs/config/port/), [Lima internals](https://lima-vm.io/docs/dev/internals)); QEMU on Linux hosts does not implement it ([lima-vm/lima#4209](https://github.com/lima-vm/lima/issues/4209), open). Adding a vsock device would mean changing the QEMU args devvm's wrapper pins and refuses to alter (`qemu.go:93-138`). Reject for v1; revisit only if devvm ships a supported host channel.

### T6 — The handler runs `ssh` from the VM to the host

The VM has no route to the host on confined tiers (restrict=on), no host credential, and giving it one would put host identity inside the sandbox — the exact escalation Factory's containment contract forbids (§5.3, §5.4). A forced-command key would still execute on the host outside the daemon's state machine. Reject.

### T7 — File mailbox (worktree, mounted folder, git refs)

Under `--clone` there is no host mount; the only return path is git. Polling a directory is not RPC (latency, ordering, no backpressure, races with git operations), and a mounted host folder is a host-write surface. Reject.

### T8 — gRPC / HTTP framing

Neither is a transport. gRPC is a candidate *encoding* on top of T1/T2/T3: HTTP/2 over a pipe needs a custom dialer, and it buys streaming and codegen at the cost of a heavier toolchain per workflow language. The op set is small request/response plus progress notifications, so JSON-RPC over a length-prefixed stream is cheaper and debuggable. If the language chosen in ticket #9 ships gRPC but no JSON library, gRPC over the same fd is the fallback.

### Transport summary

| | T0 bridge HTTP | T1 SSH exec + fd | T2 `-R` 127.77 TCP→host sock | T3 proxy rule → host TCP | T4 `-R` unix sock | T5 vsock | T6 VM→host ssh |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Exists on shipped devvm | only on `open` | yes (ssh) | yes (same primitive as links) | yes, `allowlist` tier only | **no** (sshd policy) | **no** (Linux/QEMU) | no route/credential |
| Listener in VM | — | **none** | TCP on 127.77.x.y | none in VM; host TCP | wanted; refused | — | — |
| Ambient authority for agents | yes | **none** | yes | yes, persistent | yes | — | — |
| Works on tier `none` | no | **yes** | yes | no | — | — | no |
| devvm config needed | `open` tier | none | none | local allow rule + tier | guest root | QEMU change | egress rule + host key |
| Audit source | `network log` | daemon log | daemon log | `network log --json` + daemon | — | — | — |
| Build cost | — | supervisor + SDK | supervisor + host sock | daemon HTTP + token | — | devvm/Lima work | — |

## 4. Authentication: handler versus agent sessions

### 4.1 The honest answer

**Inside one Project VM there is no enforceable distinction.** The VM user has passwordless sudo, devvm itself treats "a coding agent with root" as untrusted (Security model), and every candidate in-VM credential fails the same three tests:

- a token in the environment or a file is readable by the agent (`/proc/<pid>/environ`, the file itself);
- a Unix socket is reachable by any process of the same user, and 0600 modes cannot distinguish processes of one uid;
- the fd is duplicable through `/proc/<pid>/fd/3` by the same uid (Yama's `ptrace_scope=1` restricts `PTRACE_MODE_ATTACH`, not the `PTRACE_MODE_READ` check that guards `/proc/<pid>/fd` and `/proc/<pid>/environ`; verified on the desktop with `ptrace_scope=1`: a same-uid process opened another's pipe fd and read its environ), and root makes it moot anyway.

So the question "what stops an agent from calling the same endpoint" has a precise answer per transport:

| Transport | What an agent session must do to call it | Is that a boundary? |
| --- | --- | --- |
| T1 fd | scan `/proc/*/fd` or read `/proc/*/environ`; there is no address to call by accident | no (same uid/root), but blocks ambient and opportunistic use |
| T2 TCP | connect to a scanned `127.77.*` port, or read `FACTORY_CONTROL_ADDR` from env | no |
| T3 proxy | read env/argv for the URL and token, then `curl` | no, and permanent |
| T4 socket | `curl --unix-socket <path>` | no |
| T6 host ssh | needs a host key it does not have | yes (but it breaks containment) |

Only a kernel-enforced identity change helps: run the OpenCode server (and the agents' processes) as a **different uid without sudo**, and keep the handler's fd or a 0600 socket for the handler's uid. That is real isolation, but it cuts against v1's "full agency inside the Project VM" (§5.2), needs image work to add users, and still cannot stop an agent from writing the worktree the handler later reads (prompt injection moves to the data path). Record it as the post-v1 escalation when Capability Profiles arrive, not as a v1 mechanism.

### 4.2 What the channel can authenticate: the activation

The daemon knows which SSH connection it opened, for which Task, state, worktree, branch, base SHA and definition digest. The daemon writes the activation envelope on stdin, including a per-activation random nonce (never argv); the supervisor's first outbound frame echoes the activation id and nonce. The daemon accepts **no inbound connection at all**: the channel exists only because the daemon opened it, which is also why it cannot be port-scanned or pre-bound by another process. Consequences worth keeping:

- **Attribution**: every mediated call is recorded against the activation and Task, so an audit row can never be misattributed to another Task.
- **Scoping**: the daemon refuses an op that the state's compiled handler does not declare, and refuses every parameter that would point outside the activation's Task. A stolen fd cannot reach another Task's branch, issue, PR or worktree.
- **Replay/CSRF hygiene**: the nonce stops a stale or host-side process from driving a fresh connection, and stops cross-VM reuse. It does not stop an in-VM thief, and the design should not pretend otherwise.

Treat the op allowlist as a per-state syscall filter compiled from the workflow program (ticket #18): during `implement`, no `requestMerge` exists; during `review`, no `discardWorktree`; the merge op only exists in the state whose code is the merge gate. This bounds the blast radius by *state*, which is the only axis an in-VM caller cannot forge.

### 4.3 Why not a bearer token

A per-activation token is still worth putting in the handshake for correlation and for refusing accidental cross-connection calls, but it must be described as **not a secret**: the agent can read it, and designing as if it cannot is how a "secure" endpoint becomes a false claim. The daemon's authorization must be correct for *any* caller in the VM, because that is the real set of callers.

### 4.4 Capability leak through handler subprocesses

The handler will run tests, scripts and formatters. If fd 3 is inherited by default, every such child holds the mediated capability — including the project's own test suite, which an agent may influence. Default the fd to `CLOEXEC`; make `factory-ctl` (the CLI shim) take an explicit `--fd 3` hand-off when the workflow intends to grant it. State in the contract that "any process the handler hands the control fd to can act as the activation" — the same caveat a workdir capability carries.

## 5. Egress allowlist and local devvm config, per transport

The allowlist, provider endpoints and secret scopes are local devvm config, not part of the Workflow Artifact (ADR-0009). That makes any transport that depends on a local rule **machine-specific state the artifact cannot version**:

- **T1/T2 (ssh)**: no egress rule at all. SSH is carried by the backend's own connection, outside the guest network (`restrict=on` leaves Lima's ssh forward working — `qemu.go:21-30`; links "don't use the VM's network"). Works under `open`, `internet`, `allowlist`, `none`. The workflow's own internet work still follows the tier; its infra work does not.
- **T3 (proxy)**: needs tier `allowlist` *plus* a rule naming a host address. On `internet` and `none`, only denies apply, so the rule cannot take effect ([Network tiers](https://devvm.dev/docs/safety/network/), "for an allow on the internet or none tier, that only denies apply there"). The rule is applied by the Owner/machine, recorded only in local config, and invisible to the contract digest (§5.1 records local differences, not drift). A workflow that runs on a machine without the rule cannot reach the daemon at all — a silent, per-machine failure mode.
- **T5 (vsock)**: no interaction, because it does not exist here.
- **Audit**: only T3 appears in `devvm network log --json`, because only T3 goes through the proxy. T1/T2 calls are invisible to devvm; **the daemon must be the audit source for mediated calls** (transition log: op, activation, Task, decision, duration, result). Do not claim devvm's network log covers the control channel.

## 6. What devvm already provides that Factory should reuse

| devvm surface | Reuse |
| --- | --- |
| `devvm host --no-input` (starts the VM if stopped, ensures the Include line, prints the alias and the folder) | the daemon's "ensure VM and get ssh target" step; idempotent per activation or per VM start |
| Per-VM ssh entry with per-start pinned host keys, login key, loopback port, `ControlMaster no` (`internal/sshconfig/sshconfig.go:183-224`) | the SSH trust for T1/T2; do not invent a second key or host-key mechanism |
| Guest sshd policy (`AllowStreamLocalForwarding local`, `PermitListen 127.77.*:*`) | tells Factory exactly which forward directions are sanctioned: host→VM exec/local forwards yes, VM-side streamlocal no, VM-side TCP only in the link range |
| Links: `-R <127.77.x.y:port>:<host unix socket>` over a dedicated master (`internal/vmssh/links.go:835-847`) | the proven primitive behind T2, and the reason the range exists; also a warning that the range is devvm's, not Factory's |
| Folder identity + `--clone` (no host mount) | removes the file-mailbox option and the host-path class of attacks |
| Per-VM proxy password + per-VM placeholder suffix | the pattern for activation-scoped correlation (random, per channel, never in argv) — copy the pattern, not the false claim of process identity |
| `devvm network log --json` | audit for anything that does traverse the proxy; irrelevant to T1/T2 |
| User layers (`devvm layer new`, `devvm setup --layers`) | ship `factory-activate`, the SDK and the CLI shim in the Project VM image |
| `devvm limactl` escape hatch | explicitly unconfined; Factory must never use it in a run path |
| No API/SDK, no lifecycle hooks, no host-service concept, no documented VM→host daemon/MCP pattern | confirms the channel must be built on SSH exec, not "configured" |

## 7. Blast radius

Assume the worst realistic case: any code in the Project VM (handler, injected agent, compromised tool) can issue any op the current state declares, through the activation's channel. What it can and cannot do:

| Op | Worst case if abused | Contained by |
| --- | --- | --- |
| `dispatchAgent` | extra sessions and model spend; another agent working in the Task worktree | roster allowlist, per-activation session cap, deadline, state scope; v1 has no budget cap (§5.7), so a rate/session cap is the only brake |
| `push` | a malicious or misleading commit on the Task's own remote branch | daemon reads the tip from the VM, fixed remote/ref/base, no force, no base-branch push; the result still needs a PR and Owner merge |
| `openOrUpdatePR` | PR with misleading text; PR noise | one PR per Task branch, repo/base fixed, visible review surface |
| `requestMerge` | nothing without approval; with a stale approval, nothing | Owner approval minted host-side, head SHA + feedback digest + checks re-verified inside the merge transaction, `--match-head-commit` (§3.7–3.8) |
| `trackerTransition`/`trackerComment` | a premature but legal state change or a misleading comment on the Task's issue | legal-transition check against the recorded state, Task's issue only, rate limit, audit |
| `requestCheckpoint` | Owner-inbox noise | rate limit; a checkpoint cannot decide itself; the Owner's decision never travels through the VM's channel |
| `newWorktree`/`discardWorktree` | resource churn; destroying a worktree with uncommitted work | concurrency cap, daemon-chosen paths, dirty-worktree refusal recorded as an explicit workflow decision |
| old channel/unknown activation | — | nonce + activation id mismatch is refused and alerted; should be zero |

**Must remain impossible from inside the VM** (each enforced by a missing credential or a missing op, not by a check in the handler):

1. **Host write identity.** The host's git/gh credentials never enter the VM; the VM token is read-only (§5.3–5.4). A caller can *request* a push; it cannot perform one, choose the remote, or force.
2. **Merge without approval.** No approval value exists in the VM; approvals are host-side records bound to a head SHA and feedback digest; the merge call re-reads provider state.
3. **Secret reads.** Values live host-side in devvm's store/keychain; the VM sees placeholders; the mediated API has no op that returns a secret, and the daemon must never add one for convenience (no "env dump", no "read host config").
4. **Host execution / path traversal.** No op takes a host path, command, or ref; worktree ops use daemon-chosen paths only.
5. **Tracker authority outside the Task.** The VM has no write token; the daemon's op only moves the Task's issue along legal transitions.
6. **VM lifecycle and devvm config.** `devvm` is a host CLI; the VM holds no control path to it. Egress requests are derived by the daemon from blocked network logs (§5.6), never from a VM call.
7. **Cross-project reach.** One VM per project, one activation per Task; a call is bound to its activation record, so another project's Task/PR/issue is not addressable.

**When a handler tries an infra operation directly** (the legibility question ticket #13 inherits), refusal comes from the environment, not from a prompt: a direct `git push` fails at the read-only token; a direct tracker mutation fails at the token's scope; a direct merge is unreachable (no token, branch protection); any attempt to reach a host service fails at the proxy with a `403` naming the internal address, or times out on a confined tier. Factory should surface those as typed failures in the activation's evidence (the handler's error, the exit code, the proxy reason from `network log --json`) instead of letting a retry loop look like a stall.

A residual risk to record honestly (feeds #13/#21): because gates are workflow code running in the VM (decision 7), an agent that can influence files the handler reads can influence a *gate verdict*. The mediated channel cannot fix that; it only ensures verdicts are recorded with the pinned definition digest and that merge still requires the Owner.

## 8. Recommended shape for the downstream design

1. **Invocation and channel.** The daemon, per activation, runs `devvm host --no-input` in the project folder, then one SSH exec: `ssh <alias> -- factory-activate --activation <id>`, writing the activation envelope (state, workdir path, branch, base SHA, definition digest, allowed op set, nonce) to stdin. `factory-activate` starts the handler with fd 3 and returns its exit status. No listener is created in the VM.
2. **Protocol.** JSON-RPC 2.0 over 4-byte length-prefixed frames on fd 3, 1 MiB frame cap, one in-flight request per activation by default (ids allow more later), progress notifications for long ops, typed error codes (`not_in_state_capability`, `task_mismatch`, `stale_approval`, `dirty_worktree`, `rate_limited`, `provider_failed`), and an idempotency key of `(activation id, op, sequence)` so a retried push/PR is not duplicated.
3. **Authorization.** The daemon derives every parameter from the activation record; the op set is compiled per state; anything outside it is refused and logged. Never accept caller-supplied repo, remote, ref, base, path or evidence.
4. **Dangerous ops.** `push` reads the branch tip from the VM and pushes with the host identity; `requestMerge` re-reads the PR, checks, head SHA and feedback digest and requires the live Owner approval inside the transaction; tracker ops validate the transition against the recorded state.
5. **Checkpoints.** Do not hold the SSH channel open for an Owner decision. A handler that needs a decision returns an `awaiting-decision` state; the daemon parks it and re-invokes with the decision (ticket #21's park-vs-block question, with this transport constraint as input). If #21 chooses a blocking `awaitDecision`, keepalives (`ServerAliveInterval`) and resume-safe semantics are mandatory; the transport supports it but does not make it safe.
6. **Failure semantics.** A dropped connection is an activation with an unknown outcome: record `Crashed`/`unobserved`, keep the worktree digest, leave direct effects, and let the failure edge decide. No replay guarantee (map decision 9).
7. **Logging.** Mediated call rows in the transition log; stdout/stderr tail in the activation envelope (#20); `devvm network log --json` remains the network audit for the workflow's own egress, not for mediated calls.
8. **Image.** Ship `factory-activate`, the SDK and `factory-ctl` in the Project VM image via a devvm layer. The CLI shim speaks the fd protocol so shell scripts and tests can call ops without a socket.
9. **Escalations, in order:** (a) T2 shim only if the chosen language's tooling needs an address; (b) separate uid for agent sessions when Capability Profiles land; (c) a devvm upstream feature request for a sanctioned host-service channel if the fd proves too awkward across languages — do not silently squat `127.77.0.0/16` in the standard path.
10. **Measure** (directive #15): mediated-call count and latency per op; refusals by reason (state-scope, task mismatch, stale approval, dirty worktree, rate limit); activation channel drops; push/merge refusals; agent sessions and tokens per activation; checkpoint wait time; wrong-nonce/unknown-activation attempts (alert at any nonzero).

## 9. Unknowns to close in design

- Whether `PermitListen 127.77.*:*` accepts a **dynamic** remote-forward port (`-R 127.77.0.1:0:…`). If it does not, T2 needs a random-port allocation with retry.
- Whether devvm's next release changes the sshd policy or adds a host-service/API surface; pin the version and re-check at adoption (main is already `0.2.0-rc.1`, ahead of the installed 0.1.0).
- How long an SSH activation connection survives on this host under a long silence (agent dispatch); `ServerAliveInterval`/`ClientAliveInterval` need explicit settings in the invocation.
- Whether a devvm layer can add a second, non-sudo user cleanly enough for the post-v1 uid separation (needs image work and a sudo policy).
- SSH session logging inside the guest is not exposed by devvm; confirm whether Factory wants independent evidence of channel open/close beyond its own records.

## Sources

1. devvm docs — [Security model](https://devvm.dev/docs/internals/security/) (mounts, sshd and ssh policy, passwordless sudo, links, `--clone`), last updated 2026-11-06.
2. devvm docs — [Lima](https://devvm.dev/docs/internals/lima/) (QEMU `restrict=on` + `guestfwd`, open-tier reach to host loopback, port forwarding), 2026-11-06.
3. devvm docs — [Network tiers](https://devvm.dev/docs/safety/network/) (tiers, allow/deny rules, address rules, `network log --json`), 2026-11-06.
4. devvm docs — [Attack vectors](https://devvm.dev/docs/safety/attack-vectors/) ("Remote forwards you add", open-tier host reach), 2026-11-06.
5. devvm docs — [Network tiers (internals)](https://devvm.dev/docs/internals/network/) (proxy password, internal-address floor, `devvm network allow 127.0.0.1:5432` applies from the next connection, links), 2026-11-06.
6. devvm docs — [SSH and editors](https://devvm.dev/docs/using/ssh/) (`devvm host`, pinned host keys, agent forwarding), 2026-11-06.
7. devvm docs — [Ports and size](https://devvm.dev/docs/using/ports-size/) and [Links between VMs](https://devvm.dev/docs/using/links/) (host→VM publication; VM→VM links over ssh), 2026-11-06.
8. devvm docs — [The command line](https://devvm.dev/docs/using/command-line/) (`--no-input`, versioned `--json`), 2026-11-06.
9. devvm docs — [Customizing images](https://devvm.dev/docs/using/customizing/) and [Working on a clone](https://devvm.dev/docs/using/clone/) (layers; `--clone` mounts nothing), 2026-11-06.
10. Source `github.com/devvmhq/devvm` at `06f7221` (2026-11-21, `VERSION` 0.2.0-rc.1): `assets/layers/base.sh:185-196` (guest sshd policy and its intent comment); `internal/sshconfig/sshconfig.go:183-224` (Host block); `internal/backend/lima/qemu.go:21-42,93-138` (`restrict=on`, single `guestfwd`, refused netdev shapes); `internal/vmssh/links.go:34-38,835-847` (links as `-R 127.77.x.y:port:<host unix socket>`); `internal/proxy/policy.go:756-774` and `internal/proxy/dial.go:91-100` (address rules pass the internal-address floor); `internal/daemon/daemon.go:1-20` (background-process supervision, not an API).
11. OpenSSH 10.6p2 — `ssh_config(5)` (`RemoteForward` with Unix-domain sockets; `PermitRemoteOpen` constrains SOCKS-style remote forwards) and `sshd_config(5)` (`AllowStreamLocalForwarding`, `PermitListen`, `GatewayPorts`), local man pages.
12. Lima — [Port forwarding](https://lima-vm.io/docs/config/port/) (SSH-over-`AF_VSOCK` only for VZ/krunkit, Lima ≥ 2.0) and [Internal data structure](https://lima-vm.io/docs/dev/internals) (guest agent: virtio-serial on QEMU, vsock on VZ); [lima-vm/lima#4209](https://github.com/lima-vm/lima/issues/4209) (QEMU on Linux hosts has no vsock, open).
13. Local CLI evidence: `devvm` 0.1.0 (`devvm host --help`, `devvm --help`, `devvm ssh` absent, `devvm ls --json`).
14. Repo context: [`docs/wayfinding/closed/017-research-devvm-sandboxing.md`](../wayfinding/closed/017-research-devvm-sandboxing.md) (devvm contract, owner decision), [`docs/spec/SPEC.md`](../spec/SPEC.md) §2.5, §5 (Project VM, containment, secrets, push/merge ownership), [issue #8](https://github.com/Dahep/software-factory-harness/issues/8) (re-entrant handler decisions), ADR-0005 (daemon/Unix socket), ADR-0009 (local config).
