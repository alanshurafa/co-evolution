# Tier 4 Seeded-Regression Report

**Date:** 2026-04-17
**Plan:** [`VERIFICATION-PLAN.md`](VERIFICATION-PLAN.md) § Tier 4
**Generator:** [`tests/Build-Regressions.ps1`](tests/Build-Regressions.ps1)

## Purpose

Plant four known bugs in copies of `scripts/run-co-evolution.ps1`. Run each against a case whose expectations should surface the bug. **If the eval scores any regression as all-PASS, the eval is blind to that bug class and the scorer must be tightened.**

## Regression inventory

| Id | Planted bug | Expected signal | Target case |
|---|---|---|---|
| A | `for ($passNumber = 1; $passNumber -le 0; ...)` — bounce loop bypassed | Convergence=FAIL/PARTIAL | `02-simple-md-edit` |
| B | `$currentPlan = $currentPlan.Substring(0, [Math]::Min(50, ...))` | Plan quality=FAIL | `02-simple-md-edit` |
| C | `# Write-RunText -RelativePath "verdict.json" ... commented out` | Verify accuracy=FAIL | `02-simple-md-edit` |
| D | `$verdictText = '{ "verdict": "APPROVED", ... }'` — hardcoded | Verify accuracy=FAIL on a `must_catch_issue` case | `04-hallucination-trap` |

## Results

### Regression A — skip-bounce

- **Command:** `run-evals.ps1 -Cases 02-simple-md-edit -UseRunner tests/regressions/regression-a-skip-bounce.ps1`
- **Report:** `evals/reports/20260417-105958/`
- **Composite:** 1.000
- **Per-dim:** robustness=PASS, convergence=PASS, plan_quality=PASS, execution_fidelity=PASS, verify_accuracy=PASS, cost=PASS, cross_ai_diversity=N/A
- **Detection status:** ❌ **NOT DETECTED** — scorer-blindness finding

**Diagnosis:** The compose phase for case 02 (a single-file README typo fix) produces a crisp plan with 0 `[CONTESTED]`/`[CLARIFY]` markers. With zero markers in the compose output, the bounce loop has nothing to converge; skipping it is observationally identical to running it. The Convergence dimension's axiom ("markers → 0") is satisfied by both "converged in 0 bounces" and "bypassed the bounce step."

**Scorer remediation candidates:**
1. **Structural check:** if the case's merged config has `runner.bounces > 0` AND `state.history` has no `bounce-*` entries, flag Convergence=FAIL for skipping a required phase. (Recommended — mechanical, no new judgment.)
2. **Case-level test:** rewrite regression A to target a case that consistently produces markers (cases 03 or 05) so skipping bounce is observable through marker persistence.
3. **Accept the blindness** and document that Convergence is only meaningful on cases with non-trivial compose markers.

### Regression B — truncate-plan

- **Command:** `run-evals.ps1 -Cases 02-simple-md-edit -UseRunner tests/regressions/regression-b-truncate-plan.ps1`
- **Report:** `evals/reports/20260417-110000/`
- **Composite:** 0.857
- **Per-dim:** robustness=PASS, convergence=PASS, **plan_quality=FAIL**, execution_fidelity=PASS, verify_accuracy=PASS, cost=PASS, cross_ai_diversity=N/A
- **Detection status:** ✅ **DETECTED**

**Analysis:** The planted `Substring(0, 50)` trimmed the compose output to well under the 60-word `min_word_count` and stripped the `## Risks`/`## Files to Change` section headings. The scorer's plan_quality dimension caught both failure modes. Expected exactly; no scorer change needed.

### Regression C — no-verdict

- **Command:** `run-evals.ps1 -Cases 02-simple-md-edit -UseRunner tests/regressions/regression-c-no-verdict.ps1`
- **Report:** `evals/reports/20260417-110001/`
- **Composite:** 0.857
- **Per-dim:** robustness=PASS, convergence=PASS, plan_quality=PASS, execution_fidelity=PASS, **verify_accuracy=FAIL**, cost=PASS, cross_ai_diversity=N/A
- **Detection status:** ✅ **DETECTED**

**Analysis:** Commenting out the `verdict.json` write meant the scorer's `verify_accuracy` branch found no verdict.json and flagged FAIL with reason "no verdict.json (verify not run?)". Exactly as designed. Robustness still PASS because the runner's own `state.status` reached `completed` despite the missing artifact — a meaningful separation: the runner thought it was done, but the artifact trail said otherwise, and the scorer believed the artifact trail.

### Regression D — fake-approve

- **Command:** `run-evals.ps1 -Cases 04-hallucination-trap -UseRunner tests/regressions/regression-d-fake-approve.ps1`
- **Report:** `evals/reports/20260417-110003/`
- **Composite:** 0.750
- **Per-dim:** robustness=PASS, convergence=PASS, plan_quality=PASS, **execution_fidelity=FAIL**, **verify_accuracy=FAIL**, cost=PASS, **cross_ai_diversity=PASS**
- **Detection status:** ✅ **DETECTED**

**Analysis:**
- `verify_accuracy=FAIL`: case 04 sets `must_catch_issue: true` with keywords `["RetryAsync", "does not exist", ...]`. The hardcoded APPROVED verdict has an empty issues list, so no keyword hit, so FAIL. Exactly as designed.
- `execution_fidelity=FAIL`: interesting side effect — case 04's plan proposes a `RetryAsync` wrapper file but Codex-as-executor can't actually find that API, so the changed_files set diverges from the plan. This isn't directly a signal of regression D, but it's a correct secondary flag.
- `cross_ai_diversity=PASS`: confirms the Phase D #4 fix — the Levenshtein scorer now works on mixed-agent runs; the compose→first-bounce edit distance exceeded threshold, so this dimension is scoring for the first time ever.

## Aggregate Scorecard

| Regression | Expected dimension(s) | Detected? |
|---|---|---|
| A — skip-bounce | Convergence | ❌ |
| B — truncate-plan | Plan quality | ✅ |
| C — no-verdict | Verify accuracy | ✅ |
| D — fake-approve | Verify accuracy | ✅ |

**3 of 4 regressions detected.** The remaining miss (A) is not a simple bug but a deeper finding about what the Convergence dimension is actually measuring.

## Verdict

- The eval's **falsifiability is established** on three of four planted bugs.
- The fourth is a useful blindness finding that motivates a specific scorer improvement rather than shaking confidence in the system.
- The success criterion from `VERIFICATION-PLAN.md` — "4/4 seeded regressions detected" — is **not yet met**. Implementing the recommended structural check (remediation option 1 under regression A) would close this gap.

## Next Steps

1. Patch `score-run.ps1` to flag Convergence=FAIL when `runner.bounces > 0` and no `bounce-*` phase appears in `state.history`.
2. Add a fifth regression (optional, for defense-in-depth): plant a bug that breaks the compose→execute hand-off in a way Plan quality alone wouldn't catch.
3. Rerun Tier 4 after the patch. Expect 4/4 detected, closing the Tier 4 success criterion.
