# Roadmap: Co-Evolution

## Overview

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. The roadmap tracks milestone cycles; completed milestones are archived to `.planning/milestones/`.

## Completed Milestones

- [x] **v1.0 Unification Absorb** (shipped 2026-04-17) — Codex runtime foundation + absorbed private reference impl + eval harness + runner parity. 9 phases, 27 requirements closed. See [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) · [`milestones/v1.0-SUMMARY.md`](milestones/v1.0-SUMMARY.md) · [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md)
- [x] **v1.1 Polish & Ergonomics** (shipped 2026-04-17) — v1.0 code review fixes (WR-01/02/03) + runtime ergonomics (REVISE auto-loop, visible live mode, branch/worktree management). 4 phases, 6 requirements closed. PR [#2](https://github.com/alanshurafa/co-evolution/pull/2) · See [`milestones/v1.1-ROADMAP.md`](milestones/v1.1-ROADMAP.md) · [`milestones/v1.1-SUMMARY.md`](milestones/v1.1-SUMMARY.md) · [`milestones/v1.1-REQUIREMENTS.md`](milestones/v1.1-REQUIREMENTS.md)

## Active Milestone

*No active milestone. Next: v1.2 (PEL Proposer Only — design exploration complete, see `.planning/notes/pel-design-decisions.md`).*

## Deferred (candidates for v1.2+)

- **v1.1 follow-ups (WR-04, WR-05)** — interaction bug with worktree+dirty-parent+verify; missing `--` argv terminators on `git worktree add` and `git checkout -b`. Both narrow-trigger, non-blocking from v1.1 review.
- **BASH-EVAL-01** — Bash port of PowerShell eval harness (~2 days) — removes `pwsh` dependency from eval runs. Prerequisite for PEL.
- **META-01: Protocol Evolution Loop (PEL)** — automated bounce-to-improve-the-bouncer using evals as fitness function. Design exploration shipped with v1.1; artifacts at `.planning/notes/pel-design-decisions.md`, `.planning/notes/co-evolution-lab-concept.md`, `.planning/seeds/pel-auto-promote-and-explorer.md`, `.planning/research/questions.md`. Ready for `/gsd-new-milestone v1.2` kickoff.
