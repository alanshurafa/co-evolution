---
phase: 08-evals-absorbed
plans: [08-01]
subsystem: evals-portable-assets
tags: [eval-asset-elevation, cross-runner, pwsh-optional, cxps-02-preserved]
requires: [phase-05, phase-07]
provides: [cross-runner-eval-reach, bash-port-unblock, pwsh-optional-documentation]
affects:
  - evals/
  - schemas/
  - .gitignore
tech-stack:
  added: []
  patterns: [byte-identical-copy-with-diff-q-gate, cxps-02-discipline-preserved, portable-vs-runner-specific-split]
metrics:
  duration: 15min
  tasks_completed: 4
  commits: 4
  completed: 2026-04-17
requirements: [EVAL-01, EVAL-02, EVAL-03]
---

# Phase 8: Evals Absorbed Summary

One-liner: Elevated 14 portable eval assets (10 cases + 2 fixtures + VERIFICATION-PLAN.md + review-verdict.json) from `runners/codex-ps/evals/` and `runners/codex-ps/schemas/` to top-level `evals/` and `schemas/` via byte-identical `cp`, added `evals/README.md` documenting the pwsh-optional dependency split, and extended `.gitignore` for a future Bash eval harness — all while leaving `runners/codex-ps/` untouched (CXPS-02 preserved). Any runner can now reach the portable slice from the repo root without descending into the PS reference tree.

## What Landed Per Plan

### Plan 08-01: Elevate Portable Eval Assets (EVAL-01, EVAL-02, EVAL-03)

- 10 case YAMLs at `evals/cases/` (defaults.yaml + 9 numbered cases) — byte-identical to source
- 2 scorer fixtures at `evals/fixtures/` (mock-report.md with UTF-8 BOM preserved, mock-scores.json) — byte-identical
- `evals/VERIFICATION-PLAN.md` — byte-identical, 210 lines
- `schemas/review-verdict.json` at repo root (not under evals/) — byte-identical, still parses as valid JSON draft-07
- `evals/README.md` — new 103-line entry-point document; contains literal phrase `pwsh is optional`, names the Bash port as `deferred`, lists `agent-bouncer` + `dev-review` as pwsh-free entrypoints
- `.gitignore` extended with `evals/reports/` and `evals/fixtures/tmp/` in a named block below the `runners/codex-ps/` block
- 14-pair byte-identity sweep: all clean
- `git status --porcelain runners/codex-ps/` empty at every checkpoint (CXPS-02 binding check)

Commits: `6f337da` (cases + fixtures), `011c443` (VERIFICATION-PLAN + schema), `5558d07` (README), `c6679ac` (gitignore).

## Commit Chain

```
c6679ac  chore(08-01): extend gitignore for top-level evals runtime artifacts
5558d07  docs(08-01): add evals/README.md documenting pwsh-optional split
011c443  feat(08-01): elevate VERIFICATION-PLAN + review-verdict schema to top-level
6f337da  feat(08-01): elevate eval cases + fixtures to top-level evals/
```

All commits pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| EVAL-01 | 08-01 | Complete |
| EVAL-02 | 08-01 | Complete |
| EVAL-03 | 08-01 | Complete |

## Wave Order Executed

Single-plan phase (Wave 1 only): 08-01 T1 → T2 → T3 → T4, strictly sequential.

## Files Modified (Phase-Level)

- `evals/cases/` — 10 new files (defaults.yaml + 9 cases), all byte-identical copies
- `evals/fixtures/` — 2 new files (mock-report.md with BOM, mock-scores.json), byte-identical copies
- `evals/VERIFICATION-PLAN.md` — new file, byte-identical copy
- `evals/README.md` — new file (NOT a copy — the only new original content in Phase 8)
- `schemas/review-verdict.json` — new file, byte-identical copy, JSON-parse verified
- `.gitignore` — 4-line block added (`# Top-level evals/ runtime artifacts ...` + `evals/reports/` + `evals/fixtures/tmp/`)

Zero files under `runners/codex-ps/` touched.

## Deviations

See 08-01-SUMMARY.md for full detail. High-level: one Rule 1 bug during Task 3 — removed backticks around `pwsh` in a single sentence of `evals/README.md` so the literal phrase `pwsh is optional` is grep-matchable per the EVAL-03 acceptance gate. Fixed pre-commit; rest of the README keeps inline-code formatting. All other work landed exactly as planned.

## Verification Summary

Final phase-level verification (all gates pass):

- **14-pair byte-identity sweep:** all `diff -q` clean
- **JSON parse check:** `schemas/review-verdict.json` parses as valid JSON
- **README acceptance gates:** file exists, 103 lines, contains `pwsh is optional`, `Bash port`, `deferred`, `agent-bouncer`, `dev-review`, `runners/codex-ps`, `VERIFICATION-PLAN.md`, `review-verdict.json`, `defaults.yaml`; no UTF-8 BOM; no CRLF
- **CXPS-02 binding check:** `git status --porcelain runners/codex-ps/` empty after each task and at phase end
- **.gitignore entries:** `^evals/reports/$` and `^evals/fixtures/tmp/$` both present
- **Idempotency:** re-running the sweep + CXPS audit yields identical clean output

Final audit line printed: `PHASE-08 COMPLETE: 14 files byte-identical, README present, runners/codex-ps/ untouched, gitignore extended`.

## Unblocks

- **Cross-runner eval consumption:** any runner (current Bash `dev-review.sh`, PS reference, future Bash harness) can now reach `evals/cases/`, `evals/fixtures/`, `evals/VERIFICATION-PLAN.md`, and `schemas/review-verdict.json` from the repo root — no descent into `runners/codex-ps/` required.
- **pwsh-optional posture:** documented. A user who never installs `pwsh` can still use `agent-bouncer/agent-bouncer.sh`, `dev-review/codex/dev-review.sh`, and `lib/co-evolution.sh` end-to-end. `pwsh` is now explicitly labeled as a runtime dependency of the eval harness only.
- **Bash-port feasibility:** all reusable case definitions, fixtures, schema, and five-tier verification plan are reachable from the repo root — a future Bash eval harness port has no blockers on asset location. UPSTREAM-MESSAGE.md § "Parity requirements" remains the feature inventory.

## Known Stubs

None.

## Next Phase

Phase 9 (Lab Folded) — fold `co-evolution-lab/integrations/` + `mempalace.yaml` into the unified repo; exclude Karpathy's `autoresearch` clone (unrelated ML training) with rationale in `PROJECT.md`. Completes the Unification Absorb milestone.

## Self-Check: PASSED

- `evals/cases/` — 10 files FOUND
- `evals/fixtures/` — 2 files FOUND
- `evals/VERIFICATION-PLAN.md` — FOUND
- `evals/README.md` — FOUND (contains `pwsh is optional`, `Bash port`, `deferred`, `agent-bouncer`, `dev-review`)
- `schemas/review-verdict.json` — FOUND (JSON parses)
- `.gitignore` — evals/reports/ + evals/fixtures/tmp/ FOUND at lines 10-11
- Commits `6f337da`, `011c443`, `5558d07`, `c6679ac` — all FOUND in git log, all pushed
- `git status --porcelain runners/codex-ps/` — empty (CXPS-02 binding check)
- All 3 requirements (EVAL-01, EVAL-02, EVAL-03) complete
- 1 plan complete (08-01)
