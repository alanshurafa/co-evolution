---
phase: 04-worktree-management
plan: 01
subsystem: dev-review-runtime
tags: [bash, cli, git, worktree, branch, rtux-02]
requires: [01-code-review-fixes]
provides:
  - --branch / --worktree CLI flags + DEV_REVIEW_BRANCH / DEV_REVIEW_WORKTREE env vars (default empty = byte-parity)
  - is_git_repo, derive_auto_branch_name, derive_auto_worktree_path, maybe_setup_branch, maybe_setup_worktree helpers
  - mutual-exclusion guard fires before any RUN_DIR / state.json side effect
  - state.json gains .branch_created and .worktree_path fields when active
  - DEV-REVIEW SESSION + DEV-REVIEW COMPLETE banners echo branch/worktree info
  - self-contained bash smoke test covering 5 scenarios in <4s
affects: [dev-review-runtime, lib-co-evolution-helpers]
tech-stack:
  added: []
  patterns:
    - "log-to-stderr discipline in stdout-returning helpers — preserves caller's variable capture while keeping LOG_FILE writes intact"
    - "pre-execute setup AFTER plan+bounce, BEFORE execute — plan artifacts stay reviewable on parent branch / in $REPO_ROOT/runs/"
    - "mutual-exclusion guard fires BEFORE any side effect (mkdir / state init) — no run_dir leak on misconfigured invocation"
    - "PLAN_ONLY early-exit precedes branch/worktree dispatch — silent no-op for `--branch auto --plan-only` is intentional, matches CONTEXT.md"
    - "auto-name derivation uses already-exported $TIMESTAMP global so log/branch/worktree share one timestamp; falls back to fresh stamp for standalone test sourcing"
key-files:
  created:
    - tests/worktree-management-simulation.sh
  modified:
    - lib/co-evolution.sh
    - dev-review/codex/dev-review.sh
key-decisions:
  - "Helpers route their own log() calls to stderr (>&2) so callers can capture stdout cleanly — was a Rule 1 fix during execution because lib's log() tees to stdout via tee -a."
  - "Branch/worktree dispatch lands AFTER PLAN_ONLY's exit branch — `--branch auto --plan-only` is silently a no-op on the branching side per CONTEXT.md decision (plan artifacts stay on parent branch)."
  - "Slug algorithm: first 5 words → lowercase → [^a-z0-9-]→`-` → collapse → ≤30 chars → trim trailing `-` (deterministic, locked by Scenario A exact-string assertion)."
  - "Mutual-exclusion check inserted BEFORE WORKDIR normalization (line ~1009 of runner) so `--branch X --worktree Y` exits 1 with no RUN_DIR creation — proven by Scenario E + verification step 3."
  - "Default empty BRANCH_SPEC + WORKTREE_SPEC = Phase 3 byte-parity (no git ops, no state.json mutations); only new log lines on a default run are the two `Branch: <empty>` / `Worktree: <empty>` banner additions, analogous to Phase 3's `Live mode:` line."
patterns-established:
  - "stdout-returning helpers must redirect log() to stderr to keep variable-capture clean"
  - "test scenarios that rely on path-string comparison must compare basenames on Git Bash for Windows because git tooling outputs Windows-style paths while bash captures MSYS-style paths for the same dir"
requirements-completed: [RTUX-02]
duration: 25min
completed: 2026-04-17
---

# Phase 4 Plan 1: Worktree Management Summary

Added `--branch auto|NAME` and `--worktree auto|PATH` CLI flags (plus `DEV_REVIEW_BRANCH` / `DEV_REVIEW_WORKTREE` env vars) to the Codex dev-review runner. When active and `WORKDIR` is a git repo, the runner creates the requested branch or worktree AFTER plan+bounce land on the parent branch and BEFORE execute, switches into it, records the location in `state.json`, and echoes the location in the final DEV-REVIEW COMPLETE banner. Empty flag values and non-git workdirs no-op with a single WARNING line. Both flags are mutually exclusive — passing both `die`s with a clear message before any side effect (no `runs/` dir created). Default off preserves Phase 3 byte-parity. A self-contained bash smoke test (5 scenarios, no network, no real CLIs, ~3s) locks in the contract.

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-17 (feat/v1.1-polish)
- **Tasks:** 3
- **Commits:** 3 (atomic, per-task)
- **Files modified:** 2 + 1 created

## Task Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | `cd98af9` | feat(04-01): add is_git_repo + branch/worktree setup helpers |
| 2 | `1294477` | feat(04-01): wire --branch + --worktree flags into dev-review runner |
| 3 | `7ee77ae` | test(04-01): add worktree-management simulation covering 5 scenarios |

## Files Created/Modified

| File | Change | Delta |
|------|--------|-------|
| `lib/co-evolution.sh` | modified | +130 / 0 (Task 1) |
| `dev-review/codex/dev-review.sh` | modified | +54 / 0 (Task 2) |
| `tests/worktree-management-simulation.sh` | created | +140 lines (Task 3) |

## Architecture (1-paragraph future-archaeology note)

Five new helpers landed in `lib/co-evolution.sh`: `is_git_repo` (portable `git rev-parse --git-dir` check returning "true"/"false" on stdout), `derive_auto_branch_name` (5-word slug pipeline → `dev-review/auto-<TIMESTAMP>-<slug>`), `derive_auto_worktree_path` (sibling-dir composer → `<dirname>/<basename>-dr-<TIMESTAMP>`), `maybe_setup_branch` (no-op + WARNING when spec empty or workdir non-git, else `git checkout -b <name>` and prints name on stdout), and `maybe_setup_worktree` (analogous, runs `git worktree add <path>` and prints absolute path). Both setup helpers route their `log()` calls to stderr (`>&2`) so the caller can capture stdout into a variable without WARNING/INFO text leaking into the captured value — a Rule 1 fix discovered during Task 1 verification because lib's `log()` writes via `tee -a` which echoes to fd 1. The runner picks up two parser cases (`--branch`/`--worktree`), env-var defaults `BRANCH_SPEC="${DEV_REVIEW_BRANCH:-}"` / `WORKTREE_SPEC="${DEV_REVIEW_WORKTREE:-}"`, two result globals (`BRANCH_CREATED` / `WORKTREE_PATH`), a mutex check immediately after the parser loop closes (BEFORE `WORKDIR` normalization, BEFORE `mkdir -p "$RUN_DIR"`), two new banner lines in each of the SESSION + COMPLETE blocks, and a single dispatch block landing AFTER the PLAN_ONLY early-exit branch and BEFORE `_run_revise_loop`. PLAN_ONLY exits earlier so `--branch auto --plan-only` is intentionally a silent no-op on the branching side — matches CONTEXT.md's decision that plan artifacts stay on the parent branch / in `$REPO_ROOT/runs/`. The smoke test creates a fresh ephemeral git repo per scenario via `init_repo`, exports a deterministic `TIMESTAMP=20260101-000000` so slug assertions are exact-string, and Scenario E uses a distinctive `mutex-test-<RANDOM>` timestamp to prove the mutex guard fires before `mkdir -p "$RUN_DIR"`.

## Test Output

```
$ bash tests/worktree-management-simulation.sh
warning: in the working copy of 'README.md', LF will be replaced by CRLF the next time Git touches it
Branch created: dev-review/auto-20260101-000000-fix-the-broken-auth-flow
warning: in the working copy of 'README.md', LF will be replaced by CRLF the next time Git touches it
Worktree created: /tmp/wt-sim-Dq57oN/repo-b-dr-20260101-000000
WARNING: --branch ignored: /tmp/wt-sim-Dq57oN/not-a-repo is not a git repo
WARNING: --worktree ignored: /tmp/wt-sim-Dq57oN/not-a-repo is not a git repo
warning: in the working copy of 'README.md', LF will be replaced by CRLF the next time Git touches it
WARNING: --branch ignored: value is empty
WARNING: --worktree ignored: value is empty
ALL SCENARIOS PASSED

real    0m3.036s
```

The leaking WARNING / `Branch created` / `Worktree created` lines are stderr passthrough from the helpers' `log >&2` calls — expected behavior identical to Phase 3's pattern. CRLF warnings are git's `core.autocrlf` notification, not a test failure. All five scenarios pass in ~3s on Git Bash for Windows with no network and no real CLIs.

## Decisions Made

- **Default empty BRANCH_SPEC / WORKTREE_SPEC** — preserves Phase 3 byte-parity. Only new log output on a default run is the two `Branch: <empty>` / `Worktree: <empty>` banner lines, analogous to Phase 3's single `Live mode: false` addition.
- **Helpers `log >&2` not `log` directly** — was a planned `printf '%s' "$name"` contract; lib's `log()` tees to stdout so caller's `$(maybe_setup_branch ...)` capture would have been polluted with the WARNING/`Branch created:` text. Routing log calls inside the helpers to stderr cleanly resolves this without changing lib's `log()` semantics or breaking any other caller.
- **Mutual-exclusion check fires BEFORE `WORKDIR` normalization** — guarantees `mkdir -p "$RUN_DIR"` and `init_state_json` never run on a misconfigured invocation. Verification step 3 + Scenario E lock this in.
- **PLAN_ONLY ordering** — branch/worktree dispatch goes AFTER the PLAN_ONLY early-exit (~line 1149) so `--branch auto --plan-only` is a silent no-op on the branching side. Intentional per CONTEXT.md ("plan artifacts stay reviewable on parent branch"); not a parser error.
- **`git checkout -b` not `git switch -c`** — locked by `skills/dev-review/SKILL.md:136` per CONTEXT.md "Claude's Discretion" note; consistency wins over modernity.
- **No cleanup automation** — explicit per CONTEXT.md success criterion 3 ("leaves it intact for review/merge"). User merges/deletes branches manually after review. Future `cleanup-dev-review-branches.sh` utility deferred.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `log()` stdout pollution in stdout-returning helpers**
- **Found during:** Task 1 verification, no-op safety check (`out=$(maybe_setup_branch /tmp "" "task")` returned `WARNING: --branch ignored: value is empty` instead of empty string).
- **Issue:** Lib's `log()` writes via `tee -a "$LOG_FILE"` which echoes to fd 1; capturing the helper's stdout via `$(...)` therefore captured the WARNING/`Branch created:` text alongside the intended branch-name return value. Scenarios A and D in the smoke test would have failed.
- **Fix:** Route every `log()` call inside `maybe_setup_branch` and `maybe_setup_worktree` to stderr via `log "..." >&2`. Stdout now carries only the helper's intended return value (branch name / worktree path / empty); `LOG_FILE` writes still succeed via tee's `-a` flag.
- **Files modified:** `lib/co-evolution.sh` (10 log call-sites annotated with `>&2`)
- **Commit:** Folded into Task 1 commit `cd98af9` before commit (verification gate caught it).

**2. [Rule 1 - Bug] Scenario B `git worktree list` path-style mismatch on Git Bash for Windows**
- **Found during:** First end-to-end smoke-test run.
- **Issue:** `git worktree list` outputs paths in Windows form (`C:/Users/.../wt-sim-XXX/repo-b-dr-...`) while `maybe_setup_worktree` returns the path in MSYS form (`/tmp/wt-sim-XXX/repo-b-dr-...`). The literal `grep -q "$wt"` substring match in Scenario B failed because the two strings represent the same dir in different syntactic styles.
- **Fix:** Compare by basename instead of full path — `wt_base=$(basename "$wt"); git worktree list | grep -q "$wt_base"`. Basename is identical regardless of path-style. Adds inline comment documenting the rationale and dumps `git worktree list` output on failure for debuggability.
- **Files modified:** `tests/worktree-management-simulation.sh` (Scenario B's worktree-list assertion)
- **Commit:** Folded into Task 3 commit `7ee77ae` before commit.

Both deviations stayed within the planner's stated trust scope (Rule 1, auto-fix bugs), preserved every plan acceptance criterion, and added no new architecture. The plan file itself is unchanged because both fixes are local implementation refinements rather than design changes.

## Issues Encountered

- **CRLF warnings on git operations** in the test harness's `init_repo` helper — same category as Phase 2/3's simulation tests. Not a test failure; git's `core.autocrlf` notification is inert.
- **`/tmp` path resolution on Git Bash** produces `//tmp-dr-...` (double slash) when computing `dirname` of `/tmp` because `cd /tmp && cd .. && pwd` returns `/`. The plan's acceptance criterion explicitly allows this (`contains '/tmp-dr-' AND ends in '-dr-<TIMESTAMP>'` both pass on `//tmp-dr-...`); Scenario B uses a deeper test path so it never hits this corner.

## Threat Model Compliance

| Threat | Mitigation | Verified by |
|--------|-----------|-------------|
| T-04-01 (branch-name injection) | argv-as-single-item discipline; `auto` slugs strip `[^a-z0-9-]`; explicit names handed to git which itself enforces ref-name rules | Code inspection; Scenario A asserts exact-string slug |
| T-04-02 (worktree-path injection) | argv-as-single-item; `auto` paths composed from already-existing `dirname`/`basename`; no `eval` or `bash -c` | Code inspection; Scenario B asserts dir creation + worktree-list registration |
| T-04-04 (git self-DoS) | Setup helpers capture stderr via `err_output=$(... 2>&1)` and log WARNING on failure; main run continues on original branch | Helpers return 0 unconditionally on failure path; integration check in verification step 5 |
| T-04-07 (privilege escalation via shell-out) | Only `git` invoked; `cd "$path" && pwd` bounded to current shell | Code inspection of the two `maybe_setup_*` bodies |

Accepted threats per plan (not mitigated, documented):
- **T-04-03 (explicit hostile name targeting sensitive location)** — solo-dev tool, user attacks self.
- **T-04-05 (branch/worktree accumulation)** — cleanup deferred per CONTEXT.md; intentional.
- **T-04-06 (task-description leak via slug)** — feature, users can pass `--branch NAME` verbatim for privacy.

## User Setup Required

None. Both flags opt-in via CLI or env var; default empty preserves all existing behavior.

## Follow-ups / Known Limits

- **No automated cleanup.** Per CONTEXT.md decision, the user manually `git worktree remove <path>` and `git branch -D <branch>` after merge. A `cleanup-dev-review-branches.sh` utility is candidate future work — not blocked by anything, just out of milestone scope.
- **Worktree mode + `--live`.** Not exercised together in this phase. Live mode launches Windows terminal tail-windows tied to `$RUN_DIR/*-stderr.log` (which lives in `$REPO_ROOT/runs/`, not the worktree), so they should compose cleanly. Not tested manually because the smoke test path is hermetic.
- **Explicit `--worktree PATH` only smoke-tested via the helper layer**, not the runner CLI surface. Plan tested only `--worktree auto`; explicit paths pass through `git worktree add` unchanged so git's own errors will surface. Per the planner's tension-3 note, this is intentional — defensive path validation beyond what git itself does is out of scope.
- **Git Bash path-style mismatches** are now a documented test-harness pattern (Scenario B). Future tests that compare git-output paths against shell-captured paths should compare basenames on Git Bash for Windows.

## Next Phase Readiness

- **Phase 4 closes RTUX-02.** Third and final RTUX requirement of v1.1; the milestone is now feature-complete.
- **No further plans in v1.1.** Roadmap shows Phase 4 as the last entry; ship the milestone or open a v1.2 cycle.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND (130 lines added, commit `cd98af9`)
- `dev-review/codex/dev-review.sh` — FOUND (54 lines added, commit `1294477`)
- `tests/worktree-management-simulation.sh` — FOUND (140 lines, executable, passes all 5 scenarios, commit `7ee77ae`)
- Commits `cd98af9`, `1294477`, `7ee77ae` — all FOUND in git log
- All 4 ROADMAP success criteria for Phase 4 verified — see traceability table in plan + `04-SUMMARY.md`

---
*Phase: 04-worktree-management*
*Plan: 01*
*Completed: 2026-04-17*
