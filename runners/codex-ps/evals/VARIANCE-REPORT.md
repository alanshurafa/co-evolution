# Tier 3 Variance Report — case 01 × 3

**Date:** 2026-04-17
**Plan:** [`VERIFICATION-PLAN.md`](VERIFICATION-PLAN.md) § Tier 3

## Method

Ran `case 01-trivial-task` three times with identical config (Codex-only, `bounces=0`, `verify=false`) to quantify LLM noise in the scorer's output.

Two rounds: **before** and **after** the compose-template fix (D #6) that promoted `## Risks` from "Suggested" to a Required Section.

## Round 1 — before D #6 fix (`evals/reports/20260417-104236/`)

| Iter | Composite | Robust | Conv | Plan | Exec | Ver | Cost | X-AI |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.833 | PASS | PASS | **FAIL** | PASS | N/A | PASS | N/A |
| 2 | 1.000 | PASS | PASS | PASS | PASS | N/A | PASS | N/A |
| 3 | 0.833 | PASS | PASS | **FAIL** | PASS | N/A | PASS | N/A |

### Per-dimension agreement

| Dimension | Results | Agreement |
|---|---|---|
| robustness | PASS / PASS / PASS | 3/3 ✓ |
| convergence | PASS / PASS / PASS | 3/3 ✓ |
| plan_quality | FAIL / PASS / FAIL | **1/3 ✗** |
| execution_fidelity | PASS / PASS / PASS | 3/3 ✓ |
| verify_accuracy | N/A / N/A / N/A | 3/3 (n/a) |
| cost | PASS / PASS / PASS | 3/3 ✓ |
| cross_ai_diversity | N/A / N/A / N/A | 3/3 (n/a) |

- **Composite range:** 1.000 − 0.833 = **0.167** ✓ (≤ 0.2)
- **Robustness 3/3 PASS:** ✓
- **≥2/3 per dimension:** ✗ — plan_quality is 1/3

### Root cause (D #6)

Inspection of the three `plan.md` files showed iter 1 and iter 3 lacked the `## Risks` (or `## Assumptions`) heading entirely; iter 2 included it. The compose template's "Suggested Shape" list was treated as optional by Codex.

## Round 2 — after D #6 fix (`evals/reports/20260417-105956/`)

Template was updated to mark `## Risks` as a Required Section (matching the existing pattern for `## Files to Change`).

| Iter | Composite | Robust | Conv | Plan | Exec | Ver | Cost | X-AI |
|---|---|---|---|---|---|---|---|---|
| 1 | 1.000 | PASS | PASS | PASS | PASS | N/A | PASS | N/A |
| 2 | 0.833 | PASS | PASS | **FAIL** | PASS | N/A | PASS | N/A |
| 3 | 0.833 | PASS | PASS | **FAIL** | PASS | N/A | PASS | N/A |

### Per-dimension agreement

| Dimension | Results | Agreement |
|---|---|---|
| robustness | PASS / PASS / PASS | 3/3 ✓ |
| convergence | PASS / PASS / PASS | 3/3 ✓ |
| plan_quality | PASS / FAIL / FAIL | **1/3 ✗** |
| execution_fidelity | PASS / PASS / PASS | 3/3 ✓ |
| verify_accuracy | N/A / N/A / N/A | 3/3 (n/a) |
| cost | PASS / PASS / PASS | 3/3 ✓ |
| cross_ai_diversity | N/A / N/A / N/A | 3/3 (n/a) |

- **Composite range:** 1.000 − 0.833 = **0.167** ✓
- **Robustness 3/3 PASS:** ✓
- **≥2/3 per dimension:** ✗ — plan_quality still 1/3

### Heading inspection after the fix

```
iter01: Goal  Implementation Steps  Files to Change  Validation  Risks   ← has Risks (PASS)
iter02: Goal  Implementation Steps  Files to Change                      ← no Risks (FAIL)
iter03: Goal  Implementation Steps  Files to Change                      ← no Risks (FAIL)
```

Even with the template marking Risks as required, Codex dropped it in 2/3 runs.

### Root cause (D #7)

Case 01's task body says:
> "Include a Goal section, an Implementation Steps section, and a Files to Change section with the line: - (no file changes)"

When the task body enumerates specific sections and omits Risks, Codex treats the task-body enumeration as overriding the template's "Required" directive. **Prompt priority conflict.**

Candidate fixes (none applied yet):
1. Strengthen the template language: "These sections are required **REGARDLESS of any section list appearing in the task body.**"
2. Rewrite case 01's task to include Risks in its enumeration.
3. Both.

## Success Criteria Verdict

From `VERIFICATION-PLAN.md`:
- [x] **3/3 runs robustness=PASS** — plumbing is deterministic in both rounds
- [ ] **≥2/3 agreement per dimension** — plan_quality flips 1/3 in both rounds
- [x] **composite range ≤ 0.2** — 0.167 in both rounds

**Overall: PARTIAL.** Two of three criteria met. The remaining failure is not LLM flakiness; it's a legitimate prompt-design problem (D #7).

## What Tier 3 Proved

- The scorer itself is deterministic: given identical run artifacts, it produces identical scores. (Proven by Tier 1 unit tests; Tier 3 shows its variance comes from the runner, not from scoring noise.)
- The runner's output is not deterministic, but the sources of variance are identifiable and fixable.
- The variance test found a real prompt-design bug that pass/fail case outcomes alone would not have surfaced.

## What's Next

- Apply the D #7 fix (template language strengthening + case 01 task rewrite).
- Rerun Tier 3 and confirm plan_quality reaches ≥2/3 agreement.
- Consider adding a Tier 3 variance run on a mixed-agent case (e.g., case 03 × 3) to stress-test Cross-AI diversity's stability.
