---
phase: 06-protocol-parity
plan: 02
subsystem: bounce-verification
tags: [bounce, structural-signal, verification, upstream-parity]
requires: [06-01]
provides: [structural-bounce-signal, verify_bounce_ran-helper]
affects: [dev-review/codex/dev-review.sh]
tech-stack:
  added: []
  patterns: [structural-companion-to-semantic-signal, side-effect-global-for-count]
key-files:
  created: []
  modified:
    - path: dev-review/codex/dev-review.sh
      what: mkdir outputs/ at run-setup; write bounce-NN.txt per pass; add verify_bounce_ran helper + end-of-phase log
decisions:
  - outputs/bounce-NN.txt written AFTER cp to PLAN_PATH so the artifact matches the canonical plan content (post-strip_human_summary)
  - Zero-padded NN (printf -v) matches codex-ps regex ^bounce-\d+\.txt$
  - mkdir -p outputs/ at run-setup (not inside loop) so 0-pass runs still have the dir as a distinct signal from "never set up"
  - BOUNCE_ARTIFACT_COUNT set as global side-effect (mirrors PLAN_OUTPUT_STATUS pattern) so callers can read count without re-globbing
  - verify_bounce_ran returns exit codes but is informational — never fails the run (distinct signal for future Phase 8 evals)
metrics:
  duration: 20min
  completed: 2026-04-17
requirements: [PRTP-04]
---

# Phase 6 Plan 2: Structural Bounce Signal Summary

One-liner: Persist `outputs/bounce-NN.txt` per executed pass and add `verify_bounce_ran` so downstream tooling distinguishes "converged in 0 passes" from "bounce step skipped entirely."

## Insertion Points

| Edit | Location (post-change) | Content |
|------|------------------------|---------|
| mkdir outputs/ | `dev-review/codex/dev-review.sh` line 820 | `mkdir -p "$RUN_DIR/outputs"` after the existing `mkdir -p "$RUN_DIR"` |
| local pass_padded | `dev-review/codex/dev-review.sh` line 461 | Added to `run_bounce_phase` locals |
| cp to outputs/bounce-NN.txt | `dev-review/codex/dev-review.sh` lines 497-502 | After `cp "$output_file" "$PLAN_PATH"`: comment block + `printf -v pass_padded '%02d' "$pass"` + `cp "$output_file" "$RUN_DIR/outputs/bounce-${pass_padded}.txt"` |
| verify_bounce_ran helper | `dev-review/codex/dev-review.sh` lines 441-460 | Complete function before `run_bounce_phase` |
| end-of-phase log | `dev-review/codex/dev-review.sh` lines 540-546 | `if verify_bounce_ran "$RUN_DIR"; then log "..."; else log "..."; fi` before final `return 0` |

## Task Breakdown

| Task | Outcome | Commit |
|------|---------|--------|
| 1. Write bounce-NN.txt per pass + create outputs/ at setup | All 6 acceptance checks pass; cleanup_runtime_artifacts byte-identical | `b7abb1e` |
| 2. Add verify_bounce_ran helper + log | Helper defined before run_bounce_phase; 2 log lines present; bash -n OK | `ff0c951` |
| 3. 3-scenario simulation test | PRTP-04 SIM: OK (all three scenarios PASS) | — (verification-only) |

## Simulation Test Output

```
$ bash /tmp/prtp-04-sim-test.sh
scenario A (2 passes): PASS
scenario B (skipped): PASS
scenario C (no outputs dir): PASS
PRTP-04 SIM: OK
```

The simulation:
1. Extracts `verify_bounce_ran` from `dev-review.sh` via `awk` (isolates the function without executing the main body)
2. Scenario A: creates `run-a/outputs/bounce-01.txt` + `bounce-02.txt` → helper returns 0, `BOUNCE_ARTIFACT_COUNT=2`
3. Scenario B: creates empty `run-b/outputs/` → helper returns 1, `BOUNCE_ARTIFACT_COUNT=0`
4. Scenario C: creates `run-c/` (no outputs dir) → helper returns 1, `BOUNCE_ARTIFACT_COUNT=0`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's grep acceptance literals over-escaped**
- **Found during:** Task 1 verification
- **Issue:** Plan's acceptance criterion `grep -c "printf -v pass_padded '%02d' \"\\\$pass\""` contains bash escape sequences that resolve to `\$pass` instead of `$pass` when run through nested shells — returned 0 matches for correct code
- **Fix:** Ran a corrected acceptance check with `grep -cF 'printf -v pass_padded'` that matches the content literally. The code itself (line 501) is exactly `printf -v pass_padded '%02d' "$pass"` as the plan specifies
- **Files modified:** None (verification-only issue)

**2. [Rule 3 - Blocking] Plan's -B3 positional check insufficient**
- **Found during:** Task 1 verification
- **Issue:** Plan's `grep -B3 'outputs/bounce-${pass_padded}' ... | grep -q 'cp "$output_file" "$PLAN_PATH"'` — the intent is "the write happens AFTER the cp to PLAN_PATH". With a 3-line comment block + printf line inserted, 4 lines separate the cp from the new line, so -B3 misses the cp
- **Fix:** Re-ran with -B6; positional ordering confirmed correct (cp → comment → printf → new cp)
- **Files modified:** None

### Non-deviations

- `cleanup_runtime_artifacts` untouched as the plan requires — `find "$RUN_DIR" -maxdepth 1 -type f -name '.*' -delete` remains byte-identical; `-maxdepth 1` naturally preserves `outputs/` subdir
- End-to-end validation with a real LLM run is **deferred to Phase 8 evals absorb** (per plan output note)

## Known Stubs

None.

## Self-Check: PASSED

- `dev-review/codex/dev-review.sh` exists — FOUND
- Commit `b7abb1e` — FOUND
- Commit `ff0c951` — FOUND
- Simulation: 3/3 scenarios PASS
