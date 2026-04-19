# Phase 7 Deferred Items

Items discovered during Phase 7 execution that are out of scope for the current plan but need to be tracked for future work.

## DEF-07-01: proposer.sh stdout leak from `git worktree add`

**Status:** Closed 2026-04-19 in Phase 8 Plan 01 commit 1d43019. Phase 7 simulation re-verified 16/16 green.

**Discovered:** 2026-04-19 during Plan 02 execution (end-to-end verification of scenario A)
**Severity:** Moderate (Plan 01 surface bug; does NOT block Plan 02, but WILL block Phase 8 PR emitter)
**Scope:** Cross-plan — cannot fix in Plan 02 per the plan constraint "No modifications to Plan 01 code (lab/pel/proposer/code/**)"

### Description

`lab/pel/proposer/code/proposer.sh:306` invokes:

```bash
git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD 2>"$apply_err"
```

Only stderr is redirected. `git worktree add` also writes a status line to stdout (e.g., `"HEAD is now at ddffeef test(07-02): ..."`), which leaks into the proposer's stdout BEFORE the unified diff is emitted on line 393.

### Impact

- **Plan 02 simulation:** None — assertions use `grep -qE '^--- a/'` and `grep -qF '@@'` which tolerate leading non-diff lines.
- **Phase 8 (PR emitter):** High — Phase 8 will pipe proposer stdout into PR body construction. A leading "HEAD is now at..." line inside a fenced diff block would render incorrectly in GitHub/GitLab PR markdown.
- **lab/pel/README.md stated contract:** `lab/pel/proposer/code/proposer.sh` docstring at line 28-29 says:
  > Output (stdout): Single unified diff per D-19. Applyable via `git apply --check` at REPO_ROOT, canary-proven safe inside a sandbox worktree. All diagnostics route to stderr.
  
  The contract claims stdout is pure diff. The leak violates it.

### Fix (one-line, to be applied in Phase 8 Plan 01 or a dedicated fix plan)

Change `proposer.sh:306` from:

```bash
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD 2>"$apply_err"; then
```

to:

```bash
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD >/dev/null 2>"$apply_err"; then
```

### Verification after fix

The Plan 02 simulation will keep passing. Additionally, a new assertion can be added:

```bash
# Assert: first line of stdout is the --- header (no leaked non-diff content)
head -1 "$TEST_DIR/stdout-A" | grep -qE '^--- a/'
```

This is currently a `head -1 | grep` failure, but after the fix would pass.

### Tracking

- **Logged:** 2026-04-19 in `.planning/phases/07-code-tier-proposer/07-02-SUMMARY.md` §"Non-auto-fixed (deferred — out of scope per plan)"
- **Fix-in:** Phase 8 Plan 01 OR a dedicated fix plan before Phase 8 Plan 02 ships
- **Owner:** Next phase executor picks this up when wiring Phase 8's PR emitter to proposer.sh stdout
