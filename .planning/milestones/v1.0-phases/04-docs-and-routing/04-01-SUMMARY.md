---
phase: 04-docs-and-routing
plan: 01
subsystem: docs
tags: [docs, routing, codex, claude, bash]
requires:
  - phase: 03-codex-runtime
    provides: standalone Codex runtime behavior and supported CLI surface
provides:
  - Codex routing instructions for Co-Evolution entrypoints
  - standalone Codex runtime README
  - repo-level discovery for the Codex runtime
affects: [README, CLAUDE, dev-review-codex, docs]
tech-stack:
  added: []
  patterns: [route by task shape, startup instruction file for Codex, repo-level runtime discovery]
key-files:
  created: [dev-review/codex/instructions.md, dev-review/codex/README.md]
  modified: [README.md, CLAUDE.md]
key-decisions:
  - "Route Codex by task shape between direct execution, Agent Bouncer, and the standalone dev-review runtime."
  - "Document `instructions.md` as a reusable Codex startup router while keeping a stdin fallback for stock `codex exec`."
  - "Keep the `CLAUDE.md` update narrow and leave the Claude-side `/dev-review` skill untouched in v1."
patterns-established:
  - "Codex routing should prefer the lowest-ceremony entrypoint that still matches task risk and artifact needs."
  - "Repo-level docs should link the standalone Codex runtime back to Agent Bouncer and the Claude skill instead of presenting it as a separate product."
requirements-completed: [DOCS-01, DOCS-02]
duration: 5min
completed: 2026-04-06
---

# Phase 4: Docs And Routing Summary

**Codex runtime routing instructions, standalone runtime docs, and repo-level discovery updates**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-06T22:50:50-04:00
- **Completed:** 2026-04-06T22:55:50-04:00
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Created `dev-review/codex/instructions.md` as the Codex-facing router between direct execution, `agent-bouncer.sh`, and `dev-review.sh`.
- Added `dev-review/codex/README.md` with runtime purpose, CLI options, command examples, startup-instructions guidance, trust caveats, and exit behavior.
- Updated the root `README.md` so the standalone Codex runtime is discoverable from the repo entrypoint.
- Added a narrow `CLAUDE.md` section that records the new runtime surface without changing the existing Claude skill structure.

## Task Commits

No task commits were created in this execution pass.

## Files Created/Modified

- `dev-review/codex/instructions.md` - Codex routing rules for choosing direct execution, Agent Bouncer, or the standalone runtime
- `dev-review/codex/README.md` - Usage, examples, startup-instructions guidance, and safety notes for the Codex runtime
- `README.md` - Repo-level discovery path for the standalone Codex runtime
- `CLAUDE.md` - Narrow project-context addition for the new Codex runtime surface

## Decisions Made

- Put the routing logic in a dedicated `instructions.md` file so it can be reused as Codex startup guidance instead of duplicating routing rules in multiple places.
- Keep the runtime README honest about `codex exec`: document `--instructions` as wrapper-dependent and give a portable stdin fallback for the stock CLI.
- Treat the Claude skill and the standalone Codex runtime as parallel surfaces that share prompt/schema assets rather than as a repo restructure in this phase.

## Deviations from Plan

None - the plan executed as written.

## Issues Encountered

- The local Claude CLI auth expiry still prevents live Opus-backed verification in this environment, but that does not block the docs-and-routing deliverables for Phase 4.

## User Setup Required

None.

## Next Phase Readiness

- Phase 4 completes the current roadmap.
- The repo is ready for milestone wrap-up or a new follow-on phase focused on runtime ergonomics if needed.

---
*Phase: 04-docs-and-routing*
*Completed: 2026-04-06*
