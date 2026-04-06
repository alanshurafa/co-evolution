# Testing

## Current State

- There is no tracked unit test, integration test, or end-to-end test suite in this repository.
- There are no files named `*test*`, `*spec*`, `jest*`, `vitest*`, or `pytest*` in tracked source.
- There is no CI configuration exercising the shell tool or the Claude skill automatically.

## Existing Validation Mechanisms

- `agent-bouncer/agent-bouncer.sh` contains runtime safety checks:
- adapter existence validation before execution
- empty-output retry logic
- short-output retry logic
- marker counting for convergence
- cleanup of temp artifacts on exit
- `skill/SKILL.md` describes a verification phase that compares code changes to a refined plan and requires JSON output validated against `skill/schemas/review-verdict.json`.

## Manual Evidence In Repo

- `runs/` contains many local sample bounce runs with `original.md`, pass artifacts, stderr logs, and `run.log`.
- Those run folders function as smoke-test evidence and debugging traces rather than as assertions.
- Root-level scratch docs inside `runs/`, such as `runs/codex-workflow-sync-plan.md`, show the repo is used interactively for real planning work.

## Practical Manual Test Paths

- Run `agent-bouncer/agent-bouncer.sh <document.md>` against a small markdown file and inspect `runs/bouncer-*/run.log`.
- Verify that the input file is updated, raw pass output is captured, and the clean final document is written.
- Confirm `[CONTESTED]` and `[CLARIFY]` counts converge as expected on a two-pass bounce.
- Exercise failure cases by forcing an empty or failing adapter invocation and checking retry behavior.
- In Claude Code, run `/dev-review --plan-only <task>` and `/dev-review --verify <task>` to validate prompt and schema contracts.

## Coverage Gaps

- No automated regression protection for prompt-template placeholder changes.
- No automated test for marker counting around fenced code blocks and inline backticks.
- No automated test for run-label generation, especially since it depends on a Codex call.
- No automated test for Windows live-mode launch behavior described in `skill/SKILL.md`.
- No automated drift detection between `agent-bouncer/templates/bounce-protocol.md` and `skill/templates/bounce-protocol.md`.

## Recommendation

- The highest-value first tests would be shell-level smoke tests around `agent-bouncer/agent-bouncer.sh`.
- After that, add fixture-based tests for marker counting, HUMAN SUMMARY stripping, and run directory naming.
- The skill layer likely needs contract tests or documented smoke-test scripts because much of its behavior is declarative rather than directly executable here.
