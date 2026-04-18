---
milestone: v1.1 Polish & Ergonomics
branch: feat/v1.1-polish
pr: 2
reviewed_commits: 21
files_reviewed: 5
status: approved
blockers: 0
warnings: 2
info: 4
---

# Code Review — v1.1 Polish & Ergonomics Milestone (PR #2)

**Reviewed:** 2026-04-17
**Depth:** standard + targeted security/composition deep-dive (worktree, revise-loop, branch helpers)
**Branch:** `feat/v1.1-polish` (21 commits vs `master`)
**PR:** Pending merge to master
**Files reviewed:**
- `dev-review/codex/dev-review.sh` (~295 lines changed)
- `lib/co-evolution.sh` (~246 lines changed)
- `tests/revise-loop-simulation.sh` (171 lines, new)
- `tests/live-mode-simulation.sh` (102 lines, new)
- `tests/worktree-management-simulation.sh` (140 lines, new)

## Summary

This milestone adds three opt-in flags (`--revise-loop`, `--live`, `--branch`/`--worktree`) and addresses the three v1.0 non-blocking warnings (WR-01/02/03). All three v1.0 warnings are confirmed properly fixed by inspection of commit `5734b84`. All three new flags are default-off and produce zero behavior change when unset (verified by reading the option parser, the gate guards, and the byte-parity assertions in each phase's smoke test).

**Security posture is sound.** I exercised command-injection vectors against `--branch` and `--worktree` with shell-meta-laden values (semicolons, `$(...)`, backticks, leading `--`). All payloads were inert — git correctly rejects invalid ref names with `fatal: '...' is not a valid branch name`, and the `git worktree add "$path"` argv-as-single-item pattern blocks shell expansion. The `printf '%q'` escaping in `maybe_launch_live_window` correctly sanitizes stderr file paths before passing them through `bash -c`.

**Test coverage is good.** All three simulation tests pass on Git Bash (`tests/revise-loop-simulation.sh`, `tests/live-mode-simulation.sh`, `tests/worktree-management-simulation.sh`). Each test is hermetic (no network, no real CLIs, ephemeral git repos), idempotent, and locks in the byte-parity-when-unset invariant.

**Two warnings worth surfacing.** WR-04 below is a real interaction bug that surfaces when a user has uncommitted changes in their parent repo and uses `--worktree auto` — verify will silently skip even though the worktree itself is clean. WR-05 documents that `git worktree add "$path"` does not use the `--` argv terminator, so a path that begins with `-` (e.g., `--worktree --no-checkout`) is interpreted as a git flag rather than as a path. Neither breaks v1.0 byte-parity (default-off), neither is a security issue (no shell injection possible), but both are correctness papercuts that should be fixed in a follow-up.

**No blockers.** The milestone is mergeable as-is.

---

## WARNINGS

### WR-04: `INITIAL_GIT_DIRTY`/`INITIAL_GIT_STATUS` captured from parent repo, not from worktree

**File:** `dev-review/codex/dev-review.sh:1106-1112` + `1188-1201` + `795-822`

**Issue:** When `--worktree auto|PATH` is used, the order of operations is:

1. Lines 1106-1112: `IN_GIT`, `INITIAL_GIT_STATUS`, and `INITIAL_GIT_DIRTY` are captured from the **original** `WORKDIR` (the parent repo).
2. Lines 1188-1201: After plan+bounce, `WORKDIR` is reassigned to the new worktree path (`WORKDIR="$_new_wt"` at line 1197).
3. Lines 718-790 (`run_execute_phase`) and 795-822 (`run_verify_phase`): Both read `INITIAL_GIT_DIRTY` and `INITIAL_GIT_STATUS` while running git commands against the new `WORKDIR` (the worktree).

This means: if the user has uncommitted changes in the parent repo and runs `--worktree auto`, then:
- `run_verify_phase:818-820` short-circuits with `WARNING: verification skipped - workdir had pre-existing uncommitted changes` — even though the worktree itself is fresh.
- `run_execute_phase:774-777` "no changes detected" comparison `status_output == INITIAL_GIT_STATUS` will never match (worktree status is "" empty, parent's status is non-empty), so the no-change branch is silently dead code on this path.
- The diffstat scope branch at line 783 (`INITIAL_GIT_DIRTY != "true"`) is wrong — it'll fall through to the `[[ -n "$(git status --short)" ]]` elif case, which catches uncommitted changes only.

The user's mental model is "the worktree is fresh, so verify should compare against its baseline." The actual behavior is "verify treats the worktree as if it inherited the parent's dirty state."

**Fix:**
```bash
# After WORKDIR reassignment at line 1197, re-capture the baselines:
WORKDIR="$_new_wt"
INITIAL_GIT_STATUS=$(git -C "$WORKDIR" status --short)
INITIAL_GIT_DIRTY=false
[[ -n "$INITIAL_GIT_STATUS" ]] && INITIAL_GIT_DIRTY=true
```

Add a Phase 6 invariant test: `--worktree auto` from a dirty parent must run verify against the worktree's clean baseline, not the parent's dirty status.

### WR-05: `git worktree add "$path"` is vulnerable to flag-style paths (no `--` argv terminator)

**File:** `lib/co-evolution.sh:247` + `dev-review/codex/dev-review.sh:1005-1007`

**Issue:** The worktree creation runs `git -C "$workdir" worktree add "$path"` without the `--` argv terminator. If a user (or env var) passes `--worktree --no-checkout` or `--worktree -f`, git interprets the value as a flag, not as a path. In all the cases I tested, git rejected the command with usage output (because the flag had no following path), so no exploitable damage occurred. But this is a hardening-best-practice gap:

- `git checkout -b "$name"` (line 210) is similarly missing `--`, but `git checkout -b -- <name>` is the safer form.
- `git worktree add -- "$path"` would force `$path` to be treated as a positional path.

The worktree path is also subject to git's branch-name auto-derivation: `git worktree add "/some/path/foo"` creates a branch `foo`. If `$path` contains a literal `$(...)` string like `/tmp/x/$(touch FOO)`, git will create a branch literally named `FOO)` even though the directory creation fails (I verified this — see test trace below). The `touch` does not execute (no shell expansion), but a stray branch is left behind in the parent repo. Cleanup is awkward.

**Fix:**
```bash
# In maybe_setup_worktree, line 247:
if err_output=$(git -C "$workdir" worktree add -- "$path" 2>&1); then

# In maybe_setup_branch, line 210:
if err_output=$(git -C "$workdir" checkout -b "$name" -- 2>&1); then
# Note: -- in checkout means "no path follows," disambiguating branch vs file name.
```

Plan's threat register (Phase 4 SUMMARY, T-04-02) already documents "argv-as-single-item" as the mitigation, but doesn't note the missing `--` terminator. Adding `--` makes the mitigation rock-solid.

---

## INFO

### IN-05: `--branch auto --plan-only` is silently ignored (documented but no user warning)

**File:** `dev-review/codex/dev-review.sh:1161-1180` + `1182-1201`

The runner exits the plan-only branch at line 1180 BEFORE reaching the branch/worktree setup block at line 1188. This is intentional — the comment at lines 1184-1186 documents the design — but the user gets no signal that their `--branch` flag was effectively a no-op. They might run `dev-review.sh --plan-only --branch auto "task"`, expect a branch to be created with the plan artifact on it, and instead find the plan artifact on their original branch with no message.

**Fix (optional):**
```bash
# Add at line ~1170 inside the PLAN_ONLY block:
if [[ -n "$BRANCH_SPEC" || -n "$WORKTREE_SPEC" ]]; then
  log "INFO: --branch / --worktree ignored under --plan-only (plan artifacts stay on parent branch by design)"
fi
```

One-line UX improvement. Not a bug.

### IN-06: `write_state_field` now returns `$jq_exit` on failure (behavior change from v1.0)

**File:** `lib/co-evolution.sh:921-927`

The FIX-WR-02 patch added `return $jq_exit` to `write_state_field` on the failure path. Under `set -euo pipefail` (which the runner uses), this means a jq failure inside `write_state_field` will now ABORT the entire runner mid-flow. v1.0 implicitly swallowed the failure (the old `mv "$tmp" "$state_path"` branch chained via `&&` so no-op-on-failure was the de facto behavior).

In practice, all callers in the runner pass static jq paths (`.branch_created`, `.worktree_path`, `.completed_at`, `.verify_verdict`, `.execute_delta`, `.marker_counts.*`) so jq syntax errors are impossible. Runtime failures (disk full, OOM) are catastrophic anyway, and aborting is correct behavior. Just noting that this is a v1.0→v1.1 semantic change worth documenting.

**Fix (optional):** Either:
- Document the new behavior in the function docstring ("returns 0 on success, jq's exit code on failure — caller may need `|| true` to continue under `set -e`").
- Or guard call sites with `|| true` if they are non-critical.

I verified all 6 call sites in `dev-review.sh` (lines 1143, 1155, 1156, 1171, 1191, 1198, 1253, 1267, 1269, 1296) and none would meaningfully recover from a jq failure — abort-and-die is the right default. No code change needed unless a future caller needs different semantics.

### IN-07: `tests/worktree-management-simulation.sh` Scenario E creates real run dirs in `runs/` if mutex check changes

**File:** `tests/worktree-management-simulation.sh:118-132`

Scenario E uses a "distinctive timestamp" (`mutex-test-$RANDOM`) and asserts that no `runs/dev-review-${TIMESTAMP}` directory was created. This is a clever invariant lock. However, if the mutex check ever moves AFTER the `mkdir -p "$RUN_DIR"` block (lines 1089-1091), the test would silently leave run dirs behind in the real `runs/` directory, polluting `runs/` for subsequent test runs. Worth a follow-up cleanup step at end of scenario E:

```bash
rm -rf "$REPO_ROOT/runs/dev-review-${TIMESTAMP}" 2>/dev/null
```

Belt-and-suspenders only — the assertion already catches the regression.

### IN-08: `derive_auto_branch_name` slug truncation can leave a trailing `-` mid-word

**File:** `lib/co-evolution.sh:151-169`

The slugifier truncates to 30 chars via `slug="${slug:0:30}"`, then strips a trailing `-` via `slug="${slug%-}"`. This handles the case where the cut falls on a `-`, but does not handle the case where the cut falls mid-word and leaves a partial word. Example: a 6-word task whose 5th word is "implementation" would produce a slug like `dev-review/auto-...-fix-the-broken-auth-implem` (truncated mid-word). Not wrong — just aesthetically odd. The plan's design accepts this as "readable + unique." Not a bug.

If desired, the truncation could happen on word boundaries:
```bash
slug=$(echo "$slug" | awk -v max=30 '{
  out=""; for(i=1;i<=NF;i++) {
    cand = (out=="" ? $i : out"-"$i);
    if(length(cand) > max) break; out=cand
  } print out
}')
```

Optional polish.

---

## Composition Verification (explicit check)

I verified the cross-flag interactions called out in the brief:

| Combination | Behavior | Status |
|-------------|----------|--------|
| `--live` + `--branch` | Live windows tail stderr; branch created post-bounce, pre-execute. No interaction. | OK |
| `--live` + `--worktree` | Live windows reference stderr files in original `RUN_DIR` (not the worktree); WORKDIR reassignment doesn't affect tail targets. | OK |
| `--branch` + `--revise-loop` | Branch created once before loop starts; all execute-N/verify-N passes happen on that branch. | OK |
| `--worktree` + `--revise-loop` | Worktree created once before loop; all passes run inside the same worktree. WR-04 caveat applies (parent dirty state leaks into worktree's verify gate). | OK with caveat |
| `--plan-only` + `--branch` | Plan-only exits at line 1180; branch setup at 1188 never reached. Silent no-op as designed (IN-05). | OK |
| `--branch` + `--worktree` | Mutex check at line 1034 fires before any side effect; runner exits 1 with "mutually exclusive" message. Verified by Scenario E and a direct test (no `runs/` dir created). | OK |

---

## Security Sweep (explicit check)

**Branch name injection:** I tested `maybe_setup_branch` with `foo;rm -rf /tmp/SENTINEL`, `$(touch /tmp/SENTINEL2)`, and `` `touch /tmp/SENTINEL3` ``. All three were rejected by git (`fatal: '...' is not a valid branch name`) and no SENTINEL file was created. Shell expansion is correctly suppressed by the `git -C "$workdir" checkout -b "$name"` quoting.

**Worktree path injection:** Same exercise against `maybe_setup_worktree`. Shell injection inert. Caveat: `--worktree '/tmp/x/$(touch FOO)'` left a stray branch literally named `FOO)` in the parent repo (git's auto-branch-from-trailing-path-component, see WR-05). The `touch` did NOT execute, so no security issue, but the stray branch is awkward to clean up.

**Live mode tail command:** `printf -v tail_cmd 'tail -f %q' "$stderr_file"` correctly escapes pathological stderr file paths before they reach `bash -c`. Verified by inspection. Not security-exploitable.

**Code-injection vectors in new helpers:** None found. `maybe_*` helpers all pass user-controlled values through `git -C "$dir" <subcommand> "$arg"` patterns that are correctly quoted. No `eval`, no `bash -c $userdata`, no string concatenation into shell commands.

**Hardcoded secrets / credentials:** None.

---

## v1.0 Warning Fixes (explicit verification)

| v1.0 Warning | Phase 1 Fix | Verification |
|--------------|-------------|--------------|
| WR-01: Stale `LAST_INVOKE_EXIT_CODE` in codex verify | `LAST_INVOKE_EXIT_CODE=0` reset before the `if command -v timeout` conditional at line 865 | Confirmed at `dev-review.sh:863-865`. Reset happens before both branches of the `if/else`. The latent-bug path is now closed. |
| WR-02: `state.json` temp-file leak on jq failure | `if jq ...; then mv; else rm -f $tmp; log WARNING; fi` pattern in both `write_state_phase` and `write_state_field` | Confirmed at `lib/co-evolution.sh:863-885` and `:902-927`. Temp files cleaned up on failure path. |
| WR-03: Phase-start timestamps as global leaks | Phase functions accept `phase_start` as explicit positional arg; main flow passes it via `run_compose_phase "$_compose_phase_start"` etc. | Confirmed at `dev-review.sh:511, 710, 797, 1140, 1250, 1264`. Hidden global coupling removed; the `${_var:-fallback}` reads are gone. |

All three v1.0 warnings are properly addressed. None are partially-fixed or hand-waved.

---

## Test Coverage (explicit check)

I ran all three new simulation tests under Git Bash on Windows 11. All pass:

- `tests/revise-loop-simulation.sh`: `S1 OK / S2 OK / S3 OK / S4 OK / ALL PASS` — covers REVISE→APPROVED with budget 1, REVISE with budget 0 (v1.0 parity), REVISE cap at max, and prompt byte-identity invariant.
- `tests/live-mode-simulation.sh`: `ALL SCENARIOS PASSED` (with the expected non-Windows fallback warning) — covers LIVE_MODE=false no-op, LIVE_MODE=true on non-Windows (one warning, never blocks), LIVE_MODE=true on simulated Windows with stubbed `wt.exe`.
- `tests/worktree-management-simulation.sh`: `ALL SCENARIOS PASSED` — covers `--branch auto`, `--worktree auto`, non-git-repo fallback, empty-flag fallback, and mutual exclusion at runner level.

**Coverage gap (worth documenting, not blocking):** WR-04 above (parent-dirty + `--worktree`) is not covered by any simulation test. A Phase 5 follow-up should add Scenario F: "dirty parent + `--worktree auto`" asserting verify runs against the worktree's clean baseline, not the parent's dirty status.

---

## APPROVED

**APPROVED with 0 blockers, 2 warnings, 4 info notes.**

All v1.0 warnings (WR-01/02/03) are properly fixed. All three new flags (`--revise-loop`, `--live`, `--branch`/`--worktree`) are default-off and byte-parity-preserving when unset. Cross-flag composition works correctly. Security posture is sound — no shell-injection vectors found, hardcoded-secrets scan clean, the new helpers all use the same `git -C "$dir" subcommand "$arg"` quoting pattern that v1.0 already validated.

The two warnings (WR-04 worktree-dirty interaction, WR-05 missing `--` argv terminator) are correctness papercuts in paths that are either rare-in-practice (most users won't run `--worktree` from a dirty parent) or fail-safely (git rejects flag-style paths without doing damage). Neither blocks v1.1 ship; both should land in a v1.1.1 patch or roll into v1.2.

Ship it.

_Reviewed: 2026-04-17_
_Reviewer: Claude (gsd-code-reviewer, Opus 4.7 1M)_
_Depth: standard + targeted security/composition deep-dive_
