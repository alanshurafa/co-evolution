---
phase: 03-lab-scaffold
plan: 01
subsystem: docs
tags: [lab, beta-channel, documentation, graduation-criteria, sandbox, argv-contract]

# Dependency graph
requires:
  - phase: 02-bash-eval-harness-port
    provides: "Portable Bash eval harness — prerequisite for PEL, which becomes lab/'s first inhabitant"
provides:
  - "lab/README.md encoding the default/lab boundary with 16 verbatim items from the concept-note PRD"
  - "Sandbox guarantee contract: --lab <mode> cannot modify master directly, only via PRs"
  - "Argv contract: lab inhabitant entry points receive the full task string as $1 (single argument)"
  - "--lab <mode> invocation surface documented as the Phase 3 Plan 02 wiring target"
  - "Repo-level README.md and AGENTS.md discoverability for the new lab/ subdirectory"
affects:
  - "03-02 (--lab <mode> parser wiring — consumes the argv contract and invocation spec from this plan)"
  - "04-classifier and all subsequent PEL phases (lab/pel/ lands here)"
  - "v1.3+ PEL Auto-Promote and Explorer inhabitants (namespace reserved)"

# Tech tracking
tech-stack:
  added: []  # Docs-only plan — no new dependencies
  patterns:
    - "Phase-locked verbatim content: 16 items copied byte-exact from .planning/notes/co-evolution-lab-concept.md, each pinned by grep acceptance so future drift fails the gate"
    - "Argv-contract documentation co-located with how-to-add-inhabitant section; paired with Plan 02 dispatch-code comment for cross-reference"
    - "AGENTS.md edit placed OUTSIDE all <!-- GSD:*-start --> / <!-- GSD:*-end --> blocks so it survives regeneration sweeps"

key-files:
  created:
    - "lab/README.md (127 lines) — user-facing lab contract: boundary, lab-worthy rubric, graduation criteria, anti-criteria, disambiguation, sandbox guarantee, first-inhabitants table, how-to-add checklist with argv contract, further-reading links"
  modified:
    - "README.md — added ### [Lab](lab/) subsection between Claude Code Skill and Picking the right entrypoint"
    - "AGENTS.md — appended ## Lab Subdirectory section after the final GSD:profile-end marker"

key-decisions:
  - "Placed AGENTS.md lab callout AFTER the last <!-- GSD:profile-end --> marker (not before the first -start marker) to match repo convention of new sections appending at tail and minimize diff context against GSD regeneration"
  - "README.md Lab subsection placed between Claude Code Skill and Picking the right entrypoint — slots into existing Components tree naturally, and the routing table immediately below stays focused on default-runner choices (lab/ is orthogonal, not a row in that matrix)"
  - "Wrote L-07 anti-criteria bullets with the exact 'cause → consequence' structure from the concept note (including verbatim 'nobody actually wants it', 'we don't know if it's helping', 'redundant', 'cut losses') — paraphrase would fail the W-1 grep pins"

patterns-established:
  - "Verbatim-copy-with-grep-pinning: when a downstream artifact MUST mirror an upstream spec, pin each distinctive phrase with grep acceptance. Paraphrased regressions fail the gate, not just missing sections."
  - "Namespace-reserving placeholder callouts: README can list v1.3+ inhabitants as 'NOT created' placeholders so directory layout is predictable before the inhabitants materialize."
  - "Argv contract as a first-class lab-wide invariant: document once in lab/README.md, cross-reference from dispatch code comments, grep-pin both directions to prevent silent drift."

requirements-completed: [LAB-01]

# Metrics
duration: ~8 min
completed: 2026-04-18
---

# Phase 3 Plan 01: Lab Scaffold — lab/README.md + repo-level discoverability

**User-facing lab contract (127 lines) encoding all 16 verbatim items from the concept-note PRD — 6 graduation criteria, 4 anti-criteria with cause+consequence anchors, 5 lab-worthy qualifiers, 3 disambiguation items — plus sandbox guarantee, --lab invocation surface, first-inhabitants table with v1.3+ placeholders, and the v1.2 argv contract for lab entry points.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-18 (execution began)
- **Completed:** 2026-04-18
- **Tasks:** 2 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- **`lab/README.md` (127 lines) landed with every locked-decision item byte-exact.** All 48 grep-acceptance checks in Task 1's automated verification block passed on first run — no retries, no drift. This is the documentation artifact Phase 3 Plan 02 (runner parser) and Phases 4-8 (PEL inhabitants) will build against.
- **Repo-level discoverability wired without breaking GSD auto-generation.** README.md gets a proper `### [Lab](lab/)` subsection with usage examples; AGENTS.md gets a `## Lab Subdirectory` section placed OUTSIDE all GSD blocks so it survives regeneration. Block pairing verified: 7 starts / 7 ends, balanced.
- **Three W-1/W-3 mitigations baked in.** Anti-criteria pinned on BOTH cause AND consequence phrases (W-1: `nobody actually wants it`, `signal never stabilized` + `know if`, `obviated it` + `redundant`, `full rewrite` + `cut losses`). Argv contract documented verbatim (W-3: `full task string as` + `single argument`). Drift-mitigation links to concept note + v1.3+ seed both present and grep-pinned.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lab/README.md with all four locked verbatim sections** — `36a4f14` (docs)
2. **Task 2: Reference lab/ from repo-level README.md and AGENTS.md** — `ab8b6e1` (docs)

_No TDD cycle on this plan — pure documentation artifact with grep-based acceptance, not runtime code._

## Files Created/Modified

- `lab/README.md` (CREATED, 127 lines) — The user-facing lab contract. Sections: `# The Lab` title + what-this-is paragraph, `## Why this exists`, `## Boundary conventions`, `## What qualifies as "lab-worthy"` (5 verbatim bullets), `## Graduation criteria — lab → core` (6 verbatim numbered items), `## Anti-criteria — when to remove from lab (not graduate)` (4 verbatim bullets with cause+consequence preserved), `## What's NOT the lab` (3 verbatim disambiguation items), `## Sandbox guarantee`, `## Invocation` (example `co-evolve --lab` + `dev-review --lab` + unknown-mode fail-fast), `## First inhabitants` (table: lab/pel/ current + lab/pel-auto/ + lab/pel-explorer/ v1.3+ placeholders NOT created), `## How to add a new lab inhabitant` (5-step checklist + argv contract paragraph), `## Further reading` (links to concept note, seed, REQUIREMENTS.md).
- `README.md` (MODIFIED) — Added a `### [Lab](lab/)` subsection between `### [Claude Code Skill](skills/dev-review/)` and `### Picking the right entrypoint`. Includes a bash fence with `co-evolve --lab pel-proposer "task"` and the dev-review equivalent, plus the unknown-mode fail-fast callout.
- `AGENTS.md` (MODIFIED) — Appended a `## Lab Subdirectory` section after the final `<!-- GSD:profile-end -->` marker, linking to `lab/README.md` and noting the opt-in nature + PR-only promotion path. Explicit note that the section lives outside all GSD blocks so regeneration won't touch it.

## Decisions Made

- **AGENTS.md placement: below last GSD block, not above first.** Both options would satisfy the block-balance acceptance. Chose below because (a) new sections by convention append at tail, (b) it keeps the GSD-regenerated content (project/stack/conventions/architecture/skills/workflow/profile) as the top of the file for agent ingestion, (c) future GSD regeneration will leave a cleaner diff context if edits land after the last marker.
- **README.md placement: between Claude Code Skill and Picking-the-right-entrypoint.** The "Picking the right entrypoint" routing table underneath is about choosing among default-runner surfaces (agent-bouncer / codex runtime / skill) — lab/ is orthogonal (an opt-in dimension, not a row in that matrix), so it reads naturally as a separate capstone component rather than a table row.
- **Graduation criteria verbatim copy, not paraphrase.** The plan explicitly forbids paraphrasing L-06/L-07/L-08/L-01 items and Task 1 acceptance has 23 grep pins across these 16 items (with L-07 having 10 pins alone due to cause+consequence double-anchoring). Paraphrase would have silently failed the gate.

## Deviations from Plan

None — plan executed exactly as written.

**Total deviations:** 0
**Impact on plan:** All 48 automated grep-acceptance checks in Task 1 and all 5 checks in Task 2 passed on first run. No bugs found, no missing-critical functionality, no blocking issues. Plan was well-specified (checker's W-1/W-3 iteration added the double-anchor pins that caught the highest drift risk) so execution was a clean author-and-commit pass.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration, no env vars, no dashboard steps. This is a docs-only plan.

## Next Phase Readiness

- **Phase 3 Plan 02 is immediately unblocked.** The `--lab <mode>` invocation contract, the argv contract ($1 as single concatenated task string), and the unknown-mode fail-fast semantics are now documented in `lab/README.md` as the reference the parser implementation must match. Plan 02's `tests/lab-routing-simulation.sh` and its runner edits can cite `lab/README.md` as the behavior spec.
- **Phase 4 (Mode Classifier) has its home documented.** `lab/pel/classifier/` lands there when Phase 4 starts; the Phase 3 README lists `lab/pel/` as the v1.2 current inhabitant already.
- **No blockers or concerns carried forward.** Working tree is clean, branch is `feat/v1.2-pel-proposer` + 22 commits ahead of origin (Phase 3 execution added 2 task commits + 1 metadata commit still pending).

## Self-Check: PASSED

Verified post-write:
- [x] `lab/README.md` exists at `C:/Users/alan/Project/co-evolution-v12/lab/README.md` (127 lines)
- [x] Commit `36a4f14` exists in git log (`docs(03-lab-scaffold): create lab/README.md with the v1.2 beta-channel contract`)
- [x] Commit `ab8b6e1` exists in git log (`docs(03-lab-scaffold): wire lab/ discoverability into repo-level README + AGENTS`)
- [x] All 48 Task 1 acceptance grep checks passed (first run, no retries)
- [x] All 5 Task 2 acceptance checks passed (GSD block balance 7/7 preserved)
- [x] No forbidden placeholder directories created (`lab/pel/`, `lab/pel-auto/`, `lab/pel-explorer/` all absent per L-09)

---
*Phase: 03-lab-scaffold*
*Completed: 2026-04-18*
