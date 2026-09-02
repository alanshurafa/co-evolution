# Code Benchmark Battery — Implementation Plan

Date: 2026-08-31

## Goal

Measure whether Co-Evolution workflows produce repository patches that pass
standard deterministic evaluators, while keeping subscription usage bounded and
making every live dispatch auditable before it runs.

## Conditions

- **A — Fable solo:** one Fable coding-agent dispatch.
- **B — cross-vendor bounce:** Fable implements; Codex reviews and repairs.
- **C — Fable-led panel:** Fable implements; Codex, GLM, and Kimi critique;
  Fable performs the final repair.
- **D — Fable self-bounce:** Fable implements and then reviews/repairs its own
  patch. This controls for extra passes and compute.

Declared provider dispatches are a lower bound: one coding-agent dispatch may
contain multiple internal model turns. The live runner must enforce a declared
Claude-dispatch cap and must never infer a percentage of a Max subscription from
tokens because Anthropic does not publish a fixed weekly token denominator.

## Delivery sequence

1. Add frozen suite, condition, external-source, and subset manifests.
2. Add an offline compute estimator and fail-closed prediction validator.
3. Add a pinned SWE-bench installer, metadata fetcher, and official evaluator
   bridge under an ignored cache/results tree.
4. Add hermetic tests and wire them into the repository aggregate gate.
5. Prepare the five-task canary and validate official gold scoring when Docker
   is available.
6. Add live patch-generation drivers only after the offline harness is green.
   Begin with one task and conditions A/B/C, capped at four declared Fable
   dispatches. Measure the actual Settings > Usage change before expanding.

## Safety and scope

- No full SWE-bench run in this phase.
- No live model calls during setup or hermetic verification.
- No gold patches, hidden tests, or oracle solutions are exposed to agents.
- Every condition starts from the same clean instance and produces a standard
  prediction record for the official evaluator.
- Raw datasets, images, virtual environments, trajectories, and results stay
  below `benchmarks/results/code/` and remain uncommitted.

## Acceptance criteria

- `bash benchmarks/code/code-bench.sh check` passes.
- The estimator reports exact declared dispatch counts and refuses a cap breach
  with exit 75.
- Prediction validation rejects unknown instances, duplicates, empty patches,
  and malformed JSONL.
- The pinned metadata fetch contains only public task inputs, never gold data.
- The official SWE-bench gold canary passes once Docker is running.
- The repository aggregate test gate includes the new hermetic suite.

## Execution result

- Pinned SWE-bench source and CLI installed under the ignored results cache.
- Windows compatibility patch forces LF for the Linux `eval.sh` file only.
- Docker Desktop 29.6.2 official gold canary `sympy__sympy-20916` completed
  and resolved 1/1 with zero infrastructure, ambiguous, or evaluator errors.
- Hermetic code-benchmark suite passed 14/14; repository aggregate passed
  42/42 after isolating the intentionally installed private Kimi key.
- No live Fable, Codex, GLM, or Kimi benchmark calls were made during setup.
