---
title: Directory consolidation — collapse worktrees into single `Project/co-evolution/`
trigger_condition: >
  After `git tag v1.2` — v1.2 must be tagged and PR #3 merged to master. Phase 8.1
  (scorer/runner contract wiring) complete. SC-4 dogfood passed. At that point the
  `feat/v1.2-pel-proposer` branch is merged and `co-evolution-v12/` worktree can
  be removed safely.
planted_date: 2026-04-19
planted_during: v1.2 PEL Proposer Only — Phase 8.1 kickoff
scope: small
---

# Seed: Directory consolidation post-v1.2

## The ambition

Four co-evolution-flavored directories currently exist under `Project/`:

- `co-evolution/` — worktree on `archive/aris-manifest-spike-2026-04-08` (stale archive branch)
- `co-evolution-clean/` — worktree on `master` (idle)
- `co-evolution-v12/` — worktree on `feat/v1.2-pel-proposer` (active)
- `co-evolution-lab/` — **peer directory** (not a worktree), containing `auto-research/`, `integrations/`, and other sidecar work

The `co-evolution/` worktree vs `co-evolution-lab/` peer-dir name collision is a permanent navigation hazard. Shell cwd confusion already bit mid-session on 2026-04-19 (handoff pointed at `co-evolution-lab/.handoff/` while the real repo was at `co-evolution-v12/`).

## Target end-state

One directory: `Project/co-evolution/` on master. Worktrees spawn per-branch on demand via `git worktree add`, never live as long-term parallel checkouts.

## Cut-points (from `.planning/notes/directory-consolidation.md`)

**Cut-point A — after v1.2 PR #3 merges:**
- `git worktree remove co-evolution-v12`
- `git branch -d feat/v1.2-pel-proposer`
- Move `co-evolution/` off archive branch back to master

**Cut-point B — after `git tag v1.2`:**
- `git worktree remove co-evolution-clean/`
- Single canonical `co-evolution/` on master

**Cut-point C — `co-evolution-lab/` triage (independent, any time):**
- Audit `auto-research/`, `integrations/`, `mempalace.yaml`, `.handoff/` per-subdir
- Rename parent dir to kill the name collision

## Why deferred

Mid-flight surgery on the active workspace risks losing Phase 8.1 state and dropping the open PR. Safer to finish the v1.2 ship gate (Phase 8.1 → SC-4 → `git tag v1.2`) first, then sweep Cut-points A→B in one ~30-min pass.

## Breadcrumbs

- Full plan: `.planning/notes/directory-consolidation.md`
- Current worktree state: `git worktree list`
- Session history keyed by cwd: `.claude/projects/C--Users-alan-Project-co-evolution*/`
- Likely references to update before Cut-point A: `CLAUDE.md`, `C:/Users/alan/projects.md`, any script hardcoding `co-evolution-v12` or `co-evolution-lab` paths

## Surface this seed when

- User starts a new milestone after v1.2 ships
- User asks "where are we running this from?" or "which folder is canonical?"
- User complains about directory confusion or the `co-evolution` vs `co-evolution-lab` name collision
