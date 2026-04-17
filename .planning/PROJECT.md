# Co-Evolution

## What This Is

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. It ships a standalone Agent Bouncer, a Claude Code `/dev-review` skill, a standalone Codex Bash runtime with parity to the PowerShell reference implementation, a portable eval harness (`evals/` + `schemas/`), and a read-only reference copy of the PS runtime at `runners/codex-ps/`.

## Current State

- **Latest milestone:** v1.0 Unification Absorb — shipped 2026-04-17 (PR #1 merged at `1f9b471`, tagged `v1.0`)
- **Summary:** `.planning/milestones/v1.0-SUMMARY.md`
- **Archived roadmap:** `.planning/milestones/v1.0-ROADMAP.md`
- **Archived requirements:** `.planning/milestones/v1.0-REQUIREMENTS.md`

## Next Milestone Goals

Deferred post-milestone work (to be scoped via `/gsd-new-milestone`):

- Bash port of the PowerShell eval harness (~2 days estimated)
- Protocol Evolution Loop — automated bounce-to-improve-the-bouncer using evals as fitness function
- RTUX-01/02/03 runtime ergonomics (visible terminals, auto worktrees, REVISE-loop auto-retry) — previously marked v2
- 3 non-blocking code review warnings from v1.0 (WR-01/02/03)

## Core Value

Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps.

## Requirements

### Validated

- [x] Agent Bouncer can bounce markdown documents between Claude and Codex using `[CONTESTED]` and `[CLARIFY]` markers - existing repo
- [x] Claude Code `/dev-review` workflow, prompt templates, and review schema already exist in `skills/dev-review/` - existing repo
- [x] Shared shell helpers extracted into `lib/co-evolution.sh` consumed by both Agent Bouncer and Codex runtime - Phase 1-2
- [x] Standalone Codex `dev-review` Bash runtime with compose-bounce-execute-verify and runtime flag support - Phase 3
- [x] Codex runtime documented and routable via `dev-review/codex/instructions.md` - Phase 4

### Active (Unification Absorb milestone, 2026-04-17)

- [ ] Absorb `codex-co-evolution/` verbatim into `runners/codex-ps/` as read-only reference implementation - Phase 5
- [ ] Parity Claude adapter with upstream tool-gating patterns and skip broken `--json-schema` flag - Phase 6
- [ ] Add structural bounce-check signal to complement semantic marker counting - Phase 6
- [ ] Port five runner-parity features to the Bash runner: agent dispatcher, writable-phase flag, delta tracking, structured state.json, per-phase timeout - Phase 7
- [ ] Elevate portable eval assets (cases, fixtures, plan, schema) to top-level `evals/` and `schemas/` - Phase 8
- [ ] Fold `co-evolution-lab/integrations/` + `mempalace.yaml` into unified repo - Phase 9

### Out of Scope

- Live visible Windows Codex windows - deferred to a later runtime pass (RTUX-01)
- Automatic branch or worktree management - deferred until the core Codex runtime is stable (RTUX-02)
- Moving `skill/` into `dev-review/claude/` - separate restructure, not part of this absorb
- Karpathy's `autoresearch` ML training repo (cloned under `co-evolution-lab/auto-research/`) - unrelated domain, kept as a peer project outside the unified repo
- Bash port of PS eval harness - deferred post-milestone (~2 days estimate from upstream)
- Protocol Evolution Loop (meta-bounce for self-improving prompts/adapters using evals as fitness function) - future work, requires eval case library to mature first

## Context

- The repo is intentionally lightweight: Bash plus Markdown templates, with no package manifest or automated test suite yet.
- `.planning/codebase/` already documents the current stack, architecture, conventions, testing gaps, and concerns.
- The immediate implementation driver is `C:/Users/alan/.claude/plans/fluffy-herding-mccarthy.md`, which lays out the shared-library extraction, bouncer refactor, Codex runtime script, and follow-on docs.
- The working tree already contains unrelated changes in `skill/SKILL.md`; execution for this initiative must keep that file out of scope.
- `CLAUDE.md` started as an untracked local file, but the current implementation plan now explicitly brings it into scope for the docs-and-routing phase. Keep edits narrow to the new Codex runtime context.

## Constraints

- **Tech stack**: Bash-first runtime plus Markdown templates - existing product surface should stay shell-native
- **Compatibility**: Preserve current Agent Bouncer behavior and artifact naming while extracting helpers
- **Shared assets**: Keep prompt templates and schema under `skill/` for v1 so the new runtime reuses existing contracts
- **Execution style**: Implement and commit in visible steps aligned with the external plan so progress is easy to inspect

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep `skill/templates/` and `skill/schemas/` as the shared prompt contract in v1 | Reuse current, working assets before any repo restructure | Pending |
| Introduce `lib/co-evolution.sh` as the shared shell core | Avoid duplicating helper functions across Agent Bouncer and Codex runtime | Pending |
| Split the work into stepwise commits that mirror the external plan | Maintains visibility and makes course-correction easier after each boundary | Pending |
| Use a shared-core, platform-specific-shell architecture | Claude Code and Codex have different orchestration models even while sharing prompts and shell helpers | Pending |
| Leave the Claude runtime implementation untouched in v1 | Limits risk while the standalone Codex runtime proves the pipeline outside Claude Code | Pending |
| Keep `Co-Evolution` as the umbrella name, `dev-review` as the workflow product, and `agent-bouncer` as the generic bounce engine | Preserves naming clarity across docs, scripts, and future restructuring | Pending |
| Full merge of `codex-co-evolution/` into this public repo under `runners/codex-ps/` | No commits ever landed in the private repo so pseudonymity concern is moot; verbatim file copy preserves reference audit trail | Pending |
| Exclude Karpathy's `autoresearch` from unified repo | Unrelated ML training domain; keep focused on bounce protocol; peer project at workspace root | Pending |
| Evals are the iteration mechanism, not a Karpathy-style auto-research | Measurement layer already surfaced 8 bugs + 1 scorer blindness missed by 11 pilot bounces; add Protocol Evolution Loop only after case library matures | Pending |
| Feature branch + draft PR discipline via dedicated worktree at `co-evolution-absorb/` | Disposable escape hatch; holistic diff view vs master; reviewable as single unit at end | Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check -> still the right priority?
3. Audit Out of Scope -> reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-17 kicking off Unification Absorb milestone (phases 5-9); v1 requirements moved to Validated, v3 requirements added to Active*
