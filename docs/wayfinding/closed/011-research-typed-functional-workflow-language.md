---
title: Survey typed functional workflow languages for a Go Factory core
type: wayfinder:research
assignee: done
status: resolved
blocked-by:
- closed/001-research-harness-language.md
- closed/007-decide-harness-language.md
---

## Question

The owner requires workflow code to be **typesafe, and functional where possible** (standing input recorded on the map, 2026-10-16). Starlark — the Go-embeddable Python dialect from closed/001's default path — is untyped and fails this constraint, so the default is demoted. Survey the candidates as Factory's workflow-authoring language over the decided Go core, across the embedding strategies:

1. **Typed declarative config languages embeddable in Go** — Dhall via `dhall-golang`: how do loops, retries, human-approval gates, and step composition fit "orchestration-as-data" (workflow as a typed value the core interprets)? Evaluate ergonomics honestly, not just type soundness.
2. **Typed expression languages as guards** — cel-go (Google, official Go library): its scope and limits; whether a Dhall/CEL-style joint DSL (typed declarative definitions + typed guards) is coherent.
3. **Functional languages compiled to WASM, hosted in-process via wazero** (pure-Go runtime, no CGo) — GHC 9.6+ `wasm32-wasi` target, OCaml's WASM backend: maturity, binary size/startup, the host-import ABI for calling Factory primitives, and whether the wasm sandbox buys a real security story.
4. **External functional binaries over the versioned subprocess/JSON contract** — Roc, Gleam, F#/OCaml native: viability as first-class workflow authoring; what the contract must support (streaming, partial progress, inputs/outputs typing).

Weigh against the decided facts: harness core = Go (closed/007 ADR), RuntimeAdapter seam mandatory (closed/002). Note any untyped option that still deserves consideration despite the constraint, and say why.

Verdict must state: a recommended primary shape, the fallback order, maturity risks per candidate, and what a "hello world" workflow would look like **from the author's chair** — the ergonomics ticket that follows will build on this.

## Resolution

**Research snapshot: 2026-10-16.** Treat workflow orchestration as a **Go-owned, versioned typed graph**, not as arbitrary user code running inside the Go process. The graph is the durable, inspectable plan: typed step inputs/outputs, explicit dependencies, bounded `ForEach`, retry policy, and approval nodes. CEL may express typed, side-effect-free conditions. Keep user-authored computations behind a versioned worker protocol if the graph eventually proves too restrictive.

| Candidate / role | Maturity risk | Fit and trade-off |
| --- | --- | --- |
| **Typed workflow graph, Dhall authoring + CEL guards (primary shape)** | **Medium-high implementation risk; low semantic/runtime risk.** Dhall itself is mature and current, but the Go binding lags the current language standard. | Best fit for replayable orchestration-as-data: explicit nodes make retries, approvals, and composition visible to the core. Dhall functions/imports generate finite graphs; CEL supplies conditions. The Go interpreter owns runtime effects. Do not let a Dhall expression invoke host effects. Make current-standard conformance of `dhall-golang` an adoption gate; until then, the IR can be JSON decoded and validated by Go. |
| **Versioned subprocess worker (escape hatch)** | **Low protocol risk, medium integration/runtime risk.** OCaml is mature; Gleam is stable but needs BEAM or JS runtime; F# Native AOT works but has AOT restrictions and per-target builds. | Best fit when authors truly need general typed functional code. Keep durable state, retries, and approvals in Go; workers perform bounded computations/steps. Process isolation and independent deployment are useful, but wire types need schema validation and there is no free compile-time guarantee across the boundary. |
| **CEL alone** | **Low.** Active, versioned Go implementation; latest checked release is v0.32.0 (`cel.dev/cel-go`). | Excellent for guards, predicates, and small transformations. It is not a workflow language: each program is an expression, not a procedure or an effectful step sequence. There is no official CEL “vTier” maturity scale; that wording does not apply to CEL-Go. |
| **WASM via wazero** | **Medium-high.** wazero is a maintained pure-Go runtime, but language targets and their guest ABIs vary substantially. | Attractive future packaging/sandbox option, not the first workflow authoring choice. Haskell’s wasm target remains a tech preview outside official bindists; OCaml’s WASI backend is still a prototype branch in 2026. A Go host ABI must be designed and versioned. |
| **Roc** | **Very high.** Still pre-0.1; current compiler/platform work is active but changes quickly. | Functional and compelling, with a usable CLI platform, but not ready to anchor a supported workflow authoring contract. |
| **Starlark (untyped)** | **Low runtime risk, constraint mismatch.** | Keep only as a consciously relaxed alternative: its embeddability is attractive, but it does not meet the recorded typesafe-workflow requirement. |

### Findings by strategy

1. **Dhall as orchestration data.** Dhall’s latest language standard is 23.1 and the Haskell implementation’s latest release is 1.42.2 (Jan 2025). The Go implementation advertises v6.0.2, but that implementation tracks standard v19 and its repository history shows no recent development. This is the largest practical risk: the language idea is sound, but Factory should not silently assume the Go evaluator is current. Pin the supported standard and run the upstream conformance suite before adoption, or use a maintained evaluator / an explicitly restricted JSON frontend. [1–3]

   Dhall has finite lists, `map`, and `fold`, not arbitrary recursion or user-defined runtime loops. That is useful for generating repeated, statically known steps, but not for looping over data only discovered during a run. Put runtime iteration in an explicit graph node (`ForEach` over a prior step’s typed output, with a limit) and have the Go engine persist its cursor. Represent retry count/backoff and approval policy as typed fields on step nodes; these are engine semantics, not language effects. Compose graphs using functions, imports, records, unions, and lists. Dhall’s totality and normal form are helpful for review, but its type-oriented syntax and lack of recursive definitions impose a learning curve; verbose type explanations can also compete with concise diagnostics. The official tour demonstrates both ordinary diagnostics and the opt-in `--explain` mode, but I found no current 2026 evidence to support a blanket claim that Dhall’s errors are poor. Do not present it as “just YAML with types.” [4–6]

   A Go core should parse/typecheck/normalize a Dhall value, decode it into a closed Go IR, then validate IDs, references, allowed node variants, input/output schemas, and bounds. It should **not** evaluate workflow effects inside Dhall. A Dhall function is useful during graph construction; at runtime, the Go IR—not a closure—is authoritative.

2. **CEL as guard language / joint DSL.** CEL is explicitly non-Turing-complete, terminating, side-effect-free, and gradually typed. CEL-Go parses/checks expressions and evaluates compiled ASTs; v0.32.0 changed the canonical import/module path to `cel.dev/cel-go`. CEL programs are single expressions; bounded collection macros (`all`, `exists`, `map`, etc.) are not control-flow orchestration. [7–9]

   A typed-data-plus-expression design is coherent and used in analogous forms: Kubernetes embeds CEL expressions in typed API schemas, and the CEL Policy project places CEL expressions in a structured YAML policy tree and checks consistent result types. I found no established industry practice specifically combining Dhall with CEL. So use the pairing as two deliberately narrow layers (Dhall/IR for structure; CEL for guards), not as a claim that the combined stack is a standard DSL. [9–10]

3. **WASM and wazero.** Wazero is pure Go and defines host modules as named imported functions implemented in Go. That makes host calls possible, but the ABI is not automatic: core Wasm imports are low-level typed functions, and strings/records need a memory/pointer convention or serialization. Define a versioned import namespace and keep it capability-minimal. WASI supplies OS-like calls, not Factory operations. A module sandbox narrows ambient access; host imports remain privileged capabilities, and CPU/memory limits and cancellation still need explicit policy. [11]

   GHC 9.12.4 supports `wasm32-wasi`, but its user guide still labels the backend a tech preview, requires a custom toolchain, and says it is absent from official bindists. This is a serious toolchain/deployment risk, not a mature general target merely because the source language is mature. OCaml `wasm_of_ocaml` 6.4.1 is a current compiler release for Wasm-GC, but its modern target needs GC/tail-call/exception extensions; the separate WASI support announced in June 2026 was explicitly a working prototype looking for a production user. [12–13]

   Size and startup need measurement on Factory’s actual workflow corpus. The language projects do not publish representative 2026 workflow-module size budgets. Even small guests can carry a runtime; as a rough non-Haskell/OCaml reference, the wasm3 cookbook reports about 2.5 MB for a Go WASI “hello world.” Wazero’s own large-module discussion reported compile-and-run times ranging from about 2 seconds in interpreter mode to about 26 seconds in compiler mode for a 65 MB module on an M2; those numbers are not representative of a small guest, but show why compilation must be benchmarked, cached, and kept off latency-sensitive paths. There is no responsible basis here to promise “millisecond cold starts.” [14–15]

4. **Versioned subprocess contract.** Roc has not shipped 0.1; its latest compiler releases are alpha/nightly and the README still says “not ready for a 0.1 release.” `basic-cli` 0.25.0 is a useful, recently released platform, but the platform ABI and compiler are still coupled and evolve. Gleam 1.19.0 (Oct 5, 2026) has a stable typed language/toolchain and `gleam run` / `gleam export escript`; an Erlang escript still requires a compatible Erlang runtime, while the JavaScript target requires a JS runtime. OCaml 5.5.1 is current and native `ocamlopt` is the lowest-risk functional compiled-worker option here. F# can publish platform-specific Native AOT executables, with known compatibility constraints. [16–19]

   The contract should use versioned, schema-validated JSON for requests and final results, plus a streaming event channel for progress/partial artifacts and structured errors; include run/call IDs, deadlines, cancellation, and a clear terminal event. If workers need Factory capabilities, add explicit host-call request/response messages rather than ambient access. MCP’s current stdio and streamable-HTTP protocols demonstrate framing, progress, and cancellation patterns that can be borrowed; they are inspiration, not a requirement to adopt MCP as the worker protocol. A workflow paused for approval should be checkpointed by Go and resumed with a new request, not keep an unbounded worker process alive. [20]

### Verdict

**Primary: a typed, declarative workflow graph owned and interpreted by Go; use CEL only for guards.** Dhall is the best studied authoring syntax for that shape, because typed finite data, reuse, normalization, and imports fit generated plans better than embedding a general-purpose functional runtime. But Dhall-Go’s v19 implementation against standard 23.1 is a release/conformance blocker. The immediate Factory IR should therefore be independent of Dhall and explicitly versioned; adopt Dhall as a frontend only after a conformance spike proves the evaluator’s required subset and error UX. Until then, a hand-authored JSON IR is safer than pinning an incompatible evaluator.

**Fallback order:** (1) versioned subprocess/JSON worker protocol, first targeting native OCaml for full functional code; (2) Gleam worker where Erlang/JS runtime availability is acceptable, then F# Native AOT where .NET deployment is already acceptable; (3) WASM packaging after a target language, ABI, guest limits, and cold-start budget are proven; (4) Roc only after 0.1 and platform stability. CEL is complementary, not a fallback workflow language. Keep Starlark available only if the owner explicitly relaxes the type-safety constraint.

**Hello world, from the author’s chair (illustrative Dhall syntax).** The author writes a short graph; the Go engine owns execution, state, retries, and the approval pause:

```dhall
let Step = ./Factory/Step.dhall
let build = \(i : { name : Text }) ->
      { version = 1
      , name = "hello"
      , steps =
          [ Step.run "greet"
              { operation = "stdout.write"
              , input = { text = "Hello, ${i.name}!" }
              , retry = Step.noRetry
              }
          ]
      }
in  build
```

The top-level expression is a function from typed run input to a typed graph; the Go evaluator supplies the run input, checks/decodes the resulting graph, then owns execution, state, retries, and approval pauses. The example deliberately makes the ergonomics question visible: does a pure, typed graph feel like a workflow authorship experience, or do users expect imperative code? It assumes the IR supplies a typed `Step` package; it is not a claim that today’s Dhall-Go release can decode Factory types without conformance work.

**Reopen triggers:** Dhall-Go catches up with standard 23.1 and passes conformance; the ergonomics prototype shows authors routinely need dynamic branching/effects that make the graph awkward; Factory adopts a durable-execution requirement that changes the graph model; a stable Gleam/Roc WASM or native ecosystem materially changes the worker cost; or actual WASM benchmarks meet an agreed size/startup budget.

**The next ergonomics ticket must settle:** author language/syntax and editor/error-message quality; whether authors want graph composition or ordinary functions; typed step input/output declarations and how generated artifacts are exposed; dynamic `ForEach` bounds, branch semantics, retries/idempotency, approval UX, and secret references; whether source changes are version-pinned per run; worker packaging/dependency installation and host-call permissions; and acceptance limits for cold start, binary size, and cancellation latency. Test a hello-world, one retry, one approval, and a loop over a runtime-produced collection—not just a pretty static example.

### Primary Sources

1. Dhall language and standard 23.1: [dhall-lang/dhall-lang](https://github.com/dhall-lang/dhall-lang), [v23.1.0](https://github.com/dhall-lang/dhall-lang/releases/tag/v23.1.0), [Safety Guarantees](https://docs.dhall-lang.org/discussions/Safety-guarantees.html).
2. Dhall Haskell releases and current standard support: [dhall-lang/dhall-haskell releases](https://github.com/dhall-lang/dhall-haskell/releases).
3. Go binding version/API and release/history: [philandstuff/dhall-golang](https://github.com/philandstuff/dhall-golang), [releases](https://github.com/philandstuff/dhall-golang/releases), [main-branch commits](https://github.com/philandstuff/dhall-golang/commits/main/).
4. Dhall recursion/iteration limits and finite folds: [How to translate recursive code to Dhall](https://docs.dhall-lang.org/howtos/How-to-translate-recursive-code-to-Dhall.html).
5. Dhall authoring/tutorial/error output: [Language Tour](https://docs.dhall-lang.org/tutorials/Language-Tour.html), [Dhall in production](https://docs.dhall-lang.org/discussions/Dhall-in-production.html).
6. Dhall Go integration choices: [How to integrate Dhall](https://docs.dhall-lang.org/howtos/How-to-integrate-Dhall.html).
7. CEL official overview, typing model and usage phases: [cel.dev overview](https://cel.dev/overview/cel-overview).
8. CEL-Go current README and Go APIs: [cel-expr/cel-go](https://github.com/cel-expr/cel-go), [v0.32.0 release](https://github.com/cel-expr/cel-go/releases/tag/v0.32.0).
9. CEL language termination, expressions, macros, and complexity: [CEL language definition](https://github.com/cel-expr/cel-spec/blob/master/doc/langdef.md).
10. Examples of structured data plus CEL: [CEL Policy](https://github.com/cel-expr/cel-policy), [Kubernetes CEL documentation](https://kubernetes.io/docs/reference/using-api/cel/).
11. Wazero host imports and Go host functions: [wazero documentation](https://wazero.io/docs/), [Go package API](https://pkg.go.dev/github.com/tetratelabs/wazero).
12. Current GHC WASM target support/maturity: [GHC 9.12.4 WASM guide](https://downloads.haskell.org/ghc/9.12.4/docs/users_guide/wasm.html), [GHC 9.12.4 release notes](https://downloads.haskell.org/ghc/9.12.4/docs/users_guide/9.12.4-notes.html).
13. OCaml WASM toolchain and WASI prototype: [OCaml wasm target](https://ocaml.org/tools/wasm-target), [wasm_of_ocaml 6.4.1 package](https://ocaml.org/p/wasm_of_ocaml-compiler/6.4.1), [WASI prototype report (2026-06-09)](https://ocaml.org/backstage/2026-06-09-wasm-of-ocaml-on-wasi-a-working-prototype-looking-for-a-production-user).
14. Guest-size reference: [wasm3 cookbook](https://github.com/wasm3/wasm3/blob/main/docs/Cookbook.md).
15. Wazero compile/startup benchmark discussion: [wazero issue #2182](https://github.com/tetratelabs/wazero/issues/2182), [release benchmarks](https://github.com/tetratelabs/wazero/releases).
16. Roc status and release line: [roc-lang/roc README](https://github.com/roc-lang/roc), [Roc releases](https://github.com/roc-lang/roc/releases).
17. Roc CLI platform/current release: [basic-cli README](https://github.com/roc-lang/basic-cli), [basic-cli releases](https://github.com/roc-lang/basic-cli/releases).
18. Gleam current language and runtime/tooling: [Gleam v1.19.0 release notes](https://gleam.run/news/gleam-doesnt-compile-to-erlang-source-anymore), [command-line reference](https://gleam.run/documentation/command-line-reference).
19. Native functional worker candidates: [OCaml 5.5.1](https://ocaml.org/releases/5.5.1), [.NET Native AOT overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot).
20. Worker stream/cancellation patterns: [MCP stdio transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio), [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http), [MCP cancellation](https://modelcontextprotocol.io/specification/2026-07-28/basic/utilities/cancellation).
