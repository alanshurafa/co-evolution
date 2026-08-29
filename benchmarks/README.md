# Co-Evolution Benchmark Suite

Batch runbook for comparing plan-composition conditions (solo Fable, Codex
bounce, panel critique, self-bounce control) on identical planning tasks,
scored by three blind automated judges. See `PREREGISTRATION.md` for the
frozen hypotheses and decision rules this batch is judged against, and
`conditions.yaml` for what each condition actually runs.

This is exploratory directional evidence, not a benchmark leaderboard. Read
the pre-registration before reading the report.

## Before you start: run from the main checkout

Run batches from the main repo checkout, not a deep `.claude/worktrees/...`
path. The bouncer derives its run-dir name from a slug of the input file's
full path; combined with a deep parent directory, the resulting `state.json`
path can exceed Windows's 260-character `MAX_PATH`, and `jq.exe` fails with
"Could not open file" even though bash happily created the directory.
`run-benchmark.sh` guards against this at startup (see below), but the guard
only tells you the batch won't fit — it can't shorten your checkout path for
you. If you see the guard trip, move the checkout up a few directories rather
than fighting it from a worktree.

## Workflow

Every step below assumes you're in the repo root with `benchmarks/` as your
working reference.

**1. Lint the corpus and conditions before touching a model.**

```bash
bash benchmarks/run-benchmark.sh --check
```

Validates: all 8 corpus files parse and carry required frontmatter, the Kimi
prompt-size arithmetic clears the 11500-byte floor for every task (so
condition C never silently degrades to a 2-critic panel), and no corpus
prompt collides with a banned token (`lib/banned-tokens.txt`) in a way that
would make that task's pairs unjudgeable.

**2. Preview the batch shape before spending anything.**

```bash
bash benchmarks/run-benchmark.sh --dry-run --batch b1
```

Prints the full task x condition matrix (8x4 = 32 cells), the path-length
guard's verdict for the chosen batch id, and an estimate of GLM calls against
the daily free-tier budget. Nothing runs.

**3. Run the batch.**

```bash
bash benchmarks/run-benchmark.sh --batch b1
```

Resumes by default — a cell is complete only once its `meta.json` has
`status=="complete"` written last, so a killed or interrupted run picks back
up without redoing finished cells. Re-run a single cell with
`--force-cell t3/B`. Useful narrowing flags: `--only-task`,
`--only-condition`, `--glm-budget` (default 40/day).

Exit codes are deliberate, not the repo's usual "signal lives in artifacts"
convention: `0` means every cell in the batch completed; `75` means some
cells are stuck at `pending-quota` (see the GLM note below) and the batch
needs a re-run tomorrow; `1` is a hard failure. This orchestrator is meant to
be driven by cron, so a silent `0` exit on a half-finished batch would be
worse than a distinct "come back later" code.

**4. Judge, once every generation cell is complete.**

```bash
bash benchmarks/judge-matrix.sh --batch b1
```

Judging only starts after all generation cells finish — there's a single
freeze point here, not a rolling one, so day-one cells never get judged
against day-two cells that used a different frozen corpus state. Each pair
runs 2 position-swapped trials per judge, across all three judges (fable-5,
gpt-5.5, glm-5.3-flash); verdicts are written per pair so judging is
resumable the same way generation is.

**5. Report.**

```bash
bash benchmarks/report.sh --batch b1
```

Writes `results/b1/REPORT.md` and a committed copy under
`benchmarks/reports/b1.md`. Leads with the pre-registered B-vs-A and B-vs-D
verdicts, then per-judge matrices, judge-integrity stats, and the exploratory
sections — in that order, matching `PREREGISTRATION.md` section 1.

## GLM quota and multi-day batches

Condition C needs one GLM call per run, and GLM judging needs one call per
trial across all three judges' worth of pairs — together that can run well
past the ~50 requests/day free tier for a full 8x4 batch. `run-benchmark.sh`
and `judge-matrix.sh` both track spend in a per-batch ledger
(`results/<batch>/glm-ledger.json`) and mark any cell or pair that would
exceed `--glm-budget` as `pending-quota` instead of failing it outright.

Plan on a full batch spanning roughly 2-3 days for this reason alone. Re-run
the same command on later days — it picks up exactly where the ledger left
off, spending only the cells and pairs still marked `pending-quota`, and
exits `75` again if any remain. Pass `--allow-pending` if you need an exit
`0` from a caller that's fine treating a partially-judged batch as done for
now; the ledger keeps tracking regardless, so a later run still resumes the
rest.

The ledger only sees calls made through this suite — it can't see Z.AI's own
server-side rate window or GLM usage from other work running on the same
account. If GLM starts failing before the ledger thinks it should, that's the
likely cause; the auth-failure path aborts the affected cell without writing
so a later run retries it, rather than corrupting a partial result.
