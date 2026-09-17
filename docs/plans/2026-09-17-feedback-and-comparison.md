# Visible-feedback tests and comparison sheet

User requested the next tests, clear scoring, websites for all tests, and a
comparison sheet including our websites plus external benchmark sites.

## New tests

Run 12 fresh BigCodeBench-Hard tasks and eight fresh LiveCodeBench hard tasks.
Exclude every task selected in the preceding screen and fixed comparison.
Keep the pinned sources, images, medium effort, 300-second call limit and
8,192 combined Claude allowance. Run sequentially after four setup calls
per benchmark. No accuracy-based cancellation. Individual main-task failures
block only dependent work; infrastructure/identity/quota failures can stop a run.

BigCodeBench: randomly assign one third (minimum one) of each task's test
methods to visible feedback, retaining at least two held-out methods. Require
four or more separable methods and passing reference solutions on both splits
before selecting the fixed 12 tasks. LiveCodeBench: use official public tests
for feedback and private tests for final grading. Freeze all splits before calls.

A = Sonnet original; B = direct Sonnet revision with A's visible feedback;
C = Sonnet critique plus Sonnet revision with the same feedback;
D = Terra critique plus Sonnet revision with the same feedback;
E = independent Terra original; F = direct Terra revision with E's feedback.
Original A/E generations never see diagnostics. No participant sees held-out
tests or held-out grader results. CPU diagnostic jobs are recorded separately.

Primary score: percentage of tasks passing every held-out test. Record
delivered-correct/planned, conditional accuracy, missingness, repairs,
regressions, paired uncertainty and cost. D-B is primary; D-C and D-F are
the two other principal controls (Holm adjustment). D-A and D-E are descriptive.
All final responses freeze before held-out grading. These are modified
feedback experiments, not official whole-suite leaderboard submissions.

Eight model calls per task plus four setup calls. BigCodeBench: 100 nominal,
108 maximum (Sonnet 68, Terra 40). LiveCodeBench: 68 nominal, 76 maximum
(Sonnet 48, Terra 28). Eight total retries per benchmark, six Sonnet/two Terra,
one identical retry per eligible transient failure. Total maximum 184 calls.
No paid API fallback and no automatic benchmark expansion.

## Comparison and composite

Include every current internal result page plus clearly identified historical
archive links and external benchmark reference sites. Preserve experiment
coverage, scoring definition, protocol, findings and limitations. Do not merge
external leaderboard values with our results: their task sets and protocols
do not match our controlled runs.

Composite scores rank our workflows, not website appearance. Keep separate
panels for the earlier fixed tool-free protocol and the new feedback protocol.
For each panel, give BigCodeBench and LiveCodeBench equal weight:
composite = 100 * (correct_BCB/planned_BCB + correct_LCB/planned_LCB) / 2.
This is delivered-correct yield, not latent accuracy or an IQ score. Show
coverage and missing-outcome upper bounds alongside it. An unrun benchmark
does not silently become a zero or disappear from the weighting.

Do not pool calibration screens, judge-rated writing scores, different model
cohorts, archival duplicates or external leaderboards into this composite.
Disclose that benchmark weights are a chosen reporting convention. Keep
monetary efficiency separate because several historical calls are unpriced.

Deliver one formula-driven XLSX comparison sheet and an interactive comparison
page, plus a dedicated scored page and assessment for each new test.
