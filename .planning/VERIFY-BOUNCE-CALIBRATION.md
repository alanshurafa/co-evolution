# VERIFY: Bounce Calibration (v1.3 Phase 5, Layer 3)

Release-gate tracker for the human side of bounce-quality calibration.
Machine layers are DONE; the items below need Alan.

## What already ran (2026-06-10/11, on the Mac)

- Deterministic scorer batch over **192 historical runs** (82 non-bounce dirs
  skipped). Full report (gitignored — run names reference personal docs):
  `evals/reports/bounce-calibration-2026-06-11.md` in the working clone.
- Headline empirical findings:
  - **251 of 1,426 tracked markers (17.6%) were "resolved" by deleting their
    entire section** (`deleted-with-section`). The suspicion that drove this
    milestone is now a measured number.
  - 53 markers remain `unresolved` in final documents.
  - Only **11/192** historical runs pass the full behavior gate — mostly
    because pre-v1.3 runs persisted no per-pass clean artifacts (the exact
    gap Phase 3 closed). Runs from v1.3 onward emit full receipts.
  - Threshold-tuning distributions (word ratios, anchor retention) are in the
    report. The word-ratio tail (up to 64x) is legacy compose-mode runs whose
    "baseline" was a one-line question — mode-aware baselines fix this going
    forward; treat legacy compose runs as unscoreable for scope discipline.

## Judge batch — DONE (2026-06-10 evening, live claude CLI)

CLI authenticated via `claude setup-token` (1-year token in the macOS
keychain, exported by ~/.zshrc). Judged the 7 gate-passing technical runs
(the 2 personally-named passing runs were left for Alan):

| Verdict | Count |
|---------|-------|
| improved | 6 |
| position_biased (no claim) | 1 |
| regressed / tie / invalid-evidence | 0 |

All evidence quotes verified verbatim. First batch surfaced a verifier bug
(trailing-space quote rejection -> 6/7 false "invalid-evidence"); fixed in
commit 4adbd9f + b2ad043 era — see judge-bounce.sh history.

`improved` rate on judged runs: **6/7 (86%)** — clears the >=60% half of
the v1.4 seed trigger. The judge↔human agreement half remains below.

## Human sampling session — 2026-06-10 (resolved by delegation)

Conducted via blinded side-by-side review page (5 pairs, randomized A/B,
markers stripped) + dialog voting. Alan returned **tie on all 5 pairs** and
ruled: *"your judgment typically is going to be as good as mine — use the
strongest model we have at the time as the judge (Fable 5 on high thinking
today; could be a codex model later)."*

**Owner decision recorded:** the judge↔human agreement requirement is
replaced by a strongest-model-judge policy. `evals/judge-bounce.sh` now
defaults to `--judge-model claude-fable-5 --judge-effort high`, overridable
by flag or `JUDGE_MODEL`/`JUDGE_EFFORT` env so the judge can be upgraded or
swapped (incl. cross-family) without code changes. The all-tie human
worksheet is recorded as context, NOT as ground truth.

## Threshold recalibration — deferred to instrumented runs

The 192-run historical distributions are dominated by legacy artifact gaps
(no per-pass receipts, mode-misdetected compose runs), not by genuine band
misses — recalibrating on that noise would tune thresholds to archaeology.
Policy: keep the rubric's initial bands until **~50 v1.3-instrumented runs**
(state.json-bearing) accumulate, then recalibrate from
`evals/calibrate-bounce.sh` over those runs only.

## Closure

- [x] Judge batch over gate-passing technical runs (6/7 improved, 0
      regressed — claude default model; Fable-5 high-effort re-run in
      progress 2026-06-10 evening)
- [x] Judge↔human policy resolved (delegation, above)
- [ ] Re-check thresholds after ~50 instrumented runs (calendar item, not a
      v1.4 blocker per the owner decision)

**v1.4 gate status:** the evidence half (>=60% improved) is met (6/7); the
agreement half is superseded by the delegation decision. The adoption seed
(`.planning/seeds/npm-mcp-distribution.md`) is UNBLOCKED — start v1.4 when
ready.
