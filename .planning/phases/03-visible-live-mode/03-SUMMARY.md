---
phase: 03-visible-live-mode
plans: [03-01]
subsystem: dev-review-runtime
tags: [live-mode, windows, observability, cli, bash, rtux-01]
requires: [phase-01]
provides: [live-mode-helpers, --live-flag, platform-detection, live-mode-simulation]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
  - tests/
tech-stack:
  added: []
  patterns: [tail-window-observability, priority-ordered-platform-detection, once-per-run-warning-guard, path-shadowing-for-cross-os-tests]
metrics:
  duration: 22min
  tasks_completed: 3
  commits: 3
  completed: 2026-04-17
requirements: [RTUX-01]
---

# Phase 3: Visible Live Mode Summary

One-liner: Added a `--live` CLI flag to the Codex dev-review runtime that launches a visible Windows Terminal (or cmd.exe fallback) tailing each wrapped phase's stderr file — compose, each bounce pass, execute, and verify. On non-Windows hosts or when launchers fail, the runner logs a single warning and proceeds inline; the main run is never blocked. Default off preserves Phase 2 byte-parity. A self-contained bash smoke test (<1s, no network, no real CLIs) locks in three invariants: byte-parity when `--live` absent, single-warning idempotent fallback on non-Windows, and launcher-invocation + state.json byte-equality on simulated Windows.

## What Landed Per Plan

### Plan 03-01: Visible Live Mode (RTUX-01)

- **Task 1 — Helpers in lib/co-evolution.sh.** `LIVE_MODE` default (`: "${LIVE_MODE:=false}"`), `is_windows_host` (OSTYPE msys*/cygwin* → wt.exe → cmd.exe priority), and `maybe_launch_live_window` (no-op unless `LIVE_MODE=true`, always returns 0, once-per-run non-Windows warning guard, wt.exe preferred with cmd.exe fallback, both backgrounded + disowned).
- **Task 2 — Wire dev-review.sh.** Global `LIVE_MODE="${LIVE_MODE:-false}"`, new `--live` CLI case, usage-help line, one-line "Live mode: $LIVE_MODE" banner entry, and four `maybe_launch_live_window` call sites (compose + per-bounce-pass + execute + verify — single call covers both verifier branches; retry branches intentionally unwrapped).
- **Task 3 — Smoke test.** `tests/live-mode-simulation.sh` with three scenarios: (A) LIVE_MODE=false no-op invariant, (B) LIVE_MODE=true on non-Windows with `is_windows_host` function-override forcing the fallback path (asserts exactly one warning across three calls), (C) LIVE_MODE=true on simulated Windows with `wt.exe` stubbed via PATH shadowing (asserts stub received `phase:execute` title, stderr file pre-touched, state.json byte-identical after launch). Runs in ~0.65s.

Commits: `5c09fc1` (T1), `cd84c13` (T2), `7c15e33` (T3). All pushed to `feat/v1.1-polish`.

## Commit Chain

```
7c15e33  test(live): cover absent/non-windows/stubbed-windows scenarios
cd84c13  feat(live): add --live flag and wrap four phase invocations
5c09fc1  feat(live): add is_windows_host + maybe_launch_live_window helpers
```

All three pushed to `feat/v1.1-polish`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| RTUX-01 | 03-01 | Complete |

## Wave Order Executed

Single-plan phase (Wave 1 only): 03-01 T1 → T2 → T3, strictly sequential.

## Files Modified (Phase-Level)

- `lib/co-evolution.sh` — extended: `LIVE_MODE` default, `is_windows_host`, `maybe_launch_live_window` (+73 / 0)
- `dev-review/codex/dev-review.sh` — extended: flag parser case, usage help, banner log, four call sites (+20 / 0)
- `tests/live-mode-simulation.sh` — new 102-line self-contained smoke test

## Deviations

**None.** Plan executed exactly as written; all acceptance criteria passed first time. See `03-01-SUMMARY.md` for details.

## Verification Summary

Final phase-level verification (all four gates pass):

- **Syntax:** `bash -n` clean on all three touched files
- **CLI surface:** `bash dev-review.sh --help` includes `--live` line
- **Smoke test:** `tests/live-mode-simulation.sh` exits 0 with `ALL SCENARIOS PASSED`
- **Byte-parity guard:** With `LIVE_MODE` unset, `maybe_launch_live_window compose /tmp/x` leaves no file created and no log written — prints `BYTE_PARITY_OK`

## Invariant Compliance

Both must-not invariants from the orchestrator asserted:

- **Must-not-break** — Scenario A (LIVE_MODE unset) asserts no file touched + no warning logged → byte-parity with Phase 2 holds except for the single "Live mode: false" banner line (same category of benign addition as Phase 2's "Timeout:" line).
- **Must-not-block** — Scenario C asserts helper return code 0 + state.json byte-identical after launch, proving the launcher never interferes with the main phase's exit semantics even when it succeeds. Scenarios B+C together prove that failures (simulated via non-Windows path) log a warning and return 0.

## Threat Model Compliance

Every `mitigate` disposition in the plan's threat register verified:

| Threat | Mitigation | Check |
|--------|-----------|-------|
| T-03-01 (phase name tampering) | argv item, never shell-interpolated | Code inspection — phase names are literals or integer-derived |
| T-03-02 (stderr_file injection) | `printf -v %q` bash-quotes the path | Task 1 helper implementation |
| T-03-04 (launcher self-DoS) | `& disown` + `|| true`; main shell never waits | Task 3 Scenario C state.json byte-equality |
| T-03-06 (launcher privilege) | Only wt.exe/cmd.exe invoked, no registry writes | Code inspection of launcher command strings |

Accepted threats per plan (not mitigated, documented): T-03-03 (orphaned tail processes accumulate), T-03-05 (stderr visible in window = the feature).

## Known Stubs

None.

## Next Phase

Phase 4 (Worktree Management — RTUX-02) remains to close the v1.1 milestone. Phase 4 touches git branch/worktree setup before execute, orthogonal to this phase's observability layer — no dependency.

## Self-Check: PASSED

- `lib/co-evolution.sh` modifications — FOUND (commit 5c09fc1)
- `dev-review/codex/dev-review.sh` modifications — FOUND (commit cd84c13)
- `tests/live-mode-simulation.sh` — FOUND (102 lines, executable, passes)
- `.planning/phases/03-visible-live-mode/03-01-SUMMARY.md` — FOUND
- `.planning/phases/03-visible-live-mode/03-SUMMARY.md` — FOUND (this file)
- Commits `5c09fc1`, `cd84c13`, `7c15e33` — all FOUND in git log, all pushed
- Requirement RTUX-01 — to be marked Complete in REQUIREMENTS.md (below)
- 1 plan complete (03-01)
