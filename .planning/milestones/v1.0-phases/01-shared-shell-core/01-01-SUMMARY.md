---
phase: 01-shared-shell-core
plan: 01
subsystem: infra
tags: [bash, shell, templates, validation, codex, claude]
requires: []
provides:
  - shared shell helper library for Claude and Codex adapters
  - reusable output validation, marker counting, template filling, and verdict parsing helpers
  - fail-closed retry handling for empty post-retry output
affects: [02-bouncer-refactor, 03-codex-runtime, shared-shell-helpers]
tech-stack:
  added: []
  patterns: [side-effect-free sourced shell library, scalar placeholder substitution with explicit large-content injection, stdin-based conditional block handling]
key-files:
  created: []
  modified: [lib/co-evolution.sh]
key-decisions:
  - "Keep `fill_template()` scalar-only and leave large content injection such as `{PLAN_CONTENT}` to callers."
  - "Treat empty output after a short-output retry as a fatal validation failure."
  - "Make `fill_conditional()` preserve content while also applying placeholder substitutions."
patterns-established:
  - "Shared shell helpers are sourced with no output or filesystem side effects."
  - "Validation retries fail closed when the retry output is empty."
requirements-completed: [CORE-01, CORE-02]
duration: 16min
completed: 2026-04-06
---

# Phase 1: Shared Shell Core Summary

**Shared Bash helper library for Claude and Codex runtimes with validated template, marker, verdict, and retry behavior**

## Performance

- **Duration:** 16 min
- **Started:** 2026-04-06T19:18:00-04:00
- **Completed:** 2026-04-06T19:34:24-04:00
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Confirmed `lib/co-evolution.sh` is source-safe and exposes the Phase 1 helper surface.
- Hardened `validate_output()` so an empty retry after short-output detection aborts instead of silently passing through.
- Upgraded `fill_conditional()` to remove conditional tags and fill scalar placeholders for downstream prompt assembly.
- Verified helper behavior with Bash snippets covering sourcing, placeholder filling, marker filtering, conditional handling, verdict parsing, and retry failure handling.

## Task Commits

No task commits were created in this execution pass.

## Files Created/Modified
- `lib/co-evolution.sh` - Shared shell helper library for agent adapters, output validation, template processing, and verdict parsing

## Decisions Made
- Kept `fill_template()` limited to scalar replacements so callers can inject large content blocks explicitly and safely.
- Treated empty output after a short-output retry as fatal because accepting it would corrupt downstream orchestration.
- Preserved the stdin-filter shape for conditional helpers so later prompt assembly can pipe templates through them directly.

## Deviations from Plan

Minor execution deviation: the library already existed at the start of execution, so this pass tightened and validated it instead of creating it from scratch. No scope creep.

## Issues Encountered

- PowerShell here-string piping introduced a BOM into an initial Bash validation run. Resolved by writing an ASCII temp script before executing the validation suite.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 1 deliverable is ready for the Agent Bouncer refactor in Phase 2.
- The next phase can rely on the shared helpers for adapter invocation, validation, marker counting, conditional handling, and verdict parsing.

---
*Phase: 01-shared-shell-core*
*Completed: 2026-04-06*
