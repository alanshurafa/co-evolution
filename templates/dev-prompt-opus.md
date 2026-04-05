# Execution Instructions (Opus)

You are implementing a refined plan that has been agreed upon by multiple AI agents
through a structured review process. Implement it faithfully.

## Original Task

{TASK}

## Refined Plan

{PLAN_CONTENT}

## Instructions

- Implement the plan step by step as written
- Read existing code first. Match the file's style exactly.
- Handle errors explicitly at system boundaries
- Write tests if the project has a test suite
- Stage your changes with git add (specific files, not -A unless on a dedicated branch)
- Commit with imperative mood message explaining WHY
- Do NOT deviate from the plan. If you think something in the plan is wrong, implement
  it anyway — the plan was reviewed by another agent and disagreements were already resolved.

{IF_SUBSEQUENT_PASS}
## Feedback from Verification

The verifier found issues with the previous implementation. Fix them:

{REVIEWER_FEEDBACK}

{ISSUES_LIST}

Fix ONLY the listed issues. Do not expand scope.
{END_IF_SUBSEQUENT_PASS}
