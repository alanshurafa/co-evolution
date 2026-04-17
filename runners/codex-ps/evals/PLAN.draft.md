# Eval & Verification System for codex-co-evolution

**Author:** Claude (Opus 4.7)
**Date:** 2026-04-17
**Status:** Draft — to be bounced through `/co-evolution` before execution

## Problem Statement

`codex-co-evolution` is a 1066-line PowerShell runner that orchestrates a five-phase cross-AI workflow (compose → bounce → arbitrate → execute → verify → fix). There are 11 prior runs, one still stuck in `fix` phase after 11 days, and **no eval harness**. We cannot answer: does a given prompt change improve or regress the system? Does verify actually catch bugs? Does bounce actually surface contested decisions? How much does a run cost?

This plan builds an eval + verification system that turns those questions into measured answers.

## Goals

1. Define what "a good co-evolution run" means, concretely and measurably.
2. Build a reproducible harness that runs the system against a curated test-case library and scores each run along a fixed set of dimensions.
3. Produce comparable, time-stamped reports so regressions between prompt/template/script changes are visible.
4. Use the baseline report to prioritize the next three improvements to the runner itself.

## Non-Goals (for v1)

- Implementing the Ollama adapter. (Surfaced by the audit but genuinely not on the critical path.)
- Perfect cost accounting. Token counts will be estimated from output bytes; exact counting waits until after the Codex CLI exposes token telemetry.
- Continuous integration. v1 is a manual `./evals/run-evals.ps1` invocation.

## Prerequisite: Claude Adapter (Phase A.5)

The current runner throws at [run-co-evolution.ps1:694](../scripts/run-co-evolution.ps1:694) for any non-Codex agent. "Co-evolution" that's Codex↔Codex is model-homogeneous — it can produce agreement artifacts without ever surfacing a genuine cross-model disagreement, which is the entire point of the protocol. An eval harness that reports "converged" on Codex↔Codex runs would be misleading.

Therefore the Claude adapter moves from non-goal to **prerequisite before baseline**. Scope:

- Implement `Invoke-ClaudeCliPrompt` paralleling `Invoke-CodexExecPrompt`: takes a prompt string + working dir + output path, shells out to `claude -p "$prompt"` (non-interactive print mode) with `--output-format text`, writes to output file, captures exit code, same retry/timeout envelope.
- Remove the throw at line 694 for `claude`; keep it for `ollama` (out of scope).
- Default agent assignment becomes `Composer=claude`, `Reviewer=codex`, `Executor=claude` for bounce cases (Claude plans and implements; Codex challenges) — swap per case in YAML.
- Eval case 07 (`real-doc-bounce`) and case 03 (`contested-decision`) MUST run Claude↔Codex. Cases that only exercise runner plumbing (01 no-op, 02 simple-edit) can stay Codex↔Codex to keep costs down.
- Validation: Phase A.5 is done when `run-co-evolution.ps1 -Composer claude -Reviewer codex` completes one bounce end-to-end on a trivial task and `state.json.history` shows actual Claude output.

## Architecture

```
evals/
  PLAN.md                       # this file
  cases/                        # test case library (YAML)
    01-no-op.yaml
    02-simple-md-edit.yaml
    03-contested-decision.yaml
    04-hallucination-trap.yaml
    05-ambiguous-task.yaml
    06-multi-file-refactor.yaml
    07-real-doc-bounce.yaml     # bounces a real doc from sibling co-evolution repo
    08-real-code-refactor.yaml  # synthetic temp repo (isolated fork)
  fixtures/
    seed-repos/                 # throwaway git repos pre-built for cases that need code
    seeded-bugs/                # known-wrong code for hallucination-trap and verify-accuracy scoring
  run-evals.ps1                 # the harness (dispatches cases, captures artifacts)
  score-run.ps1                 # computes per-dimension scores from a single run
  compare-reports.ps1           # diffs two timestamped reports, flags regressions
  report-template.md            # markdown skeleton for the report
  reports/
    {YYYYMMDD-HHmmss}/
      report.md                 # per-case table, per-dimension scores, summary
      runs/{case-id}/           # symlink or copy of .co-evolution/runs/{run-id}
      raw-scores.json           # machine-readable scores for compare-reports
```

## Test Case Schema (`cases/*.yaml`)

```yaml
id: 04-hallucination-trap
title: Tests whether verify catches invented APIs
description: >
  Task asks for a feature that requires a nonexistent library method.
  Executor is likely to hallucinate; verify SHOULD flag it.
runner_flags:
  task: "Add retry logic using System.Net.Http.HttpClient.RetryAsync() to Get-Data"
  composer: codex
  reviewer: codex
  executor: codex
  bounces: 2
  verify: true
  autonomous: true
setup:
  # one of: none | temp_repo | fork_of
  mode: temp_repo
  seed_files:
    - path: src/Get-Data.ps1
      content: |
        function Get-Data { param($url) Invoke-RestMethod $url }
expectations:
  # Each expectation maps to a score dimension. Scorer checks them automatically.
  convergence:
    markers_final: 0         # markers should reach zero within bounce budget
  plan_quality:
    min_word_count: 150
    must_contain_sections: ["Plan", "Risks"]
  execution_fidelity:
    # Files the plan claims it will change must match files actually changed (jaccard >= threshold)
    min_jaccard: 0.7
  verify_accuracy:
    # Ground truth: there IS a hallucinated method. We expect verify to catch it.
    must_catch_issue: true
    issue_keywords: ["RetryAsync", "does not exist", "nonexistent", "not a member"]
  cost:
    # Soft cap; exceeding logs a warning but doesn't fail
    max_wall_clock_seconds: 600
    max_total_output_bytes: 200000
  robustness:
    state_must_reach: "completed"   # not "running" or "verify_failed"
    allow_verdict: ["APPROVED", "REVISE"]  # both acceptable; we're testing that it COMPLETED
teardown:
  cleanup_temp_repo: true
```

## Score Dimensions

Each run is scored PASS / PARTIAL / FAIL on seven dimensions. Overall grade is the per-dimension vector plus a weighted composite (robustness weighted 2x since a crashed run is a ceiling on every other dimension).

| Dimension             | Signal                                                              | Source                               |
|-----------------------|---------------------------------------------------------------------|--------------------------------------|
| Cross-AI diversity    | Case-declared mixed-agent runs actually invoked both Claude and Codex; bounce output shows genuine disagreement (≥1 `[CONTESTED]` raised mid-bounce, not only in compose) | `state.json.composer/reviewer/executor`, `outputs/bounce-*.txt` history |
| Convergence           | `markers_final == 0` within bounce budget                           | `state.json.marker_counts`           |
| Plan quality          | Length ≥ threshold, expected sections present, no lorem/TODO stubs  | `plan.md`                            |
| Execution fidelity    | Jaccard(files_claimed_in_plan, files_actually_changed) ≥ threshold  | `plan.md` + `state.json.changed_files` |
| Verify accuracy       | Verdict matches ground truth for seeded bugs; keyword match in issues[] | `verdict.json`                     |
| Cost                  | Wall-clock time, total output bytes, # of CLI invocations           | `state.json.history` timestamps, outputs/*.txt sizes |
| Robustness            | `state.json.status == "completed"`, no dangling phase, no exception in logs | `state.json`, `outputs/*.log`  |

**On Cross-AI diversity:** for Codex↔Codex cases (01, 02) this dimension is marked `N/A` and excluded from the composite. For mixed-agent cases (03, 04, 06, 07, 08) a FAIL here is near-fatal: it means we got convergence theatre without real cross-model disagreement. A bounce with zero intermediate `[CONTESTED]` markers but a clean final plan is suspicious when both models were supposed to differ.

## Harness Behaviour

1. `run-evals.ps1 [-Cases <ids>] [-Parallel] [-RepoRoot <path>]`
2. For each case: set up fixture (temp repo if needed), shell out to `scripts/run-co-evolution.ps1` with the case's flags inside the fixture working directory. Each eval run operates in its own fixture — the codex-co-evolution repo itself is never mutated by the eval.
3. Capture run dir (`.co-evolution/runs/{run-id}/`) and copy into `evals/reports/{ts}/runs/{case-id}/` before teardown.
4. Call `score-run.ps1 -CaseFile cases/XX.yaml -RunDir evals/reports/{ts}/runs/{case-id}` → appends row to `raw-scores.json`.
5. After all cases: render `report.md` from `report-template.md` and `raw-scores.json`.
6. Print summary table to console; exit 0 if no case FAILed on the Robustness dimension, else exit 1. (Other dimensions can regress without a non-zero exit in v1 — the user decides if a regression is acceptable.)

## Execution Plan

**Phase A — Scaffolding (write code, no LLM calls):**
- A1. `evals/` directory + `PLAN.md` ← done by this file
- A2. Four PowerShell scripts skeletons with parameter blocks and help text
- A3. YAML parsing helper (pick lightweight parser — prefer built-in `ConvertFrom-Yaml` if on PS 7+, else bundle `powershell-yaml` module check)
- A4. Report template with Markdown + a filled example from a mock scores file

**Phase A.5 — Claude adapter in the runner (prerequisite for mixed-agent cases):**
- A5.1. Implement `Invoke-ClaudeCliPrompt` in `scripts/run-co-evolution.ps1` paralleling the Codex adapter (prompt → stdin, output → file, retry/timeout parity)
- A5.2. Remove the `claude` branch of the throw at line 694; leave `ollama` throwing
- A5.3. Smoke-test: `run-co-evolution.ps1 -Composer claude -Reviewer codex -Task "print hello to stdout" -Bounces 1 -Verify:$false` completes with non-empty Claude output in `outputs/compose.txt`
- A5.4. Commit this change atomically before Phase B so the adapter is in HEAD when eval cases are authored

**Phase B — Test case authoring:**
- B1. Write all 8 `cases/*.yaml` with realistic tasks and expectations
- B2. Build fixtures: seed repos under `evals/fixtures/seed-repos/` for cases 4, 6, 8
- B3. Dry-run pass: the harness validates every YAML file and every fixture loads, with NO LLM calls. Must pass before Phase C.

**Phase C — Baseline run:**
- C1. Execute `run-evals.ps1` across all 8 cases (sequential first pass; ~60-90 min total based on 5-10 min per co-evolution run)
- C2. Read `report.md`; identify failing dimensions and patterns
- C3. Pick top 3 actionable issues (candidates based on audit: verdict-overwrite on fix, no-resume, adapter-gap surfacing, or whatever the data shows)

**Phase D — Iteration:**
- D1. Fix issue #1 → re-run affected cases → `compare-reports.ps1` before/after
- D2. Commit atomically per fix with message citing the eval delta
- D3. Repeat for #2 and #3
- D4. Final report committed to the repo

## Risks

- **Test flakiness from LLM nondeterminism.** Mitigation: v1 runs each case once; if too flaky, v2 adds `-N 3` to average. Document the variance honestly.
- **Cost.** 8 cases × 5-10 min each × baseline + post-fix = ~3 hours of Codex CLI compute. Soft budget is Alan's Codex plan daily quota; if we hit it, we stop and resume the next day. No autonomous runaway.
- **Codex output format drift.** If Codex stops returning JSON for verify, the scorer silently degrades. Mitigation: scorer treats unparseable verdict.json as `verify_accuracy: FAIL` with a loud error, not a silent skip.
- **Running evals writes artifacts into a live repo.** Mitigation: temp-repo fixtures; eval harness NEVER runs the runner in the codex-co-evolution repo root.
- **Real-project bounce case pollutes the sibling repo.** Mitigation: `real-doc-bounce` uses `--bounce-only` or copies the doc into a temp workspace; never writes back to `co-evolution/` repo without git-level confirmation.

## Open Questions

1. Should the scorer have a "regression" concept that reads the last report automatically, or always require `compare-reports.ps1` as a separate step? (Leaning: separate step for v1, simpler.)
2. Should we add a `--dry-run` mode to the runner itself to fix the no-op-task architecture issue as part of Phase D? (Probably yes — it's the cleanest fix for case 01.)
3. Is one run per case enough signal, or do we need 3+ for variance? (v1: one run. v2: three runs with median scoring.)

## Success Criteria

- Baseline report runs end-to-end with all 8 cases scored
- At least 5 of 7 dimensions produce meaningful signal (not all PASS or all FAIL); Cross-AI diversity must produce signal on at least one mixed-agent case
- Top 3 issues from the baseline are fixed; the post-fix report shows improvement on at least one dimension per fix, no regression on Robustness
- All artifacts reproducible: re-running the harness against HEAD should produce a similar report (±LLM variance)
