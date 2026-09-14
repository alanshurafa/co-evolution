# PlanBench attempt and publication assessment

Historical initial-attempt report. The user-directed continuations and scored
outcome are documented in [the final results](2026-09-14-planbench-results.md).

The authorized 50-task/four-arm attempt ended at its readiness gate on
September 13, 2026. Source: PlanBench commit
`fc638a1aff7df3fe7a1a1d289fa2c04cc24dc284`, fixed sampling seed 20260913,
official bundled VAL and deterministic PDDL extraction.

Ten of twelve smoke generation jobs succeeded. Fable returned a provider
safeguard refusal on one critique; its dependent revision did not run.
The seven available smoke plans validated. All 300 scored-generation jobs
were blocked by the required readiness gate, so there are no benchmark
scores and no new efficacy evidence. Refused requests were not rephrased,
models were not switched, and successful calls were not repeated.

Spend: 11/336 calls (Astra 9/280, Fable 2/56), $0.934838 known list-equivalent
cost. Cost is an estimate using historical Astra rates and Fable CLI totals,
not cash subscription billing. The original deadline and charged attempts
remain in the frozen run. The controller's receipt records 22:32:24–22:33:25
UTC, exit 2. No pending/running controller jobs remain.

Minimal validation: valid/invalid/malformed official validator fixtures;
one offline lifecycle test proving retry accounting and duplicate-free resume;
the two live excluded smoke tasks; five publication-contract tests; six
existing observatory tests; desktop/mobile inspection. The first validator
fixture check correctly caught that VAL returns exit 1 for an invalid plan;
the adapter was corrected before freezing or making any live calls.

Published deliverables are the PlanBench readiness outcome, machine-readable
evidence and assessments of all three current studies. Publishing now
requires a substantive assessment bound to each current result export's
canonical data hash. The deployment gate rejects absent/stale assessments,
new unassessed exports and assessment text not present on the public page.
Archived editions remain byte-pinned exceptions. The check enforces freshness
and completeness, not the scientific correctness of the written judgment.

Measurement remains incomplete. Provider resolution and a documented
continuation would be needed before another live attempt; this publication
does not authorize a new grant or reset the frozen run. Do not report the
seven setup successes as the requested 50-task benchmark result.
