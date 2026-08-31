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

The four conditions are declared in `conditions.json`. Condition D is retained
as a self-bounce control even when the product question focuses on A/B/C.

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

Live phases default to medium reasoning and a 900-second timeout. Override with
`CODE_BENCH_CLAUDE_EFFORT`, `CODE_BENCH_CODEX_EFFORT`, and
`CODE_BENCH_PHASE_TIMEOUT`; changing these values creates a different treatment
and must be recorded in the run manifest.

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
