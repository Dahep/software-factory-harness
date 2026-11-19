-- PROTOTYPE — the default Loop in Dhall (ticket 016). Illustrative only:
-- no `dhall` binary on this machine, so this file is syntax-shaped, not compiled.

let Gate = ./schema/Gate.dhall
let Stage = ./schema/Stage.dhall
let Envelope = ./schema/Envelope.dhall
let Wave = ./schema/Wave.dhall
let Agent = ./schema/Agent.dhall
let Fail = ./schema/Fail.dhall
let Checkpoint = ./schema/Checkpoint.dhall
let Workflow = ./schema/Workflow.dhall

let reviewer = \(persona : Text) ->
      Agent::{ role = "reviewer", persona = Some persona }

let failTo
    : Text -> Natural -> Fail.Type
    = \(stage : Text) -> \(max : Natural) ->
        Fail::{ returnTo = Some stage, max_ = Some max, then_ = "block" }

in  Workflow::{
    , apiVersion = "factory/v1"
    , kind = "Workflow"
    , metadata = { name = "default-loop", description = Some "Issues in, reviewed code out." }

    , envelope =
        Envelope::{
        , clone = True
        , network =
            { tier = "allowlist"
            , allow =
              [ "github.com", "api.github.com", "registry.npmjs.org"
              , "pypi.org", "files.pythonhosted.org", "proxy.golang.org"
              , "crates.io", "static.crates.io"
              ]
            }
        , secrets = [ "github", "model-provider" ]
        , budget = { measure = True }
        }

    , concurrency = 1

    , checkpoints =
        { triage-approval = Checkpoint::{ stage = "triage", asks = [ "TriageDecision" ] }
        , merge-approval = Checkpoint::{ stage = "merge", asks = [ "PR", "GateReport" ] }
        }

    , measure =
        [ "stage.cycle_time", "gate.verdict", "review.findings", "run.retries"
        , "run.tokens", "run.cost", "pr.merge_latency", "tool.error_rate"
        , "agent.confusion_proxies"
        ]

    , stages =
        [ Stage::{
          , id = "intake"
          , on = Some { poll = "tracker", every = "5m" }
          , wave = None
          , gates = [] : List Gate.Type
          , checkpoint = None
          , action = None
          , measure = [ "intake.new_issues", "intake.triage_latency" ]
          }
        , Stage::{
          , id = "triage"
          , on = None
          , wave = Some Wave::{ agents = [ Agent::{ role = "triager", persona = None } ] }
          , produces = Some "TriageDecision"
          , gates =
              [ Gate::{ id = "decision-shape", check = { schema = "TriageDecision" }, onFail = Fail::{ retry = Some 1, then_ = "block" } }
              , Gate::{ id = "scope-declared", check = { field = "TriageDecision.acceptance_criteria" }, onFail = failTo "triage" 2 }
              ]
          , checkpoint = Some "triage-approval"
          , action = None
          , measure = [ "triage.decision_time", "triage.owner_edits" ]
          }
        , Stage::{
          , id = "implement"
          , on = None
          , wave = Some Wave::{ agents = [ Agent::{ role = "implementer", persona = None } ] }
          , produces = None
          , gates =
              [ Gate::{ id = "build", check = { command = "make build" }, onFail = Fail::{ retry = Some 2, then_ = "block" } }
              , Gate::{ id = "tests", check = { command = "make test" }, onFail = Fail::{ retry = Some 2, then_ = "block" } }
              , Gate::{ id = "diff-present", check = { changed_files = "> 0" }, onFail = Fail::{ open_issue = Some True } }
              ]
          , checkpoint = None
          , action = None
          , measure = [ "implement.cycle_time", "implement.retries", "implement.diff_size" ]
          }
        , Stage::{
          , id = "review"
          , on = None
          , wave = Some Wave::{ agents = [ reviewer "spec-fidelity", reviewer "adversarial" ] }
          , produces = None
          , gates =
              [ Gate::{ id = "review-verdict", check = { all_reviewers = "approve" }, onFail = failTo "implement" 2 } ]
          , checkpoint = None
          , action = None
          , measure = [ "review.findings", "review.turnaround" ]
          }
        , Stage::{
          , id = "merge"
          , on = None
          , wave = None
          , gates =
              [ Gate::{ id = "pr-open", check = { pr = "open" }, onFail = Fail::{ open_issue = Some True, then_ = "block" } }
              , Gate::{ id = "checks-green", check = { pr_checks = "all_pass" }, onFail = failTo "implement" 1 }
              ]
          , checkpoint = Some "merge-approval"
          , action = Some { pr = { merge = "squash", via = "gh" } }
          , measure = [ "merge.latency", "merge.squash_size" ]
          }
        ]
    }
