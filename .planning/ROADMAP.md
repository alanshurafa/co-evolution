# Roadmap: Co-Evolution

## Overview

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. The roadmap tracks milestone cycles; completed milestones are archived to `.planning/milestones/`.

## Completed Milestones

- [x] **v1.0 Unification Absorb** (shipped 2026-04-17) — Codex runtime foundation + absorbed private reference impl + eval harness + runner parity. 9 phases, 27 requirements closed. See [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) · [`milestones/v1.0-SUMMARY.md`](milestones/v1.0-SUMMARY.md) · [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md)

## Active Milestone

None. Start the next one with `/gsd-new-milestone`.

## Deferred (candidates for next milestone)

Carried forward from v1.0 completion. Scope via `/gsd-new-milestone` when ready:

- **Bash port of PS eval harness** (~2 days estimated) — remove `pwsh` dependency from eval runs
- **Protocol Evolution Loop** — automated bounce-to-improve-the-bouncer using evals as fitness function (meta-bounce on prompts/adapters)
- **RTUX-01** — Codex runtime can launch visible Windows terminals for live pass-by-pass observation
- **RTUX-02** — Codex runtime can create and manage dedicated branches or worktrees automatically
- **RTUX-03** — Codex runtime can loop automatically on REVISE verdicts until approval or user stop
- **Code review follow-ups** — 3 non-blocking warnings from v1.0 review (stale `LAST_INVOKE_EXIT_CODE` in codex verify branch; temp-file leak on jq failure in state helpers; phase-start timestamp global coupling)
