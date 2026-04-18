---
phase: 02-revise-auto-loop
plans: [02-01]
subsystem: dev-review-runtime
tags: [revise-loop, retry, state-json, prompt-templates, rtux-03]
requires: [phase-01]
provides: [revise-auto-loop, numbered-phase-names, reviewer-feedback-injection]
affects:
  - dev-review/codex/dev-review.sh
  - lib/co-evolution.sh
  - tests/
tech-stack:
  added: []
  patterns: [extracted-loop-body-for-test-reuse, anchored-regex-phase-gate, jq-r-safe-rendering, opt-in-with-zero-default]
metrics:
  duration: 25min
  tasks_completed: 4
  commits: 4
  completed: 2026-04-17
requirements: [RTUX-03]
---

# Phase 2: REVISE Auto-Loop Summary

One-liner: Added a bounded REVISE→retry loop to the Codex dev-review runtime. On a REVISE verdict the runner re-executes with reviewer feedback injected into the prompt, up to `REVISE_LOOP_MAX` extra passes (CLI `--revise-loop N`, env fallback). Default `0` preserves v1.0 behavior byte-for-byte. Each retry pass writes a numbered `execute-N` / `verify-N` entry to `state.json`; pass 1 keeps bare names for backwards compat. A self-contained bash simulation (no network, no real CLIs, <4s) locks in the retry-and-converge, v1.0 parity, cap-at-max, and prompt byte-identity invariants.

## What Landed Per Plan

### Plan 02-01: REVISE Auto-Loop (RTUX-03)

- **Task 1 — Flag + env var.** `--revise-loop N` CLI flag and `REVISE_LOOP_MAX` env fallback (default 0 = disabled). Non-integer + negative values rejected with clear error. Help text updated.
- **Task 2 — Retry loop.** Extracted `_run_revise_loop` function wrapping execute+verify. Bounded at `REVISE_LOOP_MAX+1` total passes. Pass 1 writes bare `execute`/`verify` to `state.json`; pass 2+ writes `execute-N`/`verify-N`. `phase_is_writable` gained an anchored `^execute-[0-9]+$` regex so numbered retry passes keep the writable Claude posture (T-02-01 mitigation). Verdict JSON captured into `REVISE_FEEDBACK_JSON` before `cleanup_runtime_artifacts` can sweep it (T-02-06 mitigation).
- **Task 3 — Prompt injection.** `build_execution_prompt` gained an optional third arg. Empty/unset preserves v1.0 byte-identical output (strip_conditional path); non-empty renders the `{IF_SUBSEQUENT_PASS}` block with summary + issue bullets via `fill_conditional` and jq-based rendering (T-02-02 mitigation). Call site in `run_execute_phase` threads `REVISE_FEEDBACK_JSON` through.
- **Task 4 — Simulation.** `tests/revise-loop-simulation.sh` sources the real `_run_revise_loop` via sed-range extraction and runs it against mocked phase runners. Four scenarios cover retry-and-converge, v1.0 parity, cap-at-max, and prompt byte-identity for both codex and opus executors.

Commits: `549850c` (T1), `be0af3b` (T2), `e15332a` (T3), `fc08304` (T4). All pushed to `feat/v1.1-polish`.

## Commit Chain

```
fc08304  test(revise-loop): add REVISE auto-loop simulation covering retry, parity, and cap (RTUX-03)
e15332a  feat(revise-loop): inject reviewer feedback into execute prompt on retry passes (RTUX-03)
be0af3b  feat(revise-loop): wrap execute+verify in retry loop with numbered phase names (RTUX-03)
549850c  feat(revise-loop): add --revise-loop flag and REVISE_LOOP_MAX env var (RTUX-03)
```

All four pushed to `feat/v1.1-polish`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| RTUX-03 | 02-01 | Complete |

## Wave Order Executed

Single-plan phase (Wave 1 only): 02-01 T1 → T2 → T3 → T4, strictly sequential.

## Files Modified (Phase-Level)

- `dev-review/codex/dev-review.sh` — extended: flag parser, loop body, prompt-building helpers (+176 / −16)
- `lib/co-evolution.sh` — extended: `phase_is_writable` regex branch (+11 / 0)
- `tests/revise-loop-simulation.sh` — new 171-line self-contained simulation

## Deviations

One Rule 1 deviation during Task 4: the plan's jq asserts referenced `.phase`, but `write_state_phase` records the field as `.name`. Test uses `.name` throughout; rest of the plan executed as specified. Details in `02-01-SUMMARY.md`.

## Verification Summary

Final phase-level verification (all six gates pass):

- **Syntax:** `bash -n` clean on all three touched files
- **Help text:** `--revise-loop` visible in `bash dev-review.sh --help`
- **Flag validation:** `abc` and `-1` both rejected
- **`phase_is_writable` regex:** `execute-2`→true, `verify-2`→false, `";rm-rf /"`→false
- **Simulation:** `ALL PASS` in 3.8s (S1, S2, S3, S4 all green)
- **Commit atomicity:** 4 commits, one per task, all with `Co-Authored-By: Claude Opus 4.7 (1M context)`

## Threat Model Compliance

Every `mitigate` disposition in the plan's threat register verified:

| Threat | Mitigation | Check |
|--------|-----------|-------|
| T-02-01 (injection via phase name) | anchored `^execute-[0-9]+$` | 4-case unit test in Task 2 verify |
| T-02-02 (injection via reviewer content) | jq -r rendering | Task 3 retry-pass snapshot |
| T-02-03 (cost DoS) | integer validation, budget=N+1 | Task 1 flag validation tests |
| T-02-05 (repudiation) | per-pass `write_state_phase` | Task 4 S1 and S3 scenarios |
| T-02-06 (stale verdict) | capture-before-cleanup | code path inspection + S1 test |

## Known Stubs

None.

## Next Phase

Phase 3 (Visible Live Mode — RTUX-01) and Phase 4 (Worktree Management — RTUX-02) remain in v1.1. Neither depends on this phase's code; both can be picked up next.

## Self-Check: PASSED

- `dev-review/codex/dev-review.sh` modifications — FOUND (3 commits touch it)
- `lib/co-evolution.sh` modifications — FOUND (commit be0af3b)
- `tests/revise-loop-simulation.sh` — FOUND (171 lines, executable, passes)
- `.planning/phases/02-revise-auto-loop/02-01-SUMMARY.md` — FOUND
- `.planning/phases/02-revise-auto-loop/02-SUMMARY.md` — FOUND (this file)
- Commits `549850c`, `be0af3b`, `e15332a`, `fc08304` — all FOUND in git log, all pushed
- Requirement RTUX-03 — to be marked Complete in REQUIREMENTS.md (below)
- 1 plan complete (02-01)
