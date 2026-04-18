# Phase 4: Worktree Management - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous)

<domain>
## Phase Boundary

Give the runner `--branch auto|NAME` and `--worktree auto|PATH` CLI flags. When set, the runner creates a dedicated git branch or worktree off the current HEAD BEFORE the execute phase runs, so each dev-review invocation is isolated and reviewable. After execute completes, the runner reports the created branch/worktree location and leaves it intact for review/merge. Both flags are no-ops when passed empty or when `WORKDIR` is not a git repo (log warning, continue without branching). (RTUX-02)

Branch mode is the simpler default: create a feature branch off HEAD, switch into it, execute phases mutate there. Worktree mode is for parallel runs where you don't want to disturb the main checkout — it creates a separate working directory that the execute phase uses as its effective `WORKDIR`.
</domain>

<decisions>
## Implementation Decisions

### CLI + Defaults
- New flags: `--branch auto|NAME` and `--worktree auto|PATH` (mutually exclusive — passing both = error)
- New env vars: `DEV_REVIEW_BRANCH` and `DEV_REVIEW_WORKTREE` (CLI wins if set)
- Default both empty = no behavior change for existing callers (v1.0/v1.1 byte-parity when unset)
- `auto` means the runner derives the name itself:
  - Branch: `dev-review/auto-{timestamp}-{short-task-slug}` (slug derived from first 4-5 task words, lowercased, `-`-separated, truncated to ~30 chars)
  - Worktree: sibling dir `../{repo-basename}-dr-{timestamp}` relative to `WORKDIR`
- Named values (`--branch my-feature` / `--worktree /path/to/wt`) used verbatim

### Git-awareness Gating
- Before any branch/worktree action, verify `git -C "$WORKDIR" rev-parse --git-dir` exits 0
- If not a git repo: log warning "`--branch`/`--worktree` ignored: $WORKDIR is not a git repo"; continue with inline execution
- If flag value is empty (e.g., `--branch ""`): same no-op + warning
- Both no-op cases must leave state.json and existing execute path fully functional

### Timing Within the Phase Pipeline
- Branch/worktree creation happens AFTER plan compose + bounce (plan exists before branching) but BEFORE execute phase starts
- Rationale: plan artifacts (`outputs/plan.md`, `outputs/bounce-NN.txt`) should land on whatever branch was current when the runner started; execute phase's file changes land on the new branch. Keeps plan artifacts reviewable on the parent branch.
- For `--worktree`: after creation, the execute phase's effective `WORKDIR` becomes the worktree path. Plan artifacts stay in the original run dir (not the worktree), since `RUN_DIR` is typically under `.planning/phases/` which is outside the worktree scope.

### Helper Placement
- New helpers in `lib/co-evolution.sh`:
  - `is_git_repo "$dir"` — portable check, returns 0/1
  - `derive_auto_branch_name "$task_description"` — slugifier
  - `derive_auto_worktree_path "$workdir"` — sibling path generator
  - `maybe_setup_branch "$workdir" "$branch_spec" "$task_desc"` — creates branch, switches into it, returns branch name or empty string
  - `maybe_setup_worktree "$workdir" "$worktree_spec" "$task_desc"` — creates worktree, returns path or empty string
- All `maybe_*` helpers are no-ops when spec is empty or dir isn't a git repo (log warning, return empty)
- Main runner calls one of the two setup helpers based on CLI parsing; never both (error out in option parser)

### State.json Integration
- Record the created branch and/or worktree path in `state.json` as top-level fields:
  - `branch_created` — the branch name if `--branch` was active
  - `worktree_path` — absolute path if `--worktree` was active
- Write via existing `write_state_field` helper so the run artifact trail is complete
- Summary output at end-of-run should echo the branch/worktree location for easy review

### Cleanup Story
- **Nothing is cleaned up automatically.** Success criterion 3 says "leaves it intact for review/merge" — that's the design. Human reviews the branch, merges or deletes as normal.
- Future enhancement (not this phase): a separate `cleanup-dev-review-branches.sh` utility. Deferred.

### Claude's Discretion
- Exact slugification algorithm for `auto` names (aim for readable + unique)
- Whether to use `git checkout -b` or `git switch -c` for branch creation (latter is modern; former is universal — pick based on what's already in use elsewhere in the repo)
- How much to log during setup (be chatty on success so reviewer sees the branch name in output)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WORKDIR` global already exists at `dev-review/codex/dev-review.sh:25`
- Option parsing pattern is established at `dev-review/codex/dev-review.sh:919+` — new branch/worktree cases follow the same shape as `--workdir`, `--timeout`, etc.
- `git -C "$WORKDIR"` commands already used at lines 710, 754 for SHA tracking — confirmed pattern
- `write_state_field` helper in `lib/co-evolution.sh:760` handles state.json mutations safely
- `log` function handles user-visible output; no new logging primitive needed

### Established Patterns
- v1.0 introduced `WRITABLE_PHASES` array + `phase_is_writable` helper — branch/worktree setup is a "pre-execute" concern, not a phase-writability concern
- Phase 3's `maybe_launch_live_window` is the template for "conditional side-effect helper" — `maybe_setup_branch` / `maybe_setup_worktree` follow the same pattern (no-op if flag unset; log-and-continue on failure; never block main flow)
- Existing tests under `tests/` are self-contained simulation scripts (e.g., `revise-loop-simulation.sh`, `live-mode-simulation.sh`) — Phase 4's test should follow the same pattern: `tests/worktree-management-simulation.sh`

### Integration Points
- `dev-review/codex/dev-review.sh`:
  - Option parser: add `--branch` and `--worktree` cases + mutual-exclusion check
  - Pre-execute block (around line 700, before `PRE_EXECUTE_SHA=...`): call `maybe_setup_branch` or `maybe_setup_worktree`, update `WORKDIR` for worktree mode
  - Final summary output: include branch/worktree info
- `lib/co-evolution.sh`: new helpers listed above
- `tests/worktree-management-simulation.sh`: smoke test covering (a) `--branch auto`, (b) `--worktree auto`, (c) non-git-repo fallback, (d) `--branch ""` empty fallback, (e) `--branch` + `--worktree` mutual exclusion error

### Non-Goals
- No automatic cleanup of branches/worktrees after run — explicitly deferred
- No integration with `--live` windows (branch/worktree creation is pre-execute, silent — no live window needed)
- No support for remote branches, pushing, PRs — local-only; user handles remote ops after review
- No merge-back automation

</code_context>

<constraints>
- **Byte-parity when unset**: default-off flags must leave v1.1 behavior identical (regression tests cover this path)
- **No new dependencies**: use only `git`, `bash`, standard coreutils already required
- **Cross-platform**: test scripts must run in Git Bash on Windows (primary user environment)
- **Plan stays on parent branch**: compose + bounce artifacts should be accessible pre-merge on the parent branch, not trapped inside the worktree
- **Match v1.1 style**: follow the code style established in Phases 1-3 (inline option parsing, `maybe_*` helper naming, `state.json` field conventions, simulation-script test pattern)
</constraints>

---

*Next step: spawn `gsd-planner` to produce `04-01-PLAN.md` based on this context.*
