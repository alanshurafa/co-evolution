---
phase: 04-worktree-management
plans: [04-01]
subsystem: dev-review-runtime
tags: [worktree, branch, git, cli, bash, rtux-02]
requires: [phase-01]
provides: [branch-worktree-helpers, --branch-flag, --worktree-flag, mutual-exclusion-guard, worktree-management-simulation]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
  - tests/
tech-stack:
  added: []
  patterns: [stdout-clean-helpers-with-stderr-logs, plan-stays-on-parent-branch-pre-execute-setup, mutex-before-side-effects, basename-comparison-for-cross-pathstyle-tests]
metrics:
  duration: 25min
  tasks_completed: 3
  commits: 3
  completed: 2026-04-17
requirements: [RTUX-02]
---

# Phase 4: Worktree Management Summary

One-liner: Added `--branch auto|NAME` and `--worktree auto|PATH` CLI flags (plus `DEV_REVIEW_BRANCH` / `DEV_REVIEW_WORKTREE` env vars) to the Codex dev-review runtime so each invocation can be isolated on its own git branch or worktree, leaving a reviewable audit trail without disturbing the parent branch. Setup runs AFTER plan+bounce land on the parent branch (plan artifacts stay reviewable pre-merge) and BEFORE execute. Mutually exclusive — both flags set `die`s before any RUN_DIR creation. Empty values and non-git workdirs no-op with a single WARNING line. Default empty preserves Phase 3 byte-parity. State.json gains `.branch_created` / `.worktree_path` fields when active; both DEV-REVIEW SESSION and DEV-REVIEW COMPLETE banners echo the values for reviewer visibility. A self-contained bash smoke test (5 scenarios — branch-auto, worktree-auto, non-git fallback, empty-flag fallback, mutex error — ~3s, no network, no real CLIs) locks in the contract.

## What Landed Per Plan

### Plan 04-01: Worktree Management (RTUX-02)

- **Task 1 — Helpers in lib/co-evolution.sh.** `is_git_repo` (portable `git rev-parse --git-dir` check), `derive_auto_branch_name` (5-word slug pipeline → `dev-review/auto-<TIMESTAMP>-<slug>`), `derive_auto_worktree_path` (sibling-dir composer → `<dirname>/<basename>-dr-<TIMESTAMP>`), `maybe_setup_branch` (no-op + WARNING when spec empty or workdir non-git, else `git checkout -b` and prints name on stdout), and `maybe_setup_worktree` (analogous, runs `git worktree add` and prints absolute path). `DEV_REVIEW_BRANCH` / `DEV_REVIEW_WORKTREE` env-var defaults added to the module top alongside `LIVE_MODE`. All log calls inside the setup helpers route to stderr (`>&2`) so callers can capture stdout cleanly without WARNING/INFO leakage.
- **Task 2 — Wire dev-review.sh.** Globals `BRANCH_SPEC="${DEV_REVIEW_BRANCH:-}"` / `WORKTREE_SPEC="${DEV_REVIEW_WORKTREE:-}"` / `BRANCH_CREATED` / `WORKTREE_PATH`, two new parser cases (`--branch` / `--worktree`), two usage-help lines, mutual-exclusion check immediately after parser loop closes (BEFORE `WORKDIR` normalization, BEFORE `mkdir -p "$RUN_DIR"`), two new banner lines in DEV-REVIEW SESSION block, dispatch block AFTER PLAN_ONLY's exit branch and BEFORE `_run_revise_loop` (PLAN_ONLY exits earlier so `--branch auto --plan-only` is a silent no-op on the branching side per CONTEXT.md), state.json field writes via `write_state_field` on success, and two new banner lines in DEV-REVIEW COMPLETE block.
- **Task 3 — Smoke test.** `tests/worktree-management-simulation.sh` with 5 scenarios using ephemeral git repos: (A) `--branch auto` creates derived-slug branch and checks out, asserts exact-string slug + HEAD + log line; (B) `--worktree auto` creates sibling worktree at `<parent>/<base>-dr-<ts>`, asserts existence + inside-work-tree + worktree-list registration via basename match (path-style differs between MSYS and Windows on Git Bash); (C) non-git-repo fallback — both helpers log WARNING + return empty; (D) empty flag value fallback — both helpers log WARNING + return empty + branch count unchanged; (E) mutual exclusion at runner level — exits 1 with "mutually exclusive" message AND no RUN_DIR created (uses distinctive `mutex-test-<RANDOM>` timestamp to prove no leak). Runs in ~3s.

Commits: `cd98af9` (T1), `1294477` (T2), `7ee77ae` (T3). All on `feat/v1.1-polish`.

## Commit Chain

```
7ee77ae  test(04-01): add worktree-management simulation covering 5 scenarios
1294477  feat(04-01): wire --branch + --worktree flags into dev-review runner
cd98af9  feat(04-01): add is_git_repo + branch/worktree setup helpers
```

All three on `feat/v1.1-polish`. Final phase-completion metadata commit lands separately.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| RTUX-02 | 04-01 | Complete |

## Wave Order Executed

Single-plan phase (Wave 1 only): 04-01 T1 → T2 → T3, strictly sequential per the plan's `depends_on` chain.

## Files Modified (Phase-Level)

- `lib/co-evolution.sh` — extended: env-var defaults + 5 helpers (`is_git_repo`, `derive_auto_branch_name`, `derive_auto_worktree_path`, `maybe_setup_branch`, `maybe_setup_worktree`) (+130 / 0)
- `dev-review/codex/dev-review.sh` — extended: 4 new globals, 2 parser cases, 2 usage lines, mutex guard, 4 banner lines (SESSION + COMPLETE × 2), pre-execute dispatch block (+54 / 0)
- `tests/worktree-management-simulation.sh` — new 140-line self-contained smoke test (5 scenarios, ~3s)

## Roadmap Success Criteria — All 4 Verified

| SC # | ROADMAP criterion | Verified by |
|------|-------------------|-------------|
| SC-1 | `--branch auto\|NAME` creates a feature branch off HEAD; `auto` derives from task + timestamp | Scenario A asserts `dev-review/auto-20260101-000000-fix-the-broken-auth-flow` exact-string + HEAD switched + log line; explicit-name path proven by Task 1 helper code (single `if/else` on `branch_spec == "auto"`). |
| SC-2 | `--worktree auto\|PATH` creates a git worktree (parallel runs) | Scenario B asserts dir created + inside-work-tree + listed by `git worktree list` (basename match for cross-pathstyle); explicit-path proven by Task 1 helper code. |
| SC-3 | Runner reports created location, leaves it intact for review/merge | DEV-REVIEW COMPLETE banner now has `Branch:` and `Worktree:` lines (verified in Task 2 grep + Task 3 manual verification block); no cleanup code added per CONTEXT.md. |
| SC-4 | Both flags no-op for empty values or non-git workdir (log warning, continue) | Scenarios C (non-git) + D (empty) both pass; verification step 5 byte-parity guard prints `BYTE_PARITY_OK`. |

## Deviations

Two Rule 1 (auto-fix bug) deviations resolved before commit; both are local implementation refinements that preserved every plan acceptance criterion. See `04-01-SUMMARY.md` "Deviations from Plan" for full detail.

1. **`log()` stdout pollution** — lib's `log()` tees through fd 1 so stdout-capturing callers got WARNING text mixed with the helper's intended return value. Fix: route every `log()` call inside `maybe_setup_*` to stderr via `log "..." >&2`. LOG_FILE writes still succeed via `tee -a`. Folded into Task 1 commit.
2. **Scenario B path-style mismatch** — `git worktree list` outputs Windows-style paths on Git Bash while the helper returns MSYS-style paths for the same dir. Fix: compare by basename instead of full path. Folded into Task 3 commit.

The plan file itself is unchanged — both fixes are within the planner's scope ("auto-fix bugs"). Documented as patterns-established for future work.

## Verification Summary

All 6 phase-level verification gates from the plan pass:

1. **Syntax:** `bash -n` clean on `lib/co-evolution.sh`, `dev-review/codex/dev-review.sh`, `tests/worktree-management-simulation.sh`.
2. **CLI surface:** `bash dev-review.sh --help` includes both `--branch` and `--worktree` lines (verified with anchored grep `^\s+--branch ` to avoid matching the description text "with --worktree" embedded in the `--branch` line).
3. **Mutual exclusion fires cleanly:** `--branch auto --worktree auto` exits 1 with "mutually exclusive" message; `pre_count == post_count` for `runs/` directory listing — no RUN_DIR side-effect.
4. **Smoke test:** `bash tests/worktree-management-simulation.sh` exits 0 with final stdout line `ALL SCENARIOS PASSED` (~3s).
5. **Byte-parity guard:** With both env vars unset and empty flag values, `maybe_setup_branch "$TD" "" "task"` and `maybe_setup_worktree "$TD" "" "task"` both return empty stdout — prints `BYTE_PARITY_OK`.
6. **State.json wiring:** `write_state_field "$STATE_JSON" ".branch_created"` and `write_state_field "$STATE_JSON" ".worktree_path"` both present in runner.

## Invariant Compliance

- **Must-not-break (byte-parity)** — Default both flags absent: only new log output is the two `Branch: <empty>` / `Worktree: <empty>` banner lines per banner block, analogous to Phase 3's single `Live mode: false` addition. No state.json mutations, no git commands, no behavior change. Byte-parity guard (verification step 5) locks this in.
- **Must-not-block (run continues)** — Helpers always return 0 even on git failure; main run continues on the original branch with empty `BRANCH_CREATED` / `WORKTREE_PATH`. Scenarios C + D prove the no-op branches; helper code's `git ... 2>&1` capture + WARNING log proves the failure branches.
- **Mutex-before-side-effect** — Verification step 3 + Scenario E prove `die "--branch and --worktree are mutually exclusive"` fires BEFORE `mkdir -p "$RUN_DIR"`. No leak.

## Threat Model Compliance

Every `mitigate` disposition in the plan's threat register verified:

| Threat | Mitigation | Check |
|--------|-----------|-------|
| T-04-01 (branch-name injection) | argv-as-single-item, slug strips `[^a-z0-9-]`, git enforces ref-name rules | Code inspection + Scenario A exact-string slug |
| T-04-02 (worktree-path injection) | argv-as-single-item, `auto` paths from existing dir, no `eval` / `bash -c` | Code inspection + Scenario B path-creation success |
| T-04-04 (git self-DoS) | Captures stderr via `err_output=$(... 2>&1)`, logs WARNING, returns 0 | Helper return-code semantics + verification step 5 |
| T-04-07 (privilege escalation) | Only `git` invoked; `cd "$path" && pwd` bounded to current shell | Code inspection of `maybe_setup_*` bodies |

Accepted threats per plan (documented, not mitigated): T-04-03 (hostile name targeting sensitive location — solo-dev tool), T-04-05 (branch/worktree accumulation — cleanup deferred per CONTEXT.md), T-04-06 (task-description leak via slug — feature, not risk).

## Known Stubs

None.

## Next Phase

**v1.1 milestone is feature-complete.** Phase 4 closes the third and final RTUX requirement (RTUX-02). Roadmap shows no further phases in v1.1; the next move is either (a) ship the milestone via final review + PR, or (b) open a v1.2 cycle for the deferred items (Bash port of PS eval harness, Protocol Evolution Loop, workspace-agnostic ports of lab PS integration scripts, automatic branch/worktree cleanup utility).

## Self-Check: PASSED

- `lib/co-evolution.sh` modifications — FOUND (commit `cd98af9`)
- `dev-review/codex/dev-review.sh` modifications — FOUND (commit `1294477`)
- `tests/worktree-management-simulation.sh` — FOUND (140 lines, executable, passes all 5 scenarios)
- `.planning/phases/04-worktree-management/04-01-SUMMARY.md` — FOUND
- `.planning/phases/04-worktree-management/04-SUMMARY.md` — FOUND (this file)
- Commits `cd98af9`, `1294477`, `7ee77ae` — all FOUND in git log on `feat/v1.1-polish`
- Requirement RTUX-02 — to be marked Complete in REQUIREMENTS.md (this commit)
- 1 plan complete (04-01); phase status flips from Planned → Complete in ROADMAP.md
