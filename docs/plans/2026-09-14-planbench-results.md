# PlanBench bounded continuation — final results

The fixed 50-task, four-arm experiment reached terminal disposition for every
workflow inside its original grant and deadline. It produced 195 scored plans;
five dependent D plans remain unavailable after Fable critique refusals.
This is a completed bounded attempt with partial D coverage, not a claim of
200 generated plans or a full 110-task leaderboard submission.

| Arm | Valid | Invalid | Missing | Fixed-50 score |
|---|---:|---:|---:|---|
| A: Astra original | 50 | 0 | 0 | 100% |
| B: Astra plain revision | 50 | 0 | 0 | 100% |
| C: Astra self-review | 50 | 0 | 0 | 100% |
| D: Fable review, Astra revision | 45 | 0 | 5 | Unavailable; bounds 90–100% |

D versus each comparator has 45 paired observations, zero repairs, zero
regressions and zero percentage-point change. Exact McNemar p=1. The
empirical bootstrap interval is [0,0] because every pair ties; that is not
proof of population equivalence. The perfect baseline creates a ceiling:
even favorable missing outcomes cannot meet the predeclared +10-point gain.

Use the original Astra workflow for this benchmark. On the same 45 completed
tasks its estimated cost was $0.064781 per task versus $0.253856 for D
(3.9x), and median model-phase time was 13.859 versus 52.563 seconds (3.8x).
Observed workflow wall time contains the recovery pause and queueing, so it
cannot establish intrinsic review latency. Symbolic plan validity does not
measure plan optimality, human rework, or software-delivery productivity.

## Bounded execution and evidence

- Same benchmark commit, selected IDs, seed, prompts, models, effort, output
  targets, validator and original deadline throughout.
- First continuation preserved 11 charged calls and 10 successful jobs;
  its identical smoke retry succeeded. It generated 166 scored candidates.
- Second continuation preserved 246 calls and 244 successful jobs. It fixed
  request-specific refusal classification, permitted one identical retry
  within the existing reserve, and continued unrelated tasks.
- Final spend: 311/336 calls; Astra 255/280 and Fable 56/56. No transfers,
  resets or budget increases. Every scored task's original, plain revision,
  self-review path and external critique was attempted. Five D integrations
  lacked usable critiques and were not fabricated or replaced.
- All generated candidates froze before benchmark validation. 195 available
  scored plans passed official VAL. Eight smoke plans passed but are excluded.
- Total controller time across segments: approximately 21.8 minutes; original
  execution window through generation: approximately 2.14 hours including
  the pause. Final controller ended 2026-09-14 00:29:54 UTC, before the
  original 01:21:19 UTC deadline.
- Known list-equivalent cost $23.10987875, with no unpriced calls. This is
  historical-rate/CLI accounting, not cash subscription billing.

The original run and both continuation ledgers/attempts remain local under
`runs/planbench-hard-20260913*`. The public result includes exact extracted
action sequences, task outcomes, resource records, paired statistics,
continuation disclosure and source hashes. The initial readiness publication
is archived and byte-pinned. Its old zero-coverage finding is superseded by
the current scored report, not overwritten in history.

## Verification and publication requirements

Existing valid/invalid/malformed evaluator fixtures and duplicate-free resume
evidence were reused. A focused classification check passed; four known-answer
paired-statistics/missingness checks passed. Final audit confirmed 50 unique
tasks, all required first-stage paths attempted, 311 charged calls, no job
over two attempts, and no pending/running jobs. Publication and observatory
checks passed, and desktop/mobile layouts were inspected.

The required source-bound assessment accompanies the updated data. It states
that no validity gain was observed, the baseline is saturated, five D outcomes
are missing, and no general productivity benefit follows. No automatic larger
study is justified by this result. The saved plan's incomplete-arm reporting
rule is applied explicitly rather than converting missing outcomes to failures.
