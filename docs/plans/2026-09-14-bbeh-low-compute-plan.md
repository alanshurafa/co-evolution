# Proposed next test: compact BBEH reasoning screen

Status: proposal only. No model calls, new grant or live run authorized by
this document. Prepared September14,2026 after the PlanBench screens.

## Recommendation

Use selected official BIG-Bench Extra Hard (BBEH) Mini questions from three
families: Multi-Step Arithmetic, Web of Lies and Hyperbaton. Evaluate with
the unchanged official deterministic answer checker. This measures reasoning
performance and the incremental value of the Co-Evolution workflow. It does
not establish a general intelligence score or production productivity.

The lowest sensible initial spend is a36-call difficulty check. Run the
remaining comparison only if cheaper baselines demonstrably leave headroom.
The complete proposal has a220-call ceiling, compared with318 calls for the
last PlanBench run. Fewer calls do not guarantee fewer reasoning tokens;
measure latency/tokens in the difficulty check before committing further work.

## Why this benchmark

BBEH was designed to replace saturated BIG-Bench Hard tasks. It has4,520
full-set examples and a460-example Mini set. The official repository ships
a small Python scorer performing deterministic extraction and limited answer
normalization. It needs no LLM judge, solver process, Docker environment,
browser, images, repository builds, or model-generated parser repair.

The repository is archived and its published leaderboard is historical.
For context, the original o3-mini(high) Mini result was56.7%, not a current
Sonnet/Terra measurement. Do not infer that today's models cannot saturate
it; the difficulty gate below is mandatory.

Sources:
- Benchmark and Mini definition: https://github.com/google-deepmind/bbeh
- Historical results: https://github.com/google-deepmind/bbeh/blob/main/leaderboard.md
- Official scorer: https://github.com/google-deepmind/bbeh/blob/main/bbeh/evaluate.py
- Paper and task-level results: https://arxiv.org/html/2502.19187v2

LiveBench reasoning is the main alternative: its objective scoring and
release-version controls are useful, but public release availability and
task-specific integration add selection work. ARC-AGI-2 has exact grid
outcomes and an intelligence-oriented motivation, but grid representations
and solver/scaffolding choices add setup and can become the experiment's
dominant variable. For this next text-only test, BBEH offers the smallest
evaluator integration among the options examined. This is not a claim of
globally minimal compute across all possible benchmarks.

Alternative sources:
- https://github.com/livebench/livebench
- https://github.com/arcprize/ARC-AGI-2

## Task mix and measured input sizes

The official Mini release contains20 examples per family. Exact input matches
against each official full task file identify family membership, which is
not stored as a field in the Mini file. Verify unique matches before freezing.

| Family | Reasoning demand | Mini median input characters | Median target characters |
|---|---|---:|---:|
| Multi-Step Arithmetic | Apply unfamiliar conditional/composed operators | 1,066 | 3.5 |
| Web of Lies | Deduce truth values through chains and cycles | 2,717 | 12.5 |
| Hyperbaton | Infer and apply a new adjective-order grammar | 4,589 | 1 |

These character counts were measured offline from the official public JSON,
not estimated from leaderboard labels. They are not tokenizer measurements.
The three families cover arithmetic rule application, logical deduction and
inductive rule learning. Spatial Reasoning and Zebra Puzzles were considered,
but their Mini median prompts were7,469 and12,113 characters respectively;
defer their extra context cost initially. Do not cherry-pick the shortest
questions within a chosen family.

This is a named24-question, three-family BBEH Mini subset, not the full BBEH
or full BBEH Mini score. Full BBEH uses a different aggregate across23 tasks;
report simple subset accuracy and per-family results here, clearly labeled.

## Freeze the design before calls

Use Sonnet(claude-sonnet-5) as author/reviser and Terra(gpt-5.6-terra) as
external reviewer, both at the already-working medium effort. Keep the
known8,192-token combined Claude allowance, with short visible outputs.
Do not lower effort or cut time to manufacture mistakes.

Pin the benchmark commit, complete original question text, input IDs/hashes,
official scorer hash, prompts, model settings, allocation and analysis rules.
For each selected family, sort Mini examples by input hash and shuffle using
a recorded deterministic seed20260914. Reserve four questions for the
difficulty check and the next eight for the main test. Thus12 calibration
and24 main questions are disjoint; freeze both lists before calibration.
Keep the remaining24 questions unused. Do not replace questions after scores.

Only question inputs reach participants. Reference answers, previous scores,
other-arm outputs and scorer code stay inaccessible. Use the existing fresh,
tool-free transports. No web search, code execution or external solver calls.

## Phase1: difficulty and throughput gate —36 calls

On the12 excluded calibration questions, run:
1. Sonnet original answer.
2. Sonnet plain revision of that answer.
3. Independent Terra original answer.

Use the official scorer after these calibration outputs freeze. Publish
calibration results separately; they never enter the main score.

Proceed only when all responses are scoreable and each of the three baseline
accuracies is between3/12 and9/12 inclusive(25–75%). This is a coarse
screening rule, not proof of the true task difficulty. It checks the strongest
cheap alternative as well as the writer. High accuracy after plain revision
or in Terra alone means the main test would again have little room to help.

Also project elapsed time and token/list-equivalent cost from observed
calibration usage. If the full comparison cannot fit a two-hour execution
window, stop and present the evidence and forecast. Do not silently change
models, effort, tasks or formats based on the observed scores. If a category
has surprising results, report it; do not replace it with a favorable one.

If the gate fails, stop after36 nominal calls(plus only allowed transport
retries) and report "unsuitable at these settings". This is an intentional
low-cost outcome, not a failed full experiment. A new candidate bundle needs
a separate plan; no automatic series of benchmark searches or reruns.

## Phase2: main comparison —24 questions, five scored arms

| Arm | Workflow | Standalone calls/question |
|---|---|---:|
| A | Sonnet original | 1 |
| B | Sonnet original -> plain Sonnet revision | 2 |
| C | Sonnet original -> independent Sonnet critique -> Sonnet revision | 3 |
| D | Sonnet original -> Terra critique -> Sonnet revision | 3 |
| E | Independent Terra original | 1 |

The shared original reduces execution to seven unique calls/question:
five Sonnet and two Terra. Main total168 calls and120 final answers.
Do not drop E: it tests whether using the reviewer directly would be better.
Do not drop C: it distinguishes cross-model review from ordinary self-review.

Answers may contain a concise, checkable justification(up to150 words),
followed by the final answer in the upstream task's required format and the
official scorer's supported final-answer prefix. Critics receive that visible
answer/justification and the original problem; use at most120 words for
concrete issues. They never receive hidden reasoning or the answer key.
Keep C and D review/integration instructions identical apart from the actual
reviewer model. Preserve original benchmark instructions and scoring rules;
do not replace them with more forgiving fuzzy matching.

Generate all main outputs before main scoring. Single fixed attempt per arm,
no best-of-N, answer-key feedback, selective retries of wrong answers, or
human corrections. Retain raw responses and exact scorer inputs.

## Budget and execution limits

| Work | Sonnet calls | Terra calls | Total |
|---|---:|---:|---:|
| Difficulty gate | 24 | 12 | 36 |
| Main test | 120 | 48 | 168 |
| Retry reserve | 12 | 4 | 16 |
| Hard maximum | 156 | 64 | 220 |

New grant only; never reuse previous grants or refund attempts. Maximum one
identical transient retry/job, within family limits. Use the established
request-level error classification and preserve unpriced/failed calls.
Reasoning failures or wrong final answers are scored, not retried.

Target runtime45–90 minutes after setup; hard two-hour execution window
including the calibration phase. Cap calls at120 seconds each, concurrency
four Sonnet/two Terra, and reserve the final15 minutes for scoring/reporting.
Use the existing medium configuration from the start rather than repeating
the known high-effort smoke failure. Actual compute depends on hidden/output
reasoning, so the calibration forecast is more useful than a dollar promise.

Minimal offline checks: official scorer known-correct/wrong/format cases,
answer-key isolation, and correct job/cap accounting. Reuse the already
verified transports, process ownership and resume protections. No redundant
smoke study or AI judging panel; calibration doubles as live integration.

## Scores, decisions and claims

Primary measure: official-checker accuracy(correct/24), plus per-family
accuracy(correct/8). Primary mechanism contrast D-C. Also show D-B, D-E and
D-A, task-level repairs/regressions, cost, tokens and workflow time. D must
beat both cheap alternatives B and E to support a practical quality advantage;
beating Sonnet originals alone is insufficient.

Use task-paired, category-stratified descriptive bootstrap intervals and
exact McNemar comparisons. Distinguish preregistered primary from secondary
comparisons and adjust confirmatory claims for multiple comparisons. Tiny
or degenerate intervals are not proof of general equivalence. A24-question
screen can reveal large effects, but cannot reliably settle gains of a few
percentage points or prove broad intelligence improvement.

Practical signal to investigate: at least three net extra correct answers
(12.5 points) over each cheap baseline, plus a positive D-C difference and
acceptable measured overhead. This threshold is a screening choice, not
automatic statistical significance. If D merely matches C more cheaply,
report a possible cost/routing benefit rather than improved intelligence.
If D matches or loses to B/E while costing more, prefer the cheaper workflow.

If main scores still saturate, publish that result and stop; do not mutate
the frozen test. If evidence is promising but uncertain, propose a fresh
replication separately. No auto-expansion is included in220 calls.

Missing infrastructure outcomes remain missing with fixed-denominator bounds;
do not turn them into zero reasoning scores or discard them from headline
coverage. Completed but wrong/malformed answers follow the official checker.

## Publication

Publish the calibration gate, main results(if run), exact checker inputs,
coverage, paired evidence, resource costs and an assessment of what the test
does and does not establish. Bind that assessment to the result snapshot
using the site's existing publication gate. Label the subset and any
selection conditioning. Keep PlanBench history intact. Planning this test
does not launch it or create a recurring automation.
