# Requirements: Co-Evolution

**Core Value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps

> Completed requirements are archived per milestone under `.planning/milestones/`.
> This file tracks only requirements for the **active / next milestone**.

## Completed Milestones

- **v1.0 Unification Absorb** — 27/27 requirements Complete. See [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md).
- **v1.1 Polish & Ergonomics** — 6/6 requirements Complete (FIX-WR-01/02/03 + RTUX-01/02/03). See [`milestones/v1.1-REQUIREMENTS.md`](milestones/v1.1-REQUIREMENTS.md).

## Active Milestone

*No active milestone. Next: v1.2.*

## Deferred (candidates for v1.2+)

- **FIX-WR-04** — `INITIAL_GIT_DIRTY` captured from parent repo before `WORKDIR` is reassigned to worktree in `dev-review/codex/dev-review.sh`; triggers silent verify skip when parent is dirty AND worktree mode is active. Real interaction bug, narrow trigger. (From v1.1 code review.)
- **FIX-WR-05** — `git worktree add` and `git checkout -b` calls in `lib/co-evolution.sh` lack `--` argv terminator. Hardening gap, not security-exploitable. (From v1.1 code review.)
- **BASH-EVAL-01** — Bash port of the PowerShell eval harness (`run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`) — removes `pwsh` dependency from eval runs (~2 days estimated). Prerequisite for PEL.
- **META-01: Protocol Evolution Loop** — automated bounce-to-improve-the-bouncer using evals as fitness function. Design exploration complete; see `.planning/notes/pel-design-decisions.md` and related artifacts under `.planning/notes/`, `.planning/seeds/`, `.planning/research/`. Ready for `/gsd-new-milestone v1.2` kickoff.

---
*Active requirements reset at each milestone boundary. Historical requirements live in `milestones/vN.N-REQUIREMENTS.md`.*
