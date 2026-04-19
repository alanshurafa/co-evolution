---
phase: 02-bash-eval-harness-port
plan: 03
subsystem: eval-harness
tags: [bash, orchestrator, comparator, regression-gate, hermetic-test, fake-runner, tier-1, tier-2, tier-3, port, pel-prerequisite]

# Dependency graph
requires:
  - phase: 02-bash-eval-harness-port
    provides: "evals/lib/co-evolution-evals.sh (Plan 02-01) + evals/score-run.sh (Plan 02-02)"
provides:
  - "evals/run-evals.sh orchestrator (383 LOC) with --runner-path override"
  - "evals/compare-reports.sh two-report comparator (154 LOC)"
  - "evals/tests/fake-runner.sh hermetic test double (177 LOC)"
  - "evals/tests/scorer-verification.sh combined Tier 1+2+3 gate (234 LOC)"
  - "Updated evals/README.md framing Bash as default + PS as legacy"
  - "13/13 scenarios regression gate operational on any Bash+jq+yq environment"
affects: [pel-proposer-phases-5-8, roadmap-sc-3, ci-simulation-multi-platform]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Orchestrator CLI with --runner-path override: default dev-review.sh; hermetic fake-runner for Tier 2 without LLM cost"
    - "Pre/post listing diff of evals/reports/ to locate new report dir (keeps run-evals.sh CLI surface stable; Tier 2 scenarios clean up after themselves)"
    - "Fake runner as hermetic test double: deterministic FAKE_TS, explicit test-path location, stderr banner on every invocation, state.json mode tag"
    - "Combined verification gate: Tier 1 fixture loop via glob + Tier 3 determinism + Tier 2 end-to-end PASS/FAIL scenarios in a single script with scenario counter and uniform PASS:/FAIL: log format"
    - "Compare-reports: jq --slurpfile two-file diff with score-ordering map (PASS=3, PARTIAL=2, FAIL=1) + Unicode arrows (↓/↑) for per-dimension regression indicators"
    - "Robustness exit-code policy pinned in source AND exercised by test: grep for '(( robust_fails > 0 ))' AND a FAKE_MODE=fail-robustness scenario that expects exit 1"

key-files:
  created:
    - "evals/run-evals.sh (383 LOC) — orchestrator with --runner-path"
    - "evals/compare-reports.sh (154 LOC) — two-report comparator"
    - "evals/tests/fake-runner.sh (177 LOC) — hermetic test double"
    - "evals/tests/scorer-verification.sh (234 LOC) — combined Tier 1/2/3 gate"
  modified:
    - "evals/README.md (103 → 155 lines, +52) — Bash default, PS legacy, jq+yq deps, Tier 1/2/3 verification"

key-decisions:
  - "ASCII double-hyphen ('FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION') chosen over em-dash in the fake-runner banner to dodge Git Bash for Windows stdout-encoding quirks; source + acceptance greps align on the same string"
  - "Fake plan.md uses un-indented headings (no leading whitespace) so the scorer's anchored regex ^#+[[:space:]]+(Plan|Approach|...) matches on first try; heredoc chosen over printf to preserve multi-line structure cleanly"
  - "Fake verdict.json populates ALL 6 schemas/review-verdict.json required fields (verdict, confidence, summary, issues, scope_creep_detected, iteration_notes) -- the plan snippet only listed 4; catching this at design time avoided a scorer-side sentinel trigger"
  - "Fake state.json carries `mode: \"fake-runner\"` tag plus verify_verdict, completed_at, current_phase, marker_counts, changed_files so the scorer consumes identical shape to real dev-review.sh output; scored composite == 1.0 on PASS scenario matches 01-all-pass baseline"
  - "Tier 2 scenarios use pre/post listing diff of evals/reports/ via `comm -13` rather than adding a --reports-dir override to run-evals.sh; keeps orchestrator CLI surface stable and test purely additive"
  - "Tier 2 FAIL assertion accepts 3 outcomes (scored+robustness=FAIL, scorer-failed, fail) because different scorer/orchestrator paths can signal failure differently; empirically fake-runner produces `status=\"scored\"` + `scores.robustness=\"FAIL\"`"
  - "compare-reports.sh uses Unicode arrows (↓/↑) verbatim per PS source; Git Bash Windows renders them cleanly, no ASCII fallback needed (avoided visual divergence from PS)"
  - "Orchestrator's run_tier2_scenario cleanup defers report-dir deletion until AFTER both scenarios run, so a Tier 2 failure preserves the artifacts for post-mortem"

patterns-established:
  - "Hermetic end-to-end smoke via fake runner: D-09 Tier 2 is NOT deferred; the test runs run-evals.sh --runner-path against a test-path-isolated double that emits a deterministic run subtree"
  - "W-02 execution coverage via paired source-grep + runtime assertion: grep for 'robust_fails > 0' branch presence in run-evals.sh, plus a Tier 2 FAIL scenario that expects exit 1. Proves the branch exists AND runs"
  - "Test-path isolation for sensitive test infrastructure: fake-runner lives under evals/tests/ with explicit banner + mode tag so downstream consumers detect synthetic data"
  - "Report-dir timestamp collision via suffix bump: while [[ -e ... ]] do ts-N done; non-racing on single-process invocation, acceptable at the v1.2 posture"

requirements-completed: [BASH-EVAL-01]

# Metrics
duration: "18min 12s"
started: "2026-04-18T13:39:19Z"
completed: "2026-04-18T13:57:31Z"
tasks: 4
files_created: 4
files_modified: 1
scorer_verification: "13/13 scenarios passed"
scorer_verification_runtime_seconds: 47
---

# Phase 2 Plan 3: Runner + Comparator + Hermetic Tier 2 Gate Summary

**Shipped the orchestrator (`evals/run-evals.sh`, 383 LOC with `--runner-path` override), the comparator (`evals/compare-reports.sh`, 154 LOC), the hermetic fake runner (`evals/tests/fake-runner.sh`, 177 LOC), and the combined Tier 1+2+3 regression gate (`evals/tests/scorer-verification.sh`, 234 LOC) — all 13 scenarios pass green: 10 Tier 1 fixtures + 1 Tier 3 determinism + 2 Tier 2 hermetic end-to-end. README reframed to Bash-default with PS legacy reference intact.**

## Performance

- **Duration:** 18 min 12 s
- **Started:** 2026-04-18T13:39:19Z
- **Completed:** 2026-04-18T13:57:31Z
- **Tasks:** 4 (Task 1 run-evals + Task 2a fake-runner + Task 2b compare+verify + Task 3 README)
- **Files created:** 4
- **Files modified:** 1
- **Combined gate runtime:** 47 s (budget 90 s; comfortable margin)

## Primary Gate Result (D-09)

```
$ bash evals/tests/scorer-verification.sh
PASS: Tier 1 / Suite 01-all-pass
PASS: Tier 1 / Suite 02-robustness-fail
PASS: Tier 1 / Suite 03-convergence-partial
PASS: Tier 1 / Suite 04-plan-quality-fail
PASS: Tier 1 / Suite 05-exec-fidelity-mismatch
PASS: Tier 1 / Suite 06-verify-catches-hallucination
PASS: Tier 1 / Suite 07-verify-misses-hallucination
PASS: Tier 1 / Suite 08-unparseable-verdict
PASS: Tier 1 / Suite 09-cross-ai-rubber-stamp
PASS: Tier 1 / Suite 10-cross-ai-genuine-bounce
PASS: Tier 3 / Determinism: two runs produced byte-identical output (after stripping scored_at)
PASS: Tier 2 / pass-e2e (exit 0, report exists + non-empty, JSON valid, record count=1)
PASS: Tier 2 / fail-robustness-e2e (exit 1, report exists + non-empty, JSON valid, record count=1)
13/13 scenarios passed
```

**Exit 0. Final line EXACTLY `13/13 scenarios passed`.** No FAIL: lines on stderr. No artifacts left behind in `evals/reports/`.

## Accomplishments

### Tier 1 (golden-fixture regression, primary gate)

All 10 fixture suites under `runners/codex-ps/evals/tests/fixtures/` produce `.scores` objects byte-equal to `EXPECTED.json` under `jq -S`. Scorer (02-02's 675-LOC port) passes every suite:

| Fixture | Expected Outcome | Bash Output |
|---|---|---|
| 01-all-pass | 6×PASS + cross_ai=N/A | ✓ |
| 02-robustness-fail | robustness=FAIL | ✓ |
| 03-convergence-partial | convergence=PARTIAL | ✓ |
| 04-plan-quality-fail | plan_quality=FAIL | ✓ |
| 05-exec-fidelity-mismatch | execution_fidelity=FAIL | ✓ |
| 06-verify-catches-hallucination | verify_accuracy=PASS | ✓ |
| 07-verify-misses-hallucination | verify_accuracy=FAIL | ✓ |
| 08-unparseable-verdict | verify_accuracy=FAIL (sentinel) | ✓ |
| 09-cross-ai-rubber-stamp | cross_ai_diversity=FAIL | ✓ |
| 10-cross-ai-genuine-bounce | cross_ai_diversity=PASS | ✓ |

Test uses `glob` not hardcoded list (T-02-03-08): new suites auto-covered.

### Tier 2 (hermetic end-to-end smoke — IMPLEMENTED, not deferred)

**PASS scenario** (`FAKE_MODE=pass`):
- `run-evals.sh --case 01-trivial-task --runner-path evals/tests/fake-runner.sh`
- Observed exit: **0** (expected 0) ✓
- `report.md` exists + non-empty ✓
- `raw-scores.json` parses via `jq empty`, 1 record ✓
- Record: `status="scored"`, `scores.robustness="PASS"`, `composite=1.0` ✓

**FAIL scenario** (`FAKE_MODE=fail-robustness`):
- Same command with `FAKE_MODE=fail-robustness`
- Observed exit: **1** (expected 1) ✓ — **proves `(( robust_fails > 0 ))` branch actually runs, closes W-02 execution-assertion gap**
- `report.md` exists + non-empty ✓
- `raw-scores.json` parses via `jq empty`, 1 record ✓
- Record: `status="scored"`, `scores.robustness="FAIL"` ✓

**SC-3 resolution:** The Tier 2 scenarios depend only on Bash + jq + yq + coreutils — available on every SC-3 target platform (Git Bash / Linux / macOS). A developer on any platform runs `bash evals/tests/scorer-verification.sh` and executes a complete multi-platform CI simulation of the orchestrator path without `pwsh`.

### Tier 3 (determinism sanity)

Scoring fixture 01-all-pass twice produces byte-identical output after stripping `.scored_at`:

```
$ jq -S 'del(.scored_at)' run1.json > n1.norm.json
$ jq -S 'del(.scored_at)' run2.json > n2.norm.json
$ diff -q n1.norm.json n2.norm.json
(silent — byte-identical)
```

No `$RANDOM`, no `uuidgen`, no nanosecond clock in the hot path (inherited from Plan 02-02's scorer).

### Tier 4 (PEL dogfood)

REMAINS deferred to v1.2 Phase 5+ per CONTEXT.md D-09. Not a Phase 2 gate. Will surface when template proposer lands in Phase 5.

## `--validate` coverage

```
$ bash evals/run-evals.sh --validate
Using runner: /c/Users/alan/Project/co-evolution-v12/dev-review/codex/dev-review.sh
Validating 9 case YAML(s)...
validated: .../evals/cases/01-trivial-task.yaml
validated: .../evals/cases/02-simple-md-edit.yaml
validated: .../evals/cases/03-contested-decision.yaml
validated: .../evals/cases/04-hallucination-trap.yaml
validated: .../evals/cases/05-ambiguous-task.yaml
validated: .../evals/cases/06-multi-file-refactor.yaml
validated: .../evals/cases/07-real-doc-bounce.yaml
validated: .../evals/cases/08-real-code-refactor.yaml
validated: .../evals/cases/09-real-python-refactor.yaml
OK: 9 cases validated
```

All 9 production cases parse + merge + validate required fields (`id`, `runner.task`, `runner.composer`, `runner.executor`) + path-safe id check. No LLM cost.

## Task Commits

1. **Task 1: Port run-evals orchestrator with --runner-path override** — `c7f24bc` (feat)
   - 383 LOC. Sources lib/co-evolution.sh + evals/lib/co-evolution-evals.sh.
   - All STRIDE mitigations (T-02-03-01..06, T-02-03-10) wired.
2. **Task 2a: Add hermetic fake runner for Tier 2** — `62bde02` (feat)
   - 177 LOC. Two modes: pass | fail-robustness. ASCII banner + mode tag + test-path location.
3. **Task 2b: Add comparator + combined Tier 1/2/3 gate** — `59e7b26` (feat)
   - 154 LOC (compare-reports.sh) + 234 LOC (scorer-verification.sh).
   - 13/13 scenarios pass green on first run.
4. **Task 3: Reframe README — Bash default, PS legacy** — `658039e` (docs)
   - +63 / -11 lines. All acceptance grep checks pass.

Plan-metadata commit follows.

## API Surface Shipped

### `evals/run-evals.sh`

```
Usage: evals/run-evals.sh [OPTIONS]
  --case NAME | --cases NAME,...  Run a single / list of cases.
  --validate                      Parse + merge only; no runner invocation.
  --keep-fixtures                 Preserve tmp fixture dirs (debug aid).
  --skip-scoring                  Run cases but skip scoring.
  --repeat N                      Run each selected case N times (default 1).
  --runner-path PATH              Override runner binary (default dev-review.sh).
  --help, -h                      Show help.
```

Outputs: `evals/reports/<ts>/raw-scores.json` + `report.md` + `runs/<case-id-iter>/`. Exit 0 iff every case passes Robustness.

### `evals/compare-reports.sh`

```
Usage: evals/compare-reports.sh --before DIR --after DIR [--output PATH]
```

Emits per-case dimension-diff markdown table with `↓`/`↑` arrows. Exit 0 iff no Robustness regression.

### `evals/tests/fake-runner.sh`

```
FAKE_MODE=pass|fail-robustness bash evals/tests/fake-runner.sh \
  --composer STR --executor STR --bounces N [--verify] [--autonomous] -- TASK
```

Writes `.co-evolution/runs/fake-19700101-000000/` subtree under CWD. Emits `FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION` on stderr EVERY invocation. state.json carries `"mode": "fake-runner"`. Unknown flags silently accepted (forward-compat).

### `evals/tests/scorer-verification.sh`

```
bash evals/tests/scorer-verification.sh
```

No args. Exit 0 on `13/13 scenarios passed`; exit 1 otherwise.

## README Diff Summary

| Section | Action |
|---|---|
| `## Bash Harness (default)` | ADDED (new, ~50 lines) — invocation, deps, verification |
| `## Legacy PowerShell Harness` | RENAMED (from `## Running Evals Today`) — PS code block preserved verbatim per D-04 |
| `## pwsh Dependency — Optional` | UPDATED — added `evals/*.sh` row, flipped PS evals row to `Yes (legacy)` |
| `## Layout` | UNCHANGED |
| `## Case Schema Convention` | UNCHANGED |
| `## Reference` | UNCHANGED |
| "Bash port deferred to post-milestone" paragraph | REMOVED — replaced with forward-pointer to new Bash section |

Line count: 103 → 155 (+52). Grep confirms `deferred` appears 0 times in the verification subsection (no deferral language for Tier 2).

## Deviations from Plan

None required auto-fixing by deviation rules. All implementation decisions are scope-tightening within the plan's explicit guidance:

1. **[Discretion - Banner ASCII variant]** Plan said "if em-dash encoding is problematic... substitute `FAKE RUNNER --` with a double-hyphen ASCII variant and update acceptance grep". I proactively picked the ASCII variant from the start because the project's CLAUDE.md notes Git Bash on MINGW64 as the primary environment, and my Plan 02-02 summary documented em-dash-related quirks. Source + acceptance grep align on the ASCII string.

2. **[Discretion - Fake verdict schema completeness]** Plan snippet for fake verdict.json showed 4 required fields (verdict, confidence, summary, issues); actual schema requires 6 (adds `scope_creep_detected`, `iteration_notes`). Wrote the fake verdict with all 6 fields so it is schema-compliant — defensive against future scorer tightening.

3. **[Discretion - Fake state.json shape]** Plan snippet for state.json showed minimal fields (run_id, status, started, ended, composer, executor, history, mode); I added `task`, `reviewer`, `max_bounces`, `verify`, `autonomous`, `status_detail`, `current_phase`, `marker_counts`, `changed_files`, `verify_verdict`, `completed_at` to match the shape of `runners/codex-ps/evals/tests/fixtures/01-all-pass/run/state.json`. Resulting scored composite == 1.0 on PASS scenario, matching 01-all-pass baseline. Any missing field would surface as `plan_quality=FAIL` or `cost=N/A` via the scorer's jq defaults — wired all of them proactively.

No Rule 4 architectural changes. No auth gates. No user intervention needed.

## Issues Encountered

1. **README edit triggered a READ-BEFORE-EDIT hook reminder** — I had already Read the file earlier in this session (during the initial context load), so the edit succeeded without re-reading. Noted the hook message, confirmed the edit landed cleanly with all acceptance greps green.

2. **Git CRLF warnings on every new script commit** (cosmetic). Files on disk are LF (correct for Bash); Git Bash default `core.autocrlf=true` rewrites to CRLF on checkout. Scripts tolerate both; no action needed.

3. **Initial smoke test's `---EXIT: $?` came through as 0** because `tail -10` consumed the real exit code. Re-ran without the pipe to confirm orchestrator correctly exits 1 on FAIL scenario. Not a bug in the orchestrator.

## Known Caveats for Downstream Plans

- **Phase 3 (Lab Scaffold):** harness is now PEL-ready. `lab/pel/proposer/*/` implementations in Phases 5-7 will invoke `evals/run-evals.sh --case <name>` and parse `evals/reports/<ts>/raw-scores.json`. Tier 4 (PEL dogfood) will surface in Phase 5+ when the template proposer exercises the scorer in production-realistic conditions.
- **Fake runner should never ship to a production runner path.** state.json's `"mode": "fake-runner"` tag lets any downstream consumer detect synthetic data. The explicit `evals/tests/` location + stderr banner + `--runner-path` opt-in make accidental production use visible.
- **run-evals.sh's report-dir collision handling is single-process only.** If two harness invocations start at the same second (edge case), the `while [[ -e ]]` suffix bump is not atomic. v1.2 posture accepts this — PEL phases won't stack parallel orchestrator runs until v1.3+ parallelization work.
- **compare-reports.sh uses Unicode arrows (↓/↑).** Git Bash Windows renders cleanly; Linux/macOS also fine. If a CI log viewer ever mangles them, ASCII fallback (`v`/`^`) is a one-character-class swap in the jq program.

## Total Phase 2 Artifact Inventory

7 new files + 1 updated:

| File | LOC | Plan | Commit |
|---|---|---|---|
| evals/lib/co-evolution-evals.sh | 277 | 02-01 | d46a955 |
| evals/report-template.md | 25 | 02-01 | 654ab8e |
| evals/score-run.sh | 675 | 02-02 | c52fe2d + 9945ce4 |
| evals/run-evals.sh | 383 | 02-03 | c7f24bc |
| evals/compare-reports.sh | 154 | 02-03 | 59e7b26 |
| evals/tests/fake-runner.sh | 177 | 02-03 | 62bde02 |
| evals/tests/scorer-verification.sh | 234 | 02-03 | 59e7b26 |
| evals/README.md | 155 (+52) | 02-03 | 658039e |

Total new Bash LOC: **1920** (library 277 + scorer 675 + orchestrator 383 + comparator 154 + fake 177 + test 234 + template 20).

## Deferred-to-Future-Phase Items

All explicitly out of scope per CONTEXT.md — not regressions:

- Parallel case execution (GNU parallel / xargs -P) — v1 is serial; revisit when eval runtime > 60s
- Full CI wiring (GitHub Actions etc.) — PS harness was manual-invocation; Bash port stays manual-invocation per CONTEXT.md
- Test-only pwsh dependency for defaults.yaml parser drift check — user explicitly chose NOT to add
- Porting PS test harness (Test-Scorer.ps1, regression scripts) — D-05 out-of-scope; fixture corpus alone covers it
- Tier 4 PEL dogfood — requires mutation proposer from Phase 5+

## TDD Gate Compliance

Plan frontmatter marks Task 1 + Task 2a + Task 2b as `tdd="true"`. Per Plan 02-01's precedent for this phase (self-test co-commits), the TDD artifact for Task 1 is the `--validate` + `--help` path (exercised via the plan's `<verify>` command before commit); for Task 2a it is the stderr banner + fake-runner shape assertions (exercised via the plan's `<verify>` command before commit); for Task 2b it is the `13/13 scenarios passed` assertion (exercised via the plan's `<verify>` command before commit). All three gates passed before their commits landed.

For canonical TDD RED/GREEN separation, a future plan could split acceptance into a separate `test(...)` commit. For Phase 2's acceptance-as-test pattern (consistent across 02-01/02-02/02-03), the behavior is: write the implementation → run the acceptance-grep-or-test-invocation → commit iff green. This matches the approach used through Phase 2.

## Self-Check: PASSED

Verified claims before returning:

- `evals/run-evals.sh` exists at C:/Users/alan/Project/co-evolution-v12/evals/run-evals.sh (383 LOC); `#!/usr/bin/env bash` on line 1; `set -euo pipefail` on line 24
- `evals/compare-reports.sh` exists (154 LOC); `#!/usr/bin/env bash`; `set -euo pipefail`
- `evals/tests/fake-runner.sh` exists (177 LOC); `#!/usr/bin/env bash`; `set -euo pipefail`; banner string greppable in source
- `evals/tests/scorer-verification.sh` exists (234 LOC); `#!/usr/bin/env bash`; `set -euo pipefail`
- `evals/README.md` contains `## Bash Harness (default)` + `## Legacy PowerShell Harness`; `mikefarah` + `fake-runner` greppable; `deferred` appears 0 times; PS code block `pwsh runners/codex-ps/evals/run-evals.ps1` preserved
- Commits `c7f24bc` (Task 1), `62bde02` (Task 2a), `59e7b26` (Task 2b), `658039e` (Task 3) all present in `git log --oneline` on branch `feat/v1.2-pel-proposer`
- `bash evals/run-evals.sh --help` exits 0 and mentions `--runner-path`
- `bash evals/run-evals.sh --validate` exits 0 with `OK: 9 cases validated`
- `bash evals/tests/scorer-verification.sh` exits 0 with final line `13/13 scenarios passed`
- Gate runtime: 47 s (well under 90 s budget)
- `evals/reports/` is empty after gate completes (no artifacts leaked)
- All 4 task commits include plan-subsystem scope `02-bash-eval-harness-port-03`

---
*Phase: 02-bash-eval-harness-port*
*Plan: 03 (final plan of Phase 2)*
*Completed: 2026-04-18*
