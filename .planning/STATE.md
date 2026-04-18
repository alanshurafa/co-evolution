---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Protocol Evolution Loop — Proposer Only
status: executing
stopped_at: Completed 02-03-PLAN.md — Phase 2 fully shipped (orchestrator + comparator + hermetic fake runner + Tier 1/2/3 gate 13/13 passing + README reframe); ready to advance to Phase 3 (Lab Scaffold)
last_updated: "2026-04-18T17:22:52.473Z"
last_activity: 2026-04-18 -- Phase 3 execution started
progress:
  total_phases: 8
  completed_phases: 2
  total_plans: 6
  completed_plans: 5
  percent: 83
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-17 for v1.2 kickoff)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps. From v1.2 onward co-evolution becomes self-improving via PEL (living in `lab/`) proposing protocol mutations for human review.
**Current focus:** Phase 3 — Lab Scaffold

## Current Position

Phase: 3 (Lab Scaffold) — EXECUTING
Plan: 1 of 2
Status: Executing Phase 3
Last activity: 2026-04-18 -- Phase 3 execution started
Working directory: `C:/Users/alan/Project/co-evolution-v12/` (branch `feat/v1.2-pel-proposer`)

Progress: Phase 2 — 3/3 plans complete

## Performance Metrics

**Velocity:**

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 02-bash-eval-harness-port | 01 | 4min 30s | 2 | 2 |
| 02-bash-eval-harness-port | 02 | 20min 53s | 2 | 1 |
| 02-bash-eval-harness-port | 03 | 18min 12s | 4 | 5 |

*Reset at milestone boundary. Historical velocity preserved in `.planning/milestones/v1.1-SUMMARY.md`.*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work (v1.2 kickoff):

- [v1.2 kickoff] PEL machinery lives entirely in `lab/pel/` — default runner (`co-evolve`, `dev-review`) stays byte-parity-invisible to users who never opt into `--lab pel-proposer`
- [v1.2 kickoff] Multi-flavor fitness (bug-catcher / faster / blind-spot / general) with auto-select + transparent override — classifier frozen in v1.2
- [v1.2 kickoff] Both-layer specialization: bounce-step × GSD-phase → ~3×3 matrix of mode combinations, flavors on top; eval harness must run bounces IN CONTEXT, not as isolated fixtures
- [v1.2 kickoff] Mutable surface = templates + policy + code → LLM proposer only for code tier (random mutation of shell produces syntax errors)
- [v1.2 kickoff] v1.2 ships Option 1 (Proposer Only); Options 2 + 3 (Auto-Promote, Explorer+Curator) stay seeded until trigger conditions met
- [v1.2 kickoff] Fold WR-04/WR-05 (v1.1 review non-blockers) into v1.2 Phase 1 rather than shipping a separate v1.1.1 patch — keeps release cadence tidy
- [v1.2 kickoff] Bash port of PS eval harness (BASH-EVAL-01) is a hard prerequisite for PEL — becomes Phase 2 of v1.2
- [Phase 02-bash-eval-harness-port]: evals/lib/co-evolution-evals.sh ports PS Yaml+Report+Fixture helpers to a single idempotent-sourceable Bash library; render_report uses {{TOKEN}} not {TOKEN}; merge_yaml_defaults uses jq * for PS Merge-HashtablesDeep semantics
- [Phase 02-bash-eval-harness-port]: evals/score-run.sh ports PS 7-dimension scorer to 675-LOC Bash with jq-based ISO8601 TZ parsing, awk-based Levenshtein with 4000-char cap and BOM strip, and MINGW grep -iF workaround via awk tolower+index()
- [Phase 02-bash-eval-harness-port]: evals/run-evals.sh (383 LOC) + evals/compare-reports.sh (154 LOC) + evals/tests/fake-runner.sh (177 LOC) + evals/tests/scorer-verification.sh (234 LOC) complete the Bash harness; --runner-path flag enables hermetic Tier 2 via fake-runner test double; scorer-verification.sh wires Tier 1 (10 fixtures) + Tier 2 (PASS + FAIL scenarios exercising robust_fails>0 branch) + Tier 3 (determinism) into a single '13/13 scenarios passed' gate on any Bash+jq+yq platform without pwsh — closes SC-3
- [Phase 02-bash-eval-harness-port]: fake-runner banner is ASCII 'FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION' (double-hyphen) not em-dash to dodge Git Bash Windows stdout quirks; state.json carries mode=fake-runner tag; lives under evals/tests/ (explicit test path per T-02-03-11)

### Pending Todos

- Create `C:/Users/alan/Project/co-evolution-v12/` worktree on `feat/v1.2-pel-proposer` branch before executing Phase 1
- Archive old local branches: `feat/v1.1-polish` (merged + remote deleted; local branch in co-evolution-v11 + co-evolution-clean can be safely deleted)
- Future: Re-evaluate seed `pel-auto-promote-and-explorer.md` when trigger conditions met (Option 1 ≥4 weeks production data + canary suite + Goodhart findings + lab conventions)

### Blockers/Concerns

- **PEL economics depend on platform upgrades:** Haiku 4.5 for verify-at-scale (~10× cheaper than Opus), prompt caching on stable bounce prompts (unlocks ≥100-run eval budgets), `/compute-guard` paired with any autonomous mode. Captured in `C:/Users/alan/.claude/projects/.../memory/future_tools.md`. Treat as assumed infrastructure, not stretch goals.
- **Goodhart's law is the default outcome** of optimizing any proxy metric hard enough. v1.2's mitigation is "human review gate on every mutation PR." v1.3+ needs deeper mitigations (RQ-001 in `.planning/research/questions.md`).
- **v1.1 code review warnings carried forward:** WR-04 (INITIAL_GIT_DIRTY captured before WORKDIR reassigned in worktree mode) and WR-05 (missing `--` argv terminators on git calls). Folded into v1.2 Phase 1 as FIX-WR-04 and FIX-WR-05.

## Session Continuity

Last session: 2026-04-18T13:57:31Z
Stopped at: Completed 02-03-PLAN.md — Phase 2 fully shipped (orchestrator + comparator + hermetic fake runner + Tier 1/2/3 gate 13/13 passing + README reframe); ready to advance to Phase 3 (Lab Scaffold)
Resume file: None
Active PR: None yet on v1.2 branch (not yet created)
Reference docs: v1.0 `.planning/milestones/v1.0-SUMMARY.md`, v1.1 `.planning/milestones/v1.1-SUMMARY.md`; upstream contract at `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (all v1.0 items closed); Phase 2 final: `.planning/phases/02-bash-eval-harness-port/02-03-SUMMARY.md`
