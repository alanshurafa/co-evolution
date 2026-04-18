---
phase: 03-lab-scaffold
verified: 2026-04-17T23:55:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 3: Lab Scaffold Verification Report

**Phase Goal:** Establish the `lab/` subdirectory as a first-class beta channel with documented conventions, so every future opt-in feature (PEL tiers, future experiments) has a clear home.
**Verified:** 2026-04-17T23:55:00Z
**Status:** passed
**Re-verification:** No — initial verification.

## Goal Achievement

### Observable Truths (from ROADMAP §Phase 3 Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `lab/` dir exists with `README.md` encoding default/lab boundary, promotion flow, graduation criteria, anti-criteria | VERIFIED | `lab/README.md` (127 lines) present; all 6 graduation items + 4 anti-criteria + 5 lab-worthy + 3 disambiguation items grep-verified |
| 2 | `lab/README.md` lists current + planned inhabitants (`lab/pel/` for v1.2; `lab/pel-auto/` + `lab/pel-explorer/` as v1.3+ placeholders NOT created) | VERIFIED | `ls lab/` returns ONLY README.md (no subdirs); README lines 99-107 document all three with NOT-created annotations for v1.3+ placeholders |
| 3 | `co-evolve` + `dev-review` parse `--lab <mode>` routing; byte-parity for default invocations verified via simulation | VERIFIED | `bash tests/lab-routing-simulation.sh` → `4/4 scenarios passed`; both runners carry `--lab)` arm + `LAB_MODE=""` default + `dispatch_lab_mode` call; --lab arm precedes -- terminator in both |
| 4 | `lab/README.md` documents sandbox guarantee | VERIFIED | README lines 71-75 (`## Sandbox guarantee` + `--lab <mode>` runs cannot modify master directly... only via emitted PRs that a human reviews and merges) |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lab/README.md` | 127 lines, user-facing lab contract | VERIFIED | Exists, 127 lines exact, all 16 verbatim items present |
| `lab/` dir | Contains ONLY README.md (no premature subdirs per L-09) | VERIFIED | `ls lab/` → only `README.md` |
| `README.md` (repo) | `### [Lab](lab/)` subsection | VERIFIED | Lines 34-44 present between Claude Code Skill and Picking the right entrypoint |
| `AGENTS.md` | `## Lab Subdirectory` section OUTSIDE GSD blocks | VERIFIED | Lines 149-153 present AFTER final `<!-- GSD:profile-end -->` marker |
| `lib/co-evolution.sh` | 3 helpers (`validate_lab_mode`, `list_available_lab_modes`, `dispatch_lab_mode`) | VERIFIED | All 3 present in new `# --- Lab routing (Phase 3 LAB-01) ---` section (lines 69-132); regex `^[a-zA-Z0-9_-]+$` at line 83 |
| `co-evolve-bouncer.sh` | `--lab MODE` arm + `LAB_MODE=""` default + dispatch call | VERIFIED | LAB_MODE at line 24; --lab) at line 93 (before -- at 98); dispatch at line 129 |
| `dev-review/codex/dev-review.sh` | `--lab MODE` arm + `LAB_MODE=""` default + dispatch call | VERIFIED | LAB_MODE at line 50; --lab) at line 1012 (before -- at 1024); dispatch at line 1061 |
| `tests/lab-routing-simulation.sh` | 4-scenario hermetic gate | VERIFIED | 134 lines; exits 0 with `4/4 scenarios passed` on local execution |
| `dev-review/codex/README.md` | CLI row + `### Lab routing` subsection | VERIFIED | `--lab MODE` row at line 46; Lab routing subsection at lines 48-50 linking to `../../lab/README.md` |

### Key Link Verification (Discoverability + Wiring)

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `README.md` (repo) | `lab/README.md` | `[Lab](lab/)` markdown link + bash examples | WIRED | Line 34 anchor, line 36 link to `lab/README.md`, bash example at 38-42 |
| `AGENTS.md` | `lab/README.md` | Markdown link in `## Lab Subdirectory` | WIRED | Line 151 links to `lab/README.md`; placement outside GSD blocks confirmed |
| `co-evolve-bouncer.sh` | `lib/co-evolution.sh` helpers | `source "$SCRIPT_DIR/lib/co-evolution.sh"` + `dispatch_lab_mode` call | WIRED | Source at line 5; call at line 129 |
| `dev-review/codex/dev-review.sh` | `lib/co-evolution.sh` helpers | source + `dispatch_lab_mode` call | WIRED | Call at line 1061 passes `REPO_ROOT/lab` correctly |
| `dispatch_lab_mode` | `lab/<mode>/entry.sh` | `exec bash "$entry" "$@"` | WIRED | Line 131 of lib/co-evolution.sh; argv contract preserved (W-3) |
| `lab/README.md` | `.planning/seeds/pel-auto-promote-and-explorer.md` | Markdown links from placeholders | WIRED | Lines 106-107 link to seed file; relative path `../.planning/seeds/...` |
| `lab/README.md` | `.planning/notes/co-evolution-lab-concept.md` | Markdown link in Further reading | WIRED | Line 125 cites concept note as authoritative source |

### Data-Flow Trace (Level 4)

Not applicable — Phase 3 produces docs + arg-parser wiring, not dynamic-data renderers. Level 4 is reserved for components that consume runtime state; the `--lab <mode>` dispatch simply exec's the resolved entry.sh, which has no inhabitants in Phase 3 (by design, L-09).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Simulation gate (SC-3) | `bash tests/lab-routing-simulation.sh` | `4/4 scenarios passed` | PASS |
| Unknown-mode fail-fast on co-evolve (L-04) | `bash co-evolve-bouncer.sh --lab pel-proposer "test"` | `ERROR: unknown --lab mode: pel-proposer. Available: (none)` | PASS |
| Path-traversal rejection on dev-review (T-03-02-01) | `bash dev-review/codex/dev-review.sh --lab '../etc' "x"` | `ERROR: invalid --lab mode: ../etc (must match [A-Za-z0-9_-]+)` | PASS |
| --lab row visible in co-evolve usage (SC-3 + docs) | `bash co-evolve-bouncer.sh --help \| tail` | `--lab MODE Route to lab/<MODE>/entry.sh ...` row present | PASS |
| --lab row visible in dev-review usage (SC-3 + docs) | `bash dev-review/codex/dev-review.sh --help \| grep lab` | `--lab MODE Route to lab/<MODE>/entry.sh ...` row present | PASS |
| Syntax validity all four scripts | `bash -n` on all affected files | no errors | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| LAB-01 | 03-01 + 03-02 | Create `lab/` directory, `lab/README.md` documenting (a) boundary, (b) promotion flow, (c) graduation criteria (6 items), (d) anti-criteria (4 items), (e) first inhabitants (`lab/pel/`) | SATISFIED | All 5 sub-clauses verified; REQUIREMENTS.md traceability table shows `LAB-01 \| Phase 3 \| Completed (2026-04-18)` |

### 16 Verbatim Items — Byte-Exact Pin Spot-Check

| Category | Count | Spot-Check Evidence |
|----------|-------|---------------------|
| Graduation criteria (L-06) | 6/6 | Lines 41-46: `Runtime signal`, `Test parity`, `Documented failure modes`, `User signal`, `Rollback path`, `Name + API stable` — all grep-present |
| Anti-criteria (L-07) | 4/4 with cause+consequence | Lines 54-57: `nobody actually wants it`, `signal never stabilized`, `obviated it → redundant`, `full rewrite → cut losses` — all dual-anchored (cause + consequence) |
| Lab-worthy rubric (L-08) | 5/5 | Lines 29-33: `brick the core runner`, `correctness signal takes weeks`, `trades safety for power`, `infrastructure that doesn't exist`, `architectural bet` — all grep-present |
| Disambiguation (L-01) | 3/3 | Lines 65-67: `C:/Users/alan/Project/co-evolution-lab/`, `runners/codex-ps/`, `experiments/` — all grep-present with verbatim explanations |

### Locked Decisions L-01..L-09 — Materialization Audit

| Decision | Where materialized | Status |
|----------|--------------------|--------|
| L-01 — `lab/` distinct from peer `co-evolution-lab/` workspace | `lab/README.md` §"What's NOT the lab" (3 verbatim items, lines 61-69) | SATISFIED |
| L-02 — Flag syntax `--lab <mode>` long-form only | Both runners use `--lab)` arm; no `-l` short form; no env-var-only path | SATISFIED |
| L-03 — Byte-parity when `--lab` absent | `LAB_MODE=""` default + `if [[ -n "$LAB_MODE" ]]` guard in both runners; Scenario A of simulation verifies --help parity | SATISFIED |
| L-04 — Fail-fast on unknown mode | `dispatch_lab_mode` dies with `unknown --lab mode: X. Available: <list>`; live repro confirmed | SATISFIED |
| L-05 — Sandbox guarantee documented (not enforced) | `lab/README.md` §"Sandbox guarantee" (lines 71-75) | SATISFIED |
| L-06 — Graduation criteria 6 verbatim items | Lines 41-46 byte-exact from concept note | SATISFIED |
| L-07 — Anti-criteria 4 verbatim items with cause+consequence | Lines 54-57 dual-anchored per W-1 | SATISFIED |
| L-08 — Lab-worthy rubric 5 verbatim items | Lines 29-33 byte-exact from concept note | SATISFIED |
| L-09 — README lists first inhabitants; no placeholder dirs created | `ls lab/` → only README.md; lines 99-107 table lists all three with NOT-created annotations | SATISFIED |

### W-1 Strengthening (Anti-Criteria Cause→Consequence Dual-Anchor)

| Anti-criterion | Cause phrase | Consequence phrase | Status |
|----------------|--------------|--------------------|--------|
| 1 | `User hasn't invoked it in months` | `nobody actually wants it` | ANCHORED (line 54) |
| 2 | `fitness signal never stabilized` | `we don't know if it's helping` | ANCHORED (line 55) |
| 3 | `simpler pattern in core obviated it` | `redundant` | ANCHORED (line 56) |
| 4 | `breaks in a way we can't fix without a full rewrite` | `cut losses` | ANCHORED (line 57) |

All 4 consequence anchors present — paraphrase-drift regressions would fail the grep gate.

### W-3 Argv Contract (Triple-Pin)

| Location | Phrase anchor | Line | Status |
|----------|---------------|------|--------|
| `lab/README.md` | `full task string as` + `single argument` | Line 121 | ANCHORED |
| `co-evolve-bouncer.sh` dispatch comment | `single argv slot` | Line 125 | ANCHORED |
| `dev-review/codex/dev-review.sh` dispatch comment | `single argv slot` | Line 1056 | ANCHORED |

Triangulated — future executors reading any of the three land on the same contract.

### Path-Traversal Defense (T-03-02-01)

| Control | Evidence |
|---------|----------|
| Regex `^[a-zA-Z0-9_-]+$` in `validate_lab_mode` | `lib/co-evolution.sh:83` |
| Validation runs BEFORE any filesystem op | `dispatch_lab_mode` lines 121-123 of lib — validate first, then resolve entry path |
| Live rejection | `bash dev-review/codex/dev-review.sh --lab '../etc'` → `ERROR: invalid --lab mode: ../etc (must match [A-Za-z0-9_-]+)` |
| Simulation coverage | Scenario D exercises both `../etc` and `foo;rm` on both runners |

### Commit Integrity

Atomic Phase 3 commit train (from `git log --oneline feat/v1.2-pel-proposer -15`):

| Commit | Description |
|--------|-------------|
| `b38c141` | docs(03-lab-scaffold): generate context from concept note |
| `c9d3c7b` | docs(03-lab-scaffold): create phase plan |
| `7b5d7f9` | docs(03-lab-scaffold): revise plans per checker — W-1/W-3 fixes |
| `fe2f4de` | chore(03-lab-scaffold): begin phase 3 execution |
| `36a4f14` | docs(03-lab-scaffold): create lab/README.md with the v1.2 beta-channel contract |
| `ab8b6e1` | docs(03-lab-scaffold): wire lab/ discoverability into repo-level README + AGENTS |
| `c51d749` | docs(03-lab-scaffold): complete plan 01 |
| `9e523f0` | feat(03-lab-scaffold-02): add lab-routing helpers to lib/co-evolution.sh |
| `a3ccee3` | feat(03-lab-scaffold-02): wire --lab <mode> into both runners |
| `e3fbffb` | test(03-lab-scaffold-02): add hermetic --lab routing simulation (4 scenarios) |
| `b5efef9` | docs(03-lab-scaffold-02): document --lab <mode> in dev-review CLI table |
| `7909309` | docs(03-lab-scaffold-02): complete plan 02 (Phase 3 Lab Scaffold shipped) |

One commit per task, imperative mood, conventional-commits style, phase-scoped. Working tree clean (git status --porcelain returned empty).

### Anti-Patterns Found

None.

Shell code was audited — no TODO/FIXME/HACK/PLACEHOLDER strings in Phase 3 files, no empty implementations, no hardcoded stubs rendering user-visible output, no console.log-only handlers. `bash -n` clean across co-evolve-bouncer.sh, dev-review.sh, lib/co-evolution.sh, and tests/lab-routing-simulation.sh.

### Human Verification Required

None. Phase 3's scope is entirely programmatically verifiable:
- Documentation (grep-pinned verbatim items)
- Shell parser wiring (syntax check + live repro)
- Simulation gate (deterministic 4/4 scenarios)
- Directory layout (`ls lab/`)
- Commit log (`git log`)

No UI, no real-time behavior, no external service integration, no performance-feel judgments. The deferred artifacts (actual `lab/pel/` machinery) are Phase 4+'s verification surface, not Phase 3's.

### Gaps Summary

None. Phase 3 achieves its stated goal with zero outstanding work:

- **Identity layer (Plan 01):** `lab/` is a documented beta channel with a contract that downstream phases must honor.
- **Runtime layer (Plan 02):** Both runners parse `--lab <mode>`, dispatch through a shared helper with injection defense, and the 4-scenario simulation gate proves byte-parity + fail-fast + validation + inter-runner parity.
- **Discoverability layer:** Repo-level `README.md` + `AGENTS.md` + `dev-review/codex/README.md` all reference `lab/README.md` as the single contract source.
- **Policy layer:** 16 verbatim items, 9 locked decisions (L-01..L-09), W-1 dual-anchor, W-3 triple-pin, and the path-traversal regex are all materialized and grep-pinnable.

**SHIP recommendation:** READY TO SHIP. All four ROADMAP Success Criteria verified, LAB-01 SATISFIED, all 9 locked decisions materialized, all revision-iteration mitigations (W-1 + W-3) present. No blockers, no human verification pending, no deferred-to-later-phase items within Phase 3's scope. Working tree clean; proceed to Phase 4 (Mode Classifier).

---

*Verified: 2026-04-17T23:55:00Z*
*Verifier: Claude (gsd-verifier)*
