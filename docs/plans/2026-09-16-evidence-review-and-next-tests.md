# Co-Evolution: aggregate evidence and next-test plan

Prepared 2026-09-16. Planning only: no new benchmark calls or deployments.

## Decision

Continue one bounded, objective coding campaign. There is a promising coding
signal and an exploratory plan-quality signal, but no reliable general claim
that cross-model review outperforms a cheaper revision workflow. Stop repeating
saturated subsets and do not count failed calibration as evidence against
Co-Evolution. Do not average unlike benchmark percentages into one headline.

The live publication registry was checked against the local snapshot: all seven
study IDs and semantic data digests matched. Archived website editions and
proofs of concept are not independent replications of the current results.

## Aggregate results

| Study | Observed result | Increment attributable to cross-model review? |
|---|---|---|
| SWE-bench, completed light cohort, 50 issues | Sonnet solo 39/50 (78%); Sonnet then Terra repair 42/50 (84%); Terra solo 33/50 (66%) | Observed workflow difference +6 percentage points, not isolated reviewer causation |
| Custom written plans, six briefs | Across 18 overlapping cross-model workflows, mean gains over drafts +7.48/+5.58 rubric points under Astra/Fable judging; over self-review +4.08/+1.94 | Exploratory positive signal; judges disagree materially |
| PlanBench, Astra/Fable, 50 tasks | Original/plain/self-review 50/50 each; cross-review 45 correct and five missing | 0 points on completed pairs; full cross-review score bounded at 90–100% |
| PlanBench, Sonnet/Terra, 50 tasks | Original 48/50; plain/self/cross-review each 50/50 | Cross-review +4 points over original, 0 over either revision control |
| First BBEH screen, 12 questions | Terra 3/12; Sonnet original/revision each 1/5 received, seven missing | Review arms never ran; effect unmeasured; eight bracket-only scoring failures |
| Corrected BBEH screen, 12 new questions | Terra 7/12; Sonnet original 4/5 received, revision 3/5 received | Plain revision lost one completed answer; cross-review unmeasured; timeouts and controller loss |
| AIME 2024 screen, six questions | Original 5/6; plain revision and Terra each 6/6 | Plain revision +16.7 points; cross-review unmeasured because gate rejected |

The SWE-bench +6-point result consists of five repairs and two regressions.
Its saved repository/task bootstrap interval is about -7.6 to +18.8 points;
the exact paired McNemar p-value is 0.453. This is a useful reason to investigate,
not evidence sufficient to establish a reliable gain. Terra directly repairs
code in that workflow, so it is not the same intervention as Terra critiquing
and Sonnet revising. The change of executor and extra work are confounds.

The planning study's predeclared Sonnet-with-Terra comparison was +9 rubric
points under Astra but -1 under Fable across five paired briefs. Generation
continued after partial grading and the original deadline. Critical-violation
flags differed sharply (110/194 versus 4/187 judgments). These are not
productivity percentages or independent trials of 18 different task sets.

On Sonnet PlanBench, cross-review cost approximately $0.0655/task versus
$0.0552 for plain revision: about 19% more for the same observed 100% score.
It was cheaper than self-review ($0.0821/task), but plain revision was the
cheapest successful revision approach. These are historical list-equivalent
estimates, not subscription bills.

The BBEH setup also includes an excluded 18-call attempt with an inadequate
1,024-token combined allowance. The corrected run restored 8,192 tokens.
Do not interpret timeouts, process loss or output truncation as wrong reasoning.
The AIME manifest claimed 180 seconds but the retained code imported a
600-second default without applying that setting. Its calls all completed
under 50 seconds; usage prices and frozen runtime hashes were not saved.

### Remaining coding configurations, for completeness

These share tasks/cohorts and are not independent support for an aggregate gain.
The legacy `fable` condition label maps to Sonnet in the light cohort; actual
model metadata, not the legacy label, determines the names below.

| Cohort / configuration | Solved / submitted | Interpretation |
|---|---:|---|
| Light, Sonnet-led panel | 13/16 | Partial |
| Light, Sonnet self-review/repair | 40/49 | One missing; cross-review leads by 2/49 on shared evaluated tasks, not an independent replication |
| Light, GLM single-shot | 14/28 | Partial and different tool regime |
| Light, Kimi single-shot | 7/13 | Partial and different tool regime |
| Light, Sonnet–GLM | 38/48 | Partial |
| Light, Sonnet–Kimi | 12/17 | Partial |
| Light, Terra implements then Sonnet repairs | 35/49 | Partial; direction differs |
| Light, Terra self-review/repair | 37/50 | Complete; different author |
| Light, Sonnet best-of-two | 37/50 | Complete; different selection workflow |
| Frontier, Fable solo | 35/35 | Partial; not 100% of the planned 50 |
| Frontier, cross-vendor workflow | 33/37 | Partial; on 34 shared tasks, two regressions and no repairs versus solo (-5.9 points) |
| Frontier, Codex solo | 37/50 | Different model from light Terra cohort |
| Frontier, GLM / Kimi single-shot | 6/16 and 6/15 | Partial |

Other archived, unattempted rows and one-task proofs of concept establish
engineering readiness at most. No study here directly measured saved human
editing time, production rework or a general intelligence increase.

## What the next campaign must answer

Does Terra critique followed by Sonnet revision solve more tasks than plain
Sonnet revision, Sonnet self-critique, and simply using Terra alone, at an
acceptable cost? Keep these controls in every main test.

No public benchmark can be guaranteed unsaturated for these exact models and
settings. Difficulty labels are candidate selectors; our independent
calibration determines whether there is usable headroom. A six-question
ceiling is not proof that the entire AIME benchmark is saturated.

## Prioritized tests

### 1. LiveCodeBench code_generation_lite, hard stratum

Best first test: directly tests coding correctness with short, standalone
programs and executable tests, avoiding repository-agent setup for every task.
The upstream lite variant reduces test volume; it also supports evaluation of
already-generated custom outputs. Pin one available dataset revision and
the checker commit; filter by published hard label and documented dates.
Use all eligible platforms and a seeded random sample, not hand-picked failures.

Prepare 8 calibration tasks and 24 disjoint main tasks (seed 20260916).
Require at least 32 eligible, locally executable tasks before any model call.
Do not silently broaden the date window or difficulty after seeing scores.
Pin Python and upstream limits; check official errata before freezing IDs.
Score each final program with the upstream evaluator: one candidate per arm,
all tests pass or fail. No hidden-test feedback reaches any model.

Expected full live window: 1–2 hours after setup; hard cutoff three hours.
These are planning estimates, contingent on the calibration timings. Local
CPU verification is cheaper than new model generations, but timeouts and
test-process overhead still count. If setup exceeds 45 minutes, report that
and move to a predeclared alternate only before any participant calls.

Why first: the strongest existing signal is coding, and this isolates the
review effect with much less environment work than another SWE-bench run.
Limitation: algorithmic programming is not production maintenance; public
questions may have training exposure even when a date filter is used.

### 2. BigCodeBench-Hard, complete-prompt split

Use the published 148-task Hard subset. It tests library use and detailed
programming requirements, complementing competitive algorithms. The detailed
complete-prompt split reduces ambiguity from terse instructions. This is the
second practical test if Test 1 is feasible, or the alternative if Test 1's
calibration saturates or is too hard.

Freeze 8 calibration and 24 disjoint main tasks (seed 20260917). Validate
reference solutions in a pinned official local container before selection.
Record unavailable dependencies and unsupported tasks as an eligibility
manifest before sampling; do not discard tasks because models fail them.
Use the supplied unit tests and one generation per arm. No LLM judge.

Expected live window: 1–2 hours, three-hour cutoff, plus potentially material
one-time dependency/image setup. Local execution is preferred; remote public
evaluators introduce queueing and availability uncertainty. Do not count
dependency failures as model failures. Static exposure remains a limitation.

Why second: it tests whether any gain transfers to API usage and requirement
fulfillment, which is closer to the intended development workflow.

### 3. Reasoning Gym: fresh constraint-satisfaction tasks

This is the cheapest evaluator diagnostic, but less direct evidence of useful
software work and not a standardized leaderboard score. Use the public
versioned generators and checkers with newly frozen seeds (20260918 for
calibration; 20260919 for main). Start with graph_color at 20–25 vertices,
three colors, edge_probability 0.15, and Countdown at six supplied numbers
with targets 100–999. These are proposed settings, not measured difficulty.

Split 8 calibration and 24 main tasks equally across the two families.
Require checker fixtures to reject missing vertices, forbidden colors,
constraint violations, reused numbers and prohibited expression forms.
Keep upstream reward separately; primary binary success requires reward 1.0.
Never score graph-color JSON validity alone as success (the upstream checker
can award 0.01 to an invalid but parseable solution).

The graph generator accepts graphs solved by its greedy procedure, so larger
graphs do not guarantee deeper search difficulty. The pilot may still saturate;
if it does, stop this configuration instead of escalating it until review wins.
Generator metadata and possible solutions must remain outside model prompts.
Freeze and label these as a custom subset of a public benchmark framework.

Expected live window: 45–90 minutes, with negligible checker time for these
small instances; generation/model time still must be measured. Use this test
only if coding leaves a specific question about constraint checking, or as
the lower-setup option when code execution infrastructure is unavailable.

### Reserve: LiveCodeBench-Pro medium

Use only if ordinary hard-stratum LiveCodeBench saturates and a dedicated
judge environment can be provisioned cheaply. The documented evaluator uses
C++ and LightCPVerifier in a privileged Docker setup; it is not a drop-in
Python test and is not our cheapest first choice. It distinguishes program
failures from judge failures. Check actual test-case availability for the
selected release: the documentation notes a release with missing tests.
Do not start at its extreme hard tier: historical published results suggest
floor effects and high reasoning-token use. Neither historical scores nor
the medium label predict current Sonnet/Terra performance.

## Shared experimental contract

### Setup first, at most four model calls per benchmark

Before scored questions: run two separate trivial fixtures through each
provider (four total calls), using precisely the planned output and effort
settings. Check nonempty output, model routing, no unexpected tools, output
format and persistence. Run offline valid/invalid checker fixtures too.

The controller needs durable stdout/stderr files, a supervisor exit receipt,
transactional call reservations, enforced process timeouts and restart
reconciliation. A failed controller must not silently spawn another batch.
Unit-check the actual dispatched settings, not just manifest text. Freeze
source hashes. First test these mechanics with simulated provider failures.

Models remain Sonnet and Terra at medium effort. Retain the tested minimum
8,192 combined Claude allowance; visible critique target 200 words, generated
code target 2,000 tokens. A shared 300-second per-call limit and maximum four
concurrent calls (two per provider) are proposed. Visible targets are not hard
limits; record actual tokens, including provider-reported reasoning tokens.
If the platform cannot enforce a token limit, say so and rely on time/call
limits; never claim a guaranteed dollar cap. No paid API fallback.

### Calibration: 24 calls, eight excluded tasks

For each task run A (Sonnet original), B (plain Sonnet revision), E (Terra alone).
Freeze all responses before scoring. Continue only if all 24 arrive in usable
format, all three baseline scores lie between 2/8 and 6/8 inclusive, and the
remaining 168 calls fit the three-hour window with 20 minutes reserved for
evaluation/reporting. Forecast with measured mean and upper-tail latency and
30% overhead; report tokens and available list-equivalent cost estimates.

An irreversible transport/format failure makes the gate unattainable: stop
new dispatches and settle the current calls. Do not spend the rest of a
rejected calibration merely to characterize failure. Scores only become
available after the phase freezes. An eight-question screen is a coarse
headroom check, not proof against saturation in the independent main sample.

There is one frozen configuration per benchmark. No silent changes to model,
effort, timeout, question selection or scorer after responses are observed.

### Main: 24 fresh tasks, five scored arms, 168 unique calls

| Arm | Workflow | New calls per main task |
|---|---|---:|
| A | Sonnet original | 1 |
| B | Sonnet plainly revises A | 1 |
| C | Independent Sonnet critique of A; Sonnet revises A | 2 |
| D | Independent Terra critique of A; Sonnet revises A | 2 |
| E | Independent Terra original | 1 |

Share A across B/C/D. C/D have identical critic and revision instructions;
Sonnet is always the final reviser. Critics see the problem and candidate,
never the answer key, hidden tests, grader output, other critics or model
identity labels. No model tools during inference; execute submitted code
only in the evaluator sandbox. Score once after the main phase freezes.

Primary practical comparison: D minus B. Mechanism check: D minus C.
Alternative-model check: D minus E. D minus A is secondary and cannot by
itself show that cross-model review was needed. Equal step counts in C/D
control workflow structure, not exact provider compute.

Publish correct/24, missing/24, repairs, regressions, percentage-point deltas,
paired confidence intervals and exact paired tests; adjust the three principal
comparisons together (Holm). Report run cost and standalone arm costs without
double-counting the shared original. Separate provider failures and judge
failures from complete wrong answers. Report delivered correct/24 as an
operational metric, alongside complete-answer accuracy and missing-score
bounds; do not relabel missing answers as wrong reasoning.

### Budget and continuation decisions

Each candidate: 4 smoke + 24 calibration + 168 conditional main = 196 nominal
calls, plus at most 8 identical transient retries = 204 maximum. Maximum one
retry per eligible job; no retry of wrong answers or to change settings.
Base provider counts: Sonnet 138, Terra 58; retry reserves six/two yield hard
caps 144/60. Existing subscription limits remain authoritative.

Run sequentially, not all three automatically. At most 612 calls for all
three candidate screens and main tests if each passes; most gate rejections
stop after at most 28 nominal calls. No dollar-total estimate is defensible
before current provider usage and settings are measured.

A pilot warrants a fresh 24-task replication if D gains at least three net
correct answers over B (+12.5 points), beats C, and is not worse than E,
while remaining within twice B's measured standalone cost and time. This is
a practical replication trigger, not a significance claim or deployment rule.
If replicated, require a positive paired effect with uncertainty reported
and superiority to the relevant cheaper alternative before recommending
routine use. A separate confirmatory allocation would be up to 180 calls
(168 main, four readiness, eight reserve); it is not included in the 612.

If two completed, usable coding comparisons show no worthwhile advantage,
stop broad accuracy testing and prefer the cheaper workflow for those tasks.
A 24-task pilot cannot rule out a small benefit; it can establish that a large
promised gain is not presently supported. Never keep changing benchmarks
until a favorable result appears. Every attempted test, including failures,
gets its own website assessment, immutable evidence and explicit decision.

## Sources

Existing study assessments and linked evidence:
https://alanshurafa.github.io/co-evolution/evaluations.html

LiveCodeBench official repository, lite evaluation and custom-output support:
https://github.com/LiveCodeBench/LiveCodeBench

LiveCodeBench upstream difficulty/date scoring:
https://github.com/LiveCodeBench/LiveCodeBench/blob/main/lcb_runner/evaluation/compute_scores.py

BigCodeBench official repository and Hard subset:
https://github.com/bigcode-project/bigcodebench
https://huggingface.co/datasets/bigcode/bigcodebench-hard

Reasoning Gym public generators and scoring:
https://github.com/open-thought/reasoning-gym
https://github.com/open-thought/reasoning-gym/blob/main/reasoning_gym/algorithmic/graph_color.py
https://github.com/open-thought/reasoning-gym/blob/main/reasoning_gym/games/countdown.py

LiveCodeBench-Pro documented evaluator, infrastructure and data caveats:
https://ukgovernmentbeis.github.io/inspect_evals/evals/livecodebench_pro/
