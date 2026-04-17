# Eval Report

**Generated:** {{TIMESTAMP}}
**Cases:** {{CASE_COUNT}}  |  **Passed:** {{PASS_COUNT}}  |  **Failed/Regressed:** {{FAIL_COUNT}}  |  **Avg composite:** {{COMPOSITE_AVG}}

## Legend

- **Rob** = Robustness   **Conv** = Convergence   **Plan** = Plan quality
- **Exec** = Execution fidelity   **Ver** = Verify accuracy   **Cost** = Cost budget   **XAI** = Cross-AI diversity
- `+` PASS   `~` PARTIAL   `X` FAIL   `-` N/A

## Summary

{{CASE_TABLE}}

## Per-Case Details

{{DETAILS_SECTIONS}}

## Interpretation Notes

- **Robustness FAIL is the ceiling.** Any case that didn't reach `completed` taints the whole run — fix the robustness issue before reading other dimensions.
- **Cross-AI diversity N/A** on single-agent cases is expected; it is only scored when `composer != reviewer`.
- **Execution fidelity** compares the plan's `## Files to Change` list to `state.json.changed_files`. A FAIL here usually means the plan and the execute pass disagree — look at the raw scores' `jaccard` detail.
- **Verify accuracy PASS on a seeded-bug case** means the verdict correctly flagged the planted issue with the expected keyword(s).
