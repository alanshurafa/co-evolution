---
title: Directory consolidation — Cut-point C (co-evolution-lab triage)
trigger_condition: >
  PARTIALLY FULFILLED 2026-04-19. Cut-points A + B executed post-merge (not post-tag —
  user reordered). Remaining: Cut-point C (triage + rename `co-evolution-lab/`).
  Surface when user starts a new session or milestone, or asks about the lab dir /
  auto-research / navigation ambiguity. Independent of `git tag v1.2`.
planted_date: 2026-04-19
planted_during: v1.2 PEL Proposer Only — Phase 8.1 kickoff
fulfilled_partial_date: 2026-04-19
scope: small
---

# Seed: Directory consolidation post-v1.2 — Cut-point C remaining

## Status

**Cut-points A + B: DONE (2026-04-19 post-merge).** One canonical worktree at `Project/co-evolution/` on master. `co-evolution-v12/` and `co-evolution-clean/` worktrees removed. Local + remote `feat/v1.2-pel-proposer` branches deleted.

**Cut-point C: PENDING.** `co-evolution-lab/` peer directory still exists with sub-project detritus. Needs triage + rename.

## Cut-point C scope

`Project/co-evolution-lab/` contents (inventoried 2026-04-19):

| Subdir | Size | Git | Status | Decision needed |
|--------|------|-----|--------|-----------------|
| `auto-research/` | **4.6 GB** | yes, master (clean) | Peer project, last commit 2026-03-25 | Keep as peer? Move up to `Project/auto-research/`? Archive? |
| `auto-research-safe/` | 1.4 MB | yes, master (2 dirty) | Near-clone of auto-research | Candidate for deletion — verify vs main repo first |
| `archive/codex-co-evolution/` | 2.8 MB | yes, main (6 dirty) | Historical pre-unification repo | Keep archived, move to `Project/archive/`? |
| `co-evolution/` (inside lab) | 2.6 MB | **no** | Stale pre-v1.0-unification snapshot | Delete — superseded by canonical `Project/co-evolution/` |
| `integrations/` | 224 KB | no | Scope unclear | Audit contents; likely fold into co-evolution repo or delete |
| `mempalace.yaml` | 585 B | — | Stray config | Move to appropriate project |
| `.claude/` | — | — | Local Claude settings | Merge with `Project/co-evolution/.claude/` or delete |

**`.handoff/` already deleted** 2026-04-19 (held the obsolete HANDOFF-go-phase-seven file that triggered the v1.2-ship session).

## Remaining tasks

1. Per-subdir decisions per the table above (needs user input — most are peer-project vs archive vs delete calls).
2. Rename `co-evolution-lab/` to kill the `co-evolution/` vs `co-evolution-lab/` name collision. Candidate targets: `Project/sandbox/`, `Project/peer-projects/`, `Project/scratch/`. Pick before starting the triage so moves land in the right place.
3. Grep for hardcoded `co-evolution-lab` path references in: `CLAUDE.md`, `C:/Users/alan/projects.md`, `.claude/settings.json`, any scripts or hooks. Update before / after rename.

## Breadcrumbs

- Historical plan + inventory: `.planning/notes/directory-consolidation.md` (committed to master, still accurate for context).
- Cut-points A + B executed from `co-evolution-clean/` before its own removal; final worktree renames via `git checkout master` in the main worktree.
- Session history keyed by cwd: `.claude/projects/C--Users-alan-Project-co-evolution*/`. Post-merge sessions should land under `C--Users-alan-Project-co-evolution` (new canonical).
- `.backup/co-evolve-plan.archived.md` in `Project/co-evolution/` — moved during Cut-point A from the archive-branch working dir (was untracked, collided with master's tracked `experiments/co-evolve-plan.md`). User should review and discard or preserve.
- Empty `Project/co-evolution-v12/` dir still file-locked on Windows as of 2026-04-19 post-merge — retry `rmdir` after a restart, or via Explorer.

## Surface this seed when

- User asks about `co-evolution-lab/`, `auto-research/`, or dir-layout questions.
- User starts a new milestone (any post-v1.2 work).
- User flags "which folder should this live in?"
