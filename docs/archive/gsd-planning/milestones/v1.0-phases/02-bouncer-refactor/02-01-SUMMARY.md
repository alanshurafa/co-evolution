---
phase: 02-bouncer-refactor
plan: 01
subsystem: infra
tags: [bash, shell, codex, wsl, portability, regression]
requires:
  - phase: 01-shared-shell-core
    provides: shared helper surface for adapter invocation, validation, marker counting, and content stripping
provides:
  - agent-bouncer entrypoint sourced from the shared shell library
  - WSL-safe Codex adapter behavior for Bash-hosted runs
  - regression-validated bouncer artifact contract
affects: [03-codex-runtime, wsl-codex-adapter, shared-shell-helpers]
tech-stack:
  added: []
  patterns: [route WSL Codex calls through cmd.exe with Windows path conversion, use shared adapters for auxiliary Codex prompts such as run-name generation]
key-files:
  created: []
  modified: [agent-bouncer/agent-bouncer.sh, lib/co-evolution.sh]
key-decisions:
  - "Use `cmd.exe /c codex` with `wslpath` conversion when Bash is running under WSL."
  - "Route Agent Bouncer run-name generation through `invoke_codex()` instead of a direct Codex call."
patterns-established:
  - "Bash-hosted Codex invocations on Windows should use the shared adapter, not raw `codex` or `codex.cmd`."
  - "Regression runs should verify raw output, clean output, run naming, and stderr artifact capture together."
requirements-completed: [BNCR-01, BNCR-02]
duration: 13min
completed: 2026-04-06
---

# Phase 2: Bouncer Refactor Summary

**Agent Bouncer now rides the shared shell core and passes a Codex-in-Bash regression run on this Windows-hosted environment**

## Performance

- **Duration:** 13 min
- **Started:** 2026-04-06T19:34:30-04:00
- **Completed:** 2026-04-06T19:47:30-04:00
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Verified `agent-bouncer/agent-bouncer.sh` is syntax-clean and already sources `lib/co-evolution.sh` for validation, stripping, and marker counting.
- Fixed the shared Codex adapter so Bash-hosted WSL runs call the working Windows launcher path via `cmd.exe /c codex` with converted `-C` and `-o` paths.
- Moved run-name generation onto the shared Codex adapter so the bouncer preserves named runs even when raw Bash `codex` is broken.
- Ran a disposable regression bounce with Codex on the reviewer pass and confirmed raw output, clean output, run naming, and run-log artifact layout.

## Task Commits

No task commits were created in this execution pass.

## Files Created/Modified
- `agent-bouncer/agent-bouncer.sh` - Shared-adapter-backed run-name generation for Codex naming prompts
- `lib/co-evolution.sh` - WSL-safe Codex execution path and stdout suppression for `-o` based runs

## Decisions Made
- Route WSL Codex invocations through `cmd.exe /c codex` rather than `codex` or `codex.cmd`.
- Suppress adapter stdout because the Windows Codex path still prints content even when `-o` is set, which would otherwise corrupt bouncer logs.
- Keep the portability fix in the shared library so the Phase 3 standalone Codex runtime inherits it automatically.

## Deviations from Plan

### Auto-fixed Issues

**1. [Blocking] WSL-hosted Bash could not execute Codex correctly**
- **Found during:** Task 3 (regression bounce)
- **Issue:** Raw `codex` failed under Bash with a missing Linux optional dependency, and raw `codex.cmd` executed as batch text instead of a command.
- **Fix:** Updated `invoke_codex()` to use `cmd.exe /c codex` with `wslpath` conversion under WSL, then reran the regression bounce.
- **Files modified:** `lib/co-evolution.sh`
- **Verification:** Regression bounce completed successfully with Codex and produced the expected run artifacts.
- **Committed in:** Not committed in this execution pass

**2. [Behavior Preservation] Run-name generation bypassed the shared adapter**
- **Found during:** Task 3 (regression bounce)
- **Issue:** Agent Bouncer still called raw `codex exec` for run naming, so named runs degraded to fallback labels in the failing Bash environment.
- **Fix:** Switched run-name generation to call `invoke_codex()` with temporary prompt and output files.
- **Files modified:** `agent-bouncer/agent-bouncer.sh`
- **Verification:** Regression run produced `bouncer-bouncer-regression-test-*` instead of the fallback `bouncer-run-*`.
- **Committed in:** Not committed in this execution pass

---

**Total deviations:** 2 auto-fixed (2 blocking/behavior-preservation)
**Impact on plan:** Both fixes were necessary to preserve the intended runtime contract on the actual Bash host. No scope creep beyond the shared adapter and bouncer entrypoint.

## Issues Encountered

- The initial regression bounce failed because Bash resolved `codex` to a launcher that expected `@openai/codex-linux-x64`.
- Direct `codex.cmd` invocation from Bash failed because the batch file was interpreted as shell text.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 2 is complete and the shared Codex adapter now works in the Bash host environment needed for Phase 3.
- The standalone Codex runtime can reuse the shared adapter behavior instead of rediscovering the WSL launcher issue later.

---
*Phase: 02-bouncer-refactor*
*Completed: 2026-04-06*
