# Phase 1: Post-v1.1 Fixes — Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Inline execution (small surgical fixes, no subagent planner needed)

<domain>
## Phase Boundary

Fold the two non-blocking warnings carried forward from the v1.1 code review (WR-04 and WR-05) so the codebase is clean before PEL's surface area lands. Avoids a separate v1.1.1 patch cycle.

- **WR-04** — interaction bug: `INITIAL_GIT_STATUS` / `INITIAL_GIT_DIRTY` capture happens BEFORE `WORKDIR` is reassigned in `--worktree` mode. Dirty parent + clean worktree silently skips verify.
- **WR-05** — hardening gap: `git worktree add "$path"` and `git checkout -b "$name"` lack the `--` argv terminator / dash-prefix guard. Paths or branch names starting with `-` get misinterpreted as flags.
</domain>

<decisions>
## Implementation Decisions

### WR-04 — INITIAL_GIT_DIRTY relocation
- Move the entire `if git -C "$WORKDIR" rev-parse --is-inside-work-tree` block from BEFORE the SESSION banner (~line 1106) to AFTER the branch/worktree setup block (~line 1202).
- Rationale: capture reflects the FINAL `WORKDIR` that execute/verify phases will actually operate on. Banner still displays the original `WORKDIR` — that's a minor inconsistency but out of scope (banner-workdir alignment isn't what WR-04 is about; don't scope-creep).
- Side-effect safety: `IN_GIT`, `INITIAL_GIT_STATUS`, `INITIAL_GIT_DIRTY` are only consumed downstream in verify phase (lines 774, 783, 818). Verify runs AFTER the worktree block, so moving the capture forward in program order is safe.

### WR-05a — dash-prefix guard on branch names
- Add early return in `maybe_setup_branch` (lib/co-evolution.sh) if `$name` starts with `-`.
- Format: `WARNING: branch setup failed: branch name 'X' cannot start with '-'` → same contract as other helper failures (log to stderr, return empty on stdout, exit 0).
- Rationale: git's own ref validation would reject dash-prefixed names, but shell-level guard gives a clearer message and fails fast before the git invocation.

### WR-05b — `--` argv terminator on `git worktree add`
- Change `git -C "$workdir" worktree add "$path"` to `git -C "$workdir" worktree add -- "$path"` in `maybe_setup_worktree`.
- Rationale: standard defensive git pattern. `$path` values starting with `-` (e.g., `--no-checkout`) get treated as paths, not flags.

### Regression test — Scenario F
- Add a static-order check to `tests/worktree-management-simulation.sh` that greps the runner source and asserts the `INITIAL_GIT_STATUS` capture line number is GREATER than the `BRANCH_SPEC` setup block line number.
- This is not a dynamic e2e test — running the full verify path synthetically is too much scope. Static analysis is sufficient to catch any future regression where someone moves the capture back above the setup block.

### Claude's Discretion
- Whether to combine WR-05a + WR-05b into one commit or split them (combine: both are WR-05 sub-items, tight coupling; split: atomic-per-concern)
- Comment verbosity in the dev-review.sh relocation block — enough to explain WHY the block moved, not a novel

</decisions>

<code_context>
## Existing Code Insights

### Fix sites (identified by grep)
- `dev-review/codex/dev-review.sh` lines 1106-1112 (old) → relocate to after line 1201
- `lib/co-evolution.sh` line 210 → add dash-prefix guard before `git checkout -b`
- `lib/co-evolution.sh` line 247 → insert `--` before `"$path"` in `git worktree add`
- `tests/worktree-management-simulation.sh` → append Scenario F before the final `if (( FAILURES == 0 ))` block

### Patterns to match
- All v1.1 Phase 4 helper code already routes `log` calls to stderr with `>&2` — new WR-05a guard follows the same convention
- Scenarios A-E in the simulation test use subshell `( ... ) || fail "Scenario X (description)"` pattern — F follows the same

### Non-goals
- Banner `Workdir:` line showing the worktree path (separate cosmetic issue, not WR-04)
- Dynamic e2e test of the dirty-parent + worktree path through the full verify phase (out of scope for a static-order regression gate)
- Modernizing `git checkout -b` to `git switch -c` (v1.1 Phase 4 explicitly locked `checkout -b` per SKILL.md convention)

</code_context>

<constraints>
- **v1.1 byte-parity preserved** — every existing scenario (A-E) in the simulation test must continue to pass unchanged; any regression here means the fix broke something
- **No new CLI flags or env vars** — these are pure internal code fixes; zero user-visible surface change
- **Mirror v1.1 Phase 4 style** — comment cadence, log format, stderr routing, test scenario structure
- **Cross-platform** — fix code must not introduce platform-specific behavior (everything stays pure bash + git)
</constraints>

---

*Plan: `01-01-PLAN.md` — three atomic fix commits + one phase-complete commit.*
