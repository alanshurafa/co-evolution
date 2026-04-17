# Integrations

Reference integration configs for co-evolution workflows. Landed during the Unification Absorb milestone (Phase 9) by folding the unique portable artifacts from `co-evolution-lab/`.

## What's Here

### `mempalace.yaml`

A reference integration config for MempAlace (Alan's knowledge graph / memory tool), documenting what a co-evolution <-> MempAlace integration looks like at the config level. Structure: `wing` + `rooms[]` with keywords.

Folded from `co-evolution-lab/mempalace.yaml` (585 bytes, byte-identical).

## What Was Excluded From The Lab Absorb

The lab workspace contained several items that were **deliberately not folded**. Future contributors should know these were excluded intentionally, not overlooked.

### Karpathy's `autoresearch` clone

`co-evolution-lab/auto-research/` (and the presumed-redundant `auto-research-safe/`) — an unmodified clone of Karpathy's `autoresearch` repo. Excluded because it is an **unrelated ML training domain** with zero of this project's commits. Co-Evolution is a bounce-protocol tooling repo, not an ML training framework. The decision is recorded in the Key Decisions table in [PROJECT.md](../.planning/PROJECT.md).

### Lab-specific PowerShell integration scripts

`co-evolution-lab/integrations/co-evolution/` contained PS scripts (`run-autoresearch.ps1`, `run-co-evolve.ps1`, `run-dev-review.ps1`, `sync-upstream.ps1`) plus `schemas/`, `templates/`, and `reports/` subdirectories. Excluded because they are **workspace-specific harness scripts** tied to the lab's particular directory layout and cross-project paths. They reference autoresearch (also excluded) and duplicate harness logic that now lives in the canonical PS harness.

**Canonical PS harness:** `runners/codex-ps/scripts/run-co-evolution.ps1` (landed in Phase 5 preservation).

Porting any of these lab PS scripts to be workspace-agnostic is **deferred** — not out of scope, just not part of this milestone.

### Obsolete directories (noted for archival)

- `co-evolution-lab/co-evolution/` — stale untracked snapshot of the public repo (not a git repo). Canonical version is this repo.
- `co-evolution-lab/archive/` — historical snapshots preserved in source-repo git history.

## Adding New Integrations

Drop new reference configs here alongside `mempalace.yaml`. Update this README's "What's Here" section with a brief description.
