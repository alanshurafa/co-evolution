You are reviewing a plan that has been passed to you by another AI agent. This prompt will be used repeatedly as the plan bounces between agents. Each time you receive it, treat the plan below this instruction block as the CURRENT VERSION, not a draft, not a history, but the living document.

Fill in the bracketed fields before sending this prompt.

## Context

Original task: [fill in]
This is pass [fill in] of [fill in].
Your role this pass: [fill in]
Working directory: [fill in]

Convergence:
- If there are zero [CONTESTED] and zero [CLARIFY] notes remaining, the plan has converged. Focus on polish only.
- If this is the final pass, you MUST resolve every remaining note and MUST NOT introduce new unresolved notes.

## YOUR JOB EACH PASS:

1. Read the plan as-is.
2. Edit directly in the plan. Change the text itself. Do not use diff syntax, strikethroughs, comments, or tracked changes inside the plan body.
3. Where you AGREE and want to improve, just improve it. Do not add praise or acknowledgment.
4. Where you DISAGREE, add a [CONTESTED] note directly below the relevant line or paragraph with your counter-argument and a concrete alternative.
   Example: [CONTESTED] Use a running total instead of a list. A list stores 500K floats after 500K requests; a running total uses constant memory and still computes the average.
5. Where something is AMBIGUOUS, add a [CLARIFY] note directly below the relevant line or paragraph with two possible interpretations or a specific question.
   Example: [CLARIFY] Does "rate limit all endpoints" include /metrics? (A) Yes, treat all paths equally. (B) No, exempt observability endpoints.
6. If you can resolve an inherited [CONTESTED] or [CLARIFY] note, do so and delete the note instead of replying to it.
7. If the plan already contains a ## HUMAN SUMMARY section, do not edit existing entries. Append exactly one new line for this pass.
8. If the plan does not contain a ## HUMAN SUMMARY section, add it at the very end and append one line.
   Format: - [your role], pass [N]: [one sentence describing what you changed]

## WHAT NOT TO DO:

- Do not add changelogs, revision history, or separate review text.
- Do not reformat or restructure unless your edit specifically requires it.
- Do not add praise, process commentary, or references to earlier passes unless resolving a live note.
- Do not edit or delete earlier HUMAN SUMMARY entries.
- Do not restate the instructions before the updated plan.
- Output ONLY the updated plan document. No preamble.

[PLAN STARTS HERE]

[paste the current plan here]
