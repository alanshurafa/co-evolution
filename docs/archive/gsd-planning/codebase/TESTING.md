# Testing

The repository has two complementary, locally-run test systems: a scored **eval
harness** under `evals/` and per-component **simulation scripts** under `tests/`.
Run everything with the aggregate runner (v1.3):

```bash
bash tests/run-all.sh           # every suite, hermetic git config
bash tests/run-all.sh --quick   # skip the slow proposer/emitter suites
```

CI (`.github/workflows/ci.yml`) runs the full suite on ubuntu, macos (stock
bash 3.2), and windows (Git Bash) for every push to master and every PR.

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

# Bounce-scorer gate (document bouncer; hermetic). Prints "7/7 scenarios passed".
bash evals/tests/bounce-scorer-verification.sh
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
| `reliability-simulation.sh` | R-1/R-2 auth fail-fast, template-fill pinning, delta_status, run-suffix entropy, marker stripping (v1.3) |
| `bounce-state-simulation.sh` | bounce-state/1.0 state.json from both bouncers (v1.3) |
| `bounce-judge-simulation.sh` | blind A/B judge ordering/bias/evidence paths + HUMAN-REPORT.md (v1.3) |
| `protocol-parity-simulation.sh` | bounce-protocol.md copies pinned to canonical (v1.3) |
| `cross-platform-path-normalization-simulation.sh` | path normalization across Windows/WSL/macOS/Linux |

## Dependencies

Check any machine with `bash scripts/doctor.sh`.

- `bash` (3.2+ works, including stock macOS `/bin/bash`; 4+ recommended) and coreutils (`timeout` optional — perl fallback).
- `jq` — JSON manipulation.
- `yq` — YAML→JSON for case files (mikefarah's Go build, **not** the Python package).
- No `pwsh` required for the Bash harness. The PowerShell scripts under
  `runners/codex-ps/` are a separate, byte-stable legacy reference.

## Coverage and gaps

- **Covered:** the dev-review scoring pipeline (eval harness, made falsifiable by
  the Tier 4 seeded regressions), each PEL / lab component (simulation scripts),
  the document bouncers' state contract + reliability paths, and the bounce
  scorer/judge/report stack (v1.3).
- **Aggregate runner:** `bash tests/run-all.sh` (closed audit F-3).
- **CI:** 3-OS matrix on push/PR (closed audit F-4).
- **Thin spots:** marker-counting edge cases around fenced code blocks and
  inline backticks have only indirect coverage (via scorer fixtures); the
  judge is tested against stubs, not a live model — calibration
  (`evals/calibrate-bounce.sh`) is the live-model check.
