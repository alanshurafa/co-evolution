# Rebuild Phase 0 — TRACKER

**NEXT ACTION:** Verify Wave 1+2 worker results as they land (WP-02/03/07/09 in flight); commit each verified WP; then Wave 3 (WP-04/05/06) once WP-03 verifies.
**Current phase:** Phase 0 — Decisions, vertical slice, contract freeze
**Plan:** `.planning/rebuild/PHASE-0-PLAN.md` (this branch) | **Authority:** `C:\Users\alan\Project\Admin\docs\rebuild-proposals\co-evolution.md` (v1.1)
**Branch/worktree:** `rebuild/phase-0` @ `C:\Users\alan\Project\co-evolution\.claude\worktrees\rebuild-phase-0` (cut from origin/master `0d53f57`)
**Last updated:** 2026-07-17 (bootstrap)

## Work packages

| WP | Title | Deps | Status | Evidence |
|---|---|---|---|---|
| WP-01 | Decision record + scaffold commit | — | done | DECISIONS.md (D1–D5 + gates) committed with this tracker update |
| WP-02 | Corpus preservation copy-out | — | done | robocopy exit 1 both trees; 3,471 files / 53,879,601 B + 1 file / 28,208 B; listing digest `97430c59…` identical src/dst, INDEPENDENTLY recomputed by orchestrator; manifest at .planning/rebuild/corpus-manifest.md. Anomaly: 296 top-level run dirs (not ~302 — brief's estimate conflated entries/files; all three verification methods agree src==dst) |
| WP-03 | packages/engine scaffold | 01 | in-progress | |
| WP-04 | Slice A: real adapter call | 03 | todo | |
| WP-05 | Slice B: process-tree kill (language gate) | 03 | todo | |
| WP-06 | Slice C: bounce-state serializer vs real scorer | 02,03 | todo | |
| WP-07 | Contract kit extraction + drift test | 01 | in-progress | |
| WP-08 | Engine CI job, 3-OS (completes WP-05 proof) | 03,05 | todo | |
| WP-09 | Spec v0.2 draft (ambiguities resolved) | 01 | in-progress | (adversarial-review half of done-check runs after draft lands) |
| WP-10 | Phase 0 gate review + Phase 1 plan + STOP B | all | todo | |

## Gates

- **G1 housekeeping (Appendix A):** not requested yet — batch into WP-10's STOP B report unless hit earlier.
- **G2 publishing:** dormant (nothing publishes in Phase 0).
- **G3 metered spend:** dormant (only Haiku-class CLI smoke calls authorized).

## Assumptions log

- 2026-07-17: §8 defaults adopted per proposal v1.1 (in-place migration, protocol = markers+loop+termination, single-model → Phase 4, GSD = documented consumer); Alan may override at any gate.
- 2026-07-17: Node v22.22.2 present on the dev machine (satisfies >=20).

## Session log

- 2026-07-17 (Fable, planning): bootstrapped branch `rebuild/phase-0` from origin/master `0d53f57`; authored PHASE-0-PLAN.md + this tracker; execution handed to a fresh Opus session.
- 2026-07-17 (Fable, executing — user redirected execution into this session): S1 clean; WP-01 done direct; Waves 1+2 merged (WP-01 completes in-turn, deps met) — fanned out WP-02 (Sonnet), WP-03 (Sonnet), WP-07 (Sonnet), WP-09 (Opus); workers report, orchestrator verifies + commits. Assumption logged: merging suggested waves is within LOOP §1 batching.
