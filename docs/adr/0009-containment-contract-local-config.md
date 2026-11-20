# Containment is a versioned contract plus local devvm configuration

Each Managed Project's Workflow Artifact declares the **containment contract**: clone mode, network tier, a named network preset, an optional stable `extra_allow` list, and secret names. The full network allowlist, provider endpoints, secret scopes, and secret values are **local devvm configuration**, owned by the Owner and never version-controlled. Factory expands the preset, applies `extra_allow` and the local config to the Project VM, and records every Egress Request decision and the applied local rule in its local SQLite database. Egress approvals do not persist as artifact PRs and have no provisional state. Drift checks cover the contract fields only; local allowlist additions are recorded local state, not drift. Cost is tracked when the adapter reports usage; there is no `budget` field and no cap in v1.

## Considered Options

- **The full allowlist in the Envelope** — rejected: every egress request would need a PR; too much friction for an operational decision.
- **PR every egress approval (I7)** — rejected and reversed: the local config is the applied state; the SQLite record is the audit.
- **Tier only, no preset or `extra_allow`** — rejected: no sane defaults and no reproducible stable hosts.
- **A separate local-config repository** — rejected: the local config is operational, not versioned; the preset plus the SQLite applied rules are the recovery path.
- **Keep the `budget` field** — rejected: budgets are out of scope; cost is tracked when reported.

## Consequences

- ADR-0004 is amended: the artifact owns the contract; local devvm config owns the operational allowlist and secret scopes; I7's artifact-PR persistence is reversed; the `budget` field is removed.
- ADR-0006 is amended: the Envelope no longer carries `budget`.
- ADR-0007 is amended: a Roster Entry no longer carries `budget` or network host requirements; it declares secret names and model/tool requirements.
- Factory's SQLite gains an Egress Request entity and an applied-local-rule projection; both are backed up with the database.
- `extra_allow` is the only host list in the artifact; it holds stable project hosts and is empty by default.
- Provider endpoints are written to local config at Project Init; `bindings.dhall` carries provider and secret names and provenance, not hosts.
- A rebuilt VM is seeded from the preset, `extra_allow`, the local devvm config, and the SQLite applied rules.
- Capability Profiles remain post-v1 and narrow the contract and the local config; they do not reintroduce a budget.

Status: accepted 2026-11-20 (architecture review, candidate 3: containment contract and local config).
