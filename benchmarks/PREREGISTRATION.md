# Pre-Registration — Co-Evolution Benchmark Suite

Frozen BEFORE any generation run. Written in Phase 1, committed before Phase 6
(the full 8x4 batch). Any change after this file is committed invalidates the
batch in progress — start a new batch id instead of editing history here.

## 1. Comparisons and decision rules

**Primary comparison: B-vs-A** — does the cross-vendor Codex bounce beat stock
Fable? Decision rule, with 8 tasks, using the primary judge's sign test:

- B "helps" only at **>=7/8 decisive wins** (p<0.05, two-sided).
- **5-6/8** is "directionally positive, underpowered".
- Anything else is "no evidence".

**Secondary confirmatory comparison: B-vs-D** — cross-vendor bounce vs.
same-model self-bounce at an equal pass count. This is the comparison that
isolates the cross-AI variable itself, separate from "any second pass helps".

Everything else — condition C, difficulty cuts, Bradley-Terry ranks — is
**exploratory** and is labeled as such in the report, never presented as
confirmatory evidence.

## 2. Framing

Eight selected tasks plus automated judges produce *exploratory directional
evidence*. This batch is never described as "hard evidence" or "proof".
General claims about cross-AI bouncing are reserved for a larger held-out
replication.

## 3. Freeze rules

The following are frozen before the corresponding stage runs, and a
post-freeze change to any of them invalidates the batch:

- **Corpus** — frozen before any condition runs.
- **Judging prompts** — frozen before the first verdict.
- **Sanitization rules** — frozen before the first verdict.
- **Banned-token list** (`benchmarks/lib/banned-tokens.txt`) — frozen before
  the first verdict.
- **Tie rules** — frozen before the first verdict.
- **Second/third-judge coverage** — frozen before the first verdict.

Any post-freeze change to any of the above invalidates the batch; the
correction starts a new batch id rather than amending the running one.

## 4. Bradley-Terry tie rule

A tie counts as half a win for each condition in the pairwise comparison.
This is the same rule applied uniformly across every judge — no judge gets a
different tie convention.

## 5. Judge coverage

Three judges, each scoring every pair (never split across a subset of pairs):

- **Primary judge**: fable-5, on all pairs.
- **Codex judge**: gpt-5.5, on all pairs. Pause the batch if the codex-guard
  daily cap blocks judging — the batch already spans multiple days for GLM
  quota reasons, so a pause here is not itself a deviation.
- **GLM judge**: glm-5.3-flash, on all pairs. Free tier, and condition-neutral
  (GLM participates in generation only as one of three panel critics in
  condition C, never as a composer or reviser, so it carries no side in the
  A/B/D comparisons it is judging).
