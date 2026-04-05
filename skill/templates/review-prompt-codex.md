# Verification Instructions

Verify that code changes correctly implement this plan.

## Task

{TASK}

## Plan

{PLAN_CONTENT}

## Diff

```diff
{DIFF}
```

## Stats

{DIFF_STAT}

## Check

1. Does implementation match the plan?
2. Logic errors?
3. Edge cases handled?
4. Matches codebase style?
5. Security issues?
6. Tests for new behavior?

Filter out: pre-existing issues, linter-catchable issues, pedantic nitpicks.

Respond with JSON only:

{
  "verdict": "APPROVED" or "REVISE",
  "confidence": 0-100,
  "summary": "one paragraph",
  "issues": [{"severity": "CRITICAL|HIGH|MEDIUM|LOW", "file": "path", "line_range": "N-M", "description": "...", "suggestion": "..."}],
  "scope_creep_detected": false,
  "iteration_notes": "guidance if REVISE"
}

APPROVED (confidence >= 75): Implementation matches plan.
REVISE: CRITICAL or HIGH issues.
Do NOT REVISE for LOW-only issues.
