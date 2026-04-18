# Co-Evolution

## What This Is

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. It ships a standalone Agent Bouncer, a Claude Code `/dev-review` skill, a standalone Codex Bash runtime with parity to the PowerShell reference implementation, a portable eval harness (`evals/` + `schemas/`), and a read-only reference copy of the PS runtime at `runners/codex-ps/`.

From v1.2 onward the repo is split into two surfaces: a stable **default runner** (`co-evolve`, `dev-review`) that every user invokes, and an opt-in **`lab/`** subdirectory reached via `--lab <mode>` where experimental machinery lives. The Protocol Evolution Loop (PEL) — the system that proposes improvements to the bouncer itself — lives entirely in `lab/pel/`. Accepted PEL mutations merge to master and thereby upgrade the default runner transparently.

## Current State

- **Shipped:** v1.0 Unification Absorb — 2026-04-17 (PR [#1](https://github.com/alanshurafa/co-evolution/pull/1) merged at `1f9b471`, tagged `v1.0`). See `.planning/milestones/v1.0-SUMMARY.md`.
- **Shipped:** v1.1 Polish & Ergonomics — 2026-04-17 (PR [#2](https://github.com/alanshurafa/co-evolution/pull/2) merged at `50f9c2d`, tagged `v1.1`). See `.planning/milestones/v1.1-SUMMARY.md`.
- **Active:** v1.2 Protocol Evolution Loop — Proposer Only (started 2026-04-17).

## Current Milestone: v1.2 Protocol Evolution Loop — Proposer Only

**Goal:** Ship PEL Option 1 — an LLM-powered proposer that generates protocol-mutation PRs for human review, using the eval harness as fitness signal. PEL machinery lives entirely in `lab/pel/`; the default runner is unchanged for users who never invoke `--lab pel-proposer`. Accepted mutations merge to master and upgrade the default runner transparently.

**Target features:**
- Post-v1.1 fixes (WR-04/05) folded as Phase 1 — avoids a separate v1.1.1 patch cycle
- Bash port of the PS eval harness (PEL prerequisite — fitness function must run without `pwsh`)
- `lab/` scaffold with documented graduation conventions (PEL is first inhabitant; v1.3+ options live here too)
- Mode classifier (frozen for v1.2; auto-picks bug-catcher / faster / blind-spot / general flavor per invocation with transparent reasoning and user override)
- Template-tier mutation proposer (mutates `skills/dev-review/templates/*.md`)
- Policy-tier mutation proposer (mutates YAML/JSON policy knobs: retry caps, marker-semantics, flavor weights)
- Code-tier mutation proposer (LLM-only; mutates `lib/co-evolution.sh` and runner paths with safety rails)
- PR emission + scoring integration — the Option 1 ship: `co-evolve --lab pel-proposer` writes draft PRs with eval scores in the body

## Core Value

Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps. From v1.2, co-evolution becomes self-improving: PEL proposes protocol mutations, humans review them, accepted ones upgrade the default runner over time.

## Requirements

### Validated

- [x] Agent Bouncer can bounce markdown documents between Claude and Codex using `[CONTESTED]` and `[CLARIFY]` markers — existing repo
- [x] Claude Code `/dev-review` workflow, prompt templates, and review schema exist in `skills/dev-review/` — existing repo
- [x] Shared shell helpers extracted into `lib/co-evolution.sh` consumed by both Agent Bouncer and Codex runtime — v1.0 Phases 1-2
- [x] Standalone Codex `dev-review` Bash runtime with compose-bounce-execute-verify and runtime flag support — v1.0 Phase 3
- [x] Codex runtime documented and routable via `dev-review/codex/instructions.md` — v1.0 Phase 4
- [x] Private `codex-co-evolution/` absorbed verbatim into `runners/codex-ps/` as read-only reference — v1.0 Phase 5
- [x] Claude adapter tool-gating parity with PowerShell reference; broken `--json-schema` skipped on Windows — v1.0 Phase 6
- [x] Structural bounce-check signal (`outputs/bounce-NN.txt`) complements semantic marker counting — v1.0 Phase 6
- [x] Runner parity: agent dispatcher, writable-phase flag, delta tracking, structured `state.json`, per-phase timeout — v1.0 Phase 7
- [x] Portable eval assets elevated to top-level `evals/` + `schemas/` — v1.0 Phase 8
- [x] `mempalace.yaml` folded into `integrations/`; Karpathy `autoresearch` excluded with documented rationale — v1.0 Phase 9
- [x] v1.0 code review warnings (WR-01/02/03) addressed — v1.1 Phase 1
- [x] REVISE auto-loop (`--revise-loop N`) with state.json retry tracking — v1.1 Phase 2
- [x] Visible live mode (`--live`) with Windows tail-window launcher — v1.1 Phase 3
- [x] Branch/worktree management (`--branch auto|NAME`, `--worktree auto|PATH`) — v1.1 Phase 4

### Active (v1.2 Protocol Evolution Loop — Proposer Only, 2026-04-17)

See `.planning/REQUIREMENTS.md` for the PEL-xx and FIX-WR-04/05 requirement catalog.

### Out of Scope

- **Auto-Promote mode (Option 2)** — seeded in `.planning/seeds/pel-auto-promote-and-explorer.md`. Triggers: Option 1 has ≥4 weeks production data + canary smoke-test suite exists + Goodhart research findings + `lab/` conventions established. Deferred to v1.3+.
- **Explorer + Curator mode (Option 3)** — same seed file; same trigger conditions.
- **Classifier evolution** — v1.2 classifier is frozen. Evolving the classifier itself is a meta-meta problem deferred to v1.3+ after Option 1 data reveals whether it's needed.
- **Goodhart mitigations beyond "human review gate"** — Option 1's PR review IS the Goodhart mitigation for v1.2. RQ-001 in `.planning/research/questions.md` tracks deeper mitigations for Option 2+3.
- **Automated branch/worktree cleanup utility** — deferred from v1.1 out-of-scope list; could live as a separate utility if demand emerges.
- **Workspace-agnostic ports of lab PS integration scripts** — deferred per v1.0 Phase 9 rationale.

## Context

- The repo is intentionally lightweight: Bash plus Markdown templates, no package manifest, self-contained simulation-script testing.
- `.planning/codebase/` documents current stack, architecture, conventions, testing gaps, concerns.
- `.planning/notes/pel-design-decisions.md` + `.planning/notes/co-evolution-lab-concept.md` capture the v1.2 design exploration outputs; they're the binding reference for v1.2 planning.
- `.planning/seeds/pel-auto-promote-and-explorer.md` carries forward the ambition for Options 2+3.
- `.planning/research/questions.md` tracks open research (RQ-001: Goodhart mitigation) for later milestones.

## Constraints

- **Tech stack:** Bash-first runtime + Markdown templates — default runner surface stays shell-native. Lab may experiment with other stacks but the promotion target is Bash.
- **Byte-parity for the default runner:** every v1.2 addition must be invisible to users who don't invoke `--lab pel-proposer`. No new visible flags on `co-evolve` / `dev-review`; no behavior change on default runs.
- **Dependency policy:** No `pwsh` requirement for the default path. v1.2 Phase 2 ports the eval harness to Bash to eliminate it everywhere.
- **Safety for code mutations:** PEL code-tier mutations (Phase 7) require sandboxing + canary-before-score pattern. The proposer CAN emit broken shell; the infrastructure must catch it before scoring or merging.
- **Human review is the Goodhart backstop:** Every PEL-proposed mutation goes through human PR review in v1.2. No auto-merge paths.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep `skills/dev-review/` as the shared prompt contract | Reuse current, working assets | Accepted (v1.0) |
| `lib/co-evolution.sh` is the shared shell core | Avoid duplicating helpers | Accepted (v1.0) |
| Shared-core, platform-specific-shell architecture | Claude Code and Codex have different orchestration models | Accepted (v1.0) |
| File-copy absorb of `codex-co-evolution/` into `runners/codex-ps/` | Zero commits existed; no history to subtree-merge | Accepted (v1.0) |
| Karpathy autoresearch excluded | Unrelated ML training domain | Accepted (v1.0) |
| Evals are the iteration mechanism (not auto-research) | Upstream evals caught 8 bugs + 1 scorer blindness that 11 bounces missed | Accepted (v1.0) |
| Writable-phase default = `false` | Safer posture if caller forgets flag | Accepted (v1.0) |
| Every v1.1 flag defaults off | Byte-parity for existing callers | Accepted (v1.1) |
| PEL ships Option 1 first; Options 2+3 deferred to lab | Live environment must not be poisoned before iteration locks things down | Accepted (v1.2) |
| PEL machinery lives entirely in `lab/pel/` — not core | Default runner stays invisible to PEL complexity; lab has clear identity as "the improvement engine" | Accepted (v1.2) |
| Mutable surface = templates + policy + code | Templates alone can't fix structural bugs; policy alone can't rewrite logic | Accepted (v1.2) |
| LLM-only proposer for code tier | Random mutation of shell produces syntax errors; evolutionary search is off-limits for the code surface | Accepted (v1.2) |
| Classifier frozen in v1.2 | Meta-meta-learning (evolving the classifier) is dangerous before Option 1 data exists | Accepted (v1.2) |
| Mode classifier auto-picks flavor with transparent reasoning + user override | Black-box fitness is terrifying; user must be able to say "nope, optimize for X instead" | Accepted (v1.2) |
| `co-evolution/lab/` = first-class beta channel | Ambitious experiments need somewhere that CAN break without breaking anything that matters | Accepted (v1.2) |
| Fold WR-04/WR-05 into v1.2 Phase 1 rather than ship a v1.1.1 patch | Same cost; keeps release cadence tidy | Accepted (v1.2) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check → still the right priority?
3. Audit Out of Scope → reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-17 kicking off v1.2 Protocol Evolution Loop — Proposer Only milestone; v1.1 requirements moved to Validated, v1.2 PEL requirements added to Active; lab/core architectural split captured in Key Decisions and Core Value*
