# Eval & Verification System for codex-co-evolution

**Date:** 2026-04-17  
**Status:** Ready for execution

## Problem Statement

`run-co-evolution.ps1` is a 1066-line PowerShell runner for a six-phase cross-AI workflow: compose → bounce → arbitrate → execute → verify → fix. There are 11 prior runs, one has been stuck in `fix` for 11 days, and there is no eval harness. We cannot tell whether a prompt or script change helps, whether verify catches bugs, whether bounce produces real disagreement, or what a run costs.

This plan builds an eval and verification system that turns those questions into measurable answers.

## Goals

1. Define what a good co-evolution run means in concrete, measurable terms.
2. Build a reproducible harness that runs the system against a curated case library and scores each run on a fixed set of dimensions.
3. Produce comparable, time-stamped reports so regressions are visible after prompt, template, or script changes.
4. Use the baseline report to prioritize the next three improvements to the runner.

## Non-Goals (v1)

- Implementing the Ollama adapter.
- Perfect cost accounting. v1 records wall-clock time, provider-split invocation counts, and provider-split output bytes. Exact token accounting waits until the CLIs expose stable telemetry.
- Continuous integration. v1 is a manual `./evals/run-evals.ps1` invocation.

## Prerequisite: Claude Adapter (Phase A.5)

The current runner throws in `scripts/run-co-evolution.ps1` around line 694 for any non-Codex agent. A Codex↔Codex-only baseline can measure runner plumbing, but it cannot measure cross-model disagreement, which is the point of the protocol.

Mixed-agent baseline work therefore requires a Claude adapter first. Scope:

- Run a manual discovery step before writing the adapter: verify Claude CLI success, timeout, and auth-failure behavior on Windows; record exit codes; confirm UTF-8 handling; and choose a stdin-fed prompt path instead of shell-quoted prompt arguments.
- Implement `Invoke-ClaudeCliPrompt` so it matches the runner contract: prompt in, output file out, captured exit code, timeout, retry, and stderr logging.
- Remove the `claude` throw and keep `ollama` out of scope.
- Mixed-agent cases must set roles explicitly in YAML. The default mixed-agent pattern is `composer=claude`, `reviewer=codex`, with executor chosen per case.
- Cases `03`, `04`, `06`, `07`, and `08` must be mixed-agent. Cases `01`, `02`, and `05` can stay Codex-only to keep cost down.
- Phase A.5 is complete when `run-co-evolution.ps1 -Composer claude -Reviewer codex` completes a trivial compose→bounce run and `state.json.history` records a Claude invocation with non-empty output.

## Architecture

```text
evals/
  PLAN.md
  cases/
    defaults.yaml
    01-trivial-task.yaml
    02-simple-md-edit.yaml
    03-contested-decision.yaml
    04-hallucination-trap.yaml
    05-ambiguous-task.yaml
    06-multi-file-refactor.yaml
    07-real-doc-bounce.yaml
    08-real-code-refactor.yaml
  fixtures/
    seed-repos/
    seeded-bugs/
  run-evals.ps1
  score-run.ps1
  compare-reports.ps1
  report-template.md
  reports/
    {YYYYMMDD-HHmmss}/
      report.md
      runs/{case-id}/
      raw-scores.json
```

`reports/runs/{case-id}/` always stores copied artifacts, never symlinks.

## Test Case Schema (`cases/*.yaml`)

Shared thresholds live in `cases/defaults.yaml` and are merged into every case. Individual case files should only override case-specific values.

```yaml
id: 04-hallucination-trap
title: Tests whether verify catches invented APIs
description: >
  Task asks for a feature that requires a nonexistent library method.
runner:
  task: "Add retry logic using System.Net.Http.HttpClient.RetryAsync() to Get-Data"
  composer: codex
  reviewer: claude
  executor: codex
  bounces: 2
  verify: true
  autonomous: true
setup:
  mode: temp_repo
  seed_files:
    - path: src/Get-Data.ps1
      content: |
        function Get-Data { param($url) Invoke-RestMethod $url }
expectations:
  verify_accuracy:
    must_catch_issue: true
    issue_keywords: ["RetryAsync", "does not exist", "nonexistent", "not a member"]
teardown:
  cleanup_temp_repo: true
```

`defaults.yaml` holds the shared scoring thresholds and synonym groups, including:

- `plan_quality.must_contain_any`: one heading from `["Plan", "Approach", "Strategy"]` and one from `["Risks", "Concerns", "Caveats"]`
- `execution_fidelity.min_jaccard`
- `cross_ai_diversity.min_edit_distance`
- `cost.max_wall_clock_seconds`
- any other threshold reused across cases

## Score Dimensions

Each run is scored `PASS`, `PARTIAL`, `FAIL`, or `N/A`. Overall output is the per-dimension vector plus a weighted composite. `Robustness` is weighted 2x. `N/A` dimensions are excluded from the composite.

| Dimension | Signal | Source |
|---|---|---|
| Cross-AI diversity | Mixed-agent case actually invoked both providers and the first bounce materially changed the compose draft above a minimum edit-distance threshold | `state.json.history`, `outputs/compose.txt`, `outputs/bounce-*.txt` |
| Convergence | Final marker count reached zero within the bounce budget | `state.json.marker_counts` |
| Plan quality | Meets length threshold, contains required heading groups, and has no `TODO` or placeholder stubs | `plan.md` |
| Execution fidelity | Jaccard similarity between the plan's `## Files to Change` list and `state.json.changed_files` meets threshold | `plan.md`, `state.json.changed_files` |
| Verify accuracy | Verdict matches seeded ground truth and the issues list names the expected problem | `verdict.json` |
| Cost | Wall-clock time, provider-split invocation counts, and provider-split output bytes stay within case limits | `state.json.history`, output file sizes |
| Robustness | Run reaches `completed` with no dangling phase and no unhandled exception | `state.json`, logs |

Cross-AI diversity is `N/A` for cases `01`, `02`, and `05`.

## Harness Behaviour

1. `run-evals.ps1 [-Cases <ids>] [-RepoRoot <path>]`
2. For each case, merge `defaults.yaml` with the case file, set up its fixture, and run `scripts/run-co-evolution.ps1` inside the fixture working directory. The `codex-co-evolution` repo itself is never mutated by the eval.
3. Copy `.co-evolution/runs/{run-id}/` into `evals/reports/{ts}/runs/{case-id}/`.
4. Only tear down the fixture after the artifact copy succeeds. If the copy fails, preserve the fixture and mark the case `FAIL` on `Robustness`.
5. Call `score-run.ps1 -CaseFile cases/XX.yaml -RunDir evals/reports/{ts}/runs/{case-id}` and append the result to `raw-scores.json`.
6. After all cases finish, render `report.md` from `report-template.md` and `raw-scores.json`.
7. Print a summary table to the console. Exit `0` only if no case failed `Robustness`; otherwise exit `1`.

## Execution Plan

**Phase A — Scaffolding**

- A1. Create `evals/` structure and script placeholders.
- A2. Update the compose template so every plan emits a stable `## Files to Change` section for scoring.
- A3. Add `run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1`, and `report-template.md` skeletons with parameter blocks and help text.
- A4. Add a pinned `powershell-yaml` dependency check and fail fast with install instructions if the module is missing.
- A5. Create a mock scores file and verify `report-template.md` renders correctly.

**Phase A.5 — Claude adapter in the runner**

- A5.1. Run the manual Claude CLI discovery step and write down the adapter contract.
- A5.2. Implement `Invoke-ClaudeCliPrompt` using the chosen stdin-fed prompt path.
- A5.3. Remove the `claude` throw and keep `ollama` throwing.
- A5.4. Smoke-test `run-co-evolution.ps1 -Composer claude -Reviewer codex -Task "print hello to stdout" -Bounces 1 -Verify:$false` and confirm non-empty Claude output in the run artifacts.
- A5.5. Commit the adapter change before authoring mixed-agent eval cases.

**Phase B — Test case authoring**

- B1. Write `cases/defaults.yaml`.
- B2. Write Codex-only cases `01`, `02`, and `05`.
- B3. Build fixtures under `evals/fixtures/` for the seeded code cases.
- B4. After Phase A.5 passes, write mixed-agent cases `03`, `04`, `06`, `07`, and `08`.
- B5. Run a harness validation pass with no LLM calls: every YAML file loads, defaults merge correctly, and every fixture can be created and cleaned up.

**Phase C — Baseline run**

- C1. Run all 8 cases sequentially. Budget 90 to 150 minutes for the first full baseline.
- C2. Read `report.md` and identify the dominant failure patterns.
- C3. Pick the top 3 runner issues based on measured failures, not prior intuition.

**Phase D — Iteration**

- D1. Fix issue #1, rerun the affected cases, and compare reports.
- D2. Commit the fix with the eval delta in the commit message.
- D3. Repeat for issues #2 and #3.
- D4. Commit the final report and supporting artifacts.

## Risks

- **Claude adapter integration fails or behaves differently than Codex CLI.** Mitigation: manual discovery and smoke test before any mixed-agent case depends on it. Fallback: if blocked for more than one day, run a Codex-only baseline and mark `Cross-AI diversity` `N/A` everywhere.
- **LLM nondeterminism makes cases flaky.** Mitigation: v1 runs each case once, but any surprising result is rerun manually before it drives a code change.
- **Mixed-agent cases consume a second budget.** Mitigation: record provider-split cost signals and verify Claude credits are available before Phase C.
- **Structured verify output drifts.** Mitigation: treat an unparseable `verdict.json` as `FAIL`, never as a silent skip.
- **Evals mutate a live repo.** Mitigation: every case runs in its own fixture; the harness never runs against the `codex-co-evolution` repo root.
- **The real-doc bounce case writes back to the sibling repo.** Mitigation: copy the document into a temp workspace and bounce the copy only.

## Success Criteria

- The baseline report runs end-to-end and scores all 8 cases.
- At least 5 of the 7 dimensions show variation across the case set instead of uniform `PASS` or uniform `FAIL`.
- At least one seeded-bug case produces `FAIL` or `PARTIAL` on `Verify accuracy` in the baseline, proving the harness can surface the problem.
- The top 3 measured issues are fixed, each fix improves at least one dimension on the affected cases, and none regress `Robustness`.
- Rerunning the harness against the same `HEAD` produces broadly similar case outcomes, allowing for normal LLM variance.

