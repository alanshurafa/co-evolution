# Evals — Cross-Runner Portable Assets

This directory holds the **runner-agnostic** portable slice of the eval system:
test cases, scorer fixtures, the five-tier verification strategy, and (one level
up) the review-verdict JSON schema. Any runner — the current Bash runner, the
PS reference implementation, or a future Bash eval harness — reads from here.

## Layout

```
evals/
├── cases/
│   ├── defaults.yaml        Shared threshold defaults merged into every case
│   └── *.yaml               9 case YAMLs covering the full dimension space
├── fixtures/
│   ├── mock-report.md       Scorer unit fixture — canned report markdown
│   └── mock-scores.json     Scorer unit fixture — canned scores JSON
├── VERIFICATION-PLAN.md     Five-tier verification strategy
└── README.md                This file

schemas/
└── review-verdict.json      JSON schema for APPROVED/REVISE verdicts (draft-07)
```

Every file here (except this README) is byte-identical to its source under
`runners/codex-ps/evals/` or `runners/codex-ps/schemas/` as of Phase 8. If the
top-level copies diverge in later work, that divergence is intentional and the
`runners/codex-ps/` copies remain the Phase-5 audit trail (CXPS-02, read-only).

## Bash Harness (default)

The Bash harness runs on Git Bash (Windows) + Linux + macOS without `pwsh`.
It is the default invocation surface from v1.2 onward; the PowerShell scripts
under `runners/codex-ps/evals/` remain as a byte-stable legacy reference
(see `## Legacy PowerShell Harness` below).

### Invocation

```bash
# Run all cases end-to-end (invokes dev-review runner per case, scores, emits report).
bash evals/run-evals.sh

# Validate case YAMLs parse + merge without invoking the runner.
bash evals/run-evals.sh --validate

# Run a single case.
bash evals/run-evals.sh --case 01-trivial-task

# Run against a hermetic fake runner (Tier 2 testing, no LLM cost — see evals/tests/fake-runner.sh).
bash evals/run-evals.sh --case 01-trivial-task --runner-path evals/tests/fake-runner.sh

# Score a single captured run against a case spec.
bash evals/score-run.sh --case-file evals/cases/01-trivial-task.yaml \
                        --run-dir path/to/run \
                        --defaults-file evals/cases/defaults.yaml

# Compare two reports.
bash evals/compare-reports.sh --before evals/reports/20260417-080000 \
                              --after  evals/reports/20260418-120000

# Run the combined Tier 1 + Tier 2 + Tier 3 regression gate (all fixtures + hermetic end-to-end smoke).
bash evals/tests/scorer-verification.sh
```

### Dependencies (Bash harness)

| Tool | Role | Install |
|------|------|---------|
| `jq` | JSON manipulation (already required by `dev-review/codex/dev-review.sh`) | `scoop install jq` (Windows) / `brew install jq` (macOS) / `apt install jq` (Linux) |
| `yq` | YAML to JSON (mikefarah's Go flavor, NOT the Python package) | `scoop install yq` (Windows) / `brew install yq` (macOS) / `go install github.com/mikefarah/yq/v4@latest` (Linux) |

Both are single-binary dependencies that Just Work on every supported platform.

### Verification

- **Tier 1 (golden-fixture regression):** `bash evals/tests/scorer-verification.sh` asserts the Bash scorer reproduces PS-produced `EXPECTED.json` outputs for all 10 fixture suites under `runners/codex-ps/evals/tests/fixtures/`.
- **Tier 2 (hermetic end-to-end smoke):** Same script runs `evals/run-evals.sh --case 01-trivial-task --runner-path evals/tests/fake-runner.sh` in two modes (PASS + FAIL) to prove the orchestrator produces a non-empty `report.md`, a valid JSON `raw-scores.json`, and that the `robust_fails > 0` exit-code policy fires correctly. The fake runner is a deterministic test double — no LLM cost. Satisfies SC-3 (multi-platform CI simulation) on any Bash + jq + yq environment.
- **Tier 3 (determinism):** Same script scores the same fixture twice and asserts byte-identical output (after stripping the ISO timestamp).
- **Tier 4 (real-runner contract smoke):** Same script invokes `evals/run-evals.sh` against the REAL `dev-review/codex/dev-review.sh` with PATH-stubbed `claude` + `codex` CLIs, wrapped in a 120s timeout. Asserts state.json contract conformance end-to-end: `.status` ∈ {completed, partial, failed}, `outputs/compose.txt` non-empty, scorer produces non-null robustness. Closes the gap where WR-01/WR-02/WR-04 slipped past because every pre-ship Tier was hermetic on `fake-runner.sh`. See [`RUNNER-CONTRACT.md`](RUNNER-CONTRACT.md) for the shared spec both sides conform to.
- Final stdout line on success: `14/14 scenarios passed` (10 Tier 1 + 1 Tier 3 + 2 Tier 2 + 1 Tier 4).

## Legacy PowerShell Harness

The PowerShell harness under `runners/codex-ps/evals/` remains as a byte-stable
reference implementation. Use it to regenerate `EXPECTED.json` fixtures when
the scoring spec evolves, or to cross-check Bash output during development.
Requires `pwsh` (PowerShell Core, cross-platform).

```powershell
pwsh runners/codex-ps/evals/run-evals.ps1
pwsh runners/codex-ps/evals/score-run.ps1 <run-dir>
pwsh runners/codex-ps/evals/compare-reports.ps1 <baseline> <new>
```

Case YAMLs here resolve relative to the repo root, so the PS harness reads
them at either `evals/cases/` or `runners/codex-ps/evals/cases/` — both are
byte-identical until edits diverge. See
`runners/codex-ps/evals/UPSTREAM-MESSAGE.md` for the cross-runner parity
inventory the PS harness tracks.

## pwsh Dependency — Optional

pwsh is optional — required only to run the PS eval harness under
`runners/codex-ps/`, not the Bash runner (`agent-bouncer/agent-bouncer.sh`,
`dev-review/codex/dev-review.sh`) itself. The Bash runner has zero PowerShell
dependency; you can use the full compose-bounce-execute-verify loop on a
machine that has never heard of `pwsh`. Evals are a separate concern.

| Component                          | Requires pwsh? |
|------------------------------------|----------------|
| `agent-bouncer/agent-bouncer.sh`   | No             |
| `dev-review/codex/dev-review.sh`   | No             |
| `lib/co-evolution.sh`              | No             |
| `evals/*.sh` (Bash harness)        | No             |
| `runners/codex-ps/evals/*.ps1`     | Yes (legacy)   |
| Reading `evals/cases/*.yaml`       | No (plain YAML)|
| Reading `schemas/review-verdict.json` | No          |

## Case Schema Convention

Case YAMLs layer over `defaults.yaml` (shared thresholds). Each case sets:

```yaml
id: <string>
title: <string>
description: <string>
runner:
  task: <prompt>
  composer: codex | opus
  reviewer: codex | opus
  executor: codex | opus
  bounces: <int | "auto">
  verify: <bool>
  autonomous: <bool>
setup:
  mode: temp_repo
  seed_files: [...]        # optional
  copy_from: [...]         # optional
expectations:
  plan_quality: {...}
  execution_fidelity: {...}
  verify_accuracy: {...}
  cost: {...}
  cross_ai_diversity: {...}
teardown:
  cleanup_temp_repo: <bool>
```

See `VERIFICATION-PLAN.md` for the five-tier strategy that validates the
scorer against these expectations.

## Scorer output cache (`.co-evolve-cache/`)

The PEL PR emitter (`lab/pel/pr-emitter/`) caches scorer output at
`.co-evolve-cache/evals/<fixture-hash>-<script-hash>-<worktree-hash>[-<dirty-hash>].json`.
The cache is:

- **Gitignored** — lives per-clone, not in repo history (`.co-evolve-cache/` was added
  to the root `.gitignore` in Phase 8 Plan 01)
- **Hash-invalidated** — rebuilt when fixtures OR `evals/*.sh` OR the scored worktree
  HEAD OR the worktree dirty state change
- **Cost-attributed** — cache hits cost `$0.00`; cache misses bill against the
  emitter's `$25` budget cap (Phase 8 D-05)

No TTL — hash-based invalidation is sufficient. Delete `.co-evolve-cache/` to force
a rebuild. See `lab/pel/README.md` §PR Emitter (v1.2) for the full emitter contract.

## Reference

- **Upstream message** (why this directory exists): `runners/codex-ps/evals/UPSTREAM-MESSAGE.md`
- **PS harness source**: `runners/codex-ps/evals/` (read-only reference per CXPS-02)
- **Review verdict schema**: `../schemas/review-verdict.json`
