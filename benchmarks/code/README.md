# Code Benchmark Battery

This suite compares Co-Evolution coding workflows using deterministic external
evaluators. It complements the plan-composition benchmark in `benchmarks/`;
it does not reuse model judges when official tests can decide whether a patch
resolved an issue.

Authoritative references: [SWE-bench quickstart](https://www.swebench.com/SWE-bench/guides/quickstart/),
[SWE-bench Verified limitations](https://openai.com/index/introducing-swe-bench-verified/),
[Aider benchmark harness](https://github.com/Aider-AI/aider/blob/main/benchmark/README.md),
and [Harbor Terminal-Bench](https://www.harborframework.com/docs/tutorials/running-terminal-bench).

## Initial battery

- **SWE-bench Verified canary:** five pinned tasks from five repositories.
- **Local fixture lane:** hermetic contracts for the runner itself; no models.
- **Future lanes:** Aider Polyglot, Terminal-Bench, and a private recent-issue
  set can plug into the same prediction and reporting contract.

The conditions are declared in `conditions.json`, each with a `tier`:

| Id | Label | Tier | What runs |
|---|---|---|---|
| A | fable-solo | agentic | Fable implements once |
| B | cross-vendor-bounce | agentic | Fable implements; Codex repairs |
| C | fable-led-panel | agentic | Fable implements; Codex/GLM/Kimi critique; Fable repairs |
| D | fable-self-bounce | agentic | Fable implements, then reviews and repairs its own patch |
| E | codex-solo | agentic | Codex implements once |
| F | glm-solo-single-shot | single-shot | GLM sees the issue plus retrieved context, returns one diff |
| G | kimi-solo-single-shot | single-shot | Kimi sees the issue plus retrieved context, returns one diff |
| H | fable-glm-bounce | agentic | Fable implements; GLM critiques once; Fable repairs |
| I | fable-kimi-bounce | agentic | Fable implements; Kimi critiques once; Fable repairs |

D is retained as a self-bounce control even when the product question focuses
on A/B/C. E is the comparator that makes B's repair arm interpretable.

H and I isolate one critic each out of C's three-model panel, which is what
makes C's result attributable: if C beats B, H and I say whether a cheap
cross-vendor critic accounts for the gain. Their critics are single-shot even
though the arm is agentic — GLM and Kimi read the candidate patch in the prompt
and answer once, with no file access and no test run. The repairing agent is
Fable either way, so the arm stays agentic.

**The tier is not cosmetic.** Agentic conditions run a coding agent with file
tools and test execution. GLM and Kimi are reachable here only as chat
completions, so F and G get one prompt and one answer: no file reads, no test
runs, no second look. A single-shot number is not a like-for-like result
against an agentic one and must never be reported beside one without the
label.

## Zero-compute setup

```bash
bash benchmarks/code/code-bench.sh check
bash benchmarks/code/code-bench.sh estimate --suite swebench-verified-canary
bash benchmarks/code/code-bench.sh fetch-metadata
bash benchmarks/code/code-bench.sh setup --install
```

These commands make no model calls. The installer pins both the official
SWE-bench repository and dataset revisions from `external-sources.lock.json`.
External files live under the ignored `benchmarks/results/code/` tree.
On Windows, setup also applies the tracked LF-only compatibility patch under
`patches/`; it changes only how the harness writes the Linux `eval.sh` file.

## Capped patch generation

Prepare a clean workspace, then run a single condition. Preparation makes no
model calls. `run-workflow` refuses to start without an explicit Claude cap.

```bash
input=$(bash benchmarks/code/code-bench.sh prepare-instance \
  sympy__sympy-20916 calibration-1 A)

bash benchmarks/code/code-bench.sh run-workflow \
  --input "$input" \
  --predictions benchmarks/results/code/predictions/calibration-1.jsonl \
  --max-claude-dispatches 1
```

Use `--dry-run` on `run-workflow` to inspect its phase plan without invoking a
provider. Condition C labels its three critiques anonymously and gives Fable
the final repair decision. If `ANTHROPIC_API_KEY` is present, live generation
fails closed so Claude Console credits cannot be charged accidentally instead
of the Max subscription.

### Codex sandbox mode

Codex 0.144.5 on Windows accepts `--sandbox workspace-write` and then reports
`sandbox: read-only`, so every write is refused and a repair arm silently goes
inert while still producing a plausible review. `CODE_BENCH_CODEX_SANDBOX`
selects the mode; it defaults to `workspace-write` and the driver records the
value it used in each cell's `run-manifest.json`, because the mode changes what
the treatment actually is.

```bash
CODE_BENCH_CODEX_SANDBOX=danger-full-access bash benchmarks/code/code-bench.sh run-workflow ...
```

Elevated access is defensible only because a benchmark workspace is a
throwaway clone under the ignored `benchmarks/results/code/runs/` tree. Do not
set it for anything else.

### Single-shot tier

```bash
bash benchmarks/code/code-bench.sh run-single-shot \
  --input "$input" \
  --predictions benchmarks/results/code/predictions/matrix/F.jsonl \
  --agent glm
```

`scripts/select-context.py` picks the files the prompt shows, deterministically
and from public inputs only: paths named in the issue rank first, then files
matched by the issue's rarest identifiers, with tests and examples at half
weight. The model returns a unified diff, `scripts/extract-diff.sh` pulls it
out of the prose, and `git apply --check --recount` gates it; a rejected diff is
fed back with the apply error for up to `CODE_BENCH_SINGLE_SHOT_ATTEMPTS` tries
(default 3). `--recount` recomputes the `@@` line counts from the hunk body and
changes no line of the proposed edit. Without it the gate scores the model's
line arithmetic rather than its patch, which is an artefact of asking for a diff
at all: the agentic conditions edit files directly and never write a hunk
header. Measured on the first two GLM cells, the strict gate rejected every
attempt while `--recount` accepted the first.

A cell that never produces an applicable patch writes `outcome.json` and
contributes no prediction rather than a broken one.

`CODE_BENCH_SINGLE_SHOT_MAX_TOKENS` defaults to 32000. Both providers bill
reasoning against `max_tokens`, and on this prompt shape GLM spends roughly
19k reasoning tokens before it writes anything, so a smaller budget returns
`finish_reason=length` with empty content every single time.

Live phases default to medium reasoning and a 900-second timeout. Override with
`CODE_BENCH_CLAUDE_EFFORT`, `CODE_BENCH_CODEX_EFFORT`, and
`CODE_BENCH_PHASE_TIMEOUT`; changing these values creates a different treatment
and must be recorded in the run manifest.
Direct GLM and Kimi critiques run with bounded reasoning: GLM at
`reasoning_effort=low` (`CODE_BENCH_GLM_REASONING_EFFORT`) and Kimi with
thinking off (`CODE_BENCH_KIMI_THINKING`), under a 2500-token output cap
(`CODE_BENCH_CRITIC_MAX_TOKENS`). Both providers bill reasoning tokens against
`max_tokens`, so an unbounded critic can spend the whole budget before writing
any content and return an empty response. Each critic gets
`CODE_BENCH_CRITIC_ATTEMPTS` attempts (default 3) spaced by
`CODE_BENCH_CRITIC_RETRY_DELAY` seconds; an artifact still invalid after the
last attempt fails the cell instead of reaching the final repair.

`run-workflow --resume` reuses a successful Fable implementation and valid
critic artifacts. Provider-error text is rejected before the final Fable repair,
so a transient GLM/Kimi failure cannot silently degrade the four-model treatment.

## Official evaluator

Docker must be running. Validate the environment with a gold patch before
evaluating generated predictions:

```bash
bash benchmarks/code/code-bench.sh gold-canary
bash benchmarks/code/code-bench.sh validate-predictions predictions.jsonl
bash benchmarks/code/code-bench.sh evaluate predictions.jsonl
```

Prediction JSONL uses the official SWE-bench fields:

```json
{"instance_id":"owner__repo-123","model_name_or_path":"condition-A","model_patch":"diff --git ..."}
```

Gold patches and hidden tests are never stored in this repository or supplied
to a generation workflow.

## Results site

```bash
bash benchmarks/site/aggregate.sh
```

Builds `benchmarks/results/code/site/leaderboard.json` from the evaluator
reports, the evaluator's own per-instance verdicts, and the run manifests. Each
row carries the report file it came from and each task carries the
`report.json` that decided it, so every number on the published page can be
checked against a file on disk. The page renders that JSON and nothing else.

## Compute contract

`estimate` reports declared provider dispatches. For the five-task canary:

- A/B/C: 20 declared Fable dispatches total.
- A/B/C/D: 30 declared Fable dispatches total.
- One task across A/B/C: 4 declared Fable dispatches.

Those are lower bounds because a coding-agent session may contain multiple
model turns. Live generation must begin with one task, A/B/C, and a cap of four
declared Fable dispatches. Anthropic does not publish a fixed weekly token
allowance, so the first run is also the calibration: record Settings > Usage
before and after, then use that measured delta to decide whether to expand.

The batch command enforces that aggregate cap before cloning or dispatching:

```bash
bash benchmarks/code/code-bench.sh run-canary \
  --run-id calibration-1 \
  --conditions A,B,C \
  --task-limit 1 \
  --max-claude-dispatches 4 \
  --dry-run
```
