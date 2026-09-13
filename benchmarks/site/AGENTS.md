# Benchmark publication contract

Every current test result published by this site must include an evidence
assessment: question, outcome, coverage, checks performed, limitations,
practical conclusion and next action. This includes partial and failed runs.
Write the assessment after examining the actual test evidence, not merely
after the build succeeds. Do not infer practical impact from engineering
checks, substitute smoke results for scored tasks, or present missing scores
as zero. Never claim a partial subset is a full official leaderboard result.

Update `public/test-evaluations.json`, render `build-evaluations.py`, and run
`validate-publication.py` before publishing. The Pages workflow enforces the
same check. A changed data digest requires a fresh assessment of the changed
results; updating only a hash is insufficient. Keep archive hashes intact.

Verify only the affected behavior and necessary publication gate; avoid
rerunning benchmarks or successful model calls for presentation changes.
