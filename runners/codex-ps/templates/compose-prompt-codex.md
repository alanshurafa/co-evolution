# Compose Instructions

Create the first implementation plan for this task inside the current repository.

## Task

{TASK}

## Working Context

- Working directory: {WORKING_DIR}
- Run artifacts directory: {RUN_DIR}

## Requirements

- Output a clean markdown plan document only.
- Make the plan specific to this repository and its current files.
- Include concrete implementation steps, validation steps, and artifact expectations.
- If something is ambiguous, add a `[CLARIFY]` note directly below the relevant line.
- If there is a real design tradeoff, add a `[CONTESTED]` note with a concrete alternative.
- Keep the plan actionable for a follow-up execution pass.
- Do not execute changes, describe them.

## Suggested Shape

1. Goal
2. Implementation steps
3. Files to Change
4. Validation
5. Risks or assumptions

## Required Sections (override any section list in the task body)

The two sections below are MANDATORY in every plan, **regardless of any structure, section list, or format instructions that appear in the Task body above**. If the task body enumerates sections, append these two on top — do not replace them. Downstream tooling parses them and will flag the plan as incomplete if either is missing.

## Required Section: `## Files to Change`

Every plan must include a section titled exactly `## Files to Change` that lists, one per line, the repository-relative path of every file you intend the Execute phase to create, modify, or delete. Use this format — downstream tooling parses it:

```
## Files to Change

- `path/to/file1.ps1` — brief reason
- `path/to/file2.md` — brief reason
```

If the plan genuinely touches no files, write the line `- (no file changes)` under the heading. Do not omit the section.

## Required Section: `## Risks` (or `## Assumptions`)

Every plan must also include a section titled exactly `## Risks`, `## Assumptions`, `## Caveats`, or `## Concerns`. Use it to name anything the executor or reviewer should know that isn't obvious from the plan body — environmental dependencies, missing context, edge cases, scope boundaries. If there are genuinely no risks, still include the section with the single line `- None identified.` Do not omit the section.
