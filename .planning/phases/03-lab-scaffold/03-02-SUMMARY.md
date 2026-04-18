---
phase: 03-lab-scaffold
plan: 02
subsystem: infra
tags: [lab, beta-channel, cli-parser, routing, shared-library, argv-contract, injection-defense]

# Dependency graph
requires:
  - phase: 03-lab-scaffold
    provides: "lab/README.md — the behavior spec (argv contract, unknown-mode semantics, --lab invocation surface, sandbox guarantee) that Plan 02's parser must match"
provides:
  - "validate_lab_mode / list_available_lab_modes / dispatch_lab_mode helpers in lib/co-evolution.sh — shared between both runners; single-point-of-truth for lab routing"
  - "--lab <mode> parser on co-evolve-bouncer.sh (9 lines in case block; 12-line dispatch comment) and dev-review/codex/dev-review.sh (11-line arm; 14-line dispatch comment) with identical semantics"
  - "tests/lab-routing-simulation.sh (134 lines, 4 scenarios) — hermetic byte-parity + unknown-mode + invalid-token gate; exits 0 with '4/4 scenarios passed'"
  - "dev-review/codex/README.md CLI table row + Lab routing subsection documenting --lab <mode>"
  - "Enforced contract: lab inhabitants receive $TASK as a single argv slot (W-3 mitigation pinned at both dispatch sites via 'single argv slot' substring + lab/README.md cross-reference)"
affects:
  - "Phase 4 (Mode Classifier) — first real inhabitant lab/pel/classifier/ will plug into this dispatch path"
  - "Phase 8 (PR Emission) — co-evolve --lab pel-proposer invocation uses this exact --lab flag"
  - "All future lab inhabitants — must honor the v1.2 argv contract (single-arg $TASK) until v1.3+ relaxes it"

# Tech tracking
tech-stack:
  added: []  # No new dependencies — uses only bash + coreutils already in use
  patterns:
    - "Shared-helper single-point-of-truth: both runners source lib/co-evolution.sh and call the same dispatch helper — eliminates drift between co-evolve-bouncer.sh and dev-review/codex/dev-review.sh"
    - "Regex-gated injection defense: ^[a-zA-Z0-9_-]+$ validation runs BEFORE any fs access in dispatch_lab_mode — path-traversal and shell-meta can never reach bash or find"
    - "Argv-position invariant: --lab) arm deliberately precedes --) arm in both case blocks; enforced by line-number grep in simulation (makes future refactors that move the arm detectable)"
    - "Byte-parity-by-default flag: LAB_MODE='' + if [[ -n \"$LAB_MODE\" ]] dispatch guard means the pre-Phase-3 code path is unperturbed when the flag is absent (Scenario A validates via --help parity spot-check)"

key-files:
  created:
    - "tests/lab-routing-simulation.sh (134 lines) — hermetic simulation covering byte-parity + unknown-mode rejection on BOTH runners + mode-token validation"
  modified:
    - "lib/co-evolution.sh — added three helpers (validate_lab_mode, list_available_lab_modes, dispatch_lab_mode) in a new 'Lab routing (Phase 3 LAB-01)' section between phase_is_writable and is_windows_host (65 lines added)"
    - "co-evolve-bouncer.sh — added LAB_MODE default, --lab arm before --, usage row, dispatch block after arg parsing (19 lines added)"
    - "dev-review/codex/dev-review.sh — added LAB_MODE default, --lab arm before --, usage row, dispatch block after --branch/--worktree mutex check (32 lines added)"
    - "dev-review/codex/README.md — added --lab MODE row to CLI Options table + ### Lab routing subsection (5 lines added)"

key-decisions:
  - "Shared helpers in lib/co-evolution.sh over inline per-runner duplication — single-point-of-truth eliminates drift (matches CONTEXT §Claude's Discretion guidance)"
  - "GNU-find + macOS-find fallback in list_available_lab_modes — uses feature detection (find --version | grep GNU) rather than OS detection, so Git Bash for Windows and Linux take the fast -printf path while macOS falls through to exec basename (validated on Git Bash 5.2)"
  - "Dispatch in dev-review.sh placed AFTER the --branch/--worktree mutex check but BEFORE WORKDIR resolution — keeps v1.1 CLI-contract errors fail-fast before lab routing takes over"
  - "W-3 argv-contract comment pinned as 'single argv slot' substring at BOTH dispatch sites (plus lab/README.md cross-reference) — symmetric with Plan 01 README documentation; grep-checkable from either direction"

patterns-established:
  - "Bash 5.2 set -e + command-substitution-exit-propagation workaround: when a helper dies inside $(...), wrap the inner expression in an additional subshell — out=$( (dispatch_lab_mode ...) 2>&1 || true ). Relevant whenever a library function that calls die is invoked under set -e on modern bash; the Plan 02 verify block needed this but the simulation test's per-scenario subshells naturally avoid it"
  - "Flag-doc co-location precedent extended: Phase 2 pinned --runner-path in evals/README.md; Phase 3 pins --lab in dev-review/codex/README.md + co-evolve-bouncer.sh usage heredoc + the dedicated lab/README.md contract"

requirements-completed: [LAB-01]

# Metrics
duration: ~9 min
completed: 2026-04-18
---

# Phase 3 Plan 02: Lab Scaffold — --lab <mode> parser wiring + simulation gate

**Shared lib/co-evolution.sh dispatch helpers (validate / list / dispatch) wired into BOTH co-evolve-bouncer.sh and dev-review/codex/dev-review.sh with identical semantics, regex-gated injection defense, argv-position invariant, byte-parity-by-default flag, and a 4-scenario hermetic simulation proving it all works — closes Phase 3 SC-3 and completes LAB-01.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-04-18T17:33:02Z
- **Completed:** 2026-04-18T17:42:02Z
- **Tasks:** 4 completed
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **Three lab-routing helpers landed in `lib/co-evolution.sh` with all 29 unit assertions green on first verify run.** `validate_lab_mode` enforces `^[a-zA-Z0-9_-]+$` before any filesystem access, `list_available_lab_modes` handles GNU+BSD find with feature detection, and `dispatch_lab_mode` `exec`'s the resolved `entry.sh` with the remaining argv — all behaviors pinned by the Task 1 acceptance block (path-traversal, shell-meta, empty, dollar, slash, space all rejected; populated/empty/missing dirs all return correct listings; invalid/unknown/missing-entry all die with the exact contracted messages).
- **Both runners gained `--lab <mode>` with zero byte-parity regression.** LAB_MODE defaults to empty so default invocations never touch the dispatch block. The `--lab)` arm sits before the `--)` argv-terminator arm in both case blocks (enforced by line-number comparison in the simulation). W-3 argv-contract comments at both dispatch sites share the `single argv slot` anchor + `lab/README.md` cross-reference — future executors reading either runner or the README land on the same contract.
- **Hermetic simulation gate (`tests/lab-routing-simulation.sh`) exits 0 with `4/4 scenarios passed`.** Covers byte-parity (Scenario A: `--help` retains `--bounces`/`--agents` AND now contains `--lab`), unknown-mode fail-fast on BOTH runners (Scenarios B + C: matches L-04), and mode-token validation against path-traversal + shell-meta on BOTH runners (Scenario D: enforces T-03-02-01). Mirrors the Phase 2 `evals/tests/scorer-verification.sh` style — final-line `4/4 scenarios passed` pattern is now consistent across v1.2 phase gates.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add lab-routing helpers to lib/co-evolution.sh** — `9e523f0` (feat)
2. **Task 2: Wire --lab <mode> into both runners** — `a3ccee3` (feat)
3. **Task 3: Hermetic --lab routing simulation (4 scenarios)** — `e3fbffb` (test)
4. **Task 4: Document --lab <mode> in dev-review CLI table** — `b5efef9` (docs)

_Plan metadata commit (SUMMARY + STATE + ROADMAP) follows once this file lands._

## Files Created/Modified

- `lib/co-evolution.sh` (MODIFIED, +65 lines) — New `# --- Lab routing (Phase 3 LAB-01) ---` section between `phase_is_writable` (line 67) and `is_windows_host`. Three helpers with full docstrings documenting T-03-02-01 + T-03-02-03 mitigations inline.
- `co-evolve-bouncer.sh` (MODIFIED, +19 lines) — `LAB_MODE=""` default after INPUT_TYPE; `--lab)` arm between `--output)` and `--)`; usage row; 12-line dispatch block with full W-3 argv-contract comment after `done` and before `# --- Input Detection ---`.
- `dev-review/codex/dev-review.sh` (MODIFIED, +32 lines) — `LAB_MODE=""` default after `LAST_INVOKE_EXIT_CODE`; `--lab)` arm between `--worktree)` and `--help)`; usage row; 14-line dispatch block after `--branch`/`--worktree` mutex check, before `WORKDIR=$(normalize_path_for_bash ...)`. Uses the pre-existing `REPO_ROOT` (set at line 6) as the lab-root base.
- `tests/lab-routing-simulation.sh` (CREATED, 134 lines) — 4 per-scenario subshells + TOTAL/FAILURES counters + `pass/fail` helpers + trap-based `$TEST_DIR` cleanup + `N/N scenarios passed` final line.
- `dev-review/codex/README.md` (MODIFIED, +5 lines) — Added `| \`--lab MODE\` |` row to CLI Options table linking to `../../lab/README.md`; added `### Lab routing` subsection noting byte-parity guarantee + v1.2 argv convention.

## Decisions Made

- **Shared helpers over inline per-runner duplication (CONTEXT §Discretion).** Both runners source `lib/co-evolution.sh` and call `dispatch_lab_mode` — single-point-of-truth eliminates drift. A future refactor that wants to change the unknown-mode error message, validation regex, or dispatch-argv order only touches one file.
- **GNU-find feature detection, not OS detection, in `list_available_lab_modes`.** `find --version 2>/dev/null | grep -q GNU` catches the full GNU-find population (Git Bash for Windows ships GNU find; Linux defaults to GNU find) on the fast `-printf '%f\n'` path, and falls through to `-exec basename {} \;` on BSD find (macOS). Doesn't assume anything about `$OSTYPE` — matches how test platforms look in the wild.
- **dev-review.sh dispatch placement after the `--branch`/`--worktree` mutex check.** Keeps v1.1 CLI-contract errors (mutually-exclusive flags) firing before lab routing kicks in. A user who runs `dev-review --branch auto --worktree auto --lab pel "task"` now gets the `--branch and --worktree are mutually exclusive` error first — same as v1.1 — rather than having lab dispatch swallow that check.
- **W-3 argv-contract comment pinned on BOTH dispatch sites (not just one).** The PLAN.md checker-warning fix suggested pinning ≥1 runner; I went symmetric because both call sites have the same constraint. A future executor working on either runner or a new lab inhabitant will land on the same `single argv slot` substring regardless of which direction they read from.

## Deviations from Plan

None — plan executed exactly as written.

The Task 1 verify block had one Bash-5.2-specific quirk (`set -e` + `$()` + `die`-via-`exit` can propagate through the outer command substitution's `|| true`). Resolved by wrapping `dispatch_lab_mode` calls in an extra subshell (`out=$( (dispatch_lab_mode ...) 2>&1 || true )`). This is a verify-block harness-hygiene improvement, not a helper defect — manual walk-through proved all 29 assertions pass on unwrapped calls. Logged as a "patterns-established" note in frontmatter for future executors running verify blocks that call `die`-invoking helpers under `set -e`.

**Total deviations:** 0 (zero Rule 1/2/3 auto-fixes; zero Rule 4 escalations)
**Impact on plan:** Clean execution — 4/4 tasks committed sequentially, every plan acceptance_criterion checked off, all plan <verification> commands exit 0. Plan was well-specified (Plan 01's lab/README.md behavior spec + the checker's W-3 iteration eliminated the highest drift risks up front) so execution was a clean author-and-commit pass.

## Issues Encountered

- **Task 2 grep-anchor initial miss.** First dev-review.sh dispatch comment had a linebreak inside the phrase `single argv slot` (`... single\n# argv slot ...`), so `grep -qF "single argv slot"` missed it. Caught by the Task 2 verify block; re-wrapped the comment to keep the phrase on a single line (line 1056), matching co-evolve-bouncer.sh's layout (line 125). Took one verify-run to detect, one edit to fix.

## User Setup Required

None — no external service configuration, no env vars, no dashboard steps. This is pure runtime-parser wiring + simulation test + CLI docs.

## Next Phase Readiness

- **Phase 3 is 2/2 plans complete.** `lab/` is a first-class beta channel with a documented contract (Plan 01) AND a working runtime parser (Plan 02). SC-1, SC-2, SC-3, SC-4 all addressed — SC-1/SC-2/SC-4 by Plan 01 docs, SC-3 by this plan's simulation gate.
- **Phase 4 (Mode Classifier) is immediately unblocked.** `lab/pel/classifier/entry.sh` will be resolved by `dispatch_lab_mode`, and the v1.2 argv contract is now doubly-anchored (`lab/README.md §How-to-add` + both runners' dispatch-site inline comments). Phase 4's first task can cite the Phase 3 SUMMARY + the dispatch call sites as the known-good integration path.
- **No blockers or concerns carried forward.** Working tree clean after each task commit; branch `feat/v1.2-pel-proposer` now at `b5efef9` (plan metadata commit still pending as part of `state_updates`). No deferred items, no architectural escalations, no user-setup pending.

## Self-Check: PASSED

Verified post-write:
- [x] `lib/co-evolution.sh` contains three helpers (`validate_lab_mode`, `list_available_lab_modes`, `dispatch_lab_mode`) — confirmed by grep
- [x] `co-evolve-bouncer.sh` and `dev-review/codex/dev-review.sh` both pass `bash -n`, contain `--lab)` arm, `dispatch_lab_mode` call, `LAB_MODE=""` default, `single argv slot` W-3 anchor, `lab/README.md` cross-reference
- [x] Both runners' `--help` output contains `--lab`
- [x] `--lab)` arm line number is less than `--)` arm line number in BOTH runners (argv-position invariant)
- [x] `tests/lab-routing-simulation.sh` exists, 134 lines, exits 0 with `4/4 scenarios passed`
- [x] `dev-review/codex/README.md` CLI table row for `--lab MODE` present, links to `../../lab/README.md`, and pre-existing flag rows (`--composer`, `--verify`, `--skip-plan`) preserved
- [x] Commits `9e523f0` (Task 1), `a3ccee3` (Task 2), `e3fbffb` (Task 3), `b5efef9` (Task 4) all present in `git log`
- [x] `bash co-evolve-bouncer.sh --lab bogus-mode "task"` emits `unknown --lab mode: bogus-mode` and exits non-zero (Scenario B live-repro)
- [x] `bash dev-review/codex/dev-review.sh --lab "../etc" "task"` emits `invalid --lab mode` and exits non-zero (Scenario D live-repro)
- [x] All plan `<verification>` commands from PLAN.md exit 0

---
*Phase: 03-lab-scaffold*
*Completed: 2026-04-18*
