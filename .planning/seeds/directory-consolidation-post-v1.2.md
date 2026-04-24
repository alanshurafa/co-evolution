---
title: Directory consolidation — FULFILLED (all cut-points complete)
trigger_condition: >
  FULFILLED 2026-04-23. No action needed. File retained as historical record of
  what moved where, for future sessions that encounter references to the old
  co-evolution-lab/ layout.
planted_date: 2026-04-19
planted_during: v1.2 PEL Proposer Only — Phase 8.1 kickoff
fulfilled_partial_date: 2026-04-19
fulfilled_full_date: 2026-04-23
scope: small
status: fulfilled
---

# Seed (retired): Directory consolidation post-v1.2

## Status: FULFILLED

All three cut-points executed across 2026-04-19 (A+B) and 2026-04-23 (C). See the "Outcome log" for what landed where.

## Outcome log

**Cut-points A + B (2026-04-19 post-merge):**
- `co-evolution-v12/` worktree removed (held `feat/v1.2-pel-proposer`, merged + deleted remotely)
- `co-evolution-clean/` worktree removed
- Main worktree `co-evolution/` switched from `archive/aris-manifest-spike-2026-04-08` to `master`
- Local + remote `feat/v1.2-pel-proposer` branches deleted
- Result: single canonical worktree at `Project/co-evolution/` on master

**Cut-point C (2026-04-23 post-v1.2-tag):**

| Source (in `co-evolution-lab/`) | Destination | Disposition |
|---------------------------------|-------------|-------------|
| `auto-research/` (4.6 GB peer project, git, clean) | `Project/auto-research/` | Moved — now a peer of co-evolution |
| `auto-research-safe/` (1.4 MB near-clone, 2 dirty) | `Project/auto-research-safe/` | Moved (2 uncommitted files preserved for later audit) |
| `archive/codex-co-evolution/` (2.8 MB, git, 6 dirty) | `Project/archive/codex-co-evolution/` | Moved — historical reference, 6 dirty files preserved |
| `archive/integration-lab-20260407/` (2.3 MB) | `Project/archive/integration-lab-20260407/` | Moved — historical lab snapshot |
| `archive/README.md` | `Project/archive/README-lab-archive-historical.md` | Moved with clarifying name |
| `co-evolution/` (2.6 MB, stale pre-unification snapshot, not git) | `Project/archive/co-evolution-pre-unification/` | Archived (had AGENTS.md, co-evolve-bouncer.sh, README.md that DIFFERED from master — pre-unification historical content) |
| `integrations/` (224 KB, not git, PS integration scripts) | `Project/archive/integrations-pre-unification/` | Archived — deferred-port PS scripts from v1.0 Phase 9 carry-forward |
| `mempalace.yaml` (585 B) | `Project/archive/mempalace-wing-config.yaml` | Archived — wing config for mempalace MCP brain; review + relocate when re-wiring mempalace |
| `.claude/` (settings.local.json + scheduled_tasks.lock) | *(deleted)* | Stale session residue only — canonical `Project/co-evolution/.claude/` supersedes |
| `.handoff/` | *(deleted 2026-04-19)* | Obsolete HANDOFF-go-phase-seven file |
| `.backup/co-evolve-plan.archived.md` (in `co-evolution/`) | *(deleted 2026-04-23)* | Structurally identical to master's `experiments/co-evolve-plan.md` |

**Parent dir `co-evolution-lab/`**: empty as of 2026-04-23 but file-locked by the session's shell cwd. Will release after session end or a reboot — `rmdir` it manually then.

**Final `Project/` layout** (co-evolution-related):
```
Project/
├── co-evolution/                           ← canonical, on master
├── auto-research/                          ← peer project (4.6 GB)
├── auto-research-safe/                     ← backup clone (2 dirty files)
├── archive/
│   ├── co-evolution-pre-unification/       ← pre-v1.0 snapshot
│   ├── codex-co-evolution/                 ← archived repo
│   ├── integration-lab-20260407/           ← April snapshot
│   ├── integrations-pre-unification/       ← deferred PS scripts
│   ├── mempalace-wing-config.yaml          ← MCP wing config
│   └── README-lab-archive-historical.md    ← original archive README
├── codex-co-evolution/                     ← (separate, pre-existing)
└── co-evolution-lab/                       ← EMPTY, delete manually after lock releases
```

## Breadcrumbs

- Historical plan + inventory: `.planning/notes/directory-consolidation.md` (tracked on master, describes the pre-consolidation state).
- Session history keyed by cwd: `.claude/projects/C--Users-alan-Project-co-evolution*/`. Historical sessions keyed under the old `-lab/` and `-v12/` paths are still searchable for context; new sessions from canonical land under `C--Users-alan-Project-co-evolution`.
- No hardcoded `co-evolution-lab/` references in `CLAUDE.md` or `projects.md` at consolidation time (greped 2026-04-23).

## If something turns out to be missing

Before assuming data loss: check `Project/archive/` — nothing was deleted except `.handoff/` (obsolete), `.backup/co-evolve-plan.archived.md` (identical to master's tracked version), and `.claude/` residue (settings.local.json from the v1.2-ship session + a scheduled_tasks lock file).
