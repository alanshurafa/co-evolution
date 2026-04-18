---
phase: 09-lab-folded
plan: 01
subsystem: integrations-lab-fold
tags: [lab-fold, byte-identity, exclusion-discipline, milestone-closeout, unification-absorb]
requires: [phase-05, phase-08]
provides: [top-level-integrations-dir, mempalace-reference-config, lab-absorb-exclusion-record]
affects:
  - integrations/mempalace.yaml
  - integrations/README.md
key-files:
  created:
    - integrations/mempalace.yaml
    - integrations/README.md
  modified: []
decisions:
  - "Copy, don't move — co-evolution-lab/mempalace.yaml source stays intact so the lab workspace can be archived non-destructively at the user's discretion"
  - "integrations/ follows the Phase 8 top-level adjacent-folder pattern (evals/, schemas/) — no nesting under runners/ or dev-review/"
  - "Exclusion rationale for autoresearch is NOT restated in integrations/README.md — README defers to the Key Decisions table in PROJECT.md for authority"
  - "Lab PS integration scripts (run-autoresearch.ps1, run-co-evolve.ps1, run-dev-review.ps1, sync-upstream.ps1) marked `deferred`, not `out-of-scope` — door left open for future workspace-agnostic ports"
  - "README points at runners/codex-ps/scripts/run-co-evolution.ps1 as the canonical PS harness so future readers know where the non-lab-specific logic lives"
metrics:
  duration: 2min
  tasks_completed: 2
  commits: 2
  completed: 2026-04-17
requirements: [LABF-01, LABF-02]
---

# Phase 9 Plan 01: Fold mempalace.yaml into integrations/ and document lab-absorb exclusions

One-liner: Created top-level `integrations/` directory, copied the sole portable lab artifact (`mempalace.yaml`, 585 bytes) byte-identically from `C:/Users/alan/Project/co-evolution-lab/`, and wrote `integrations/README.md` naming the five excluded items (Karpathy's `auto-research/` clone, lab PS integration scripts, stale mirror clone at `co-evolution/`, `archive/`, `auto-research-safe/`) with rationale — closing the Unification Absorb milestone.

## What Landed Per Task

### Task 1: Create integrations/ directory and copy mempalace.yaml byte-identically (LABF-01)

- Created `integrations/` directory at repo root (new top-level folder, follows Phase 8 `evals/` + `schemas/` adjacent pattern)
- Copied `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` -> `integrations/mempalace.yaml` with `cp -p`
- `diff -q` silent — byte-identical
- Size exactly 585 bytes
- First line exactly `wing: co_evolution`
- SHA256 matches plan's recorded value: `1720843dc4486ace49d0e30ce143fca7769747a2eb56bbe1489129658ace0661`
- Lab source file at `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` still present (copy, not move)

Commit: `9a838d5`

### Task 2: Write integrations/README.md documenting fold scope and exclusions (LABF-02)

- Created `integrations/README.md` — 36 lines
- `## What's Here` — names `mempalace.yaml` as the sole folded artifact with byte-identical provenance
- `## What Was Excluded From The Lab Absorb` — three sub-sections covering all five excluded items:
  - Karpathy's `autoresearch` clone (`auto-research/` + presumed-redundant `auto-research-safe/`) — defers to PROJECT.md Key Decisions table
  - Lab-specific PowerShell integration scripts (`run-autoresearch.ps1`, `run-co-evolve.ps1`, `run-dev-review.ps1`, `sync-upstream.ps1` + `schemas/`/`templates/`/`reports/` subdirs) — marked `deferred`, points at canonical PS harness `runners/codex-ps/scripts/run-co-evolution.ps1`
  - Obsolete directories — stale `co-evolution/` mirror + `archive/` snapshots noted for archival
- `## Adding New Integrations` — one-paragraph guidance for future contributors
- All 8 acceptance grep gates pass (see table below)

Commit: `0a7f708`

## Commit Chain

```
0a7f708  docs(09-01): add integrations/README.md documenting fold scope and exclusions
9a838d5  feat(09-01): fold mempalace.yaml into integrations/
```

Both commits pushed to `feat/unification-absorb` on `origin`.

## Byte-Identity Evidence

| Property | Source | Destination | Match |
|----------|--------|-------------|-------|
| Path | `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` | `integrations/mempalace.yaml` | — |
| Size (bytes) | 585 | 585 | OK |
| First line | `wing: co_evolution` | `wing: co_evolution` | OK |
| SHA256 | `1720843dc4486ace49d0e30ce143fca7769747a2eb56bbe1489129658ace0661` | `1720843dc4486ace49d0e30ce143fca7769747a2eb56bbe1489129658ace0661` | OK |
| `diff -q` | — | — | silent (clean) |
| Source still exists after copy | yes | — | OK (copy, not move) |

## README Acceptance Gates (all pass)

| Gate | Check | Status |
|------|-------|--------|
| File exists | `test -f integrations/README.md` | OK |
| Contains `runners/codex-ps` | canonical PS harness pointer | OK |
| Contains `PROJECT.md` | defers autoresearch-decision authority | OK |
| Contains `autoresearch` (case-insensitive) | exclusion named | OK |
| Contains `workspace-specific` (case-insensitive) | PS scripts exclusion rationale | OK |
| Contains `byte-identical` (case-insensitive) | fold fidelity stated | OK |
| Contains `deferred` (case-insensitive) | PS script porting correctly marked deferred | OK |
| Line count >= 25 | actual 36 lines | OK |

## Phase-Level Verification (all pass)

```bash
test -f integrations/mempalace.yaml                                    # OK (LABF-01)
diff -q "C:/Users/alan/Project/co-evolution-lab/mempalace.yaml" \
        integrations/mempalace.yaml                                    # silent (LABF-02)
grep -qi "autoresearch" integrations/README.md                         # OK (LABF-02)
grep -q  "PROJECT.md"   integrations/README.md                         # OK (LABF-02)
grep -qi "workspace-specific" integrations/README.md                   # OK (CXPS-02 pattern)
grep -q  "runners/codex-ps"   integrations/README.md                   # OK (CXPS-02 pattern)
test -f "C:/Users/alan/Project/co-evolution-lab/mempalace.yaml"        # OK (copy, not move)
```

## Excluded Items Named in README (all 5)

| # | Item | Rationale in README |
|---|------|--------------------|
| 1 | `co-evolution-lab/auto-research/` | unrelated ML training domain; defers to PROJECT.md |
| 2 | `co-evolution-lab/auto-research-safe/` | presumed redundant with `auto-research/` (parenthetical inside autoresearch section) |
| 3 | `co-evolution-lab/integrations/co-evolution/` (PS scripts) | workspace-specific; duplicates canonical PS harness; porting deferred |
| 4 | `co-evolution-lab/co-evolution/` | stale untracked mirror of the public repo; canonical is this repo |
| 5 | `co-evolution-lab/archive/` | historical snapshots preserved in source-repo git history |

## Deviations

None. Plan executed exactly as written.

No Rule 1 fixes, no Rule 2 additions, no Rule 3 unblocks, no Rule 4 escalations. The plan's frontmatter `must_haves` (artifacts + key_links) all landed on the first pass, and every acceptance grep gate passed without iteration.

## Threat Mitigations Applied

- **T-09-01 (silent byte mutation during copy):** `diff -q` immediately after `cp`, plus independent SHA256 check. Both confirm byte identity against the plan's recorded hash. Would have caught line-ending conversion, BOM insertion, or silent truncation.
- **T-09-02 (lab source accidentally moved/deleted):** explicit `test -f` on the source after the copy step. Source file confirmed present post-copy.
- **T-09-03 (exclusion discipline regression — future contributor re-adds autoresearch):** README names all five excluded items with rationale; defers to PROJECT.md Key Decisions table for authority on the autoresearch decision. Grep-matchable substrings (`autoresearch`, `workspace-specific`, `deferred`) make the exclusion record machine-detectable.
- **T-09-04 (future contributor edits the wrong `co-evolution/` directory):** README explicitly calls out the stale `co-evolution-lab/co-evolution/` mirror as "not a git repo" and names this repo as the canonical version.

## Requirements Coverage

| Req | Landed via | Status |
|-----|------------|--------|
| LABF-01 | Task 1 (integrations/mempalace.yaml byte-identical copy) | Complete |
| LABF-02 | Task 2 (integrations/README.md names autoresearch exclusion, defers to PROJECT.md, byte-identical provenance stated) | Complete |

## Milestone Closeout

Phase 9 is the final phase of the **Unification Absorb** milestone. With LABF-01 and LABF-02 complete:

- All 17 v3 requirements are Complete (CXPS-01/02 + PRTP-01..05 + RNPT-01..05 + EVAL-01..03 + LABF-01..02)
- The `co-evolution-lab/` workspace at `C:/Users/alan/Project/co-evolution-lab/` can now be archived at the user's discretion — every item worth keeping has been folded into this repo or deliberately excluded with recorded rationale
- The private `codex-co-evolution/` workspace was already covered by Phase 5 CXPS-01 (byte-identical copy to `runners/codex-ps/`)

## Known Stubs

None. Both files are complete: `mempalace.yaml` is a byte-identical copy of a production-complete reference config, and `README.md` documents all five excluded items with no TODO markers or placeholder prose.

## Self-Check: PASSED

- `integrations/mempalace.yaml` — FOUND (585 bytes, SHA256 `1720843d...`)
- `integrations/README.md` — FOUND (36 lines)
- Commit `9a838d5` — FOUND in git log, pushed to origin
- Commit `0a7f708` — FOUND in git log, pushed to origin
- Source file at `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` — still present (copy, not move)
- All 8 README acceptance grep gates pass
- All 7 phase-level verification gates pass
- Both requirements (LABF-01, LABF-02) complete
