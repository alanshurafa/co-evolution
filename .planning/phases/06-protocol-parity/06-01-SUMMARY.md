---
phase: 06-protocol-parity
plan: 01
subsystem: claude-adapter
tags: [claude, tool-gating, permission-mode, upstream-parity]
requires: [phase-05]
provides: [phase-aware-tool-gating]
affects: [lib/co-evolution.sh, dev-review/codex/dev-review.sh]
tech-stack:
  added: []
  patterns: [writable-phase-flag, array-based-flag-assembly, invoke_agent-positional-threading]
key-files:
  created: []
  modified:
    - path: lib/co-evolution.sh
      what: invoke_claude accepts 4th positional writable arg; assembles text-phase vs write-phase flags
    - path: dev-review/codex/dev-review.sh
      what: invoke_agent threads writable to invoke_claude; compose/bounce/review pass "false", execute passes "true"
decisions:
  - Default writable="false" — safer posture when a caller forgets to pass the flag
  - invoke_codex path narrowed from variadic "$@" to explicit positionals since codex has no writable-flag analogue; documented inline for Phase 7 revisit
  - ensure_valid_plan_output's retry call explicitly passes "false" (unambiguous — retry is only reachable from compose/bounce)
  - Adapter-level comment rewritten to avoid verbatim "--tools \"\"" and "json-schema" literals so grep-based CI guards (PRTP-03) stay tight
metrics:
  duration: 35min
  completed: 2026-04-17
requirements: [PRTP-01, PRTP-02, PRTP-03]
---

# Phase 6 Plan 1: Claude Adapter Tool Gating Summary

One-liner: Phase-aware tool gating for `claude -p` — text phases use `--disallowedTools`, write phases use `--permission-mode bypassPermissions --allowedTools ... --add-dir`, and `--json-schema` is banned everywhere.

## Flag Strings Adopted

**Text phase (compose / bounce / review):**
```
--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"
```

**Write phase (execute, execute-retry):**
```
--permission-mode bypassPermissions \
--allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" \
--add-dir "$WORKDIR"
```

Both verbatim from `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` item 4.

## Files Touched

- `lib/co-evolution.sh` lines 19-45 — `invoke_claude` rewritten with 4th positional `writable` arg and array-based flag assembly. Broken `--tools ""` flag removed from non-WSL branch.
- `dev-review/codex/dev-review.sh`:
  - Lines 79-104 — `invoke_agent` accepts 4th positional writable, forwards to `invoke_claude`, ignores for `invoke_codex` (with comment explaining narrowing from `"$@"`)
  - Line 355 — `ensure_valid_plan_output` retry call explicitly appends `"false"`
  - Line 434 — `run_compose_phase` passes `"false"`
  - Line 489 — `run_bounce_phase` passes `"false"`
  - Lines 547 & 555 — `run_execute_phase` primary + retry both pass `"true"`
  - Line 651 — `run_verify_phase` (Claude verifier branch) passes `"false"`

## Task Breakdown

| Task | Outcome | Commit |
|------|---------|--------|
| 1. Add writable parameter + flag assembly | lib/co-evolution.sh rewritten; all 6 grep guards pass | `dab8f76` |
| 2. Thread flag through invoke_agent + 5 call sites | 5 edits to dev-review.sh; bash -n OK; all 7 grep guards pass | `e78bf24` |
| 3. Mocked smoke test | `PRTP-01/02/03 SMOKE: OK` (verification-only, no commit) | — |

## Smoke Test Output

```
$ bash /tmp/prtp-smoke-test.sh
PRTP-01/02/03 SMOKE: OK
```

The test:
1. Mocked `claude` binary (dumps argv as JSON) prepended to `$PATH`
2. Sourced `lib/co-evolution.sh`
3. Text phase call → argv contains `--disallowedTools` + exact disallow list; no `--tools` or `--json-schema`
4. Write phase call (WORKDIR=/tmp/fake-wd) → argv contains `--permission-mode bypassPermissions`, `--allowedTools` + exact allow list, `--add-dir /tmp/fake-wd`; no `--tools` or `--json-schema`
5. Default call (no 4th arg) → behaves as text phase (safer default proven)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Acceptance-criterion grep false-positives on explanatory comment**
- **Found during:** Task 1 verification
- **Issue:** Initial comment inside `invoke_claude` contained verbatim `--tools ""` and `--json-schema` strings — tripped the `! grep -q -- '--tools ""'` and `! grep -q 'json-schema'` acceptance guards
- **Fix:** Rewrote comment to describe the banned flags in prose (e.g., "the empty-string variant of the older tools flag") so the literals never appear except in the actual call paths
- **Files modified:** `lib/co-evolution.sh` (same edit cycle)
- **Commit:** `dab8f76` (final content)

**2. [Rule 3 - Blocking] /tmp path mismatch between Write tool and Git Bash**
- **Found during:** Task 3 smoke test
- **Issue:** `Write` tool wrote to a different `/tmp/` (platform-dependent) than Git Bash's `/tmp/` (which maps to `C:/Users/alan/AppData/Local/Temp`). `bash /tmp/prtp-smoke-test.sh` failed with "No such file"
- **Fix:** Wrote the throwaway script to the Windows path directly so `bash /tmp/...` in Git Bash resolves it
- **Files modified:** None (/tmp scripts are not committed)

### Non-deviations (planner warnings resolved)

- Planner warning about `ensure_valid_plan_output` retry at line 355: resolved by explicitly appending `"false"` with a comment noting the retry only fires from compose/bounce (text phases)
- Planner warning about `invoke_codex` narrowing: resolved by adding a one-line comment explaining codex has no writable-flag analogue and that Phase 7 may revisit

## Known Stubs

None.

## Self-Check: PASSED

- `lib/co-evolution.sh` exists — FOUND
- `dev-review/codex/dev-review.sh` exists — FOUND
- Commit `dab8f76` — FOUND
- Commit `e78bf24` — FOUND
- Smoke test: `PRTP-01/02/03 SMOKE: OK`
