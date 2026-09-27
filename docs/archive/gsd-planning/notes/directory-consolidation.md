# Directory consolidation plan (post-v1.2)

**Status:** deferred — execute after `git tag v1.2`
**Owner:** Alan
**Created:** 2026-04-19

## Problem

Four co-evolution-flavored directories exist under `C:\Users\alan\Project\`:

| Path | What | State |
|------|------|-------|
| `co-evolution/` | Worktree on `archive/aris-manifest-spike-2026-04-08` | Stale archive branch |
| `co-evolution-clean/` | Worktree on `master` | Idle |
| `co-evolution-v12/` | Worktree on `feat/v1.2-pel-proposer` | Active until PR #3 merges |
| `co-evolution-lab/` | **Not a worktree.** Separate dir containing `auto-research/`, `auto-research-safe/`, `archive/codex-co-evolution/` (all own git repos), `co-evolution/` (plain folder), `integrations/`, `mempalace.yaml`, `.handoff/` | Sidecar playground |

The name collision between `co-evolution/` (worktree) and `co-evolution-lab/` (peer workspace) is a permanent navigation hazard.

## Decisions

1. **Canonical directory:** `Project/co-evolution/` — all three worktrees collapse into this single checkout on master.
2. **Name collision:** `co-evolution-lab/` must be renamed to kill ambiguity. Target name TBD at Cut-point C (`sandbox/`, `co-evolution-workspace/`, or per-subproject split).
3. **`co-evolution-lab/` content disposition:** decided per-subdir at Cut-point C; not blocking v1.2 tag.

## Cut-points (execute in order)

### Cut-point A — after v1.2 PR #3 merges to master

```bash
# From any worktree:
git worktree remove co-evolution-v12
git branch -d feat/v1.2-pel-proposer   # branch merged, local ref no longer needed
```

Then switch the active checkout:
```bash
# co-evolution/ is stuck on archive/aris-manifest-spike-2026-04-08. Either:
# (a) move it to master:
cd co-evolution/ && git checkout master && git pull
# or (b) remove it:
git worktree remove co-evolution/
```

Default: option (a) — `co-evolution/` becomes the canonical master checkout.

**Post-A state:** `co-evolution/` (master) + `co-evolution-clean/` (master, now redundant).

### Cut-point B — after `git tag v1.2`

```bash
git worktree remove co-evolution-clean/
```

**Post-B state:** single `Project/co-evolution/` directory on master. Any future branch work uses `git worktree add` fresh.

### Cut-point C — `co-evolution-lab/` triage (independent, any time)

Triage each subdir:

- `auto-research/` — own git repo. Likely peer project. **Action:** leave where it is, or rename parent dir.
- `auto-research-safe/` — own git repo. Duplicate? **Action:** audit vs `auto-research/`, delete duplicate.
- `archive/codex-co-evolution/` — own git repo, archive. **Action:** confirm archived, leave or move under a `Project/archive/` umbrella.
- `co-evolution/` (plain folder, not git) — stale copy? **Action:** audit contents, delete if redundant.
- `integrations/` — scope unclear. **Action:** audit; fold into repo if belongs in `co-evolution/`, otherwise peer project.
- `mempalace.yaml` — stray config. **Action:** move to appropriate project.
- `.handoff/` — session handoff files. **Action:** not long-lived; delete or move to `.claude/handoffs/` by convention.

Rename parent dir last, once subdir dispositions settle.

## Validation checklist (run after Cut-point B)

- [ ] `git worktree list` shows exactly one entry: `Project/co-evolution/` on master
- [ ] `Project/co-evolution-v12/` and `Project/co-evolution-clean/` gone
- [ ] `Project/co-evolution/` on master, `git status` clean
- [ ] Session history for co-evolution still resolvable under `.claude/projects/C--Users-alan-Project-co-evolution*/`
- [ ] No scripts, docs, or CLAUDE.md references the dead paths

## Risks

- **Session history path drift:** Claude Code keys session dirs by cwd. After moving, new sessions land under `C--Users-alan-Project-co-evolution` (fresh). Old session JSONLs remain under `C--Users-alan-Project-co-evolution-v12` and `C--Users-alan-Project-co-evolution-lab`. Intentional — historical context preserved.
- **Lingering references:** `CLAUDE.md`, `projects.md`, scripts, or hooks may hardcode `co-evolution-v12` or `co-evolution-lab`. Grep for these paths before Cut-point A and update in a prep commit.
- **`.handoff/` file loss:** If `co-evolution-lab/.handoff/` holds active state, move before deleting the dir.
