# Sonnet/Terra replication of the bounded PlanBench screen

User requested another run with Sonnet and Terra after the Astra baseline
saturated. Use Sonnet as original author and final reviser; Terra as external
critic. Keep high effort in both seats, matching the previous screen's label.
Exact models: claude-sonnet-5 and gpt-5.6-terra. No substitutions.

Reuse the same pinned official PlanBench Hard corpus, exact50 task IDs and
two disjoint smoke IDs, seed20260913, prompts, deterministic extraction and
VAL. Do not select a different subset using earlier scores. Participants get
no previous outputs, scores, tools or session history. This is a new stage
and grant; earlier evidence and accounting stay unchanged.

Arms: A Sonnet original; B Sonnet plain revision; C independent Sonnet
critique then Sonnet revision; D Terra critique then Sonnet revision. Each
task's original is shared across arms. No scoring until generation freezes.

312 base calls including smoke, at most24 retries. Hard cap336:
Claude/Sonnet280 (250study+10smoke+20retry), Codex/Terra56
(50study+2smoke+4retry). No transfers or refunds. Existing subscription
accounts only. One controller; concurrency4 author and2 reviewer;
120-second per-call timeout. At most one identical retry for transport or
recognized per-request content refusal. Other provider/account failures stop
their family. Do not retry incorrect plans or tune prompts against outcomes.

New execution window starts2026-09-14 03:12:02UTC. Stop new calls05:52:02;
finish/score/report by06:12:02 (three hours). Smoke throughput must fit.
Use the current tested ledger, isolation, request-specific refusal handling
and exact-byte evidence export. Role-routing/budget checks and the existing
offline retry/resume test cover the changed controller behavior.

Output targets remain4096 for plans and1024 for critiques. Claude's transport
now enforces the matching cap per call, since Claude is the author as well as
self-critic. Codex caps remain prompt targets. This transport difference from
the Astra run must be disclosed; effort labels do not imply equal compute.

Primary contrast D-C, secondary D-B/D-A, official valid-plan percentages,
paired repairs/regressions, intervals and exact McNemar. Retain missingness
and bounds. Same practical threshold: at least5 net extra solves over C,
improvement over B, and at most2x B median observed workflow time. Disclose
queue/recovery effects separately from model-phase time. Baseline>=90% is
ceiling-limited; do not change tasks or efforts to manufacture headroom.

Publish this run separately from the Astra/Fable screen, with a fresh
source-bound assessment, exact action sequences and costs. Add a side-by-side
comparison only with coverage and model/transport differences explicit.
No result or saturation is assumed before scoring.

## Readiness amendment, 03:33 UTC

The first high-effort smoke phase spent six calls: five Sonnet, one Terra.
One original exceeded120 seconds; one self-critique exceeded the1,024-token
combined output allowance. No scored task had started. Both roles now use
medium effort and Claude receives8,192 combined reasoning/response tokens;
visible targets, prompts, task IDs and validator remain unchanged. The prior
high-effort outputs remain excluded rather than reused across profiles.

The same grant retains all six calls. Its old allocation is settled at6,
and330 calls remain allocated to the new stage: Claude275 and Codex55.
After312 planned new calls, the remaining retry reserves are15 and3.
The original deadline is unchanged. This is explicitly a medium-effort trial,
not a model-only comparison against Astra/Fable at high effort. The amendment
was based on runtime failures, with no scored outputs inspected or tuned.

## Completed result

The medium-effort stage completed all312 generation jobs and all200 scored
plans without runtime failures. A scored48/50 (96%); B/C/D each50/50 (100%).
The two original plans executed legally but missed the goal; plain revision,
self-review and Terra review all fixed them. D-C and D-B each0points;
D-A +4points (two repairs), with no regressions. Baseline96% is still above
the predeclared90% ceiling threshold, and both controls are perfect.

Mean estimated per-task cost: A $0.03295, B $0.05517, C $0.08210,
D $0.06546. Terra review is about19% more expensive than plain revision and
20% cheaper than Sonnet self-review, with the same100% score. Prefer plain
revision for this benchmark; the test does not establish extra reviewer
accuracy benefit or generalized productivity improvement.

Cumulative318/336 calls: Claude265/280, Codex53/56, including all six earlier
high-effort smoke calls. Known list-equivalent cost $7.290998; one early
timeout remains unpriced. The medium controller ran03:33:56–03:53:09UTC,
inside the original06:12:02 deadline. All208 exported scored/smoke action
sequences reproduce their validator-input hashes. Earlier Astra/Fable data
and archived editions remain unchanged. Results publish separately at
planbench-sonnet-terra.html with the required source-bound assessment.
