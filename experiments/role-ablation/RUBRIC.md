# Role Ablation Experiment — Grading Rubric

## Purpose

Determine whether role preambles (reviewer/composer lenses) improve the quality of bounced outputs across diverse input types. Three configurations tested:

- **no-roles**: No role preamble. Just the bounce protocol + content.
- **light-roles**: Lightweight universal roles ("find what's wrong" / "make it simpler").
- **heavy-roles**: Current plan-specific roles (correctness+completeness / simplicity+pragmatism).

## Grading Dimensions (1-5 each)

### 1. Disagreement Quality
Did the bounce produce real, substantive pushback — or polite surface-level changes?

| Score | Meaning |
|-------|---------|
| 1 | No real disagreement. Pass 1 just rephrased or agreed. |
| 2 | Minor wording changes framed as disagreements. |
| 3 | Some genuine pushback on 1-2 points, but others glossed over. |
| 4 | Strong, specific disagreements with concrete alternatives on most points. |
| 5 | Every weak point challenged. Alternatives are better than the originals. |

### 2. Convergence Quality
Does the final output feel resolved and coherent — or are there loose threads?

| Score | Meaning |
|-------|---------|
| 1 | Final output is messy. Unresolved markers or contradictory content. |
| 2 | Markers resolved but content feels patched together, not unified. |
| 3 | Mostly coherent. One or two spots feel like they were argued rather than integrated. |
| 4 | Clean, unified document. Hard to tell two agents wrote it. |
| 5 | Reads like a single expert wrote it. Every point earned its place. |

### 3. Improvement Delta
How much better is the final output compared to what a single AI pass would produce?

| Score | Meaning |
|-------|---------|
| 1 | No meaningful improvement. Could have been a single-pass response. |
| 2 | Minor polish. A few words changed, nothing substantive. |
| 3 | Noticeable improvement. 2-3 real additions or corrections. |
| 4 | Significantly better. Several weak points strengthened, gaps filled. |
| 5 | Transformative. The final output is qualitatively different and clearly superior. |

### 4. Appropriateness
Did the AI correctly understand what the input needed (answer a question, refine a draft, develop an idea, stress-test an argument)?

| Score | Meaning |
|-------|---------|
| 1 | Completely wrong interpretation. Answered a question that wasn't asked, or rewrote content that should have been critiqued. |
| 2 | Partially right but missed the intent. Over-expanded what should be tight, or over-simplified what needed depth. |
| 3 | Got the general intent but some aspects mishandled. |
| 4 | Correctly identified what was needed and delivered accordingly. |
| 5 | Perfect read. The response format, depth, and focus exactly match what the input called for. |

### 5. Conciseness
Did the output stay tight, or grow unnecessarily?

| Score | Meaning |
|-------|---------|
| 1 | Bloated. More than double the input length with no justification. |
| 2 | Grew significantly with some padding or repetition. |
| 3 | Moderate growth, mostly justified by new content. |
| 4 | Tight. Every addition earns its place. |
| 5 | Optimal length. Nothing to add, nothing to remove. |

## Grading Procedure

For each of the 30 runs:

1. Read the original input (`inputs/XX-name.md`)
2. Read the final output (`results/CONFIG__XX-name/FINAL.md`)
3. Optionally read intermediate passes for context
4. Score each of the 5 dimensions (1-5)
5. Record in the grading spreadsheet

## Grading Output Format

For each grader (Claude, Codex, Gemini, Grok), produce a CSV:

```
config,input,disagreement,convergence,improvement,appropriateness,conciseness,total,notes
no-roles,01-factual-question,4,3,3,5,4,19,"Strong pushback but convergence felt rushed"
light-roles,01-factual-question,5,4,4,5,4,22,"Best balance of disagreement and resolution"
heavy-roles,01-factual-question,3,5,3,3,5,19,"Very tight but missed the actual question"
```

## Analysis

After all 4 graders complete:
1. Average scores per config across all inputs and graders
2. Average scores per input type across all configs (to see if certain input types benefit more from roles)
3. Inter-grader agreement (do all 4 AIs rank the configs the same way?)
4. Per-dimension breakdown (does one config win on disagreement but lose on convergence?)
