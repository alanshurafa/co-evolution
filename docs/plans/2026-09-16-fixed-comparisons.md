# Fixed Sonnet/Terra comparisons

User authorized configuration and execution after the earlier calibration
gates repeatedly prevented effectiveness measurement. This is a new design
and new task cohorts; the previous runs stay closed.

1. BigCodeBench-Hard: 24 fresh tasks from the 142 reference-validated tasks,
   excluding all 32 previously selected tasks; seed 20260920.
2. LiveCodeBench hard: 12 fresh tasks from the same pinned date window and
   errata-filtered pool, excluding all 32 previous tasks; seed 20260921.

Both use the five arms: A Sonnet original; B plain Sonnet revision; C Sonnet
critique then Sonnet revision; D Terra critique then Sonnet revision; E Terra
alone. A is shared across B/C/D. No hidden-test feedback reaches participants.
All main candidates freeze before scoring. Exactly one candidate per arm.

Four setup calls per benchmark check working transport and evaluator. There
is no calibration or accuracy-based cancellation. Individual timeouts,
truncated outputs and request failures preserve their charges and block only
dependent work. Authentication, quota, isolation or local infrastructure
failures can stop the run because valid measurement is no longer possible.

Sonnet and Terra use medium effort, 300 seconds per call, the established
8,192 combined Claude allowance, and at most two calls per provider. Each
run has a three-hour window, including 20 minutes reserved after dispatch.
Visible code/critique targets remain 2,000 tokens/200 words.

BigCodeBench: 172 nominal calls plus eight retry slots, maximum 180
(Sonnet 128, Terra 52). LiveCodeBench: 88 nominal plus eight retries, maximum
96 (Sonnet 68, Terra 28). Combined maximum 276; no paid API fallback or
automatic expansion. Existing subscription/usage limits remain authoritative.

Primary contrast is D minus B. Report D minus C, E and A as well. Report
paired repairs/regressions, uncertainty and Holm-adjusted principal tests.
Separately report delivered-correct/planned, complete-answer accuracy and
missing-score bounds. Missingness must not be relabeled as wrong reasoning.
High baseline scores will be published as an outcome, not a reason to
discard the comparison. Costs include all attempts and do not double-count
the shared original when comparing standalone workflows.

Publish both result pages and assessments, with source/runtime hashes and
per-task evidence, without overwriting the earlier calibration publications.
