# Eval Report

**Generated:** 2026-04-17 08:10:32 -04:00
**Cases:** 3  |  **Passed:** 2  |  **Failed/Regressed:** 1  |  **Avg composite:** 0.74

## Legend

- **Rob** = Robustness   **Conv** = Convergence   **Plan** = Plan quality
- **Exec** = Execution fidelity   **Ver** = Verify accuracy   **Cost** = Cost budget   **XAI** = Cross-AI diversity
- `+` PASS   `~` PARTIAL   `X` FAIL   `-` N/A

## Summary

| Case | Rob | Conv | Plan | Exec | Ver | Cost | XAI | Composite | Status |
|------|---|---|---|---|---|---|---|-----------|--------|
| 01-trivial-task | + PASS | + PASS | + PASS | ~ PARTIAL | + PASS | + PASS | - N/A | 0.85 | ok |
| 04-hallucination-trap | + PASS | ~ PARTIAL | + PASS | X FAIL | + PASS | ~ PARTIAL | + PASS | 0.62 | ok |
| 06-multi-file-refactor | ? ? | ? ? | ? ? | ? ? | ? ? | ? ? | ? ? | -- | FAIL |

## Per-Case Details

### 01-trivial-task

- **Status:** ok
- **Run ID:** 20260417-090000

| Dimension | Score |
|-----------|-------|
| robustness | PASS |
| convergence | PASS |
| plan_quality | PASS |
| execution_fidelity | PARTIAL |
| verify_accuracy | PASS |
| cost | PASS |
| cross_ai_diversity | N/A |


### 04-hallucination-trap

- **Status:** ok
- **Run ID:** 20260417-091500

| Dimension | Score |
|-----------|-------|
| robustness | PASS |
| convergence | PARTIAL |
| plan_quality | PASS |
| execution_fidelity | FAIL |
| verify_accuracy | PASS |
| cost | PARTIAL |
| cross_ai_diversity | PASS |


### 06-multi-file-refactor

- **Status:** fail
- **Error:** `runner exited non-zero during execute phase`


## Interpretation Notes

- **Robustness FAIL is the ceiling.** Any case that didn't reach `completed` taints the whole run — fix the robustness issue before reading other dimensions.
- **Cross-AI diversity N/A** on single-agent cases is expected; it is only scored when `composer != reviewer`.
- **Execution fidelity** compares the plan's `## Files to Change` list to `state.json.changed_files`. A FAIL here usually means the plan and the execute pass disagree — look at the raw scores' `jaccard` detail.
- **Verify accuracy PASS on a seeded-bug case** means the verdict correctly flagged the planted issue with the expected keyword(s).

