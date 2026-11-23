# Languages for the workflow program: survey and ranked shortlist

**Research date: 2026-11-23.** Answers [issue #9](https://github.com/Dahep/software-factory-harness/issues/9) under the contract fixed by the rewrite map ([issue #8](https://github.com/Dahep/software-factory-harness/issues/8)). All claims are cited to the source that owns them; source access dates are 2026-11-23 unless stated. Binary sizes and startup times marked **measured** were produced on this machine for this note (Linux x86_64, rustc 1.94.1, Deno 2.9.8, Go 1.27.1) and are evidence about the toolchain as installed, not a benchmark.

No decision is taken here. The ranked order is a synthesis of the facts below; "What would flip the order" names the criteria that reorder it.

## The contract being priced

From issue #8: a workflow program is user-authored, statically typed, committed to the Project repo, and consists of **one re-entrant handler per state**. Each activation receives the typed state and a workdir capability, performs direct effects (filesystem, subprocess, git, HTTP, daemon agent calls) inside the Project VM, and returns the next typed state. States are **generated as a sum type from project config**, and the build must reject a missing handler. The daemon persists state, invokes the program, records the activation envelope, and pins the definition digest.

Two consequences drive the ranking more than any language's marketing:

1. **Handler coverage must be a build failure, not a convention.** A language whose exhaustiveness signal is a suppressible warning needs an explicit flag (and a test that the flag stayed on) before it meets the contract.
2. **The invocation model is part of the language choice.** A fresh process per activation is the simplest contract, and it prices runtime boot: milliseconds are free, hundreds of milliseconds are a design constraint that forces a warm-process protocol or an ahead-of-time native image.

## Ranked shortlist

Order is weighted: type fit for a generated state sum (30%), direct-IO cost per handler (20%), reproducible build and artifact (20%), invocation cost/fit (15%), editor/debug and adoption risk (15%).

| # | Language | Coverage signal | Deployable unit (no runtime in VM) | Measured / documented cost | Main maturity risk |
|---|---|---|---|---|---|
| 1 | **OCaml 5.5** | warning 8, escalatable to error | native ELF, OCaml runtime linked in, dynamic libc | startup not measured; no published figure | Dune lock dirs are young; JSON codecs need a ppx |
| 2 | **Rust 1.100** | hard error (E0004) | static musl ELF | **537 KiB** with serde; **~1 ms** startup (measured) | edition churn every 3 years; not functional-first |
| 3 | **F# 11 / .NET 11** | warning FS0025, escalatable | NativeAOT ELF (glibc-bound) | size not published; AOT startup documented as native | NativeAOT + reflection JSON needs care; Ionide is community |
| 4 | **Haskell / GHC 9.14** | warning, in `-W`/`-Wall` | ELF with RTS; fully static needs a static GHC build | artifact commonly tens of MB (community) | heaviest toolchain and build times; record ergonomics |
| 5 | **Swift 6.4** | hard error | static musl ELF via Static Linux SDK | ~5–6 MB stripped (community) | smallest Linux server ecosystem; new 6.4 subprocess API |
| 6 | **Kotlin 2.4** | hard error for `when` expressions | Kotlin/Native (Tier 2) or GraalVM image | JVM boot is the cost; native figure unpublished | Kotlin LSP is alpha; two backends with different stories |
| 7 | **Dart 3.14** | hard error (sealed switch) | `dart compile exe` self-contained | 49 ms compiled hello (Dart team, 2019) | least expressive type system of the shortlist |
| 8 | **Scala 3.8** | warning | GraalVM `native-image` or JVM | JVM boot; native figure unpublished | no stdlib JSON; 3.8.0 shipped a bytecode regression |
| 9 | **TypeScript / Deno 2.9** | manual (`never` + flags) | `deno compile` binary | **105 MB**, **~12 ms** startup (measured) | types erased, so the state sum needs a runtime validator |
| 10 | **Java 27 / 25 LTS** | hard error (pattern switch) | GraalVM image or jlink runtime | JVM boot | no stdlib JSON; native-image build cost |
| 11 | **Gleam 1.19** | hard error | escript/shipment **needs Erlang**; JS target needs Node/Deno | BEAM boot, ~100 ms (community) | fs/subprocess are community packages |
| 12 | **C# 15 / .NET 11** | warning CS8509, only switch expressions | NativeAOT ELF | AOT startup native | `union` is weeks old; docs still moving |
| 13 | **Zig 0.16** | hard error (tagged-union switch) | static ELF | ~1–2 MB (community) | 0.x std rewrite; `zls` is community |
| 14 | **Crystal 1.19** | union `case` exhaustiveness | static ELF (needs musl libs) | unpublished | small core team; minor-version breaking changes |

**Not eligible under the stated contract** (evidence in the cards below): Elm (no filesystem or subprocess at all), PureScript (needs Node; pre-1.0 since 2015), Unison (the artifact is a content-addressed codebase, not reviewable text; JVM interpreter), Roc (pre-0.1 by its own README), Idris 2 (no subprocess/HTTP facility in the stdlib; Chez backend), Erlang/Elixir (no compile-time exhaustiveness), Go (no sum types and no compiler exhaustiveness; see the note on the generated-interface workaround).

## 1. OCaml — best native fit for a generated state machine

**Type fit.** Variants *are* the sum type; records, inline records, GADTs, polymorphic variants, and full pattern matching are core language ([OCaml manual 5.5](https://ocaml.org/manual/5.5/index.html)). Exhaustiveness is **warning 8 `partial-match`** — "Partial match: missing cases in pattern-matching" — and the manual documents `@8` as "enable and mark as fatal", so a dune flag (`(flags (:standard -w @8))`) turns a missing state handler into a build failure ([batch compiler manual, warning reference](https://ocaml.org/manual/5.4/comp.html)). Errors are ordinary ML inference errors; OCaml 5.4's release notes count "nearly a dozen improved error messages" among its changes ([5.4.0 release, 2025-10-09](https://ocaml.org/releases/5.4.0)).

The catch for this contract is effects: OCaml 5's handlers are **not** typed effects. The manual says plainly that "unlike languages such as Eff and Koka, effect handlers in OCaml do not provide effect safety; the compiler does not statically ensure that all the effects performed by the program are handled" ([effects chapter, 5.5](https://ocaml.org/manual/5.5/effects.html)). That does not hurt this design — the contract wants *direct* effects, with the state value carrying the explicitness — but any expectation of "the type system proves which effects a handler performs" is unmet.

**IO.** Direct and unceremonious: `Unix.open_process_full` returns in/out/err channels for a shell command ([Unix module, 5.5](https://ocaml.org/manual/5.5/api/Unix.html)); `Sys`/`In_channel`/`Out_channel` cover files. A `make test` gate is an `open_process_full`, a read, and a close. JSON is the one place ceremony appears: `Yojson.Safe.from_string`/`to_string` handle the tree, and `ppx_deriving_yojson` generates `*_of_yojson`/`*_to_yojson` for a variant type ([yojson](https://ocaml.org/p/yojson/3.0.0), [ppx_deriving_yojson 3.10.0](https://ocaml.org/p/ppx_deriving_yojson/latest/README.html)). Since states and their codec are generated anyway, that ppx is a build-graph dependency, not author work.

**Toolchain.** Current stable is **5.5.2 (2026-10-23)**; 5.5.0 shipped 2026-06-19 with a relocatable compiler and stdlib additions ([release list](https://ocaml.org/releases)). Dune is the build system; **Dune 3.25.0 (2026-11-12)** documents lock directories: `dune pkg lock` writes `dune.lock`, and "whenever Dune encounters a dune.lock folder, it will use the set of dependencies defined in the lock", including source locations for every package ([Dune 3.25 changelog](https://ocaml.org/changelog/2026-11-12-dune3250), [locking tutorial](https://dune.readthedocs.io/en/latest/tutorials/dune-package-management/locking.html)). Portable lock directories (one solution across platforms) were announced as a developer preview in 2025 ([OCaml Backstage, 2025-05-19](https://ocaml.org/backstage/2025-05-19-portable-lock-directories-for-dune-package-management)), so this path is newer than Cargo's, though it is documented and shipped.

`ocamlopt` produces a native executable with the OCaml runtime linked in; it is not a fully static binary by default — static linking is a C-linker flag (`-ccopt -static`) against whatever static libc is present, not a first-class mode ([native-code manual](https://ocaml.org/manual/5.5/native.html)). Inside a Project VM that ships a base image, dynamic libc is acceptable; portability of the binary across VM images is not. No primary source publishes a binary size, and none was measured here.

**Editor/debug.** OCaml-LSP 1.26.1 was released 2026-11-06, with Merlin behind it ([OCaml changelog](https://ocaml.org/changelog/2026-11-06-ocaml-lsp-1261-draft)); `ocamldebug` works at the source level, and gdb/lldb are documented for native debugging ([manual, native debugger](https://ocaml.org/manual/5.5/native-debugger.html)). Editors are solid rather than best-in-class.

**Maturity risk.** The compiler and opam ecosystem are decades old and the language is stable across 5.x, but two items are young: Dune's package-management lock path, and tooling around it. License: LGPL-2.1 **with a static-linking exception** (the compiler was relicensed in 4.03, 2016) ([4.03.0 release notes](https://ocaml.org/releases/4.03.0)) — no obstacle to shipping a proprietary workflow binary. Stewardship is multi-party (INRIA, OCaml Software Foundation, Tarides, Jane Street), so bus factor is low risk.

**Why first.** It is the only candidate where the state-machine shape is the language's native idiom, handler coverage can be made a hard build failure with one flag, direct IO is a stdlib call, and the artifact is a small native executable built by a mature compiler. The costs are real but bounded: a ppx for JSON, a younger lockfile story, and no fully static mode.

## 2. Rust — the strongest artifact and the strictest coverage guarantee

**Type fit.** `enum` with payloads is the sum type, `match` is exhaustive, and a missing arm is a **hard compile error, E0004**: "the compiler cannot guarantee a matching pattern for one or more possible inputs" ([Rust error index](https://doc.rust-lang.org/error_codes/E0004.html)). Structs are records, pattern matching includes guards and bindings, and diagnostics are the ecosystem's best-known asset. No effects are tracked — `Result` and plain IO calls are the model — which matches a contract that wants direct effects and an explicit state value. The trade is that Rust is not functional-first: shared mutable state inside a handler needs ownership design, and there are no higher-kinded types. A handler is a straight-line function over an enum, which is the easy case.

**IO.** `std::fs` and `std::process::Command` are stdlib; `Command::output()` captures stdout, stderr, and exit status in one call. HTTP is `reqwest` or `ureq` (crate, not stdlib); JSON is `serde`/`serde_json` with `#[derive(Serialize, Deserialize)]`, `from_str`/`to_string` ([serde_json docs](https://docs.rs/serde_json/latest/serde_json)). Serde's adjacently-tagged enum representation gives the daemon a stable wire shape without hand-written encoders. A handler that runs `make test` and reads an artifact is roughly ten lines.

**Toolchain.** Current stable is **1.100.0 (2026-11-12)** on a six-week train ([announcement](https://blog.rust-lang.org/2026/11/12/Rust-1.100.0/)). `rust-toolchain.toml` pins the toolchain per directory ([rustup book, overrides](https://rust-lang.github.io/rustup/overrides.html)); `Cargo.lock` pins the graph; `cargo vendor` copies all crates.io and git dependencies into a local directory for offline builds, and `--offline` makes network access an error ([cargo vendor](https://doc.rust-lang.org/cargo/commands/cargo-vendor.html)). `x86_64-unknown-linux-musl` is a Tier 2 target with host tools — "guaranteed to build", musl 1.2.5 — and produces a static ELF ([platform support](https://doc.rust-lang.org/rustc/platform-support.html)).

Measured on this machine: a program that reads a file, plus `serde`/`serde_json` with a three-variant state enum, is **549,528 bytes stripped** as a static musl binary (451,864 bytes glibc-dynamic); twenty runs take **20 ms total**, about 1 ms per process. A process-per-activation contract is free here.

**Editor/debug.** `rust-analyzer` is a first-party, best-in-class LSP; `rust-gdb`/`rust-lldb` and the `Debug` trait are the documented debugging path. Nothing else on the list matches the out-of-box experience.

**Maturity risk.** Lowest on the list: Rust Foundation stewardship, a published stability guarantee that predates 1.0's success, and editions every three years with a documented migration path (2024 edition shipped with 1.85.0). License MIT/Apache-2.0 ([rust-lang policies](https://www.rust-lang.org/policies/licenses)). The costs are compile time with dependencies, a borrow checker an author must learn, and a style that is "typed imperative with ADTs" rather than functional.

**Why second, not first.** On artifact, reproducibility, startup, editor, and churn it beats OCaml; on "functional where possible" and on the ergonomics of the definition itself it loses. If the deciding weight is "survives as a reviewed, committed, buildable artifact", this is first.

## 3. F# — the best authoring ergonomics in a heavier runtime

Discriminated unions and records are first-class, and incomplete matches produce **FS0025**, a warning that the project file promotes to an error with `<WarningsAsErrors>FS0025</WarningsAsErrors>` ([FS0025 reference](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/compiler-messages/fs0025), [DU reference](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/discriminated-unions)). IO is .NET: `System.IO`, `System.Diagnostics.Process` with redirected streams, `HttpClient`, `System.Text.Json`. Typed compact JSON is the gap: `System.Text.Json` has no built-in DU converter, so `FSharp.SystemTextJson` or hand-written converters are required — and reflection-based converters interact badly with trimming/AOT, so a NativeAOT build must be tested early.

Toolchain: F# 11 ships with .NET 11 (GA 2026-11-10, STS); .NET 10 is the LTS through Nov 2028 ([.NET 11 announcement](https://devblogs.microsoft.com/dotnet/announcing-dotnet-11/)). Locking is opt-in `packages.lock.json` ([NuGet lock-file reference](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files)). `PublishAot=true` produces a self-contained native executable, documented as running only on the same or newer Linux/glibc ([NativeAOT docs](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot)). Size is not published; community reports 10–30 MB.

Editor: Ionide/FsAutoComplete is community-maintained (no Microsoft LSP); debugging on Linux is netcoredbg (community). License MIT. Risk is the runtime/AOT layer, not the language: the Project VM must carry either the .NET runtime or an AOT image that was validated against the VM's glibc, and the JSON path must be AOT-safe.

## 4. Haskell — best types, heaviest build

GHC's ADTs, GADTs, and pattern matching are excellent; `-Wincomplete-patterns` is in the standard `-W`/`-Wall` sets ([GHC 9.14.1 user's guide, warnings](https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/using-warnings.html)), and `-Werror` makes it fatal. Records are the weak spot: `OverloadedRecordDot` (GHC 9.2+) and `DuplicateRecordFields` soften it, but they are extensions over a famously awkward record system ([GHC 9.14 guide, records](https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/exts/overloaded_record_dot.html)). IO is `IO` plus `System.Process.readProcessWithExitCode` and `System.Directory` ([process docs](https://hackage.haskell.org/package/process/docs/System-Process.html)); JSON is `aeson` with `FromJSON`/`ToJSON` instances or generic derivation ([aeson docs](https://hackage.haskell.org/package/aeson/docs/Data-Aeson.html)). All effects are in `IO`, and typed-effect libraries are opt-in and not needed here.

Toolchain: GHC **9.14.1** released 2025-12-19; 9.14.2 was at rc3 on 2026-11-12, with GHC 10.0 in alpha — the project now publishes LTS releases to slow the train ([GHC blog](https://ghc.gitlab.haskell.org/homepage/blog.html), [LTS release blog, 2025-07-07](https://ghc.gitlab.haskell.org/homepage/blog/20250702-ghc-release-schedules.html)). `cabal freeze` writes exact versions into `cabal.project.freeze` ([cabal commands](https://cabal.readthedocs.io/en/stable/cabal-commands.html)), and building offline from a populated store works. The artifact is the problem: GHC links its runtime into the executable but stays dynamically linked to libc/libgmp, and a fully static executable requires a GHC built against static libraries — not a documented first-class mode (GHC's `-staticlib` is "link all passed files into a static library", not a static executable) ([linking options](https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/phases.html)). GHC itself is a large install and dependency builds are long, which is a real tax on a per-project VM image.

Editor is the best non-Rust option: HLS is "the official Haskell language server (LSP) implementation" ([README, Apache-2.0](https://github.com/haskell/haskell-language-server)). Risk: ecosystem breakage across GHC majors, build time, image size. License BSD-3-Clause.

## 5. Swift 6.4 — a surprise contender with a thin server ecosystem

Enums with associated values are the native sum type, and a non-exhaustive switch over an enum is a **compiler error** ("a switch statement must be exhaustive when considering an enumeration's cases") ([The Swift Programming Language, Enumerations](https://docs.swift.org/swift-book/LanguageGuide/Enumerations.html)). Swift 6.4 (2026-09-15) stabilized the `Subprocess` package, so `try await Subprocess.run(.name("make"), arguments: ["test"], output: .string(limit: 4096))` captures output in one call ([Swift 6.4 announcement](https://www.swift.org/blog/swift-6.4-released)); `Codable` + `JSONDecoder`/`JSONEncoder` are stdlib. Toolchain: `Package.resolved` is generated and meant to be committed, and the **Static Linux SDK** produces "a fully statically linked executable, with no external dependencies at all (not even the C library)" via `--swift-sdk x86_64-swift-linux-musl` ([SwiftPM resolving docs](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/resolvingpackageversions), [static Linux guide](https://swift.org/documentation/articles/static-linux-getting-started.html)). Editor: first-party SourceKit-LSP and LLDB. Risk: the Linux server ecosystem is the smallest of the shortlist, the static SDK is musl-only and brings its own dependency constraints, and 6.4 is recent. License Apache-2.0 with runtime exception.

## 6–10. The JVM, Dart and Deno tier

These all clear the type bar to differing degrees but pay at the process boundary or in the type system.

- **Kotlin 2.4.21 (2026-10-08)** is the best of the JVM group for this contract: sealed hierarchies + `when` expressions are checked exhaustively by the compiler, and `kotlinx.serialization` encodes a sealed hierarchy automatically with a discriminator ([sealed classes](https://kotlinlang.org/docs/sealed-classes.html), [serialization polymorphism](https://kotlinlang.org/docs/serialization-polymorphism.html)). Its problem is deployment: the JVM path pays cold-start per activation, and Kotlin/Native (`linuxX64`, Tier 2) is a second, younger backend; the official Kotlin LSP is alpha and partly closed-source ([kotlin-lsp](https://github.com/Kotlin/kotlin-lsp)). Gradle dependency locking is opt-in ([Gradle docs](https://docs.gradle.org/current/userguide/dependency_locking.html)).
- **Dart 3.14.1 (2026-11-17)** has sealed classes with exhaustive switch checking as a compile error, `dart:io` `Process.run` (captured stdout/stderr), `dart:convert` JSON, `pubspec.lock` with `--enforce-lockfile`/`--offline`, and `dart compile exe` producing a self-contained native executable ([branches/exhaustiveness](https://dart.dev/language/branches), [dart compile](https://dart.dev/tools/dart-compile), [pub get](https://dart.dev/tools/pub/cmd/pub-get)). The Dart team documented 49 ms for a compiled hello-world in 2019 ([dart2native announcement](https://dart.dev/blog/announcing-dart-2-6)). It is the least expressive type system here (no ADT-pattern ergonomics beyond sealed switches, no effects), and it is Google-stewarded BSD-3.
- **Scala 3.8** has `enum`/sealed hierarchies, but exhaustiveness is a **warning**, there is no stdlib JSON (circe/uPickle with macro derivation), and no first-party lockfile — plus 3.8.0 shipped a runtime bytecode regression with a published postmortem ([Scala 3.8 notes](https://www.scala-lang.org/news/3.8/), [postmortem, 2026-01-29](https://scala-lang.org/blog/post-mortem-3.8.0.html)). Apache-2.0, Scala Center.
- **TypeScript on Deno 2.9.8 (2026-10-21)** has the best IO/DX pair on the list — `Deno.Command(...).output()`, `Deno.readFile`, `fetch`, built-in LSP/debugger, `deno.lock`, `--cached-only` and vendoring ([Deno compile](https://docs.deno.com/examples/deno_compile/), [Deno packages](https://docs.deno.com/runtime/packages/)). It fails the type requirement in the way that matters: **types are erased**, so a missing state handler is not a compile error, and a typed state value on stdin needs a runtime schema validator. Measured: `deno compile` hello is **104,993,992 bytes** (the docs say "roughly 70 MB"), and twenty runs take **234 ms** (~12 ms each).
- **Java 25 LTS / 27** is the only mainstream language where a pattern switch over a sealed hierarchy is a **compile-time error** ([Java 21 pattern matching for switch](https://docs.oracle.com/en/java/javase/21/language/pattern-matching-switch.html)) and records are stdlib. But there is no stdlib JSON (Jackson is mandatory), and the JVM/native-image deployment story is the same cost as Kotlin's without kotlinx.serialization's sealed-type support. GPLv2+CE.

## 11–14. Clears or misses the bar with a cost

- **Gleam 1.19.2 (2026-10-12)** is the cleanest small type system here: custom types with compiler-checked exhaustiveness errors, and copy-paste code actions ([case expressions](https://tour.gleam.run/flow-control/case-expressions), [exhaustiveness in 0.33](https://gleam.run/news/v0.33-exhaustive-gleam)). But the stdlib has no filesystem or subprocess; those are `simplifile` and community packages (`shellout`), and the deployable unit is an escript or Erlang shipment that **requires Erlang in the VM** ([CLI reference](https://gleam.run/writing-gleam/command-line-reference)). Apache-2.0, community-governed. Good language, wrong deployment shape for a per-project VM unless the VM already standardizes on BEAM.
- **C# 15 / .NET 11** shipped `union` types and `closed` hierarchies on 2026-11-10, with the compiler checking switch *expressions* over them — but CS8509 is a warning, switch *statements* are unchecked, and the docs are weeks old ([union reference](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/union), [CS8509](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-messages/cs8509)). A reasonable post-1.0 answer; not a 2026 one.
- **Zig 0.16.0 (2026-04-14)** has tagged unions and a `switch` that must be exhaustive ([language reference, switch](https://ziglang.org/documentation/master/#switch)), static binaries by default, and `build.zig.zon` hashes as a lockfile. But there is no pattern matching beyond switch/if-capture, no records-with-fields semantics beyond structs, `zls` is community, and the 0.x standard library is still being rewritten (the `std.Io` change in 0.15). Not a stable authoring surface for users.
- **Crystal 1.19.2 (2026-04-27)** has union types with exhaustive `case`, excellent IO ergonomics (`Process`, `HTTP::Client`, `JSON`), and `--release --static` — but static builds require musl/static libs, exhaustiveness is limited to union-typed dispatch, and the LSP is community ([case docs](https://crystal-lang.org/reference/latest/syntax_and_semantics/case.html), [static linking guide](https://crystal-lang.org/reference/latest/guides/static_linking.html)). Small core team.

## Excluded, with the reason

| Candidate | Why it fails this contract |
|---|---|
| **Elm 0.19.3** | No filesystem, no subprocess, no Node APIs: "managed effects" only, via `Cmd`/`Sub` and ports ([effects](https://guide.elm-lang.org/effects), [ports](https://guide.elm-lang.org/interop/ports)). A handler cannot run `make test`. |
| **PureScript 0.15.17** | Real `Effect` tracking and Node bindings for fs/child_process, but requires Node in the VM, has no single binary, and has been pre-1.0 since 2015 with multi-year release gaps. |
| **Unison 2.0** | Typed abilities are the best effect story on paper, but the artifact is a content-addressed codebase manipulated by `ucm` (JVM), not text a reviewer reads in a PR, and there is no native binary ([1.0 announcement](https://www.unison-lang.org/unison-1-0/)). Reviewability is a hard requirement here. |
| **Roc** | "Roc is not ready for a 0.1 release yet" (project README); platform model needs a matching host platform this contract does not have ([repo](https://github.com/roc-lang/roc)). |
| **Idris 2 0.8.0** | Dependent types are overkill; the stdlib has no subprocess-with-capture or HTTP, and deployment is Chez Scheme. |
| **Erlang / Elixir** | No compile-time exhaustiveness; Elixir's gradual types warn only and exhaustive checking is a roadmap item ([Elixir types](https://hexdocs.pm/elixir/gradual-set-theoretic-types.html)). |
| **Go 1.26** | No sum types, and type switches are not required to be exhaustive ([spec](https://go.dev/ref/spec#Type_switches)); the exhaustive-switch proposal is unimplemented ([golang/go#36387](https://github.com/golang/go/issues/36387)). A code generator *can* force per-state coverage by emitting an interface with one method per state and requiring the author's type to implement it — a missing method is a compile error — but the handler body still dispatches through type switches the compiler does not check for exhaustiveness, and the pattern-matching and record ergonomics are the weakest here. Viable as the "one language with the daemon" trade, not as the best type fit. |

## The hello loop, in the top two

Both sketches assume the build step generates `state` (one constructor per configured state, payload types from project config) and its codec. The handler signature is the contract from #8: typed state in, workdir capability in, next typed state out. Agent dispatch is a daemon command executed inside the VM; the gate is a real subprocess.

### OCaml

```ocaml
(* state.ml — GENERATED from project config; do not edit *)
type state =
  | Intake    of { issue : int; attempt : int }
  | Implement of { branch : string; feedback : string option }
  | Gate      of { branch : string }
  | Done      of { merged : bool }
[@@deriving yojson]

type outcome = { status : string; summary : string } [@@deriving yojson]
type gate    = { passed : bool; output : string }   [@@deriving yojson]

(* handler.ml — AUTHORED by the project *)
let run cmd =
  let ic = Unix.open_process_in cmd in
  let out = In_channel.input_all ic in
  (Unix.close_process_in ic, out)

let agent ~workdir ~role ~prompt =
  let cmd = Printf.sprintf "cd %s && factory agent run --role %s --prompt %s"
      (Filename.quote workdir) role (Filename.quote prompt) in
  match run cmd with
  | Unix.WEXITED 0, out -> Yojson.Safe.from_string out |> outcome_of_yojson |> Result.get_ok
  | _, out -> { status = "crashed"; summary = out }

let gate ~workdir =
  match run (Printf.sprintf "cd %s && make test" (Filename.quote workdir)) with
  | Unix.WEXITED 0, out -> { passed = true; output = out }
  | _, out -> { passed = false; output = out }

(* A missing constructor here is warning 8, escalated to an error by dune. *)
let handle : state -> workdir:string -> state = fun state ~workdir ->
  match state with
  | Intake { issue; attempt } ->
      let fb = if attempt = 0 then None else Some "previous attempt failed" in
      Implement { branch = Printf.sprintf "factory/issue-%d" issue; feedback = fb }
  | Implement { branch; _ } ->
      let _ = agent ~workdir ~role:"implementer"
          ~prompt:(Printf.sprintf "Implement the task on branch %s" branch) in
      Gate { branch }
  | Gate { branch } ->
      let g = gate ~workdir in
      if g.passed then Done { merged = false }
      else Implement { branch; feedback = Some g.output }
  | Done _ -> Done { merged = true }   (* terminal: daemon stops re-invoking *)

let () =
  let s = In_channel.input_all stdin |> Yojson.Safe.from_string |> state_of_yojson
          |> Result.get_ok in
  let next = handle s ~workdir:(Sys.getenv "FACTORY_WORKDIR") in
  print_string (Yojson.Safe.to_string (state_to_yojson next))
```

Cost: one ppx, one `Unix` call per effect, no encoder boilerplate beyond the deriving attribute. The `match` *is* the handler map; deleting a state constructor from the config and regenerating produces a build error at the `handle` function, which is exactly the compile gate #18 asks for. A `dune` flag makes it fatal: `(flags (:standard -w @8))`.

### Rust

```rust
use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Serialize, Deserialize)]                 // GENERATED from project config
#[serde(tag = "state", content = "data", rename_all = "snake_case")]
enum State {
    Intake { issue: u32, attempt: u32 },
    Implement { branch: String, feedback: Option<String> },
    Gate { branch: String },
    Done { merged: bool },
}

#[derive(Deserialize)] struct Outcome { status: String, summary: String }
#[derive(Deserialize)] struct GateReport { passed: bool, output: String }

fn agent(workdir: &str, role: &str, prompt: &str) -> Outcome {
    let out = Command::new("factory")
        .args(["agent", "run", "--role", role, "--prompt", prompt])
        .current_dir(workdir).output().expect("spawn factory");
    serde_json::from_slice(&out.stdout).unwrap_or(Outcome {
        status: "crashed".into(),
        summary: String::from_utf8_lossy(&out.stderr).into(),
    })
}

fn gate(workdir: &str) -> GateReport {
    let out = Command::new("make").arg("test").current_dir(workdir)
        .output().expect("spawn make");
    GateReport {
        passed: out.status.success(),
        output: format!("{}{}", String::from_utf8_lossy(&out.stdout),
                                 String::from_utf8_lossy(&out.stderr)),
    }
}

fn handle(state: State, workdir: &str) -> State {   // AUTHORED
    match state {                                    // E0004 if a state is missed
        State::Intake { issue, attempt } => State::Implement {
            branch: format!("factory/issue-{issue}"),
            feedback: (attempt > 0).then(|| "previous attempt failed".into()),
        },
        State::Implement { branch, .. } => {
            let _ = agent(workdir, "implementer",
                          &format!("Implement the task on branch {branch}"));
            State::Gate { branch }
        }
        State::Gate { branch } => {
            let g = gate(workdir);
            if g.passed { State::Done { merged: false } }
            else { State::Implement { branch, feedback: Some(g.output) } }
        }
        State::Done { .. } => State::Done { merged: true },
    }
}

fn main() {
    let mut input = String::new();
    std::io::Read::read_to_string(&mut std::io::stdin(), &mut input).unwrap();
    let state: State = serde_json::from_str(&input).unwrap();
    let workdir = std::env::var("FACTORY_WORKDIR").unwrap();
    println!("{}", serde_json::to_string(&handle(state, &workdir)).unwrap());
}
```

Cost: three crates (`serde`, `serde_json`, optionally `reqwest` for HTTP), no codec boilerplate, and the build is 537 KiB static with ~1 ms startup in the measured configuration. The gate is `make test`'s exit status; the agent call is a subprocess; the only "framework" is stdio.

Note on both: the daemon should generate the state type, the codec, and the JSON wire schema, then *also* generate a golden round-trip fixture. That is what makes the guarantee durable — a hand-edited state type that the workflow program never serializes the same way should fail CI, not fail at activation time.

## Invocation contract: what each family implies

| Model | Cost per activation | Fits | Breaks |
|---|---|---|---|
| **Process per activation, JSON on stdin/stdout** | OCaml/Rust/Swift/Dart/AOT ~1–50 ms; Deno ~12 ms (measured); JVM/BEAM 100s of ms | every compiled candidate; simplest daemon contract, no protocol lifecycle | JVM/BEAM unless a native image or warm pool is added |
| **Long-lived worker, length-prefixed JSON/msgpack over a UNIX socket** | one boot per VM/session | JVM, BEAM, Deno, any REPL-ish runtime | daemon must own crash/restart, backpressure, and protocol versioning; a handler crash is now a worker crash |
| **Embedded runtime (WASM/QuickJS)** | negligible | nothing on this list without a WASI shim | real `git`, `make`, and subprocess access — exactly what the contract needs; ticket #15 already treats code-mode as *not* the workflow layer |

Facts that decide this in #18: Rust and OCaml make the simplest model cheap; Kotlin/Scala/Java/Gleam make it expensive enough to force the second model; Dart, Swift, F#, and Deno sit in between. msgpack is available in both top candidates (`rmp-serde`; an OCaml `msgpack` package), but JSON is the more reviewable and debuggable wire format and neither candidate's decode cost is material at activation sizes.

## What would flip the order

- **Weight "reviewed, committed, buildable artifact" above type ergonomics** → Rust first. It has the only combination of hard exhaustiveness, vendored offline builds, a 537 KiB static binary, and 1 ms startup measured here.
- **Require a fully static binary with no libc dependency** → Rust, Swift (Static Linux SDK), Zig. OCaml, F#, Haskell, and the JVM group lose this criterion outright.
- **Require a warm runtime anyway** (e.g. the daemon keeps a worker per Project VM for latency) → the JVM/BEAM penalty shrinks and Kotlin (sealed `when` + kotlinx.serialization) and Gleam (best small type system on BEAM) move up sharply.
- **Require one language for daemon and workflow program** → Go, with generated per-state interfaces for coverage; the type-system cost is large and should be priced explicitly.
- **Forbid a second toolchain in the Project VM** → whichever language the VM image already carries wins; this is an operational fact, not a language fact, and should be recorded in the VM image spec.
- **Treat effect tracking as mandatory** → only Unison (abilities), PureScript/Elm (`Effect`/`Cmd`), and Lean's `IO` come close, and all fail reviewability, deployment, or IO respectively. This criterion is incompatible with the rest of the contract as written.

## Open questions this survey could not settle

1. **OCaml binary size and startup** — no primary source publishes either, and no OCaml toolchain was installed on the survey machine. A 30-minute spike on the Project VM image would settle both.
2. **F# NativeAOT + DU JSON** — whether `FSharp.SystemTextJson` survives trimming/AOT without a hand-written converter is not documented in the sources found. This is the single fact that decides whether F# is a top-three or a top-six answer.
3. **Dune lock directories vs opam switch pinning** — which one the build step (ticket #18) can rely on inside the VM, and whether `dune pkg` is still labelled experimental in the 3.25 docs (the docs page does not say; the 2025 announcement still called it a developer preview).
4. **Swift static SDK + `Subprocess`** — the 6.4 `Subprocess` package and the musl static SDK are both recent; whether they compose cleanly for a program that also links Foundation needs a build spike.
5. **Handler coverage under generated code** — every candidate here relies on the generator emitting the state type correctly. The compile gate proves *handler* coverage, not that the generated type matches the project config; that needs the golden-fixture check described above, and it is language-independent.

## Sources

Accessed 2026-11-23.

- OCaml releases and dates: https://ocaml.org/releases · manual 5.5: https://ocaml.org/manual/5.5/index.html · warning 8: https://ocaml.org/manual/5.4/comp.html · effects (no effect safety): https://ocaml.org/manual/5.5/effects.html · `Unix`: https://ocaml.org/manual/5.5/api/Unix.html · native linking: https://ocaml.org/manual/5.5/native.html · Dune 3.25: https://ocaml.org/changelog/2026-11-12-dune3250 · Dune lock dirs: https://dune.readthedocs.io/en/latest/tutorials/dune-package-management/locking.html · yojson: https://ocaml.org/p/yojson/3.0.0 · ppx_deriving_yojson: https://ocaml.org/p/ppx_deriving_yojson/latest/README.html · OCaml-LSP 1.26.1: https://ocaml.org/changelog/2026-11-06-ocaml-lsp-1261-draft
- Rust 1.100.0: https://blog.rust-lang.org/2026/11/12/Rust-1.100.0/ · E0004: https://doc.rust-lang.org/error_codes/E0004.html · platform support (musl Tier 2): https://doc.rust-lang.org/rustc/platform-support.html · cargo vendor: https://doc.rust-lang.org/cargo/commands/cargo-vendor.html · rustup toolchain file: https://rust-lang.github.io/rustup/overrides.html · serde_json: https://docs.rs/serde_json/latest/serde_json
- F#/C#/.NET 11: https://devblogs.microsoft.com/dotnet/announcing-dotnet-11/ · FS0025: https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/compiler-messages/fs0025 · DUs: https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/discriminated-unions · NativeAOT: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot · NuGet lock file: https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files · C# union: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/union
- Haskell: GHC blog (9.14.1 2025-12-19; 9.14.2-rc3 2026-11-12): https://ghc.gitlab.haskell.org/homepage/blog.html · warnings: https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/using-warnings.html · records: https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/exts/overloaded_record_dot.html · linking options: https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/phases.html · `System.Process`: https://hackage.haskell.org/package/process/docs/System-Process.html · aeson: https://hackage.haskell.org/package/aeson/docs/Data-Aeson.html · cabal freeze: https://cabal.readthedocs.io/en/stable/cabal-commands.html · HLS: https://github.com/haskell/haskell-language-server
- Swift 6.4: https://www.swift.org/blog/swift-6.4-released · enumerations (exhaustive switch): https://docs.swift.org/swift-book/LanguageGuide/Enumerations.html · SwiftPM lock: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/resolvingpackageversions · static Linux SDK: https://swift.org/documentation/articles/static-linux-getting-started.html
- Kotlin: https://kotlinlang.org/docs/sealed-classes.html · serialization: https://kotlinlang.org/docs/serialization-polymorphism.html · Kotlin/Native: https://kotlinlang.org/docs/native-overview.html · kotlin-lsp: https://github.com/Kotlin/kotlin-lsp · Gradle locking: https://docs.gradle.org/current/userguide/dependency_locking.html
- Dart: https://dart.dev/language/branches · https://dart.dev/tools/dart-compile · https://dart.dev/tools/pub/cmd/pub-get · https://dart.dev/blog/announcing-dart-2-6
- Scala 3.8: https://www.scala-lang.org/news/3.8/ · postmortem: https://scala-lang.org/blog/post-mortem-3.8.0.html
- Deno: https://docs.deno.com/examples/deno_compile/ · https://docs.deno.com/runtime/packages/ · Deno 2.9.8 release: https://github.com/denoland/deno/releases
- Java pattern switch: https://docs.oracle.com/en/java/javase/21/language/pattern-matching-switch.html · JDK releases: https://openjdk.org/projects/jdk
- Gleam: https://tour.gleam.run/flow-control/case-expressions · https://gleam.run/news/v0.33-exhaustive-gleam · https://gleam.run/writing-gleam/command-line-reference
- Zig: https://ziglang.org/documentation/master/#switch · https://ziglang.org/news/0.16.0-released/
- Crystal: https://crystal-lang.org/reference/latest/syntax_and_semantics/case.html · https://crystal-lang.org/reference/latest/guides/static_linking.html
- Go: https://go.dev/ref/spec#Type_switches · https://github.com/golang/go/issues/36387
- Excluded: https://guide.elm-lang.org/effects · https://guide.elm-lang.org/interop/ports · https://www.unison-lang.org/unison-1-0/ · https://github.com/roc-lang/roc · https://idris-lang.org/pages/download.html · https://hexdocs.pm/elixir/gradual-set-theoretic-types.html
