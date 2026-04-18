# Plan 01-01 Summary: Post-v1.1 Fixes

**Completed:** 2026-04-17
**Commits:** `3a06af8`, `68b9d76`, `f265135` (plus `26df0c9` plan)

## What shipped

### Task 01-01.1 — WR-05 hardening (`3a06af8`)
- `maybe_setup_branch` in `lib/co-evolution.sh` now rejects branch names starting with `-` with a clear `WARNING:` message before calling git
- `maybe_setup_worktree` now uses `git worktree add -- "$path"` (standard `--` argv terminator)
- Both fixes follow the existing `maybe_*` helper contract (log to stderr, return empty stdout, exit 0 — never block main flow)

### Task 01-01.2 — WR-04 relocation (`68b9d76`)
- `INITIAL_GIT_STATUS` / `INITIAL_GIT_DIRTY` capture block in `dev-review/codex/dev-review.sh` moved from line ~1106 (before the SESSION banner) to line ~1202 (after the branch/worktree setup block)
- Comment added explaining the WHY (worktree mode's reassigned `WORKDIR` is what execute/verify will see; capture must reflect that)
- Grep verifies: capture at line 1202 > setup at line 1180 ✓

### Task 01-01.3 — Scenario F regression gate (`f265135`)
- Appended Scenario F to `tests/worktree-management-simulation.sh`
- Static-order check: greps runner source, extracts line numbers for `BRANCH_SPEC` setup + `INITIAL_GIT_STATUS` capture, asserts capture > setup
- Fails with a clear WR-04 regression message if the order flips in a future refactor

## Verification

All six gates pass:
1. `bash -n dev-review/codex/dev-review.sh` — clean
2. `bash -n lib/co-evolution.sh` — clean
3. `bash tests/worktree-management-simulation.sh` — all 6 scenarios pass (A-F), final line `ALL SCENARIOS PASSED`
4. Grep confirms `git worktree add --` appears in `lib/co-evolution.sh`
5. Grep confirms dash-prefix guard exists in `maybe_setup_branch`
6. Grep confirms INITIAL_GIT_STATUS capture line > BRANCH_SPEC setup line in runner

## Deviations from plan

None.

## Non-goals preserved

- Banner `Workdir:` line still shows original `WORKDIR` (cosmetic, out of scope)
- No dynamic e2e test of the full verify path (static regression gate sufficient)
- `git checkout -b` retained (not switched to `git switch -c`)
