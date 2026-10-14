---
title: What should the tracker adapter interface support (Fizzy, Linear, GitHub…) and how do permissions map?
type: wayfinder:research
blocked-by: []
assignee: done
status: resolved
---

## Question

Factory manages multiple projects, each with its own issue tracker. Define the **abstract capabilities and data model** a tracker adapter must expose (issues, labels/states like needs-triage → ready, assignments, dependencies/blocking, comments, history/audit) by studying GitHub Issues (via `gh`), https://github.com/basecamp/fizzy, and Linear's data model and permission systems. Verdict: a draft adapter interface (capability list), what each target tracker can/can't support, and the **permission concern**: how per-agent tracker permissions (read, comment, create, assign, close, merge-adjacent actions) map onto each tracker's own permission model, and what the harness must gate itself.

## Resolution

### Draft adapter contract

Treat the adapter as a translation and authorization boundary, not as a lowest-common-denominator tracker schema. Keep provider IDs opaque, preserve provider-specific fields/events, and expose unsupported operations as unsupported rather than silently emulating them. Normalize only shared concepts; configured workflow labels/states map to harness phases without changing the provider's underlying meaning.

```text
TrackerAdapter
  capabilities() -> CapabilitySet
  listIssues(query) -> Page<Issue>
  getIssue(IssueRef) -> Issue
  createIssue(IssueDraft) -> Issue
  updateIssue(IssueRef, IssuePatch) -> Issue
  transitionIssue(IssueRef, WorkflowTarget) -> Issue
  assign(IssueRef, PrincipalRef) / unassign(...)
  listComments(IssueRef, cursor?) -> Page<Comment>
  addComment(IssueRef, body) -> Comment
  listActivity(IssueRef, cursor?) -> Page<Activity>     # optional fidelity
  listDependencies(IssueRef) -> Dependencies
  addDependency(IssueRef, relation, IssueRef) / removeDependency(...)
  authorize(actor, operation, IssueRef?) -> Allow | Deny | NeedsApproval
```

`Issue` should include `providerRef` (provider + workspace/repository/team + opaque ID), title/body/url, creator, assignees, labels/tags, workflow state (provider ID/name/category), open/closed/archive status, timestamps, and provider extensions. `Comment` includes opaque ID, body, author and timestamps. `Activity` carries actor, event type, timestamp and provider payload; it must not promise immutable audit semantics. `Dependencies` distinguish at least `blocked_by` and `blocking`; do not conflate hierarchy/sub-issues with blocking. `CapabilitySet` reports read/list, create, update, workflow transition, assignment, comments, dependency relations, activity/history, and deletion separately, with per-capability read/write fidelity and any configuration constraints. The optional `authorize` check supports early UX but is not the security boundary: the harness must gate every mutation immediately before calling the provider and still handle provider denial.

Model harness operations explicitly: `read`, `comment`, `create`, `edit`, `assign`, `transition`, `close`, `dependency.manage`, and (if enabled elsewhere) `merge`. A transition into a configured terminal state is a close-like operation and should be checked as `close`, not merely generic edit. Merge is repository/PR functionality and is not implied by tracker access.

### Support and permission mapping

| Concern | GitHub Issues via `gh` / API | Basecamp Fizzy | Linear API |
|---|---|---|---|
| Issue model | Repository-scoped issues (REST issue endpoints also return PRs); title/body, open/closed + close reason, issue type/fields where enabled. | Board-scoped Cards; title/rich description, published/draft, closed/postponed, card number and board. No repository concept. | Team-scoped Issues; title/description, team, workflow state, assignee, labels, priority and other schema fields. GraphQL IDs and human-readable identifiers. |
| Workflow / triage | Open/closed are native lifecycle states; labels are free-form metadata, not a single workflow state. Projects and issue fields may provide configurable status, depending on setup. A pipeline such as `needs-triage → ready-for-agent` is normally label convention/configuration. | Ordered board Columns are native workflow stages; special triage (“Maybe?”), “Not Now”, and “Done” states are distinct from a column. Tags are separate metadata. Map these deliberately; do not treat tags as workflow. | Team WorkflowStates are native state values, categorized (including backlog/started/completed/canceled); team triage can route new issues to Triage. Labels are separate. Map configured state IDs/names to harness phases. |
| Assignment | Native, multi-assignee; API supports add/remove and issue representations expose assignees. | Native, multiple assigned users on a card. | Native human assignee. For Linear agent apps, assignment is app `delegate` (human retains assignee/ownership), enabled by `app:assignable`. |
| Blocking / dependencies | Native issue relations (`blocked_by` / `blocking`) and separate sub-issue hierarchy; `gh issue create/edit/view` supports dependency flags and JSON fields. | No dependency/blocking relation found in the public API or Card/Board model examined. Report unsupported; never fake it with tags/comments. | Issue relation model supports linked issue relationships, including blocking/dependency semantics; expose relation kinds as provider-specific values and normalize only blocking directions. |
| Comments | Native issue comments, list/create/update/delete endpoints and `gh issue comment`. | Native comments on Cards, with list/create/update/delete API. | Native issue comments through GraphQL; comment creation has dedicated OAuth `comments:create` scope. |
| Activity/history | Timeline endpoint exposes typed events (including labels, assignment, state and blocking changes); issue/comment timestamps and actors are available. | Activity feed records actions such as triage, assignment, close and comments, but Fizzy explicitly describes it as a feed rather than an immutable audit log; eventable/board data may reflect current state. | GraphQL activity/history and webhooks support change tracking; webhook update events include actor and `updatedFrom`. Treat as provider activity, not a guaranteed immutable audit ledger. |
| Provider permission basis | `gh` is a CLI client using the authenticated GitHub identity/token; it does not create a separate agent permission model. Access combines token scopes/selected repositories with repository/org role. Fine-grained PATs/GitHub Apps can narrow repositories and permission family; Issues permission is generally read or write, not independent per-action grants. Repository role (e.g. Triage vs Write) constrains operations. | Personal access tokens are per-identity and only `Read` or `Read + Write` for the account. The server also enforces account roles and board access (`all_access` or explicit board user access); board administration is separate and restricted. Token write permission does not create per-agent or per-operation grants. | Personal API keys are user credentials; OAuth supports scopes including `read`, broad `write`, `issues:create`, and `comments:create`. Workspace admin installs `actor=app` agent integrations and can grant/revoke team access; API calls remain constrained by workspace/team access. Agent assignment/mention scopes are explicit. |
| Harness must gate | If several agents share one credential, the provider sees the same principal and its broad permissions. Gate comment/create/assign/close separately in harness policy. Prefer a dedicated GitHub App installation token scoped to only the project repositories and minimum Issues permission; it still cannot express every per-agent action split. Avoid `gh` credential sharing with untrusted agents. | Use a dedicated low-privilege identity/token per trust boundary, preferably Read if no writes are needed. With Read+Write, enforce each agent's `comment/create/assign/close` policy in the harness; board membership and role remain additional provider checks. | Prefer OAuth with only required scopes. `issues:create` and `comments:create` can separate those writes from generic `write`; there is no equivalent narrow scope for each update/assign/close action. For app actors, team-access changes are admin-controlled and the app scope gate for assignment is `app:assignable`; enforce per-agent granular rules in harness regardless. |
| Merge-adjacent actions | PR creation/review/merge APIs are separate and may require repository Contents/Pull requests permissions and branch-rule checks; keep outside tracker adapter and authorize separately. | No PR merge capability in card API. | Git integration/PR merge is not an issue operation; authorize separately in the code-host adapter. |

### Permission conclusion

There are two principals to keep distinct: the provider credential principal (what GitHub/Fizzy/Linear authorizes) and the harness agent principal (the agent requesting this operation). Provider-native auth is authoritative but typically coarser than `read/comment/create/assign/close` per agent. The harness therefore needs an operation-level policy check on *every* mutation, even when the provider credential is read/write and even if a prior capability probe allowed the action. Do not give the raw shared credential to agents. Prefer distinct, least-privilege credentials per project/trust boundary, use provider scopes/repository/team/board grants to reduce blast radius, and retain harness audit records linking agent, operation, provider identity, target and result. A provider API returning HTTP success is not by itself proof the intended field changed: verify important writes by reading back, especially where GitHub documents that some unauthorized label/assignee/field changes may be silently dropped.

### Primary sources

- GitHub: [About issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/about-issues), [REST issue endpoints](https://docs.github.com/en/rest/issues/issues), [issue comments](https://docs.github.com/en/rest/issues/comments), [issue timeline](https://docs.github.com/en/rest/issues/timeline), [issue dependencies / `gh` flags](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies), [fine-grained PAT permissions](https://docs.github.com/en/rest/overview/permissions-required-for-fine-grained-personal-access-tokens), and [GitHub CLI issue commands](https://cli.github.com/manual/gh_issue).
- Fizzy (first-party API documentation and source): [API overview/authentication](https://github.com/basecamp/fizzy/blob/main/docs/api/README.md), [authentication](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/authentication.md), [cards](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/cards.md), [boards and board access](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/boards.md), [columns](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/columns.md), [comments](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/comments.md), [activities](https://github.com/basecamp/fizzy/blob/main/docs/api/sections/activities.md); source model references: [`Card`](https://github.com/basecamp/fizzy/blob/main/app/models/card.rb), [`Board::Accessible`](https://github.com/basecamp/fizzy/blob/main/app/models/board/accessible.rb), and [`User::Role`](https://github.com/basecamp/fizzy/blob/main/app/models/user/role.rb).
- Linear: [GraphQL API and issue/workflow examples](https://linear.app/developers/graphql), [OAuth scopes and token model](https://linear.app/developers/oauth-2-0-authentication), [agent actor/team access and assignable scope](https://linear.app/developers/agents), and [webhook event/activity payloads](https://linear.app/developers/webhooks). The public GraphQL schema is introspectable at `https://api.linear.app/graphql` and via the [Linear API schema explorer](https://studio.apollographql.com/public/Linear-API/variant/current/home).
