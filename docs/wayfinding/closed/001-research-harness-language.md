---
title: Which implementation language for the Factory harness (and why)
type: wayfinder:research
blocked-by: []
assignee: done
status: resolved
---

> **Superseded in part (2026-11-18).** The workflow-authorship recommendation in the Verdict below — embedded Starlark, or a subprocess/JSON contract — was superseded by tickets 011/016 and ADR-0006: Workflows are typed declarative data authored in Dhall and compiled to a Go-owned IR. The Go core recommendation stands (ADR-0001); OCaml and TypeScript remain escape hatches only if that decision is reopened.

## Question

Which memory-managed (or opt-in-memory-managed) language should the Factory harness itself be implemented in — weighing the owner's preference for functional languages, agent-ecosystem glue (LLM SDKs, MCP, subprocess/process supervision, git, SSH ops), single-binary distribution, long-running daemon reliability, and extension story? Candidates to compare honestly: **Roc**, **Mojo**, **Go**, **OCaml**, **TypeScript** (baseline for ecosystem fit), and any the research surfaces. Verdict must state: maturity/stability risk, ecosystem fit for LLM/tooling glue, ergonomics for user-defined workflow code interoperability, and a recommendation with escape hatches.

## Question (owner's crux)

No TypeScript unless the ecosystem argument is overwhelming; the owner leans functional (Roc-like) or memory-managed-with-optional-control (Mojo-like).

## Resolution

**Research snapshot: 2026-10-14.** These are not equal-risk choices. The harness is primarily a long-running systems-and-integration service, not a performance-critical compute kernel. The recommendation therefore weights operational maturity, process/network glue, and deployability above syntax preference.

| Language | Maturity and stability risk | LLM/MCP and operations glue | Distribution and daemon fit | User-defined workflow interoperability |
| --- | --- | --- | --- | --- |
| **Go** | **Low.** Long-established production language with the Go 1 compatibility promise and regular releases. Its style is imperative rather than strongly functional. [1] | **High.** First-party MCP SDK is Tier 1; OpenAI and Anthropic both publish Go SDKs (OpenAI currently labels its Go SDK beta). The standard library handles HTTP, processes and cancellation; invoking installed `git`/`ssh` also reuses the user's existing config and credentials. [2][3][4] | **High.** Straightforward ahead-of-time executable distribution; `//go:embed` can bundle assets. Mature goroutines, context cancellation, runtime diagnostics and broad production use suit a daemon. Native C dependencies still complicate fully static builds. [5][6] | **High for a deliberately bounded extension API; medium for arbitrary Go plugins.** Embed Starlark, a Python-like configuration/scripting language, and expose workflow operations as host-provided functions. For arbitrary user languages, use a versioned subprocess/JSON contract. Starlark is not a drop-in full Python runtime. [7] |
| **OCaml** | **Low-to-moderate.** A mature functional language; OCaml 5.5.1 is current. OCaml 5's multicore runtime is established, but the effect-based Eio I/O stack is much younger than Go's standard server stack. [8][9] | **Medium.** Good typed HTTP/process/package options, Eio for direct-style concurrent I/O, and a pure-OCaml Git implementation. MCP and LLM SDK options exist but are community projects, not official SDK-tier offerings; SSH coverage is also less uniform. [9][10][11] | **Medium-high.** `ocamlopt` builds native executables that do not need `ocamlrun`; dependencies on C libraries and target-specific packaging remain. Eio offers fibers, cancellation, and cross-platform OS abstractions, but its newer ecosystem adds integration risk. [9][12] | **Medium.** The language is a natural fit for declarative/typed workflow definitions, but there is no comparable mainstream embedded scripting ecosystem. Prefer a stable subprocess/protocol boundary for third-party workflow code rather than promising in-process OCaml plugin compatibility. |
| **TypeScript** | **Low for language/runtime; moderate operational packaging risk.** TypeScript is mature, but its types are erased and runtime behavior is JavaScript/Node (or another JS runtime). [13] | **Very high.** The broadest JS-first agent and provider ecosystem; official TypeScript MCP SDK is Tier 1 and runs on Node, Bun, and Deno. OpenAI and Anthropic publish TypeScript SDKs. Go now has official MCP and provider SDKs too, so TypeScript's advantage is real but not a blocker for this harness. [2][3][14] | **Medium.** Node single-executable applications exist, but require bundling and have module/native-addon constraints; this is less frictionless than Go's normal build. Node is proven for daemons, though the event loop and runtime/dependency updates add operational surface. [15] | **Very high.** The natural choice if users should write arbitrary JavaScript/TypeScript workflows and import its ecosystem. Runtime validation still needs schemas or explicit checks; compile-time types alone do not validate external workflow inputs. [13][14] |
| **Mojo** | **High.** Mojo 1.1 is versioned, open source, and past prototype status, but the official roadmap still puts systems application programming in progress. Async, algebraic data types/pattern matching, package management, and parts of the default memory-safety model remain roadmap work. That is too much change for the daemon's foundation today. [16] | **Low-to-medium today.** Python interop can reach CPython libraries, but Mojo's own roadmap says it has prioritized core abstractions over Python library parity. Python interop requires Python 3.10–3.14; calling Mojo from Python is documented as early development. The documented subprocess API is currently a simple command-to-output helper, not a rich process-supervision story. [17][18] | **Potentially high, but not proven for this use.** Mojo can build executables and offers controlled memory management, but its current product focus/toolchain work is still evolving. Python interop also weakens a standalone artifact if the harness relies on CPython packages. [16][17] | **Medium-low.** Python interop is an escape hatch, not yet a stable workflow/plugin contract; it introduces a Python runtime and Mojo↔Python boundary. Revisit after Phase 2's async, packaging, and safety roadmap has landed. [16][17] |
| **Roc** | **Very high.** The project explicitly says it is not ready for a 0.1 release; the new compiler and platforms remain actively changing. [19] | **Low-to-medium.** The `basic-cli` platform already covers command execution, HTTP, TCP, files, environment, and related CLI needs, but its platform package is at a release-candidate level, has documented transport limitations, and there is no official MCP/provider SDK ecosystem. [20] | **Potentially high for a narrow target.** Roc's platform architecture can produce application binaries, but each application depends on one host-defined platform and its supported targets/operations. That is a fragile foundation for a general-purpose, long-lived integration daemon today. [20][21] | **Low.** Roc is attractive for functional workflow logic, but effects and host functionality are mediated by a single platform; it is not a smooth fit for importing arbitrary user code or composing third-party runtimes. [21] |

### Verdict

**Choose Go for the harness core.** It is not the owner's most functional option, but it best satisfies the actual workload with the least ecosystem and release risk. The decisive point is that TypeScript is not the only practical route to LLM/MCP glue anymore: Go has a Tier 1 official MCP SDK and official OpenAI and Anthropic clients, while keeping simpler binary distribution and mature subprocess supervision. Invoke native `git` and `ssh` where that best preserves the user's environment rather than reimplementing their credential/config behavior.

For workflow authorship, keep the core in Go and expose a small, explicit workflow API through embedded Starlark (or a versioned process/JSON interface for users who need a full external language). Bound the operations exposed to scripts and apply execution/resource limits; do not treat an embedded language by itself as a security sandbox.

**Escape hatches:**

- If the owner's functional-language preference outweighs the extra integration work, **OCaml 5 + Eio** is the strongest functional alternative. Keep provider/MCP integrations behind replaceable HTTP/protocol adapters and use process boundaries for user extensions.
- Choose **TypeScript** instead only if the defining requirement becomes users authoring rich JavaScript workflows or using JS-only agent libraries. That ecosystem case could justify accepting Node packaging/runtime costs; today's provider/MCP gap in Go is not large enough.
- Reassess **Mojo** when its official Phase 2 roadmap (especially async, application-level libraries/package management, and memory-safety completion) is substantially complete. **Roc** is a future experimental option, not a current production-harness choice.

### Sources

Sources below are first-party project documentation or project repositories; moving pages were checked on 2026-10-14.

1. Go compatibility promise and release policy: [Go 1 Compatibility](https://go.dev/doc/go1compat), [Go 1.26 release notes](https://go.dev/doc/go1.26); Go's production and runtime goals: [Go FAQ](https://go.dev/doc/faq).
2. MCP official SDK tiers and supported languages: [MCP SDKs](https://modelcontextprotocol.io/docs/2026-07-28/sdk); official Go SDK features, versions, stdio command transport: [modelcontextprotocol/go-sdk](https://github.com/modelcontextprotocol/go-sdk).
3. Provider libraries: [OpenAI Go SDK](https://github.com/openai/openai-go) (currently marked beta), [OpenAI official SDK list](https://developers.openai.com/api/docs/libraries), [Anthropic Go SDK](https://github.com/anthropics/anthropic-sdk-go).
4. Go process control: [`os/exec`](https://pkg.go.dev/os/exec) (`CommandContext` provides context-driven cancellation and argument-based execution).
5. Go embedded assets: [`embed` package](https://pkg.go.dev/embed).
6. Go's production history and managed runtime: [Go FAQ](https://go.dev/doc/faq); runtime profiling and tracing: [`runtime/pprof`](https://pkg.go.dev/runtime/pprof), [`runtime/trace`](https://pkg.go.dev/runtime/trace); compatibility/release notes in [1].
7. Embedded workflow option: [google/starlark-go](https://github.com/google/starlark-go) (interpreter, host-provided functions, and application-embedding examples).
8. Current OCaml releases and 5.5 series: [OCaml releases](https://ocaml.org/releases).
9. OCaml 5 effects-based concurrency and OS abstractions: [Eio README](https://github.com/ocaml-multicore/eio), [Eio API](https://ocaml-multicore.github.io/eio/eio/Eio/index.html). Eio package history: [opam package](https://ocaml.org/p/eio).
10. Community MCP implementation: [tmattio/ocaml-mcp](https://github.com/tmattio/ocaml-mcp); community provider abstraction: [ahrefs/ocaml-ai-sdk](https://github.com/ahrefs/ocaml-ai-sdk).
11. OCaml package ecosystem and Git/SSH options: [opam repository overview](https://ocaml.org/tools/opam-repository), [mirage/ocaml-git](https://github.com/mirage/ocaml-git), [mnet-ssh](https://ocaml.org/p/mnet-ssh), [awa SSH](https://ocaml.org/p/awa).
12. OCaml native and standalone executable modes: [OCaml compiler backend documentation](https://ocaml.org/docs/compiler-backend).
13. TypeScript's runtime/type-erasure model: [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html), [TypeScript basics](https://www.typescriptlang.org/docs/handbook/2/basic-types.html).
14. Official TypeScript integrations: [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk), [OpenAI Node/TypeScript SDK](https://github.com/openai/openai-node), [Anthropic TypeScript SDK](https://github.com/anthropics/anthropic-sdk-typescript).
15. Node single-executable application packaging and limitations: [Node.js SEA documentation](https://nodejs.org/api/single-executable-applications.html).
16. Mojo version, maturity markers, current phase and outstanding systems-language work: [official Mojo roadmap](https://docs.modular.com/mojo/roadmap).
17. Mojo Python boundary: [Python interoperability](https://mojolang.org/docs/manual/python/), [calling Mojo from Python](https://mojolang.org/docs/manual/python/mojo-from-python).
18. Mojo process API: [subprocess `run`](https://mojolang.org/docs/std/subprocess/subprocess/run); executable build CLI: [Mojo CLI](https://mojolang.org/docs/cli).
19. Roc release/maturity statement: [roc-lang/roc README](https://github.com/roc-lang/roc).
20. Roc CLI platform capabilities, supported targets, release pin, and current network limitations: [roc-lang/basic-cli README](https://github.com/roc-lang/basic-cli).
21. Roc platform ownership and host/application boundary: [Roc Platforms FAQ](https://www.roc-lang.org/faq), [platforms language reference](https://www.roc-lang.org/docs/main/langref/platforms).
