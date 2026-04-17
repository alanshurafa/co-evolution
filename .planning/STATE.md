# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-06)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps
**Current focus:** Unification Absorb milestone - fold `codex-co-evolution/` + `co-evolution-lab/` into this public repo (phases 5-9)

## Current Position

Phase: 5 of 9 (Codex PS Preservation — first phase of Unification Absorb milestone)
Plan: 0 of 1 in current phase (not yet planned)
Status: Ready to plan
Last activity: 2026-04-17 - P0 Required-Section blocks committed (8b741ba); feature branch `feat/unification-absorb` open as draft PR #1
Working directory: `C:/Users/alan/Project/co-evolution-absorb/` (worktree on feat/unification-absorb)

Progress: [#####-----] 4/9 phases complete (milestone 1 of 2 done)

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 17 min
- Total execution time: 1.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Shared Shell Core | 1 | 0.3h | 0.3h |
| 2. Bouncer Refactor | 1 | 0.2h | 0.2h |
| 3. Codex Runtime | 1 | 0.5h | 0.5h |
| 4. Docs And Routing | 1 | 0.1h | 0.1h |

**Recent Trend:**
- Last 5 plans: 04-01, 03-01, 02-01, 01-01
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 0]: Reuse `skill/templates/` and `skill/schemas/` as the v1 shared prompt contract
- [Phase 0]: Keep execution visible through stepwise commits aligned to the external implementation plan
- [Phase 0]: Use a shared-core, platform-specific-shell architecture for the Claude and Codex runtimes
- [Phase 1]: Fail validation if a short-output retry returns empty content
- [Phase 1]: Allow `fill_conditional()` to replace scalar placeholders after removing tag lines
- [Phase 2]: Route WSL Bash Codex calls through `cmd.exe /c codex` with `wslpath` conversion
- [Phase 2]: Use the shared Codex adapter for run-name generation to preserve named bouncer runs
- [Phase 3]: Normalize Windows path arguments inside the Bash runtime before directory resolution
- [Phase 3]: Treat verifier auth failures as explicit review-needed exits rather than generic parse failures
- [Phase 4]: Route Codex by task shape between direct execution, Agent Bouncer, and the standalone runtime
- [Phase 4]: Use `dev-review/codex/instructions.md` as the reusable Codex startup router for this repo
- [Milestone: Unification Absorb]: Full merge of codex-co-evolution into this public repo (pseudonymity concern moot — no commits ever landed separately)
- [Milestone: Unification Absorb]: Feature branch + draft PR discipline; new worktree at `co-evolution-absorb/` isolated from `co-evolution/` (archive) and `co-evolution-clean/` (master tip)
- [Milestone: Unification Absorb]: Karpathy's `autoresearch` clone excluded from unified repo (unrelated ML training, not about bounce protocol)
- [Milestone: Unification Absorb]: Evals are the iteration mechanism (not Karpathy-style auto-research); Protocol Evolution Loop deferred as future post-absorb work
- [P0]: Required-Section blocks copied verbatim from upstream compose template to eliminate ~66% missing-section variance

### Pending Todos

- Plan Phase 5 (Codex PS Preservation) via `/gsd-plan-phase 5 --bounce` (dogfoods co-evolution on its own migration)
- Decide whether `runners/codex-ps/` absorbs a verbatim copy or git-filter-copy (codex-co-evolution has zero commits, so verbatim = simplest)
- Future: Bash port of PS eval harness (~2 days, deferred post-milestone)
- Future: Protocol Evolution Loop (meta-bounce for self-improving prompts, post-milestone)

### Blockers/Concerns

- Per-phase timeout (RNPT-05) is flagged by upstream as "single most painful gap" — one PS case hung 1h 39min. Prioritize during Phase 7 implementation.
- `pwsh` dependency introduced by Phase 8 — optional but required to run PS eval harness. Document clearly.
- Claude `--json-schema` broken on Windows in `-p` mode — must NOT be used; prompt-side JSON + parse-side validation only (PRTP-03)

## Session Continuity

Last session: 2026-04-17 (active)
Stopped at: Milestone kickoff — phases 5-9 planned, ready to enter Phase 5 planning
Resume file: None — use `git log feat/unification-absorb` for full context
Active PR: https://github.com/alanshurafa/co-evolution/pull/1 (draft)
Reference doc: `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (available after Phase 5) — the MUST/SHOULD/parity list
