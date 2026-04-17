# Verification Plan for the Eval System

**Date:** 2026-04-17
**Status:** Proposal — ready for execution after baseline completes
**Sibling plan:** [`PLAN.md`](PLAN.md) — the eval system itself

## The Problem

The eval system at `evals/` is a judgment machine: it runs the co-evolution runner, captures artifacts, and assigns `PASS`/`PARTIAL`/`FAIL`/`N/A` on seven dimensions.

**An eval is only useful if the eval itself is correct.** If the scorer silently miscalculates, we waste hours chasing phantom problems or miss real regressions. We need a layered verification strategy that answers, for each layer of the stack:

> "Does this layer do what it claims, and how will I know when it stops?"

This plan is that strategy.

## Scope

In-scope for v1:
- The scorer (`score-run.ps1`) and its seven dimensions
- The harness (`run-evals.ps1`) and its fixture/runner/scoring pipeline
- The report renderer (`lib/Report.ps1`) and comparison tool (`compare-reports.ps1`)
- The runner's correctness *as measured by the eval* (not the eval itself being used to verify the runner — that's circular)

Out-of-scope (v2 or later):
- Automated CI integration
- Cost accounting with real token counts (Codex/Claude CLI don't expose stable telemetry yet)
- Linux/macOS portability (v1 is Windows PS 5.1 only)
- Eval for the Ollama adapter (not implemented)

## Four Verification Tiers

Tests are organized by latency and cost. Run cheap tests often, expensive tests on demand.

### Tier 1 — Unit tests for the scorer (offline, <30s)

Canned run-directory fixtures with known scores. Purely deterministic — no LLM calls, no fixture creation overhead. Catches parse errors, indexer bugs (like the Levenshtein `$i-1` bug already found), and scoring-logic regressions.

**Location:** `evals/tests/Test-Scorer.ps1` + `evals/tests/fixtures/`

**Fixtures to build:**

| Fixture | Shape | Expected scores |
|---|---|---|
| `all-pass` | state.status=completed, markers=0, plan has Goal+Risks, plan.md lists `README.md`, state.changed_files=[README.md], verdict=APPROVED | All 7 PASS |
| `robustness-fail` | state.status=running, current_phase=verify | Robustness=FAIL, everything else whatever |
| `convergence-partial` | markers.total=1 | Convergence=PARTIAL |
| `plan-quality-fail` | plan.md = 10 words, no headings | Plan=FAIL |
| `exec-fidelity-mismatch` | plan says `a.ps1`, state.changed_files=[`b.ps1`] | Exec=FAIL (jaccard=0) |
| `verify-catches-hallucination` | verdict=REVISE, issues mention "RetryAsync"; case expects must_catch_issue=true with keyword "RetryAsync" | Verify=PASS |
| `verify-misses-hallucination` | verdict=APPROVED, case expects must_catch_issue=true | Verify=FAIL |
| `unparseable-verdict` | verdict.json = `{not json` | Verify=FAIL with reason="unparseable" |
| `cross-ai-rubber-stamp` | compose.txt ≈ bounce-01.txt (edit distance < 0.05), case has composer≠reviewer | Cross-AI=FAIL |
| `cross-ai-genuine-bounce` | compose.txt and bounce-01.txt differ > 20% | Cross-AI=PASS |

**Test runner:**

```powershell
# evals/tests/Test-Scorer.ps1
$fixtures = Get-ChildItem "$PSScriptRoot/fixtures" -Directory
$failures = @()
foreach ($f in $fixtures) {
    $expected = Get-Content "$($f.FullName)/EXPECTED.json" | ConvertFrom-Json
    $actual   = & "$PSScriptRoot/../score-run.ps1" `
        -CaseFile "$($f.FullName)/case.yaml" `
        -RunDir "$($f.FullName)/run"
    foreach ($dim in $expected.scores.PSObject.Properties.Name) {
        if ($actual.scores.$dim -ne $expected.scores.$dim) {
            $failures += "[$($f.Name)] $dim: expected $($expected.scores.$dim), got $($actual.scores.$dim)"
        }
    }
}
if ($failures.Count -gt 0) { $failures | Write-Host; exit 1 }
Write-Host "OK: $($fixtures.Count) fixtures scored correctly" -ForegroundColor Green
```

**Success criterion:** 100% of fixtures score exactly as expected.

### Tier 2 — Harness plumbing (offline, <5 min)

Validates the pipeline *around* the scorer — fixture creation, artifact copy, report rendering, exit codes — without spending LLM credits.

**Tests:**
1. `run-evals.ps1 -Validate` — YAML load, fixture round-trip for all 9 cases. **Already passes.**
2. `run-evals.ps1 -Cases <id> -FakeRunner` — new `-FakeRunner` flag that, instead of invoking `run-co-evolution.ps1`, copies a canned run dir into the fixture. This exercises: seed → fixture → fake-run → artifact copy → score → report. Exercise this with 3 cases to confirm the scorer integrates cleanly with the harness and the report renders.
3. `compare-reports.ps1 <ts1> <ts2>` with two canned raw-scores.json — confirms the comparison tool flags regressions correctly.

**Implementation:** add `-FakeRunner` flag to `run-evals.ps1` that reads the canned run dir path from `case.setup.fake_run_source`.

**Success criterion:** all three tests pass, exit code 0.

### Tier 3 — End-to-end variance (online, ~15 min, ~$0.50–$1)

LLMs are non-deterministic. Two runs of the same case will produce different word counts, different diffs, different verdict phrasings. This tier quantifies that noise so we know how much to trust a single run.

**Method:**
1. Add `-Repeat N` flag to `run-evals.ps1` that runs each selected case N times.
2. Run case 01 (Codex-only, cheapest) × 3 times: `run-evals.ps1 -Cases 01-trivial-task -Repeat 3`
3. Optionally case 04 (mixed-agent with ground-truth keyword) × 3: `run-evals.ps1 -Cases 04-hallucination-trap -Repeat 3`

**Success criteria:**
- 3/3 runs have `robustness=PASS` (plumbing is deterministic)
- ≥2/3 runs agree on every dimension (one flip from PASS↔PARTIAL is acceptable; PASS↔FAIL is not)
- Composite score range ≤ 0.2 across the 3 runs

**If the criterion fails:** The scorer thresholds are too tight. Widen the bands in `defaults.yaml` (e.g. `min_jaccard` from 0.5 to 0.4), or flip the scorer to a median-of-three verdict.

**Artifact:** `evals/VARIANCE-REPORT.md` listing per-(case, dimension) min/median/max across the 3 runs.

### Tier 4 — Seeded regression detection (online, ~25 min, ~$1–$2)

**This is the single most important test.** If we deliberately break the runner, does the eval catch it? If not, the eval is useless.

**Method:** create `evals/tests/regressions/` with three deliberately-broken runner variants. Each is a copy of `scripts/run-co-evolution.ps1` with one planted bug:

| Regression | Planted bug | Expected dimension to flag |
|---|---|---|
| `regression-a-skip-bounce` | Comment out the bounce loop | Convergence (markers remain from compose) |
| `regression-b-truncate-plan` | Replace compose output with `$normalized.Substring(0, [Math]::Min(50, $normalized.Length))` | Plan quality (word count) |
| `regression-c-no-verdict` | Skip `Write-RunText verdict.json` in verify | Verify accuracy (no verdict.json) |
| `regression-d-fake-approve` | Hardcode verdict.json to `{"verdict":"APPROVED"}` regardless of real output | Verify accuracy on case 04 (must_catch_issue=true) |

**Harness change:** `run-evals.ps1 -Cases 02-simple-md-edit -UseRunner <path>` parameter that lets the harness point at an alternate runner file for one invocation.

**Success criterion:** For each of the 4 regressions, ≥1 of the expected dimensions flags FAIL or PARTIAL. If any regression scores all-PASS: the eval is blind to that class of bug — fix the scorer.

**Artifact:** `evals/SEEDED-REGRESSION-REPORT.md` with per-regression expected/actual scoring.

### Tier 5 — Human calibration (manual, ~30 min human time)

A sanity check that the eval's verdicts match what an informed human would say.

**Method:**
1. Pick 3 completed baseline runs (one PASS composite, one mid, one FAIL).
2. For each, hand-score the 7 dimensions WITHOUT looking at the automated scores.
3. Compare to the automated scores. Record agreement rate as (agreed dimensions) / 21.

**Success criterion:** ≥80% agreement. Disagreements should cluster around judgment-heavy dimensions (plan_quality), not mechanical ones (robustness, cost).

**Artifact:** `evals/META-EVAL.md` with the human scores, the automated scores, the delta, and notes.

## Execution Schedule

Assumes the current full baseline (in-flight) completes first.

### Phase V0 — Finish baseline (now, ~20 min remaining)

Already running in background (`b540hh12v`). Will auto-resume when done.

### Phase V1 — Build test infrastructure (~2 hr offline work)

Can start during V0 since it's LLM-free.

- **V1.1** (30 min): Capture 10 Tier 1 fixtures. Derive 5 from real baseline runs (copy state.json/plan.md/verdict.json into `evals/tests/fixtures/real-*/`). Synthesize the other 5 by hand-editing fixtures to trigger specific edge cases.
- **V1.2** (30 min): Write `evals/tests/Test-Scorer.ps1` — a ~60-line PS script that iterates fixtures and compares scores against `EXPECTED.json`. No dependency on Pester.
- **V1.3** (20 min): Write `evals/tests/Test-Harness-Validate.ps1` — wrapper that invokes `run-evals.ps1 -Validate` and asserts exit 0.
- **V1.4** (20 min): Add `-FakeRunner` flag to `run-evals.ps1` + a `-UseRunner <path>` flag + a `-Repeat N` flag.
- **V1.5** (20 min): Write the 4 seeded-regression runner variants.

**Gate:** Run `evals/tests/Test-Scorer.ps1` and `Test-Harness-Validate.ps1`. Must exit 0 before V2.

### Phase V2 — Run Tiers 1 and 2 (~5 min)

- **V2.1:** `powershell.exe -File evals/tests/Test-Scorer.ps1` → expect exit 0
- **V2.2:** `powershell.exe -File evals/tests/Test-Harness-Validate.ps1` → expect exit 0
- **V2.3:** Manual: `powershell.exe -File evals/run-evals.ps1 -Cases 01-trivial-task -FakeRunner` → scorer and report render without invoking LLMs

### Phase V3 — Run Tier 3 variance (~15 min, real LLM cost)

- **V3.1:** `powershell.exe -File evals/run-evals.ps1 -Cases 01-trivial-task -Repeat 3`
- **V3.2:** Analyze raw-scores.json from the 3 runs. Produce `evals/VARIANCE-REPORT.md` with the per-dimension min/median/max.
- **V3.3:** If any dimension varies by > 1 level, tune the threshold in `defaults.yaml` and re-run.

### Phase V4 — Run Tier 4 seeded regressions (~25 min, real LLM cost)

- **V4.1:** `powershell.exe -File evals/run-evals.ps1 -Cases 02-simple-md-edit -UseRunner evals/tests/regressions/regression-a-skip-bounce.ps1`
- **V4.2:** Repeat for regressions b, c. For regression-d run against case 04 (hallucination-trap).
- **V4.3:** Produce `evals/SEEDED-REGRESSION-REPORT.md`. Each regression must be detected; if any is missed, open an issue on the scorer.

### Phase V5 — Human calibration (~30 min manual, no LLM cost)

- **V5.1:** Open 3 completed baseline run dirs side-by-side.
- **V5.2:** Hand-score the 21 (case, dimension) pairs.
- **V5.3:** Compare to automated. Write `evals/META-EVAL.md`.

## Success Gate

The eval system is "verified" for v1 when ALL of:

- [ ] Tier 1: 10/10 unit-test fixtures score exactly as expected
- [ ] Tier 2: `-Validate` passes all 9 cases; `-FakeRunner` + report render on 3 sample cases
- [ ] Tier 3: Case 01 variance within tolerance (robustness 3/3 PASS; ≥ 2/3 agreement per dimension; composite range ≤ 0.2)
- [ ] Tier 4: 4/4 seeded regressions detected
- [ ] Tier 5 (optional for v1): ≥ 80% human-automated agreement on 3-case sample

If Tier 4 fails: the eval is provably incomplete. Fix the scorer and re-run Tiers 1, 4.

## Risks & Mitigations

- **LLM noise swamps signal.** Tier 3 is specifically the calibration for this. Mitigation: tune thresholds in `defaults.yaml` until same-config runs agree.
- **Fixture drift.** If the runner's JSON schema evolves, canned fixtures rot. Mitigation: commit fixtures under git so changes are reviewable; rebuild fixtures when the runner's `state.json` keys change.
- **Over-fitting thresholds to baseline.** We tune thresholds to pass baseline, then they may be too generous on new cases. Mitigation: keep Tier 4 regression tests adversarial — they must always detect the planted bug even if baseline passes.
- **Circular verification.** The eval uses the runner's `state.json` as ground truth for robustness; we can't use the eval to verify the runner's state-writing. Mitigation: treat state.json writes as an axiom; if they're wrong, Tier 4 regressions surface that separately.
- **Windows path and encoding fragility.** Already hit UTF-8 BOM, CRLF, StrictMode `.Count`. Mitigation: widespread `@()` wrapping, explicit `-Encoding UTF8`, and `$ErrorActionPreference='Continue'` around native commands.

## What Verification Does NOT Replace

- **Real-world use.** The eval can pass every tier above and still miss a bug the user hits. Keep running real tasks through the system and feeding failures back into the case library.
- **Periodic re-baselining.** Even with a verified eval, re-run the full baseline after any runner or prompt change. A passing eval on stale baseline is not evidence of current health.
- **Judgment.** "Plan quality" is inherently judgment-laden. The scorer approximates it with heuristics (word count, heading presence). For high-stakes changes, a human should still eyeball the plan.
