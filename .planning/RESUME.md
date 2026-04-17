# Resume Handoff — v1.1 Polish & Ergonomics

**Paused:** 2026-04-17 (mid-milestone, between Phase 3 and Phase 4)
**Project:** co-evolution (public repo at https://github.com/alanshurafa/co-evolution)
**Milestone:** v1.1 Polish & Ergonomics — 3/4 phases done

---

## Where to pick up

**Worktree:** `C:/Users/alan/Project/co-evolution-v11/` (branch: `feat/v1.1-polish`)
**Draft PR:** https://github.com/alanshurafa/co-evolution/pull/2

**Next action:** Execute **Phase 4 — Worktree Management (RTUX-02)**.

On the desktop, just say:
> "Continue v1.1 milestone — execute Phase 4 (Worktree Management, RTUX-02)."

Claude can read this RESUME.md and the rest of `.planning/` to rebuild full context.

---

## Milestone status

| Phase | Requirement | Status | Commits |
|-------|-------------|--------|---------|
| 1 Code Review Fixes | FIX-WR-01/02/03 | ✅ Complete | `5734b84` |
| 2 REVISE Auto-Loop | RTUX-03 | ✅ Complete | `549850c`, `be0af3b`, `e15332a`, `fc08304`, `db1f044` |
| 3 Visible Live Mode | RTUX-01 | ✅ Complete | `5c09fc1`, `cd84c13`, `7c15e33`, `9bc5597` |
| **4 Worktree Management** | **RTUX-02** | **⏸ Planned, not started** | — |

## What's done

### Phase 1 — Code Review Fixes (commit `5734b84`, inline execution)
- FIX-WR-01: `LAST_INVOKE_EXIT_CODE=0` reset before codex verify conditional
- FIX-WR-02: `mktemp` temp file cleanup on jq failure in `write_state_phase` + `write_state_field`
- FIX-WR-03: phase start timestamps passed as explicit function args (removed enclosing-scope global coupling)

### Phase 2 — REVISE Auto-Loop (RTUX-03)
- `--revise-loop N` CLI flag + `REVISE_LOOP_MAX` env var (default 0 = disabled)
- Loop wraps execute+verify; numbered phase names `execute-N` / `verify-N` from pass 2
- Reviewer feedback injected into execute prompt on retry (issues JSON rendered via jq -r)
- `phase_is_writable` gained anchored regex `^execute-[0-9]+$` for retry passes
- Self-contained simulation test `tests/revise-loop-simulation.sh` with 4 scenarios (retry-and-converge, v1.0 parity, cap-at-max, prompt byte-identity)

### Phase 3 — Visible Live Mode (RTUX-01)
- `--live` CLI flag + `LIVE_MODE` env var (default off)
- `is_windows_host` platform detector + `maybe_launch_live_window` helper in `lib/co-evolution.sh`
- Wired into 4 phase sites: compose, each bounce pass, execute, verify
- Tail-window approach: detached `wt.exe` / `cmd.exe start` tailing phase stderr file
- Additive / must-not-block invariant: launcher failure logs warning, inline execution continues
- Self-contained simulation test `tests/live-mode-simulation.sh` (no-op / non-Windows fallback / stubbed Windows)

## What's next — Phase 4: Worktree Management (RTUX-02)

**Goal:** The runner can auto-create a git branch or worktree for the task before execute, so each dev-review run is isolated and reviewable.

**Success criteria (from ROADMAP.md):**
1. `--branch auto|NAME` creates a feature branch off the current HEAD before execute; `auto` derives a name from the task description + timestamp
2. `--worktree auto|PATH` creates a git worktree instead of a branch (useful for parallel runs)
3. After execute completes, runner reports the created branch/worktree location and leaves it intact for review/merge
4. Both flags are no-ops when passed empty or when workdir is not a git repo (log warning, continue with no branching)

**Expected shape:** 1 plan, ~3 tasks (CLI flag + branch/worktree helpers + smoke test). Should be similar scope to Phases 2 and 3.

**Suggested prompt to Claude to resume:**
```
Continue v1.1 milestone. Phase 4 is Worktree Management (RTUX-02).
Plan and execute per the same autonomous flow we used for Phases 2 and 3:
write 04-CONTEXT.md, spawn gsd-planner for 04-01-PLAN.md, then
gsd-executor. After Phase 4 lands, run the ship sequence
(/gsd-ship --review → merge → /gsd-complete-milestone → tag v1.1).
```

## After Phase 4 — Ship sequence

Same pattern as v1.0:
1. **Code review gate:** Spawn `gsd-code-reviewer` on the branch diff vs master
2. **Mark PR #2 ready** (gh pr ready 2) if review is clean
3. **Merge:** `gh pr merge 2 --merge --delete-branch` (rebase failed on v1.0 due to worktree; use merge commit)
4. **Complete milestone:** `/gsd-complete-milestone v1.1` to archive the milestone artifacts
5. **Tag + push:** `git tag -a v1.1 -m "..." && git push --tags`
6. **Collapse planning files** (if needed — ROADMAP + REQUIREMENTS trim like we did after v1.0)

## Reference points

- **v1.0 milestone archive:** `.planning/milestones/v1.0-*.md`
- **v1.0 code review:** `.planning/REVIEW.md` (0 blockers, 3 warnings all now addressed in Phase 1)
- **v1.0 PR:** https://github.com/alanshurafa/co-evolution/pull/1 (merged at `1f9b471`)
- **v1.1 PR:** https://github.com/alanshurafa/co-evolution/pull/2 (draft)
- **Upstream contract:** `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (read if you forget why any v1.0 decision was made)
- **Phase 1-3 SUMMARYs:** `.planning/phases/0[1-3]-*/*-SUMMARY.md`

## Environment notes (for fresh session)

- **Worktrees active:**
  - `co-evolution/` — archive branch (parked, leave alone)
  - `co-evolution-clean/` — master tip (synced with origin)
  - `co-evolution-v11/` — feat/v1.1-polish (active — this is where Phase 4 lands)
- **Shell:** Windows 11 / MINGW64 / Git Bash. Use forward slashes in paths.
- **cwd quirk:** Shell cwd resets to `C:/Users/alan/Project/co-evolution-lab/` between Bash calls; every Bash invocation must `cd C:/Users/alan/Project/co-evolution-v11` first.
- **`jq`, `timeout`, `sha256sum`** all available in Git Bash.
- **Claude CLI** auth may be stale on the desktop — run `claude /login` if needed before any live invocations.

## Deferred to v1.2+

- **BASH-EVAL-01:** Bash port of PowerShell eval harness (~2 days)
- **META-01:** Protocol Evolution Loop (needs design discussion before planning)

---

*Generated at session boundary. Delete this file after Phase 4 ships (or leave as audit trail).*
