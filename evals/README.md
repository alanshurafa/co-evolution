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

## Running Evals Today

Only the PowerShell harness currently runs the cases end-to-end:

```powershell
pwsh runners/codex-ps/evals/run-evals.ps1
pwsh runners/codex-ps/evals/score-run.ps1 <run-dir>
pwsh runners/codex-ps/evals/compare-reports.ps1 <baseline> <new>
```

The harness is Windows-PowerShell-first but `pwsh` (PowerShell Core, cross-
platform) works too. Case YAMLs here resolve relative to the repo root, so the
PS harness reads them at either `evals/cases/` or
`runners/codex-ps/evals/cases/` — both are byte-identical until edits diverge.

A Bash port of the harness is **deferred to post-milestone work**. See
`runners/codex-ps/evals/UPSTREAM-MESSAGE.md` § "Parity requirements" for the
feature inventory a Bash port needs to achieve.

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
| `runners/codex-ps/evals/*.ps1`     | Yes            |
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

## Reference

- **Upstream message** (why this directory exists): `runners/codex-ps/evals/UPSTREAM-MESSAGE.md`
- **PS harness source**: `runners/codex-ps/evals/` (read-only reference per CXPS-02)
- **Review verdict schema**: `../schemas/review-verdict.json`
