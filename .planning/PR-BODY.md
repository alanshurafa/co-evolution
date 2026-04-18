## Summary

v1.1 Polish & Ergonomics — addresses the three non-blocking warnings from v1.0 and delivers the three deferred runtime ergonomics requirements (RTUX-01/02/03). All four phases complete; code review approved with 0 blockers.

## Phases shipped

| Phase | Requirement | Commits |
|-------|-------------|---------|
| 1 Code Review Fixes | FIX-WR-01/02/03 | `5734b84` |
| 2 REVISE Auto-Loop | RTUX-03 | `549850c`, `be0af3b`, `e15332a`, `fc08304`, `db1f044` |
| 3 Visible Live Mode | RTUX-01 | `5c09fc1`, `cd84c13`, `7c15e33`, `9bc5597` |
| 4 Worktree Management | RTUX-02 | `cd98af9`, `1294477`, `7ee77ae`, `60067a1`, `9bb3eea` |

## What shipped

**Phase 1 — Code review fixes (from v1.0 review)**
- `LAST_INVOKE_EXIT_CODE=0` reset before codex verify conditional (WR-01)
- `mktemp` temp file cleanup on jq failure in `write_state_phase` + `write_state_field` (WR-02)
- Phase start timestamps passed as explicit function args, removing enclosing-scope global coupling (WR-03)

**Phase 2 — REVISE auto-loop (RTUX-03)**
- `--revise-loop N` CLI flag + `REVISE_LOOP_MAX` env var (default 0 = disabled)
- Loop wraps execute+verify with numbered phase names (`execute-N` / `verify-N` from pass 2)
- Reviewer feedback injected into execute prompt on retry
- `phase_is_writable` gained anchored regex for retry passes
- `tests/revise-loop-simulation.sh` covers 4 scenarios

**Phase 3 — Visible live mode (RTUX-01)**
- `--live` CLI flag + `LIVE_MODE` env var (default off)
- `is_windows_host` platform detector + `maybe_launch_live_window` helper
- Wired into 4 phase sites: compose, each bounce pass, execute, verify
- Tail-window approach via detached `wt.exe` / `cmd.exe start`
- Additive / must-not-block invariant: launcher failure logs warning, inline execution continues
- `tests/live-mode-simulation.sh` covers no-op / non-Windows / stubbed-Windows fallback

**Phase 4 — Worktree management (RTUX-02)**
- `--branch auto|NAME` + `--worktree auto|PATH` CLI flags (mutually exclusive)
- `DEV_REVIEW_BRANCH` / `DEV_REVIEW_WORKTREE` env var fallbacks
- New helpers in `lib/co-evolution.sh`: `is_git_repo`, `derive_auto_branch_name`, `derive_auto_worktree_path`, `maybe_setup_branch`, `maybe_setup_worktree`
- Branch/worktree creation happens post-plan, pre-execute; plan artifacts stay on parent branch
- State.json records `.branch_created` + `.worktree_path` for audit trail
- Final summary banner echoes created location for easy review
- No-ops gracefully when flags empty or `WORKDIR` is not a git repo
- `tests/worktree-management-simulation.sh` covers 5 scenarios (branch-auto, worktree-auto, non-git fallback, empty-flag fallback, mutex error)

## Code review result

**APPROVED with 0 blockers, 2 warnings, 4 info notes.** Same posture as v1.0 (which shipped with 3 warnings).

Both warnings are real but narrow-trigger — captured for v1.2+ follow-up:

- **WR-04** — `INITIAL_GIT_DIRTY` captured from parent repo before `WORKDIR` is reassigned to worktree; triggers silent verify skip when parent is dirty AND worktree mode is active. Real interaction bug, narrow trigger.
- **WR-05** — `git worktree add` and `git checkout -b` lack `--` argv terminator. Hardening gap, not security-exploitable (git rejects invalid refs harmlessly).

Full review: `.planning/REVIEW.md`.

## Deferred to v1.2+

- **WR-04 / WR-05** — the two non-blocking warnings above
- **Bash port of PS eval harness** (~2 days) — removes `pwsh` dependency from eval runs
- **Protocol Evolution Loop** — automated bounce-to-improve-the-bouncer using evals as fitness function. Design exploration complete; artifacts under `.planning/notes/`, `.planning/seeds/`, `.planning/research/`. Ready for `/gsd-new-milestone v1.2` kickoff.

## Verification

- Per-phase acceptance criteria all passed
- Simulation tests pass: revise-loop (4 scenarios), live-mode (3 scenarios), worktree-management (5 scenarios)
- Syntax check clean on runner + lib + all tests
- Byte-parity guards verified: every new flag is default-off with zero behavior change when unset
- Flag composition matrix verified: `--live` × `--branch`/`--worktree`, `--revise-loop` × `--branch`/`--worktree`, `--plan-only` × `--branch` all compose correctly

## Test plan

- [x] All four phases' simulation tests run to completion
- [x] `--help` text shows all new flags (`--revise-loop`, `--live`, `--branch`, `--worktree`)
- [x] `bash -n` clean on `dev-review/codex/dev-review.sh` and `lib/co-evolution.sh`
- [x] No-op paths (empty flags, non-git-repo) verified to match v1.0 baseline behavior

## Breaking changes

None. All four phases are additive — every new flag defaults off, preserving v1.0 behavior for unmodified callers.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
