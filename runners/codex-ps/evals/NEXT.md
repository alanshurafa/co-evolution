# Next Steps Plan — codex-co-evolution eval system

**Date:** 2026-04-17
**Status:** Proposal
**Upstream:** [`BASELINE-SUMMARY.md`](BASELINE-SUMMARY.md) — what we just finished and what's still open

## Goals (in priority order)

1. Close the verification loop — get Tier 3 to ≥ 2/3 agreement, get Tier 4 to 4/4 detected.
2. Produce a real baseline across all 9 cases (we only have 3 cases with real scores: 01, 02, and the pilot fakes).
3. Harden the runner against the three "original audit" bugs that still haven't been touched: no resume, verdict overwritten on fix, no per-phase timeout.
4. Wire the eval into the workflows that actually run (GSD flags, weekly re-baseline).
5. Broaden the case library with one or two more real projects.

Everything below maps to one of these. Phases are independent enough that any can be skipped or reordered.

## Phase F1 — Close the Verification Loop (~2 hr, ~$2-5 LLM)

**Goal:** Hit the remaining success criteria from `VERIFICATION-PLAN.md` so the eval has no known gaps.

### F1.1 Fix D #7 (case task body overrides template)
- Edit `templates/compose-prompt-codex.md`: add a sentence to the Required Section block — "These sections are required REGARDLESS of any section list that appears in the task body above."
- Edit `evals/cases/01-trivial-task.yaml`: add "a Risks section (even if just `- None identified.`)" to the task enumeration.
- Commit cost: 0 LLM. Offline edit.

### F1.2 Scorer patch for Tier 4a blindness
- In `evals/score-run.ps1`, add a structural check under Convergence: if the merged case has `runner.bounces > 0` (or `auto`) but `state.history` contains no entry whose `phase` starts with `bounce-`, flag Convergence=FAIL with detail "bounce phase skipped."
- Rerun `regression-a-skip-bounce` to confirm Convergence=FAIL.

### F1.3 Rerun Tier 3 variance on case 01 after F1.1
- `run-evals.ps1 -Cases 01-trivial-task -Repeat 3`
- Success: plan_quality ≥ 2/3 PASS, composite range ≤ 0.2.
- If it still fails, read the 3 plans by hand to identify the next prompt gap.

### F1.4 Rerun Tier 3 variance on a mixed-agent case
- `run-evals.ps1 -Cases 03-contested-decision -Repeat 3` (claude composer / codex reviewer, verify=false — cheap and fast)
- Confirms Cross-AI diversity is as stable across runs as Robustness is.
- This is the *other* side of the Tier 3 test — we've only measured Codex-only variance so far.

### F1.5 Tier 5 human calibration (manual)
- Pick three existing scored runs covering a spread of composites (e.g., 01 at 1.0, a Tier 4 at 0.857, the original Tier 3 round-1 iter 1 at 0.833).
- Hand-score the 21 (case, dimension) pairs without looking at automated scores.
- Record in `evals/META-EVAL.md`. Success: ≥ 80% agreement.

**Exit criterion for F1:** all `VERIFICATION-PLAN.md` success gates green (or explicitly waived with written reason).

## Phase F2 — Real Baseline on All 9 Cases (~90 min, ~$8-15 LLM)

We have scored runs for cases 01, 02, and fakes. Cases 03-09 are still theoretical.

### F2.1 Full baseline run
- `run-evals.ps1` (no filter — all 9 cases)
- Budget 90 minutes; run in background.
- Critical: the runner now has all D #1-#5 fixes. Cases that hung or crashed before should complete.

### F2.2 Analyze
- Which dimensions split into interesting distributions vs degenerate uniform PASS?
- Which cases produce variance that's *prompt-specific* vs *model-level*?
- What's the per-case cost breakdown — which cases eat the most Codex/Claude tokens?
- Write findings into `evals/FIRST-FULL-BASELINE.md`.

### F2.3 Update the case library based on baseline
- If a case consistently degenerates to all-PASS or all-FAIL, its thresholds in `defaults.yaml` are mis-tuned. Record; don't fix yet.
- If a case exposes a new D #N finding, log it; decide whether to fix or defer.

**Exit criterion for F2:** a scored report for all 9 cases exists; every dimension shows at least some variation across the case set (per the original plan's success criterion from PLAN.md).

## Phase F3 — Runner Hardening (half-day, ~$3-5 LLM)

The three "original audit" bugs never got fixed during the eval work. F1+F2 will make these more painful — fix them now.

### F3.1 Per-phase timeout
- Add a configurable timeout to `Invoke-CodexProcess` / `Invoke-ClaudeProcess` (default 600s per call).
- On timeout: kill the process, mark state.json status=`timeout`, write a summary, exit with a clear error.
- This would have turned the 1h 39min stuck verify into a 10-min failure.
- Test: temporarily set timeout to 30s on case 02; confirm the timeout fires and state.json is captured cleanly.

### F3.2 Verdict history preservation on fix retry
- Today the runner overwrites `verdict.json` on retry — we lose the attempt-1 verdict when attempt-2 runs.
- Change to `verdict-01.json`, `verdict-02.json`, ... plus a `verdict.json` symlink/copy of the latest.
- Scorer reads `verdict.json` (latest) by default, but gains the ability to read attempt history.
- Tier 1 fixture: "attempt-1 REVISE → attempt-2 APPROVED" case; confirms scorer picks final not first.

### F3.3 Resume capability
- Runner accepts optional `-ResumeFrom <run-id>`.
- Reads state.json, finds last completed phase, resumes from next phase.
- Harness's `-UseRunner` flag already lets us test this with a modified runner.
- Lower priority than F3.1 and F3.2 — useful but not blocking anything.

### F3.4 Re-baseline after F3
- Rerun the F2 baseline after F3 to confirm nothing regressed.

**Exit criterion for F3:** any single Codex or Claude hang is now a 10-min failure instead of a multi-hour zombie.

## Phase F4 — Workflow Integration (half-day, no LLM)

Makes the eval discoverable and automatic.

### F4.1 Wire into `/gsd:ship --review`
- `CLAUDE.md` already documents `/gsd:ship --review`. Point it at `evals/run-evals.ps1` with the cases changed by the current phase.
- Pre-PR gate: composite ≥ 0.8 across affected cases, no Robustness failures.

### F4.2 Weekly re-baseline cron
- Add a scheduled task (`create_scheduled_task` via Claude's MCP) that reruns the full 9-case baseline every Sunday night.
- Compares Monday's report to last Monday's via `compare-reports.ps1`.
- Emails/notifies if composite drops or if a dimension regresses by more than one level.

### F4.3 Eval dashboard
- Lightweight markdown dashboard generated from the last N reports: composite trend line, per-dimension pass-rate histogram, cost-over-time.
- Builds on `compare-reports.ps1` — extend it to aggregate N reports rather than diff 2.
- Ties to your existing `localhost.md` port registry if it needs a local web view.

## Phase F5 — Broaden Case Library (~4 hr, ~$5-10 LLM)

### F5.1 Add 2 more real-project cases
Drawing from the earlier project scout:
- **Case 10 — humanoid-robot-website doc bounce:** bounce the stale 21st.dev component references in CLAUDE.md. Doc-only, safe.
- **Case 11 — co-evolution sibling code refactor:** consolidate the `_build_phases` / `_compose_plan` shell duplication (if still present). Medium blast radius; use a fork.

### F5.2 Tune thresholds in `defaults.yaml`
- After F2 and F5.1, we have 11 cases' worth of score distributions.
- Pick thresholds at percentiles rather than guesses: `min_jaccard` at the 20th percentile observed, `min_edit_distance` at the 10th percentile.
- Re-run; confirm the tuning doesn't break Tier 4.

### F5.3 Case taxonomy
- Tag each case by: language, scope (single-file/multi-file/no-op/doc), difficulty, agent combo.
- Makes it cheap to add new cases in under-covered combinations.

## Phase F6 — Stretch (variable, defer)

Not blocking anything; revisit later.

- **F6.1 Ollama adapter** — enables 3-way cross-AI and offline runs. Low priority if Claude+Codex are working well.
- **F6.2 Linux/macOS port** — translate the PS harness to bash. Only worth it if you want the tool to leave your Windows machine.
- **F6.3 LLM-judge for subjective dimensions** — replace the word-count + heading heuristics for plan_quality with a cheap second-model judgement call. More accurate but adds cost + another failure surface.

## Recommended Execution Order

**Today / this week:**
- F1 (all five subtasks) — closes the verification loop in one short session.
- F2.1 alone (launch the baseline, let it run, read results later) — highest info-per-dollar.

**Next session:**
- F2.2 / F2.3 (analyze baseline)
- F3.1 (per-phase timeout) — single most valuable hardening.

**This month:**
- F3.2 and F3.3 (history + resume)
- F4.1 (GSD integration)

**Nice-to-have:**
- F4.2, F4.3, F5

## Budget Check

Total LLM spend across F1-F5: roughly **$20-35**. F2 is the biggest single line item (~$8-15) because it runs all 9 cases end-to-end.

## Non-Goals for This Next Push

- Rewriting the scorer from scratch. The current heuristics are good enough once F1 lands.
- Formal statistical analysis of variance. N=3 is fine for surfacing gross issues; we don't need ANOVA.
- Publishing the repo. `user.useConfigOnly=true` is still in effect; that's your choice to make.

## What to Do Right Now if You Want to Start

1. Execute F1.1-F1.2 (two small file edits, no LLM cost, ~10 min).
2. Kick off F1.3 in the background (~12 min, ~$0.50).
3. While F1.3 runs, start F2.1 (~90 min, can run overnight).
4. Come back in the morning; read reports; decide on F3.
