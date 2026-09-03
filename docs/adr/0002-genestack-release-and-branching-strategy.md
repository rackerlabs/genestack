# Architectural Decision Record (ADR)

| Field | Value |
|---|---|
| **Title** | Genestack Release and Branching Strategy (Updated) |
| **Status** | ACCEPTED |
| **Date** | 2026-02-17 |
| **Supersedes** | [`docs/adr/0001-genestack-release-and-branching-strategy.md`](0001-genestack-release-and-branching-strategy.md) |
| **Superseded by** | _(none)_ |

> **Companion document:** The full, normative spec lives in [`docs/release-strategy.md`](../release-strategy.md). This ADR records the *decision*; that doc records the *rules*.

## Context

### Problem Statement
Genestack orchestrates an integrated stack of three distinct upgrade domains — Kubernetes/kubespray infrastructure, non-OpenStack platform operators, and OpenStack services — each with different upstream release cadences, risk profiles, and test requirements. A single monolithic "roll-up" release conflates these domains, forcing operators to test and deploy unrelated changes together and making incident isolation difficult.

We need a release model that:

1. Isolates each upgrade domain into a dedicated release slot so operators know exactly what a given release contains.
2. Keeps the Kubernetes foundation fresh (quarterly) while deferring riskier OpenStack platform upgrades to a half-year cadence.
3. Preserves a stable, test-from-tag release artifact for every shipped version.
4. Allows fast, scoped patching against the *exact* content of any released tag.

### Considered Options

| # | Option | Fit |
|---|---|---|
| 1 | **GitFlow** | Reject. Long-lived `develop` branch adds merge churn and diverges from the `main`-is-trunk convention already in use. |
| 2 | **GitHub Flow** | Reject. Single-branch model cannot provide a stable, re-testable release artifact per quarter. |
| 3 | **Trunk-Based + Release Branches** | Adopt. `main` remains the trunk for all feature/fix work; short-lived `release-YYYY.X` branches provide the frozen, testable release surface. |
| 4 | **OpenStack-style time-based** | Rejected as primary. Matches upstream OpenStack cadence but gives no room for quarterly Kubernetes foundation upgrades. |

### Definitions

- **dev-branch** — the `main` git branch. Source of truth for ongoing development. All feature/fix work lands here first.
- **release-branch** — `release-YYYY.X`, cut from `main` at the start of a calendar quarter. Remains open for the lifetime of that quarter's upgrade train (see Maintenance below).
- **release-tag** — `release-YYYY.X.{0|1}` (with optional `.{0|1}` patch suffix). An immutable snapshot of a release-branch used for deployment/rollback.
- **upgrade domain** — a logical group of components treated as a single upgrade concern (K8s/Kubespray, non-OpenStack operators, or OpenStack services).

## Decision

We adopt a **time-based, domain-scoped Release Branching** strategy:

1. **Quarterly cadence.** A `release-YYYY.X` branch is **cut from `main`** at the start of each calendar quarter (February, May, August, November). Four release branches are produced per year.

2. **Domain-scoped release tiers per year.** Each calendar year is split into **two odd-numbered quarters** and **two even-numbered quarters**:
   - **Odd quarters (`YYYY.1`, `YYYY.3`):** — OpenStack upgrade year. The release is the **OpenStack platform upgrade** to the upstream OpenStack release that shipped most recently *before* this Genestack release. (e.g., Genestack `2026.1` deploys OpenStack `2026.1`; Genestack `2026.3` deploys OpenStack `2026.2`.)
   - **Even quarters (`YYYY.2`, `YYYY.4`):** — Kubernetes and operator upgrade year. The release upgrades **Kubernetes + kubespray** and the **non-OpenStack Helm operators/charts**. OpenStack services charts are *not* modified in even quarters.

3. **Tag-based release tiers within a branch.** Each release-branch produces tagged releases in a fixed order with explicit component scope:
   - `release-YYYY.X.0` — **Foundation tier.** Kubernetes/kubespray upgrades + any bug fixes required to land that foundation. *(In odd-numbered quarters this carries the OpenStack upgrade instead.)*
   - `release-YYYY.X.1` — **Operator tier.** All non-OpenStack Helm operators/charts upgraded to current supported versions. *(Not produced in odd-numbered quarters, which are OpenStack-only.)*
   - Patch tags `.0.1`, `.1.1`, etc. — **Fix-only** backports scoped to their parent tag (see Fix flow below).

4. **`main` is the trunk.** All fixes land in `main` first, then are cherry-picked to the relevant release-branch. A `.0.1` patch only backports fixes relevant to the `.0` tag's pinned component set; a `.1.1` patch only backports fixes relevant to the `.1` tag's set. Cross-tier contamination is forbidden.

5. **Two-active-branch maintenance window.** Only the **current** release-branch and the **immediate previous** release-branch are maintained. Older branches are EOL'd at the cut of the next quarter.

> **OpenStack version lag.** OpenStack releases on a coordinated 6-month cadence (odd-year `.1` and `.2` releases). Genestack's odd-numbered Genestack releases target the *most recent completed OpenStack release*, which is always one half-cycle behind the calendar. This is intentional to guarantee a tested, stable OpenStack baseline.

## Consequences

| Dimension | Positive | Negative |
|---|---|---|
| **Test surface** | Each upgrade domain is tested in isolation; operators can adopt K8s or OpenStack upgrades independently. | More release tags per year to validate. |
| **Risk isolation** | K8s/kubespray blast radius is fully separated from OpenStack platform risk. | OpenStack stays on a 6-month cadence, delaying non-critical feature delivery. |
| **Rollback** | Any tag is a precise, re-deployable snapshot; patches are strictly scoped. | Requires disciplined cherry-pick hygiene (no fix-forward, no cross-tier leakage). |
| **Operator UX** | Release notes and product matrix are predictable per tier. | Odd-year operators must wait 6 months for K8s foundation upgrades that even years deliver quarterly. |

## Related Decisions
- `docs/adr/0003-helm-chart-version-pinning.md` _(future)_ — pins exact chart versions and commit hashes inside `helm-chart-versions.yaml`.
- `docs/adr/0004-openstack-release-targeting.md` _(future)_ — defines the OpenStack `.1`-lag targeting rule and validation bar.
