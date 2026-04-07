---
phase: 03-codex-runtime
plan: 01
subsystem: infra
tags: [bash, shell, codex, claude, verification, wsl]
requires:
  - phase: 02-bouncer-refactor
    provides: shared shell helper usage and WSL-safe Codex execution from Bash
provides:
  - standalone Codex dev-review runtime script
  - Windows-path normalization for Bash-launched runtime arguments
  - clear non-success handling when verifier auth is unavailable
affects: [04-docs-and-routing, codex-runtime, verifier-behavior]
tech-stack:
  added: []
  patterns: [Windows path normalization before Bash directory resolution, WSL guardrails for Codex workdirs, structured Codex verification via schema output]
key-files:
  created: []
  modified: [dev-review/codex/dev-review.sh]
key-decisions:
  - "Normalize Windows `--workdir` and `--plan` paths inside Bash so PowerShell-launched runs work."
  - "Use a dedicated Codex-schema verifier path for structured JSON output."
  - "Surface expired verifier authentication as an explicit warning and exit 2 instead of a generic parse failure."
patterns-established:
  - "Codex runtime arguments may arrive as Windows paths and should be normalized before any `cd` or file checks."
  - "Verifier transport failures should degrade into a review-needed status, not a misleading success."
requirements-completed: [CDRT-01, CDRT-02, CDRT-03, CDRT-04]
duration: 35min
completed: 2026-04-06
---

# Phase 3: Codex Runtime Summary

**Standalone Bash-hosted Codex dev-review runtime with compose, bounce, execute, skip-plan, and verifier fallback behavior**

## Performance

- **Duration:** 35 min
- **Started:** 2026-04-06T21:47:00-04:00
- **Completed:** 2026-04-06T22:21:42-04:00
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Completed `dev-review/codex/dev-review.sh` so it can compose, bounce, execute, and optionally verify using the shared shell helpers and prompt assets.
- Added WSL-aware normalization for Windows `--workdir` and `--plan` inputs, plus an early guard when Codex would otherwise target an unsupported `\\wsl.localhost\...` workspace.
- Added a dedicated Codex schema-verification path and clearer verifier-auth failure handling.
- Smoke-tested plan-only, bounce, execute, and skip-plan modes in disposable Windows temp repos and workdirs.

## Task Commits

No task commits were created in this execution pass.

## Files Created/Modified
- `dev-review/codex/dev-review.sh` - Standalone Codex runtime for compose, bounce, execute, and optional verify orchestration

## Decisions Made
- Normalize Windows paths inside the runtime instead of assuming it is always launched from an already-normalized Bash working directory.
- Keep Codex structured verification local to the runtime because it needs schema-specific output handling beyond the base shared adapter.
- Treat verifier authentication failures as explicit review blockers and return exit code `2` so callers can decide whether to retry or review manually.

## Deviations from Plan

### Auto-fixed Issues

**1. [Blocking] PowerShell-launched Bash runs could not use Windows `--workdir` paths**
- **Found during:** Task 3 (plan-only smoke test)
- **Issue:** `bash dev-review.sh --workdir C:\...` failed because Bash tried to `cd` into the raw Windows path.
- **Fix:** Added Windows-path normalization for `--workdir` and `--plan` before directory resolution and file checks.
- **Files modified:** `dev-review/codex/dev-review.sh`
- **Verification:** Plan-only, execute, and skip-plan smoke tests all succeeded when launched with Windows temp paths.
- **Committed in:** Not committed in this execution pass

**2. [Clarity] Verifier auth expiry surfaced as a generic parse warning**
- **Found during:** Task 3 (verify smoke test)
- **Issue:** Expired Claude auth produced an unreadable verdict state even though the runtime correctly avoided success.
- **Fix:** Added explicit verifier-auth detection and warning text before the generic verdict parser path.
- **Files modified:** `dev-review/codex/dev-review.sh`
- **Verification:** Verify smoke test now exits `2` with a clear auth-refresh warning.
- **Committed in:** Not committed in this execution pass

---

**Total deviations:** 2 auto-fixed (2 blocking/clarity)
**Impact on plan:** Both fixes were necessary to make the runtime usable from the actual Windows-hosted Bash environment. No feature scope expanded beyond the runtime contract.

## Issues Encountered

- Claude CLI authentication is currently expired in this environment, so the verify smoke test could not produce an APPROVED or REVISE verdict from Opus.
- The runtime now reports that condition explicitly and exits `2`, which matches the plan's non-success review-needed path.

## User Setup Required

None for the runtime itself.

To fully exercise Opus-backed verification later, refresh the local Claude CLI session.

## Next Phase Readiness

- Phase 3 runtime work is complete and ready for the docs-and-routing pass.
- Phase 4 can document the runtime exactly as implemented, including Windows-path handling and the verifier-auth caveat.

---
*Phase: 03-codex-runtime*
*Completed: 2026-04-06*
