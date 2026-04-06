# Co-Evolution

## What This Is

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. It already ships a standalone Agent Bouncer and a Claude Code `/dev-review` skill, and the current initiative is to add a standalone Codex runtime for the same compose-bounce-execute-verify workflow.

## Core Value

Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps.

## Requirements

### Validated

- ✓ Agent Bouncer can bounce markdown documents between Claude and Codex using `[CONTESTED]` and `[CLARIFY]` markers — existing repo
- ✓ Claude Code `/dev-review` workflow, prompt templates, and review schema already exist in `skill/` — existing repo

### Active

- [ ] Extract shared shell helpers into a reusable library for Co-Evolution runtimes
- [ ] Refactor Agent Bouncer to consume the shared library without changing its artifact contract
- [ ] Add a standalone Codex runtime for `dev-review` that can compose, bounce, execute, and optionally verify
- [ ] Support shell-friendly runtime options for plan-only, skip-plan, model override, and working directory control
- [ ] Document the Codex runtime and route Codex toward the right Co-Evolution entrypoint

### Out of Scope

- Live visible Windows Codex windows — deferred to a later runtime pass
- Automatic branch or worktree management — deferred until the core Codex runtime is stable
- Moving `skill/` into `dev-review/claude/` — separate restructure, not part of this implementation pass

## Context

- The repo is intentionally lightweight: Bash plus Markdown templates, with no package manifest or automated test suite yet.
- `.planning/codebase/` already documents the current stack, architecture, conventions, testing gaps, and concerns.
- The immediate implementation driver is `C:/Users/alan/.claude/plans/fluffy-herding-mccarthy.md`, which lays out the shared-library extraction, bouncer refactor, Codex runtime script, and follow-on docs.
- The working tree already contains unrelated changes in `skill/SKILL.md` and an untracked `CLAUDE.md`; execution for this initiative must avoid pulling those into commits.

## Constraints

- **Tech stack**: Bash-first runtime plus Markdown templates — existing product surface should stay shell-native
- **Compatibility**: Preserve current Agent Bouncer behavior and artifact naming while extracting helpers
- **Shared assets**: Keep prompt templates and schema under `skill/` for v1 so the new runtime reuses existing contracts
- **Execution style**: Implement and commit in visible steps aligned with the external plan so progress is easy to inspect

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep `skill/templates/` and `skill/schemas/` as the shared prompt contract in v1 | Reuse current, working assets before any repo restructure | — Pending |
| Introduce `lib/co-evolution.sh` as the shared shell core | Avoid duplicating helper functions across Agent Bouncer and Codex runtime | — Pending |
| Split the work into stepwise commits that mirror the external plan | Maintains visibility and makes course-correction easier after each boundary | — Pending |

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
*Last updated: 2026-04-06 after GSD initialization*
