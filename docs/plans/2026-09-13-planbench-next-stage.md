# Next-stage evaluation: PlanBench Hard, bounded co-evolution screen

Status: proposed execution plan, 2026-09-13. No benchmark calls launched.

## Decision and question

Use PlanBench's released Blocksworld Hard PDDL task set. Score legal action
sequences reaching the specified goal using the benchmark's official
evaluation path and VAL validator. This tests executable symbolic planning,
not writing quality, software delivery, or human productivity.

Question: does one independent Fable critique improve Astra's valid-plan
rate beyond a fresh Astra self-critique, and is it worth the added resources
relative to a plain Astra revision?

The upstream static leaderboard lists 110 Blocksworld Hard instances. Use a
fixed random 50-instance subset for this time-bounded screen. Call the result
"PlanBench Blocksworld Hard — fixed 50-task co-evolution subset". It is not
a full-set leaderboard score or a zero-shot score for the multi-call arms.

Sources checked September 13, 2026:
- https://github.com/karthikv792/LLMs-Planning
- https://github.com/karthikv792/LLMs-Planning/blob/main/llm_planning_analysis/README.md
- https://github.com/KCL-Planning/VAL

TravelPlanner is a reasonable later application-oriented benchmark, but its
database setup and reference LLM-based postprocessing add work and potential
confounds for this short run. Its public validation set has offline scoring;
test evaluation uses the official leaderboard:
https://github.com/OSU-NLP-Group/TravelPlanner

## Frozen experiment

| Arm | Workflow | Standalone calls/task |
|---|---|---:|
| A | Astra original plan | 1 |
| B | Same original -> Astra plain revision | 2 |
| C | Same original -> fresh Astra critique -> Astra revision | 3 |
| D | Same original -> fresh Fable critique -> Astra revision | 3 |

Proposed exact seats: gpt-6-astra/high as author, reviser and self-critic;
claude-fable-5-1/high as external critic. These models are participants, not
judges in this stage. Probe exact availability; no silent model fallback.

All arms branch from the identical immutable original per task. C and D
use the same critique and integration instructions with reviewer identity
removed. Critiques receive the task and original, not other arms' outputs.
Only the resulting action sequence is evaluated. Use fresh isolated contexts,
no browsing, solver tools, repository instructions, historical study scores,
reference solutions, or validator feedback. Run final scoring only after
the candidates are frozen. Disable LLM-based extraction/translation; use
the upstream deterministic PDDL extraction/evaluation path.

Use upstream zero-shot PDDL task instructions, plus the smallest common
output-format instruction needed by the official parser. No invented task
content or benchmark-specific solution hints. Pin source, parser, VAL build,
model settings, prompts, and task manifest hashes before the first scored
task. Sample the sorted released IDs with seed 20260913 before generation;
write the actual selected IDs to the manifest. Do not select by model scores.
Freeze the randomized execution order too. Do not change task set or domain
after seeing ceiling/floor effects.

One output per arm, no best-of-N selection. Same author settings in every
arm, same critic output cap in C/D. Proposed answer caps: 4096 tokens for
plans/revisions and 1024 for critiques, where the transport supports them;
record actual enforcement and provider limits. Never silently truncate a
received plan. Equal effort labels/pass counts do not mean equal compute.

## Budget and elapsed time

Sharing each original requires six calls per task: one draft, one plain
revision, two critiques, two integrations. Thus 50 tasks yield 200 candidate
plans for 300 calls: 250 Astra and 50 Fable. Evaluator requires no LLM calls.

Proposed new-stage ceiling: 336 calls, including two disjoint unscored smoke
tasks run through the four arms (12 calls), plus 24 transient-retry slots.
Family maxima: Astra 280 (250+10+20), Fable 56 (50+2+4). No transfer between
families, refunds, or reuse of remaining authorization from the prior study.
The ceiling is a proposal, not a claim that these calls are already spent
or that the old grant authorizes them. Existing subscription routes only;
no new paid API fallback or usage-credit reset.

Target elapsed time: 90–150 minutes after dependencies are available; hard
deadline three hours from execution start, including the readiness check.
Initial setup is not yet verified: if it cannot finish promptly, report that
the run is not ready rather than promise a completed benchmark score.

Use one controller, at most six in-flight model calls (four Astra, two Fable),
subject to supported provider limits. This is bounded job concurrency, not
additional research agents. At 60–90 seconds per Astra call, 250 Astra calls
at concurrency four represent roughly 63–94 minutes of occupied slots,
before dependency gaps/retries; hence the runtime range is an estimate.
Use a 120-second per-call timeout. Count every dispatch before sending it.
Checkpoint immutable successful jobs; resume only unfinished eligible jobs.

At two hours 40 minutes, stop new dispatches; drain/terminate owned in-flight
work within its timeout, validate, and write the report by three hours.
Use one fresh retry only for a transient transport failure within global
retry and time caps. Invalid plans and malformed model outputs do not get
repair retries. A verified provider/account failure stops that family and
settles a partial report; no unattended restart or expanded allowance.

## Minimal readiness and implementation

1. Reuse the repaired isolation, model-identity checks and reservation ledger
   patterns from the planning study. Create a separate run directory/grant;
   never alter either previous study's evidence.
2. Pin the official benchmark and evaluator, and locate the exact 110-task
   manifest. Use the existing Linux/WSL environment if needed. Do not run
   unrelated planning tasks or build the entire benchmark suite.
3. Verify evaluator wiring with one known-valid and one intentionally invalid
   action sequence, and check invalid serialization is rejected. Reference
   fixtures must not be visible to study participants.
4. Run the two excluded smoke tasks once to verify all four paths, artifact
   recording, model identity, parser compatibility, and observed throughput.
   These are engineering checks, not task-selection or prompt-tuning trials.
5. Verify one checkpoint/resume with a disposable offline fixture so successful
   calls cannot repeat. Trust existing green isolation/accounting tests unless
   their code changes. Freeze the scored manifest and launch once.

If readiness or throughput cannot support the deadline, report the obstacle
and estimated capacity. Do not silently shrink the scored subset or retry
implementation indefinitely inside the live run.

## Score and analysis

Primary score for each complete arm: 100 * valid goal-reaching plans / 50.
Each task is worth two percentage points. All steps must be legal and the
goal must be satisfied. Do not require an optimal/shortest plan unless the
pinned official scoring protocol does so. Invalid final model output fails.
Validator crashes, missing responses and unattempted jobs are infrastructure
missingness, explicitly separate from an incorrect generated plan.

If incomplete, show coverage, observed valid/invalid counts and missing counts,
with a score range [100*valid/50, 100*(valid+missing)/50]. Do not present an
observed-subset percentage as a completed 50-task benchmark score. Give
paired comparisons only for jointly evaluated tasks, with their denominator.

Primary contrast: D minus C. Secondary contrasts: D minus B and D minus A.
Report percentage-point differences, paired bootstrap intervals over task IDs,
and the exact McNemar result for D/C's discordant outcomes. Secondary tests
are descriptive. Show repairs (comparator fails, D passes) and regressions
(comparator passes, D fails). Never count reused originals as independent
samples. One generation per task limits inference across stochastic reruns.

Report calls, input/output/cached tokens where available, unpriced usage,
standalone estimated cost per arm, incremental shared experimental spend,
and measured elapsed time per workflow. Shared campaign spend and standalone
workflow cost are different quantities; do not divide one into the other.

Example only: D solves 35/50 and C solves 30/50 -> 70% versus 60%, +10 points,
five additional solved tasks. This is not an observed result.

## Predeclared decision

A practical positive screen requires D to solve at least five more tasks
than C (+10 points) and improve over B, with no more than twice B's measured
median end-to-end workflow time. Report measured cost alongside this choice.
This is an operational threshold, not automatically statistical significance.

- Threshold met and paired interval excludes zero: evidence supporting this
  workflow on this benchmark; consider a fresh replication/application test.
- Positive difference with interval spanning zero: promising/inconclusive;
  do not announce a proven benefit or enlarge the run automatically.
- No gain over B, net regression, or excessive overhead: prefer plain revision
  for this use and do not expand the same matrix.
- Baseline >=90% or all arms <=10%: report a ceiling/floor-limited screen;
  do not switch tasks mid-run to manufacture a difference.

Fifty tasks can reveal large effects but are insufficient to reliably settle
small gains. Public static tasks may have training exposure. State-action
planning results do not establish human productivity or general intelligence.

## Deliverable

One scored four-row table, the paired D/C wins/losses, resource costs, coverage,
and a short practical recommendation; preserve machine-readable results and
raw attempts with provenance. Prepare a website-ready report in the existing
style, labeled with the known benchmark, exact subset and multi-call protocol.
Do not overwrite the prior custom-planning results or imply leaderboard
submission. This task produces the plan; live execution has not begun.
