# Bug #5 diagnosis scratchpad (delete after fix lands)

## Symptom

`pr-emitter.sh:669` emits `ERROR: scorer run failed for before` and exits 2 on every real PEL invocation (observed 2026-04-20 first SC-4 dogfood attempt).

## Reproduction

Date captured: 2026-04-21
Method: Code inspection of `lab/pel/pr-emitter/pr-emitter.sh:667-674` cross-referenced with `evals/run-evals.sh:378-386` (tail).

Partial live repro: `codex exec "bash evals/run-evals.sh"` started at 2026-04-21T17:49Z from REPO_ROOT, processed cases 01-03 successfully, began case 04 at 14:00, subagent terminated at 14:00 cutting the codex child process. Log at `/tmp/bug-5-stderr-1776793750.log`.

## Exact first-failure signature (from code, not runtime)

`evals/run-evals.sh` terminal exit-code policy at line 380-386:

```bash
robust_fails=$(jq -r '[.[] | select(.status == "fail" or .status == "scorer-failed" or (.scores.robustness // "FAIL") == "FAIL")] | length' "$report_dir/raw-scores.json")
if (( robust_fails > 0 )); then
  log "FAIL: $robust_fails case(s) failed on Robustness dimension"
  exit 1
fi
log "PASS: all cases succeeded on Robustness"
exit 0
```

`lab/pel/pr-emitter/pr-emitter.sh:667-674` wrapper:

```bash
if ! (cd "$worktree_dir" && bash "$REPO_ROOT/evals/run-evals.sh" >"$tmp_out" 2>&1); then
  rm -f "$tmp_out" "$marker"
  die "scorer run failed for $label" 2
fi
scores_file=$(find "$worktree_dir/evals/reports" -maxdepth 2 -name raw-scores.json -newer "$marker" 2>/dev/null | head -1)
rm -f "$tmp_out" "$marker"
[[ -n "$scores_file" && -f "$scores_file" ]] \
  || die "scorer did not produce raw-scores.json for $label" 2
```

## Matched hypothesis path

**Path 2-revised (emitter-side contract gap, not runner-side).**

The plan's Path 2 assumed the fix would be in `score-run.sh` or `dev-review.sh`. Code inspection shows the actual fix is in pr-emitter: it conflates "run-evals.sh exited 1 because scoring completed AND ≥1 case robust-failed" with "scorer crashed." The first case is VALID scored data; the second is a hard error. pr-emitter's `if ! ...` then-branch treats both the same.

## Root cause (one sentence)

`pr-emitter.sh:run_scorer_cached` treats `run-evals.sh` exit code 1 ("some cases robust-failed, raw-scores.json still produced") as equivalent to a scorer crash, and dies before ever reading the valid scores file that was written one line later.

## Why this blocks every real PEL invocation

Real PEL runs use real dev-review.sh against real cases. Dev-review bounce cycles don't always converge (that's expected — some cases are designed to exercise the robust-fail branch; see `evals/tests/scorer-verification.sh` Tier 2). The moment even one case produces robustness=FAIL, run-evals.sh exits 1, and pr-emitter dies. Hermetic tests don't see this because `tests/pr-emitter-simulation.sh` uses a pre-seeded cache (Scenario J) that skips the scorer entirely.

## Why Phase 8.1 / WR-01..04 fixes didn't catch it

Phase 8.1 fixed the state.json/artifact contract so the scorer can actually PARSE real dev-review output. Those fixes are necessary and correct. Bug #5 is a SEPARATE contract gap one layer up (exit-code semantics between run-evals.sh and its callers). It was latent until Phase 8.1 made the scorer produce output — only then did the exit-code wire get exercised with non-zero exits from robust-fails.

## Fix task to run

**A.2-revised (emitter-side fix, cleaner than plan's Path 2).**

Replace the `if ! (...)` pattern with explicit exit-code capture + raw-scores.json presence check. Treat exit 1 as non-fatal if raw-scores.json exists; only die if raw-scores.json is missing (which unambiguously means the scorer crashed before writing).

## Cost spent on diagnosis

~$1-3 of API quota burned on the partial 4-case scorer run. Worth it for the live confirmation that cases 01-03 DID score successfully (confirming no runner-side regressions since Phase 8.1).
