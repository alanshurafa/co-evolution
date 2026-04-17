---
phase: 03-visible-live-mode
plan: 01
subsystem: dev-review-runtime
tags: [bash, cli, windows, observability, rtux-01]
requires: [01-code-review-fixes]
provides:
  - --live CLI flag and LIVE_MODE env var (default off = Phase 2 byte-parity)
  - is_windows_host platform-detection helper (OSTYPE msys*/cygwin* → wt.exe → cmd.exe)
  - maybe_launch_live_window helper — always returns 0, logs warning on failure, backgrounded + disowned
  - four call sites wired (compose, each bounce pass, execute, verify)
  - self-contained bash smoke test covering absent / non-Windows / simulated-Windows scenarios
affects: [dev-review-runtime, observability-layer]
tech-stack:
  added: []
  patterns:
    - "observability layer pattern — live-mode is an additive tail-window, not a state-model change (state.json schema unchanged)"
    - "platform detection priority: OSTYPE → wt.exe → cmd.exe (first match wins, cheap introspection)"
    - "backgrounded + disowned subshell for launchers so main shell never waits on the window"
    - "once-per-run warning guard (LIVE_MODE_WARNING_LOGGED) keeps non-Windows log output tidy"
    - "wt.exe stubbed via PATH shadowing + is_windows_host function override for cross-OS CI testing"
key-files:
  created:
    - tests/live-mode-simulation.sh
  modified:
    - lib/co-evolution.sh
    - dev-review/codex/dev-review.sh
key-decisions:
  - "Default LIVE_MODE=false — byte-parity with Phase 2 preserved; banner gains one 'Live mode:' line (analogous to Phase 2's 'Timeout:' addition)."
  - "Helper always returns 0 — launcher failures log a warning but never block the main phase (must-not-block invariant)."
  - "Single maybe_launch_live_window call before the codex/opus verify branch covers both verifier paths (no duplication)."
  - "Retry passes intentionally NOT wrapped per CONTEXT.md — reduces window noise during already-failing runs."
  - "tail-window approach chosen (main runner stays inline) — zero IPC, zero exit-code forwarding complexity."
patterns-established:
  - "platform-specific observability lives behind a boolean guard + a function override hook — tests can stub is_windows_host to simulate any platform"
  - "PATH-shadowing of .exe stubs enables Windows-path testing on Linux/macOS CI"
requirements-completed: [RTUX-01]
duration: 22min
completed: 2026-04-17
---

# Phase 3 Plan 1: Visible Live Mode Summary

**Added a `--live` CLI flag to the Codex dev-review runtime that launches a visible Windows Terminal window tailing each wrapped phase's stderr file (compose, each bounce pass, execute, verify). On non-Windows, or when both `wt.exe` and `cmd.exe` fail, the runner logs a single warning and proceeds inline — the main run never blocks. Default off preserves byte-parity with Phase 2.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-04-17 (feat/v1.1-polish)
- **Tasks:** 3
- **Commits:** 3 (atomic, per-task, all pushed)
- **Files modified:** 2 + 1 created

## Task Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | [`5c09fc1`](https://github.com/alanshurafa/co-evolution/commit/5c09fc1) | feat(live): add is_windows_host + maybe_launch_live_window helpers |
| 2 | [`cd84c13`](https://github.com/alanshurafa/co-evolution/commit/cd84c13) | feat(live): add --live flag and wrap four phase invocations |
| 3 | [`7c15e33`](https://github.com/alanshurafa/co-evolution/commit/7c15e33) | test(live): cover absent/non-windows/stubbed-windows scenarios |

## Files Created/Modified

| File | Change | Delta |
|------|--------|-------|
| `lib/co-evolution.sh` | modified | +73 / 0 (Task 1) |
| `dev-review/codex/dev-review.sh` | modified | +20 / 0 (Task 2) |
| `tests/live-mode-simulation.sh` | created | +102 lines (Task 3) |

## Architecture (1-paragraph future-archaeology note)

Two helpers landed in `lib/co-evolution.sh`: `is_windows_host` (priority-ordered detection: `$OSTYPE` msys/cygwin → `wt.exe` on PATH → `cmd.exe` on PATH → "false") and `maybe_launch_live_window "$phase_name" "$stderr_file"`. The latter is a no-op when `LIVE_MODE != "true"`, returns 0 even on launcher failure so the main run is never blocked, and logs a single once-per-run warning on non-Windows via a `LIVE_MODE_WARNING_LOGGED` guard. `dev-review.sh` picked up a `--live` CLI case (sets `LIVE_MODE=true`), four `maybe_launch_live_window` call sites (compose + per-bounce-pass + execute + verify), a one-line "Live mode: $LIVE_MODE" banner addition, and a usage help line. Retry branches are intentionally not wrapped — CONTEXT.md explicitly calls out that retry passes are already noisy and window-worthy only when they're first attempts. The smoke test uses function-override + PATH-shadowing stubs so Scenarios B (non-Windows forced) and C (simulated Windows + stubbed wt.exe) pass on any OS without a real Windows host — enabling CI that doesn't have `wt.exe` available.

## Test Output

```
$ bash tests/live-mode-simulation.sh
WARNING: --live is Windows-only (OSTYPE=msys); falling back to inline execution.
ALL SCENARIOS PASSED

real    0m0.650s
```

The WARNING line leaks to stdout because `log()` writes through `tee -a "$LOG_FILE"` — expected Bash behavior, not a test failure. All three scenarios (A, B, C) pass in under a second with no network, no real CLIs, no git repo required.

## Decisions Made

- **LIVE_MODE default is "false"** — byte-parity with Phase 2 preserved. The only new log line on a non-live run is the single "Live mode: false" banner entry, analogous to Phase 2's "Timeout:" addition.
- **Helper always returns 0** — even wt.exe and cmd.exe both failing logs a WARNING and returns 0. The main phase's exit code semantics are untouched.
- **Single verify call site** — one `maybe_launch_live_window` before the codex/opus verifier branch covers both (stderr file path is the same either way: `$RUN_DIR/review-stderr.log`).
- **Retry branches NOT wrapped** — CONTEXT.md "Skip wrapping: retry passes"; keeps window count reasonable during recovery scenarios.
- **Tail-window approach** — main runner stays inline, a side-car tail window is the observability layer. Zero IPC, zero exit-code forwarding complexity; planner's recommended strategy adopted verbatim.
- **OSTYPE msys* pattern** — primary detection signal; falls back to binary presence on PATH for WSL and bare Windows shells where OSTYPE may not be set.

## Deviations from Plan

**None.** Plan executed exactly as written. All acceptance criteria passed first time with no auto-fixes needed.

## Issues Encountered

- **CRLF warning on commit** of `tests/live-mode-simulation.sh` — same as Phase 2's `revise-loop-simulation.sh`. Git `core.autocrlf` normalizes on next touch; file runs correctly as-is (confirmed post-commit). No action needed.

## Threat Model Compliance

| Threat | Mitigation | Verified by |
|--------|-----------|-------------|
| T-03-01 (tampering via phase name) | Passed as `--title "$phase_name"` argv item, never as shell-interpolated text | Code inspection; phase names are literals or `bounce-${pass_padded}` (integer-derived) |
| T-03-02 (injection via stderr_file in `bash -c`) | `printf -v tail_cmd 'tail -f %q' "$stderr_file"` bash-quotes the path | Task 1 helper implementation; path source is internal `$RUN_DIR/*-stderr.log` only |
| T-03-04 (launcher self-DoS) | `& disown` + `|| true` ensures main shell never waits | Task 3 Scenario C: state.json byte-equality asserted after launch |
| T-03-06 (launcher privilege) | Only `wt.exe` / `cmd.exe` invoked, no registry/env-persistent writes | Code inspection; launcher command strings are static |

Accepted threats (per plan):
- **T-03-03 (orphaned tail processes across many runs)** — user-observable, acceptable for solo-dev workflow.
- **T-03-05 (stderr contents visible in a window)** — that's the feature; no new disclosure channel is opened.

## User Setup Required

None. Feature is opt-in via `--live` flag or `LIVE_MODE=true` env var; default off preserves all existing behavior.

## Follow-ups / Known Limits

- **Tail window lifecycle.** Windows opened by `--live` stay open after the phase exits (`tail -f` never returns). Users close them manually. Acceptable for v1.1 — a future enhancement could write a sentinel `### PHASE COMPLETE ###` line to the stderr file so a tail filter can self-terminate.
- **WSL not explicitly tested.** `is_windows_host` returns "true" when `cmd.exe` is reachable, which covers WSL; but Scenario C only simulates the check. Users running the runner from WSL may need to verify that `wt.exe new-tab` actually opens a visible window from inside WSL — should work (the bash that runs inside the window is the WSL bash via the stub path), but untested on real hardware today.
- **Retry passes are invisible when live.** Execute retry and bounce retry (inside `ensure_valid_plan_output`) are intentionally unwrapped. If a user debugging a flaky first-pass wants to see the retry stream too, they currently have to tail the retry-stderr file manually. Could be revisited if it becomes a pain point.

## Next Phase Readiness

- **Phase 3 closes RTUX-01.** Second of three RTUX requirements; only RTUX-02 (Phase 4, worktree management) remains in v1.1.
- **No blockers for Phase 4.** Phase 4 touches git branch/worktree setup before execute, which is orthogonal to the live-mode observability layer.

---
*Phase: 03-visible-live-mode*
*Plan: 01*
*Completed: 2026-04-17*
