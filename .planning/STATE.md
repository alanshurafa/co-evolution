---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Protocol Evolution Loop — Proposer Only
status: defining_requirements
stopped_at: v1.2 milestone kickoff — PROJECT.md updated, requirements and roadmap pending; design exploration already complete in .planning/notes/pel-design-decisions.md
last_updated: "2026-04-17T22:00:00.000Z"
last_activity: 2026-04-17 -- v1.2 started; PROJECT.md reflects lab/core split, requirements + roadmap to follow
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-17 for v1.2 kickoff)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps. From v1.2 onward co-evolution becomes self-improving via PEL (living in `lab/`) proposing protocol mutations for human review.
**Current focus:** v1.2 Protocol Evolution Loop — Proposer Only. PEL machinery lives entirely in `lab/pel/`; default runner unchanged for users who never invoke `--lab pel-proposer`.

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-17 — v1.2 Protocol Evolution Loop milestone started; design exploration complete
Working directory (recommended): `C:/Users/alan/Project/co-evolution-v12/` (not yet created — user to create on `feat/v1.2-pel-proposer` branch before phase 1 execution)

Progress: [          ] 0/0 phases complete — defining requirements

## Performance Metrics

**Velocity:**

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

### Pending Todos

- Create `C:/Users/alan/Project/co-evolution-v12/` worktree on `feat/v1.2-pel-proposer` branch before executing Phase 1
- Archive old local branches: `feat/v1.1-polish` (merged + remote deleted; local branch in co-evolution-v11 + co-evolution-clean can be safely deleted)
- Future: Re-evaluate seed `pel-auto-promote-and-explorer.md` when trigger conditions met (Option 1 ≥4 weeks production data + canary suite + Goodhart findings + lab conventions)

### Blockers/Concerns

- **PEL economics depend on platform upgrades:** Haiku 4.5 for verify-at-scale (~10× cheaper than Opus), prompt caching on stable bounce prompts (unlocks ≥100-run eval budgets), `/compute-guard` paired with any autonomous mode. Captured in `C:/Users/alan/.claude/projects/.../memory/future_tools.md`. Treat as assumed infrastructure, not stretch goals.
- **Goodhart's law is the default outcome** of optimizing any proxy metric hard enough. v1.2's mitigation is "human review gate on every mutation PR." v1.3+ needs deeper mitigations (RQ-001 in `.planning/research/questions.md`).
- **v1.1 code review warnings carried forward:** WR-04 (INITIAL_GIT_DIRTY captured before WORKDIR reassigned in worktree mode) and WR-05 (missing `--` argv terminators on git calls). Folded into v1.2 Phase 1 as FIX-WR-04 and FIX-WR-05.

## Session Continuity

Last session: 2026-04-17 (active — v1.2 kickoff in progress)
Stopped at: PROJECT.md refresh complete; REQUIREMENTS.md + ROADMAP.md to follow in this same session; then recommend user creates co-evolution-v12 worktree for Phase 1 execution.
Resume file: `.planning/notes/pel-design-decisions.md` — binding design decisions; `.planning/notes/co-evolution-lab-concept.md` — lab architecture conventions; `.planning/seeds/pel-auto-promote-and-explorer.md` — deferred Options 2+3 with trigger conditions; `.planning/research/questions.md` — RQ-001 Goodhart
Active PR: None yet on v1.2 branch (not yet created)
Reference docs: v1.0 `.planning/milestones/v1.0-SUMMARY.md`, v1.1 `.planning/milestones/v1.1-SUMMARY.md`; upstream contract at `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (all v1.0 items closed)
