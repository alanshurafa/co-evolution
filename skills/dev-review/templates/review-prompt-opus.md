# Verification Instructions (Opus Subagent)

You are verifying that code changes correctly implement a refined plan.
The plan was agreed upon by multiple AI agents through a structured review process.

## Original Task

{TASK}

## The Refined Plan

{PLAN_CONTENT}

## Code Changes (Diff)

```diff
{DIFF}
```

## Diff Stats

{DIFF_STAT}

## Verify Against Plan

Check that the implementation:
1. **Completeness** — Does it implement everything in the plan?
2. **Correctness** — Does the code do what the plan describes? Logic errors?
3. **Edge cases** — Are boundary conditions handled? Actively enumerate: empty/null/zero, max-size, concurrent access, partial failure, malformed input, unicode, timezone skew, and cases NOT exercised by existing tests.
4. **Style** — Does it match existing codebase style?
5. **Security** — Any OWASP issues?
6. **Tests** — Are new behaviors covered?
7. **Plan adherence** — Did the executor follow the plan or deviate?
8. **Unstated assumptions** — What inputs, states, or environments does this code silently assume (ordering, idempotency, auth, clock, encoding, config)? Name each and note whether it holds in production — not just under the current test suite.
9. **Adversarial scenarios** — Imagine how a hostile or careless caller breaks this: race conditions, retries, reordering, resource exhaustion, truncated data, cancellation mid-operation, replayed requests. List at least one plausible failure mode the existing test suite would NOT catch, and flag it as HIGH if exploitable.

## Filtering (remove false positives before reporting)

- Pre-existing issues not introduced by this diff — REMOVE
- Issues a linter/typechecker would catch — REMOVE
- Pedantic nitpicks — REMOVE
- Plan deviations that are clearly improvements — note but don't block

## Output Format

Respond with ONLY a JSON object:

```json
{
  "verdict": "APPROVED" or "REVISE",
  "confidence": 0-100,
  "summary": "one paragraph assessment",
  "issues": [
    {
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "file": "path/to/file.ext",
      "line_range": "42-55",
      "description": "what the issue is",
      "suggestion": "how to fix it"
    }
  ],
  "scope_creep_detected": false,
  "iteration_notes": "guidance for next iteration if REVISE"
}
```

- APPROVED (confidence >= 75): Implementation matches the plan and works correctly.
- REVISE: CRITICAL or HIGH issues that must be fixed.
- Do NOT REVISE for LOW-only issues.
