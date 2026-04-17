# Requirements: Co-Evolution

**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps

> Completed requirements are archived per milestone under `.planning/milestones/`.
> This file tracks only requirements for the **active / next milestone**.

## Completed Milestones

- **v1.0 Unification Absorb** — 27/27 requirements Complete (10 v1 CORE/BNCR/CDRT/DOCS + 17 v3 CXPS/PRTP/RNPT/EVAL/LABF). See [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md) for full traceability.

## Carried Forward (deferred — candidates for next milestone)

These were scoped but not shipped in v1.0. Scope via `/gsd-new-milestone` when ready.

### Runtime Ergonomics (from v2 bucket)

- **RTUX-01**: Codex runtime can launch visible Windows terminals for live pass-by-pass observation
- **RTUX-02**: Codex runtime can create and manage dedicated branches or worktrees automatically
- **RTUX-03**: Codex runtime can loop automatically on REVISE verdicts until approval or user stop

### Post-v1.0 Follow-ups (from code review + deferred-ideas)

- **BASH-EVAL-01**: Bash port of the PowerShell eval harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) — removes `pwsh` dependency from eval runs (~2 days estimated)
- **META-01**: Protocol Evolution Loop — automated bounce-to-improve-the-bouncer using evals as fitness function. Reads eval failures, proposes protocol/prompt/adapter deltas, bounces them, scores against the same cases, keeps improvements.
- **FIX-WR-01**: Reset `LAST_INVOKE_EXIT_CODE=0` before the codex verify conditional at `dev-review/codex/dev-review.sh:768-776` (latent, not firing today)
- **FIX-WR-02**: Clean up `mktemp` temp files on jq failure in `write_state_phase` / `write_state_field` (cosmetic leak in `$TMPDIR`)
- **FIX-WR-03**: Pass phase-start timestamps as explicit function args rather than relying on enclosing-scope globals with `${var:-fallback}` fallback pattern

## Active Requirements

None. Start the next milestone via `/gsd-new-milestone` to populate this section.

---
*Active requirements reset at each milestone boundary. Historical requirements live in `milestones/vN.N-REQUIREMENTS.md`.*
