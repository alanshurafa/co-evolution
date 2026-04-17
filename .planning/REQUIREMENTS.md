# Requirements: Co-Evolution

**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps

> Completed requirements are archived per milestone under `.planning/milestones/`.
> This file tracks only requirements for the **active / next milestone**.

## Completed Milestones

- **v1.0 Unification Absorb** — 27/27 requirements Complete. See [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md).

## Active Milestone: v1.1 Polish & Ergonomics

### Code Review Fixes

- [ ] **FIX-WR-01**: Reset `LAST_INVOKE_EXIT_CODE=0` before the codex verify conditional at `dev-review/codex/dev-review.sh:768-776` (latent; not firing today because execute always leaves 0 on the path to verify, but covers future callers that might not)
- [ ] **FIX-WR-02**: `write_state_phase` and `write_state_field` in `lib/co-evolution.sh` must clean up `mktemp` temp files when `jq` fails (no stale files left in `$TMPDIR`)
- [ ] **FIX-WR-03**: Pass phase-start timestamps as explicit function arguments instead of relying on enclosing-scope globals with `${var:-fallback}` fallback (removes hidden coupling in `abort_on_timeout` / phase runners)

### Runtime Ergonomics (from deferred v2 bucket)

- [ ] **RTUX-01**: Codex runtime can launch visible Windows terminals (`wt.exe` / `cmd.exe`) for live pass-by-pass observation via `--live` CLI flag. Windows-only feature; on non-Windows, `--live` logs a warning and falls back to inline execution.
- [ ] **RTUX-02**: Codex runtime can create and manage dedicated branches or worktrees automatically via `--branch auto|NAME` and `--worktree auto|PATH` flags. No-ops when workdir is not a git repo.
- [x] **RTUX-03**: Codex runtime can loop automatically on REVISE verdicts until approval or max-iterations via `--revise-loop N` flag. Each loop pass recorded in `state.json` as a new phase entry. (Complete 2026-04-17 — Phase 2)

## Deferred (candidates for v1.2+)

- **BASH-EVAL-01**: Bash port of the PowerShell eval harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) — removes `pwsh` dependency from eval runs (~2 days estimated)
- **META-01**: Protocol Evolution Loop — automated bounce-to-improve-the-bouncer using evals as fitness function. Reads eval failures, proposes protocol/prompt/adapter deltas, bounces them, scores against the same cases, keeps improvements. Needs design discussion before planning.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-WR-01 | Phase 1 | Planned |
| FIX-WR-02 | Phase 1 | Planned |
| FIX-WR-03 | Phase 1 | Planned |
| RTUX-03 | Phase 2 | Complete |
| RTUX-01 | Phase 3 | Planned |
| RTUX-02 | Phase 4 | Planned |

**Coverage:**
- v1.1 requirements: 6 total (3 FIX-WR + 3 RTUX)
- Mapped to phases: 6
- Unmapped: 0 ✓

---
*Active requirements reset at each milestone boundary. Historical requirements live in `milestones/vN.N-REQUIREMENTS.md`.*
