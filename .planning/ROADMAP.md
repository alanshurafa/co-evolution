# Roadmap: Co-Evolution

## Overview

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. The roadmap tracks milestone cycles; completed milestones are archived to `.planning/milestones/`.

## Completed Milestones

- [x] **v1.0 Unification Absorb** (shipped 2026-04-17) — Codex runtime foundation + absorbed private reference impl + eval harness + runner parity. 9 phases, 27 requirements closed. See [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) · [`milestones/v1.0-SUMMARY.md`](milestones/v1.0-SUMMARY.md) · [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md)

## Active Milestone: v1.1 Polish & Ergonomics (2026-04-17)

Address the non-blocking code review warnings from v1.0, then deliver the three deferred runtime ergonomics requirements (RTUX-01/02/03).

- [x] **Phase 1: Code Review Fixes** - Address WR-01/02/03 from v1.0 code review (stale exit code, temp-file leak, global coupling) — shipped 5734b84
- [x] **Phase 2: REVISE Auto-Loop** - Codex runtime auto-loops on REVISE verdicts until APPROVED or max-iterations (RTUX-03) — shipped 2026-04-17
- [x] **Phase 3: Visible Live Mode** - Launch visible Windows terminals for live pass-by-pass observation (RTUX-01) — shipped 2026-04-17 (5c09fc1, cd84c13, 7c15e33)
- [x] **Phase 4: Worktree Management** - Codex runtime creates/manages dedicated branches or worktrees (RTUX-02) — shipped 2026-04-17 (cd98af9, 1294477, 7ee77ae)

## Phase Details

### Phase 1: Code Review Fixes
**Goal**: Address the three non-blocking warnings from v1.0 code review (WR-01/02/03) so the codebase is free of latent issues before adding new features.
**Depends on**: v1.0 shipped
**Requirements**: [FIX-WR-01, FIX-WR-02, FIX-WR-03]
**Success Criteria** (what must be TRUE):
  1. `LAST_INVOKE_EXIT_CODE` is reset to 0 before the codex verify conditional at `dev-review/codex/dev-review.sh:768-776`
  2. `write_state_phase` and `write_state_field` clean up `mktemp` temp files on jq failure (no leftover files in `$TMPDIR`)
  3. Phase-start timestamps are passed as explicit function args, not relied on via enclosing-scope globals with `${var:-fallback}` pattern
**Plans**: 1 plan

### Phase 2: REVISE Auto-Loop
**Goal**: When the verify phase returns a REVISE verdict, the runner automatically loops back through execute+verify up to a configurable max-iterations, addressing the verdict's issues each pass.
**Depends on**: Phase 1
**Requirements**: [RTUX-03]
**Success Criteria** (what must be TRUE):
  1. `--revise-loop N` CLI flag (and `REVISE_LOOP_MAX` env var) set the max auto-retry count (default 0 = disabled for backwards compatibility)
  2. On REVISE verdict, the runner rewrites the execution prompt to include the reviewer's feedback (JSON issues array), re-executes, re-verifies
  3. Loop terminates on APPROVED, on max iterations reached, or on fatal error
  4. Each loop pass is recorded in `state.json` as a new phase entry (`execute-2`, `verify-2`, etc.) with its own start/complete timestamps
**Plans**: 1 plan
  - [ ] 02-01-PLAN.md — Add `--revise-loop N` flag, retry loop around execute+verify with numbered state.json phases, reviewer-feedback prompt injection, and simulation smoke test

### Phase 3: Visible Live Mode
**Goal**: Give the runner an option to launch a visible Windows Terminal window for each phase so the user can observe the bouncer/executor in real time (pass-by-pass).
**Depends on**: Phase 1
**Requirements**: [RTUX-01]
**Success Criteria** (what must be TRUE):
  1. `--live` CLI flag opens a new visible Windows terminal window (`wt.exe` or `cmd.exe`) per phase invocation instead of running inline
  2. Windows-only feature; on non-Windows environments, `--live` is accepted but logs a warning and falls back to inline execution
  3. Each live window tails the phase's stderr/stdout file in real time
  4. Main runner still waits for the phase to complete and records `state.json` normally
**Plans**: 1 plan

### Phase 4: Worktree Management
**Goal**: The runner can automatically create a git branch or worktree for the task before execute, so each dev-review run is isolated and reviewable.
**Depends on**: Phase 1
**Requirements**: [RTUX-02]
**Success Criteria** (what must be TRUE):
  1. `--branch auto|NAME` creates a feature branch off the current HEAD before execute; `auto` derives a name from the task description + timestamp
  2. `--worktree auto|PATH` creates a git worktree instead of a branch (useful for parallel runs)
  3. After execute completes, runner reports the created branch/worktree location and leaves it intact for review/merge
  4. Both flags are no-ops when passed empty or when workdir is not a git repo (log warning, continue with no branching)
**Plans**: 1 plan

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 (2, 3, 4 are parallelizable after 1 lands, but for autonomous sequencing we run serially)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Code Review Fixes | 1/1 | Complete | 2026-04-17 |
| 2. REVISE Auto-Loop | 1/1 | Complete | 2026-04-17 |
| 3. Visible Live Mode | 1/1 | Complete | 2026-04-17 |
| 4. Worktree Management | 1/1 | Complete | 2026-04-17 |

## Deferred (candidates for v1.2+)

- **Bash port of PS eval harness** (~2 days) — remove pwsh dependency from eval runs
- **Protocol Evolution Loop** — automated bounce-to-improve-the-bouncer using evals as fitness function (needs design discussion before planning)
