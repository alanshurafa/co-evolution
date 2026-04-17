---
phase: 09-lab-folded
plans: [09-01]
subsystem: integrations-lab-fold
tags: [lab-fold, byte-identity, exclusion-discipline, milestone-closeout, unification-absorb-final]
requires: [phase-05, phase-08]
provides: [top-level-integrations-dir, mempalace-reference-config, lab-absorb-exclusion-record, unification-absorb-milestone-complete]
affects:
  - integrations/
tech-stack:
  added: []
  patterns: [byte-identical-copy-with-diff-q-gate, copy-not-move-for-peer-projects, exclusion-discipline-with-rationale, defer-to-project-md-for-decision-authority]
metrics:
  duration: 2min
  tasks_completed: 2
  commits: 2
  completed: 2026-04-17
requirements: [LABF-01, LABF-02]
---

# Phase 9: Lab Folded Summary

One-liner: Folded the sole portable artifact from `co-evolution-lab/` (`mempalace.yaml`, 585 bytes, byte-identical) into a new top-level `integrations/` directory and authored `integrations/README.md` naming all five excluded items with rationale — closing the **Unification Absorb** milestone with LABF-01 and LABF-02 both Complete.

## What Landed Per Plan

### Plan 09-01: Fold mempalace.yaml into integrations/ and document lab-absorb exclusions (LABF-01, LABF-02)

- `integrations/` directory created at repo root (new top-level folder, parallels `evals/`, `schemas/`, `runners/`)
- `integrations/mempalace.yaml` — byte-identical copy of `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` (585 bytes, SHA256 `1720843dc4486ace49d0e30ce143fca7769747a2eb56bbe1489129658ace0661`), `diff -q` silent
- `integrations/README.md` — 36 lines documenting what was folded, what was excluded, and why
- Lab source file untouched (copy, not move) — `co-evolution-lab/` can now be archived non-destructively
- All 8 README acceptance grep gates pass
- All 7 phase-level verification gates pass

Commits: `9a838d5` (mempalace.yaml fold), `0a7f708` (README).

## Commit Chain

```
0a7f708  docs(09-01): add integrations/README.md documenting fold scope and exclusions
9a838d5  feat(09-01): fold mempalace.yaml into integrations/
```

Both commits pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| LABF-01 | 09-01 | Complete |
| LABF-02 | 09-01 | Complete |

## Wave Order Executed

Single-plan phase (Wave 1 only): 09-01 T1 -> T2, strictly sequential.

## Files Modified (Phase-Level)

- `integrations/mempalace.yaml` — new file, byte-identical copy of lab source
- `integrations/README.md` — new file (36 lines, the only new original content in Phase 9)

Zero files under `runners/codex-ps/`, `evals/`, `schemas/`, or any other existing directory were touched by Phase 9.

## Excluded Items (All 5 Named in integrations/README.md)

| # | Lab path | Rationale |
|---|----------|-----------|
| 1 | `co-evolution-lab/auto-research/` | Unmodified Karpathy clone; unrelated ML training domain. Defers to PROJECT.md Key Decisions table for authority. |
| 2 | `co-evolution-lab/auto-research-safe/` | Presumed redundant with `auto-research/` (parenthetical inside autoresearch section). |
| 3 | `co-evolution-lab/integrations/co-evolution/` (PS scripts) | Workspace-specific harness scripts (`run-autoresearch.ps1`, `run-co-evolve.ps1`, `run-dev-review.ps1`, `sync-upstream.ps1` + `schemas/`/`templates/`/`reports/`). Duplicate canonical harness logic at `runners/codex-ps/scripts/run-co-evolution.ps1`. Porting **deferred**, not out-of-scope. |
| 4 | `co-evolution-lab/co-evolution/` | Stale untracked mirror of this public repo (not a git repo). Canonical version is this repo. |
| 5 | `co-evolution-lab/archive/` | Historical snapshots already preserved in source-repo git history. |

## Deviations

See 09-01-SUMMARY.md. High-level: **zero deviations**. The plan executed exactly as written. No Rule 1 bugs, no Rule 2 additions, no Rule 3 unblocks, no Rule 4 escalations. First-pass clean on every acceptance gate.

## Verification Summary

Final phase-level verification (all gates pass):

- **Byte-identity gate:** `diff -q` silent between source and destination `mempalace.yaml`
- **Size gate:** 585 bytes exactly
- **First-line gate:** `wing: co_evolution`
- **SHA256 independent check:** matches plan's recorded hash
- **Source integrity:** `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` still present (copy, not move)
- **README acceptance (8 gates):** file exists, >= 25 lines (actual 36), contains `runners/codex-ps`, `PROJECT.md`, `autoresearch`, `workspace-specific`, `byte-identical`, `deferred`
- **Exclusion-discipline cross-check:** all 5 excluded items named with rationale; decision authority deferred to PROJECT.md for autoresearch

## Unblocks

- **Lab workspace archival:** `C:/Users/alan/Project/co-evolution-lab/` can now be archived at the user's discretion. Every item worth keeping is either folded into this repo (`mempalace.yaml`) or deliberately excluded with recorded rationale (autoresearch, lab PS scripts, stale mirror clone, archive/, auto-research-safe/).
- **Milestone closeout:** With LABF-01 and LABF-02 Complete, all 17 v3 requirements are Complete. The **Unification Absorb** milestone is done.
- **Future integration configs:** `integrations/` is now an established top-level folder. New reference configs drop alongside `mempalace.yaml`.

## Milestone Closeout — Unification Absorb (2026-04-17)

Phase 9 closes the Unification Absorb milestone. Final tally across phases 5-9:

| Phase | Plans | Requirements | Status |
|-------|-------|--------------|--------|
| 5. Codex PS Preservation | 1/1 | CXPS-01, CXPS-02 | Complete |
| 6. Protocol Parity | 3/3 | PRTP-01..05 | Complete |
| 7. Runner Parity | 3/3 | RNPT-01..05 | Complete |
| 8. Evals Absorbed | 1/1 | EVAL-01..03 | Complete |
| 9. Lab Folded | 1/1 | LABF-01, LABF-02 | Complete |

Total v3 requirements: 17/17 Complete. Archivable peer workspaces:

1. `C:/Users/alan/Project/codex-co-evolution/` — covered by CXPS-01 (byte-identical at `runners/codex-ps/`)
2. `C:/Users/alan/Project/co-evolution-lab/` — covered by LABF-01 + LABF-02 (mempalace.yaml folded; exclusions documented)

## Known Stubs

None.

## Next Phase

None — Phase 9 is the final phase of the Unification Absorb milestone. Future work tracked under:

- v2 requirements (`RTUX-01`, `RTUX-02`, `RTUX-03`) — visible Windows terminals, automatic worktree management, auto-loop on REVISE
- Post-milestone work: Bash port of the PS eval harness (deferred, ~2 days estimate), Protocol Evolution Loop (meta-bounce for self-improving prompts, requires eval case library maturity first), workspace-agnostic ports of the lab's PS integration scripts (if ever needed)

## Self-Check: PASSED

- `integrations/mempalace.yaml` — FOUND
- `integrations/README.md` — FOUND (36 lines)
- `.planning/phases/09-lab-folded/09-01-SUMMARY.md` — FOUND
- Commits `9a838d5`, `0a7f708` — all FOUND in git log, all pushed to origin
- Source file at `C:/Users/alan/Project/co-evolution-lab/mempalace.yaml` — still present
- Both requirements (LABF-01, LABF-02) complete
- 1 plan complete (09-01)
- Milestone Unification Absorb — 17/17 v3 requirements Complete
