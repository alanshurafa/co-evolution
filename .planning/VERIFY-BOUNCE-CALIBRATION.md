# VERIFY: Bounce Calibration (v1.3 Phase 5, Layer 3)

Release-gate tracker for the human side of bounce-quality calibration.
Machine layers are DONE; the items below need Alan.

## What already ran (2026-06-10/11, on the Mac)

- Deterministic scorer batch over **192 historical runs** (82 non-bounce dirs
  skipped). Full report (gitignored — run names reference personal docs):
  `evals/reports/bounce-calibration-2026-06-11.md` in the working clone.
- Headline empirical findings:
  - **251 of 1,426 tracked markers (17.6%) were "resolved" by deleting their
    entire section** (`deleted-with-section`). The suspicion that drove this
    milestone is now a measured number.
  - 53 markers remain `unresolved` in final documents.
  - Only **11/192** historical runs pass the full behavior gate — mostly
    because pre-v1.3 runs persisted no per-pass clean artifacts (the exact
    gap Phase 3 closed). Runs from v1.3 onward emit full receipts.
  - Threshold-tuning distributions (word ratios, anchor retention) are in the
    report. The word-ratio tail (up to 64x) is legacy compose-mode runs whose
    "baseline" was a one-line question — mode-aware baselines fix this going
    forward; treat legacy compose runs as unscoreable for scope discipline.

## Blocked on a human (in order)

- [ ] **Log in the claude CLI on the Mac** (`claude`, then `/login`). The
      judge batch errored cleanly: "Not logged in". Then:
      `bash evals/calibrate-bounce.sh --runs-dir runs/ --judge --max-judge 10`
- [ ] **Blind-sample 5 judged runs** using the worksheet at the bottom of the
      calibration report (verdicts hidden until your call is recorded).
- [ ] **Compare judge↔human agreement.** ≥4/5: trust the judge for routine
      gating. ≤2/5 or systematic self-preference: wire a third-family judge
      (OpenRouter) before relying on verdicts.
- [ ] **Recalibrate `evals/bounce-thresholds.yaml`** from the distribution
      section (a band failing >30% of known-good runs is miscalibrated; a
      band nothing fails is toothless).
- [ ] Record the outcome here and fold results into the
      `feat/bounce-quality-scorer` goals (the rubric this milestone built).

## Closure

This tracker closes when judge↔human agreement is recorded and thresholds
have been recalibrated once. It blocks the **v1.4 adoption seed**
(`.planning/seeds/npm-mcp-distribution.md`), not v1.3 phase completion.
