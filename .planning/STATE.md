---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Phase 5 complete — runners/codex-ps/ verbatim copy + REFERENCE-STATUS.md landed; ready for Phase 6 (Protocol Parity)
last_updated: "2026-04-17T18:00:00.000Z"
last_activity: 2026-04-17 -- Phase 05 execution complete
progress:
  total_phases: 9
  completed_phases: 5
  total_plans: 6
  completed_plans: 5
  percent: 83
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-06)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps
**Current focus:** Unification Absorb milestone - fold `codex-co-evolution/` + `co-evolution-lab/` into this public repo (phases 5-9)

## Current Position

Phase: 6 of 9 (Protocol Parity — ready to plan)
Plan: 1 of 1 in previous phase complete (05-01 landed)
Status: Ready to plan Phase 6
Last activity: 2026-04-17 -- Phase 05 execution complete
Working directory: `C:/Users/alan/Project/co-evolution-absorb/` (worktree on feat/unification-absorb)

Progress: [######----] 5/9 phases complete (Phase 5 of Unification Absorb done)

## Performance Metrics

**Velocity:**

- Total plans completed: 5
- Average duration: 16 min
- Total execution time: 1.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Shared Shell Core | 1 | 0.3h | 0.3h |
| 2. Bouncer Refactor | 1 | 0.2h | 0.2h |
| 3. Codex Runtime | 1 | 0.5h | 0.5h |
| 4. Docs And Routing | 1 | 0.1h | 0.1h |
| 5. Codex PS Preservation | 1 | 0.25h | 0.25h |

**Recent Trend:**

- Last 5 plans: 05-01, 04-01, 03-01, 02-01, 01-01
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
- [Phase 5]: Verbatim file copy (not subtree merge) chosen because codex-co-evolution had zero commits — no history to preserve
- [Phase 5]: Read-only declaration goes in a dedicated REFERENCE-STATUS.md file, never injected into upstream content, to preserve byte-level verbatim guarantee
- [Milestone: Unification Absorb]: Full merge of codex-co-evolution into this public repo (pseudonymity concern moot — no commits ever landed separately)
- [Milestone: Unification Absorb]: Feature branch + draft PR discipline; new worktree at `co-evolution-absorb/` isolated from `co-evolution/` (archive) and `co-evolution-clean/` (master tip)
- [Milestone: Unification Absorb]: Karpathy's `autoresearch` clone excluded from unified repo (unrelated ML training, not about bounce protocol)
- [Milestone: Unification Absorb]: Evals are the iteration mechanism (not Karpathy-style auto-research); Protocol Evolution Loop deferred as future post-absorb work
- [P0]: Required-Section blocks copied verbatim from upstream compose template to eliminate ~66% missing-section variance

### Pending Todos

- Plan Phase 6 (Protocol Parity) — implement MUST-items 3-6 from runners/codex-ps/evals/UPSTREAM-MESSAGE.md (Claude adapter tool-gating, skip --json-schema, structural bounce check, bounce-protocol reconciliation)
- Archive `C:/Users/alan/Project/codex-co-evolution/` workspace — verbatim copy is now safely preserved at runners/codex-ps/ (decision unblocked by Phase 5 completion)
- Future: Bash port of PS eval harness (~2 days, deferred post-milestone)
- Future: Protocol Evolution Loop (meta-bounce for self-improving prompts, post-milestone)

### Blockers/Concerns

- Per-phase timeout (RNPT-05) is flagged by upstream as "single most painful gap" — one PS case hung 1h 39min. Prioritize during Phase 7 implementation.
- `pwsh` dependency introduced by Phase 8 — optional but required to run PS eval harness. Document clearly.
- Claude `--json-schema` broken on Windows in `-p` mode — must NOT be used; prompt-side JSON + parse-side validation only (PRTP-03)

## Session Continuity

Last session: 2026-04-17 (active)
Stopped at: Phase 5 execution complete — runners/codex-ps/ verbatim copy + REFERENCE-STATUS.md landed (commits 438e435, ccc3418, pushed); ready for Phase 6 planning
Resume file: None — use `git log feat/unification-absorb` for full context
Active PR: https://github.com/alanshurafa/co-evolution/pull/1 (draft)
Reference doc: `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` — the MUST/SHOULD/parity list (NOW AVAILABLE at runners/codex-ps/evals/UPSTREAM-MESSAGE.md)
