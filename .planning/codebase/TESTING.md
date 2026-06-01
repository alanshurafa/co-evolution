# Testing

The repository has two complementary, locally-run test systems: a scored **eval
harness** under `evals/` and per-component **simulation scripts** under `tests/`.
There is no aggregate test runner and no CI workflow, so each is invoked directly
on Bash (Git Bash on Windows, WSL, macOS, or Linux).

## 1. Eval harness (`evals/`)

A scored, fixture-based harness that runs the dev-review code pipeline
(`dev-review/codex/dev-review.sh`) end-to-end against a case library and grades
each run across seven dimensions: plan quality, execution fidelity, verify
accuracy, cost, cross-AI diversity, robustness, and convergence. See
`evals/README.md` for the full contract.

```bash
# Run every case end-to-end (invoke runner per case, score, write report).
bash evals/run-evals.sh

# Validate the case YAMLs parse + merge without invoking the runner.
bash evals/run-evals.sh --validate

# Run a single case.
bash evals/run-evals.sh --case 01-trivial-task

# Score one already-captured run against a case spec.
bash evals/score-run.sh --case-file evals/cases/01-trivial-task.yaml \
                        --run-dir <run-dir> --defaults-file evals/cases/defaults.yaml

# Compare two report directories.
bash evals/compare-reports.sh --before <reportA> --after <reportB>

# Regression gate (hermetic, no LLM cost). Prints "14/14 scenarios passed".
bash evals/tests/scorer-verification.sh
```

Pieces:

- `evals/run-evals.sh` — orchestrator: case selection, fixture setup, scoring, report.
- `evals/score-run.sh` — scores a single run across the seven dimensions.
- `evals/compare-reports.sh` — diffs two report directories.
- `evals/lib/co-evolution-evals.sh` — shared scoring library.
- `evals/cases/*.yaml` — 9 cases (`01`–`09`) layered over `defaults.yaml`.
- `evals/tests/scorer-verification.sh` — the regression gate: Tier 1 golden
  fixtures, Tier 2 hermetic end-to-end (via `evals/tests/fake-runner.sh`),
  Tier 3 determinism, Tier 4 real-runner contract smoke. Final line on success:
  `14/14 scenarios passed`.

Reports are written to `evals/reports/<timestamp>/`, which is gitignored.

## 2. Simulation scripts (`tests/`)

Standalone, hermetic Bash scripts — one per component — that stub the agent CLIs
(`claude`, `codex`) and assert behavior with no network and no LLM cost. Each is
run on its own:

```bash
bash tests/<name>-simulation.sh
```

`ls tests/*-simulation.sh` is the authoritative list. As of this writing:

| Script | Covers |
|--------|--------|
| `classifier-simulation.sh` | PEL mode classifier (`lab/pel/classifier/`) |
| `router-simulation.sh` | lab router (`lab/pel/router/`) |
| `lab-routing-simulation.sh` | `--lab <mode>` routing + validation on both runners |
| `code-proposer-simulation.sh` | code-tier proposer (`lab/pel/proposer/code/`) |
| `policy-proposer-simulation.sh` | policy-tier proposer (`lab/pel/proposer/policy/`) |
| `template-proposer-simulation.sh` | template-tier proposer (`lab/pel/proposer/template/`) |
| `pr-emitter-simulation.sh` | PR emitter + scorer cache (`lab/pel/pr-emitter/`) |
| `revise-loop-simulation.sh` | dev-review REVISE auto-loop (RTUX-03) |
| `live-mode-simulation.sh` | `--live` / `LIVE_MODE` window launch + non-Windows fallback |
| `worktree-management-simulation.sh` | `--branch` / `--worktree` setup + teardown (RTUX-02) |

## Dependencies

- `bash` (>= 4) and coreutils.
- `jq` — JSON manipulation.
- `yq` — YAML→JSON for case files (mikefarah's Go build, **not** the Python package).
- No `pwsh` required for the Bash harness. The PowerShell scripts under
  `runners/codex-ps/` are a separate, byte-stable legacy reference.

## Coverage and gaps

- **Covered:** the dev-review scoring pipeline (eval harness, made falsifiable by
  the Tier 4 seeded regressions) and each PEL / lab component (simulation scripts).
- **No aggregate runner:** there is no single command that runs everything. Run
  the eval gate and each simulation script individually.
- **No CI:** nothing runs these automatically on push or PR; they are manual.
- **Thin spots:** the document bouncer (`co-evolve-bouncer.sh`) has no dedicated
  scoring test of its own; marker-counting edge cases around fenced code blocks
  and inline backticks have no explicit assertion.
