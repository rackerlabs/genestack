# Architectural Decision Record (ADR)

> This record is **archived** for historical reference. The superseded strategy is preserved here unchanged.
> New strategy: see `docs/adr/0002-genestack-release-and-branching-strategy.md`.

## Title
Genestack Release and Branching Strategy (Superseded)

## Status
SUPERSEDED by `docs/adr/0002-genestack-release-and-branching-strategy.md`

## Date
2025-02-17

## Context
Problem Statement: To ensure we are releasing a reliable product we need to adopt a release branching strategy. The following strategies were considered:

1. Gitflow:
   - Purpose: A structured approach for managing releases, focusing on long-lived branches for development and release management.
   - Branches: main (or master), develop, feature, release, hotfix.

2. GitHub Flow:
   - Purpose: A simplified workflow for continuous delivery, focusing on frequent deployments and a single source of truth.
   - Branches: main, Feature branches.
   - Best for: Fast-paced environments with frequent deployments and smaller teams.

3. Trunk-Based Development:
   - Purpose: Emphasizes a single main branch as the source of truth, with short-lived feature branches merged back frequently.
   - Branches: main (or trunk), Feature branches.

4. Release Branching:
   - Purpose: Isolates release management work from ongoing development, creating a stable branch for testing and preparing for a release.
   - Branches: main (or develop), Release-candidate, Release.

## Decision
Use Release Branching Strategy for genestack — ACCEPTED (superseded).

## Consequences
- Static point-in-time codebase testable repeatably.
- Stable branches isolated from `main`.

## Outstanding Todo's
Superseded — see ADR-0002.
