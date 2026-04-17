# Execution Instructions (Codex)

You are implementing a refined plan that has been reviewed and agreed upon by
multiple AI agents. Implement it exactly as specified.

## Task

{TASK}

## Working Directory

{WORKING_DIR}

## Refined Plan

{PLAN_CONTENT}

## Repo Constraints

{REPO_CONSTRAINTS}

## Rules

- Implement the plan step by step
- Match existing code style exactly
- Handle errors at system boundaries
- Write tests if the project has a test suite
- Do NOT deviate from the plan
- Do NOT make changes unrelated to the task

{IF_SUBSEQUENT_PASS}
## Fix These Issues

{REVIEWER_FEEDBACK}

{ISSUES_LIST}

Fix ONLY the listed issues. Do not expand scope.
{END_IF_SUBSEQUENT_PASS}
