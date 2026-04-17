---
phase: 02-revise-auto-loop
plan: 01
subsystem: dev-review-runtime
tags: [bash, revise-loop, retry, state-json, templates, rtux-03]
requires: [01-code-review-fixes]
provides:
  - bounded REVISE auto-retry loop in the Codex dev-review runtime
  - --revise-loop N CLI flag and REVISE_LOOP_MAX env var (default 0 = disabled, v1.0 parity)
  - numbered state.json phase entries (execute-2, verify-2, ...) for each retry pass
  - reviewer-feedback injection into retry-pass execute prompts for both codex and opus templates
  - self-contained bash simulation test (tests/revise-loop-simulation.sh) covering retry, parity, cap, and byte-identity invariants
affects: [evals-absorbed, dev-review-runtime, state-json-consumers]
tech-stack:
  added: []
  patterns:
    - "extracted loop body into _run_revise_loop so tests and main flow share one implementation"
    - "verdict JSON captured into in-memory env var before cleanup_runtime_artifacts can sweep the normalized-verdict file (T-02-06 mitigation)"
    - "^execute-[0-9]+$ regex gate in phase_is_writable — anchored to refuse command-injection-style phase names (T-02-01 mitigation)"
    - "jq -r rendering of reviewer-authored fields into the execute prompt (T-02-02 mitigation — safely escapes adversarial content)"
    - "fill_conditional preserves conditional blocks and substitutes {KEY} placeholders only on retry passes; strip_conditional keeps first-pass output byte-identical to v1.0"
key-files:
  created:
    - tests/revise-loop-simulation.sh
  modified:
    - dev-review/codex/dev-review.sh
    - lib/co-evolution.sh
key-decisions:
  - "Default REVISE_LOOP_MAX=0 preserves v1.0 single-pass behavior bit-for-bit; opt-in only."
  - "Pass 1 keeps bare execute/verify phase names in state.json; pass 2+ writes execute-N/verify-N — no breaking change for existing state.json consumers (Phase 8 eval scorer)."
  - "Extract loop body into _run_revise_loop so the simulation test and main flow run the exact same implementation (planner's suggested approach adopted)."
  - "Capture REVISE_FEEDBACK_JSON into memory before cleanup_runtime_artifacts runs — belt-and-suspenders against any future TOCTOU where cleanup might fire mid-loop."
  - "phase_is_writable regex is anchored (^execute-[0-9]+$) so malformed phase names cannot escalate to writable posture."
patterns-established:
  - "bounded retry loop sits between plan completion and run-completion timestamp — no other call sites need touching"
  - "prompt templates declare conditional blocks once; first-pass callers strip, retry-pass callers fill — one template, two paths"
requirements-completed: [RTUX-03]
duration: 25min
completed: 2026-04-17
---

# Phase 2 Plan 1: REVISE Auto-Loop Summary

**Bounded REVISE→retry loop in the Codex dev-review runtime, with feedback injection, numbered state.json phases, and a <4-second self-contained simulation test — all opt-in via --revise-loop N (default 0 preserves v1.0 byte-for-byte).**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-17 (feat/v1.1-polish)
- **Tasks:** 4
- **Commits:** 4 (atomic, per-task, all pushed)
- **Files modified:** 2 + 1 created

## Task Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | [`549850c`](https://github.com/alanshurafa/co-evolution/commit/549850c) | feat(revise-loop): add --revise-loop flag and REVISE_LOOP_MAX env var (RTUX-03) |
| 2 | [`be0af3b`](https://github.com/alanshurafa/co-evolution/commit/be0af3b) | feat(revise-loop): wrap execute+verify in retry loop with numbered phase names (RTUX-03) |
| 3 | [`e15332a`](https://github.com/alanshurafa/co-evolution/commit/e15332a) | feat(revise-loop): inject reviewer feedback into execute prompt on retry passes (RTUX-03) |
| 4 | [`fc08304`](https://github.com/alanshurafa/co-evolution/commit/fc08304) | test(revise-loop): add REVISE auto-loop simulation covering retry, parity, and cap (RTUX-03) |

## Files Created/Modified

| File | Change | Delta |
|------|--------|-------|
| `dev-review/codex/dev-review.sh` | modified | +176 / −16 (tasks 1-3) |
| `lib/co-evolution.sh` | modified | +11 / 0 (task 2) |
| `tests/revise-loop-simulation.sh` | created | +171 lines |

## Architecture (1-paragraph future-archaeology note)

The main flow's execute+verify block was replaced with a single call to `_run_revise_loop`, a shell function that bounds the REVISE retry count to `REVISE_LOOP_MAX + 1` total passes. Pass 1 writes bare `execute` / `verify` entries to `state.json` (byte-identical to v1.0); passes 2..N write `execute-N` / `verify-N`. `phase_is_writable` picked up an anchored regex branch (`^execute-[0-9]+$`) so numbered retry passes keep the writable Claude posture without enumerating every possible number. Between passes, the normalized verdict JSON is captured into `REVISE_FEEDBACK_JSON` **before** `cleanup_runtime_artifacts` can sweep the `.verdict-normalized.json` file — this env var is then threaded to `build_execution_prompt` (extended with an optional third arg), which uses `fill_conditional` + jq-based rendering (`build_reviewer_feedback_summary` + `build_issues_list_markdown`) to materialize the `{IF_SUBSEQUENT_PASS}` block in the next pass's execute prompt. The simulation test sources `_run_revise_loop` verbatim from `dev-review.sh` (via `sed` range extraction), mocks the phase runners, and asserts against real `state.json` output — so any future change to the loop body must also update the test, or CI will catch the drift.

## Test Output

```
$ bash tests/revise-loop-simulation.sh
S1 OK
S2 OK
S3 OK
S4 OK
ALL PASS

real    0m3.841s
```

All four scenarios pass in under 4 seconds with no network calls, no real CLI invocations, and no git repo required.

## Decisions Made

- **Extract loop body into `_run_revise_loop`** — planner's suggestion accepted. Test and main flow share one implementation; divergence impossible without the test also breaking.
- **Anchored regex in `phase_is_writable`** — `^execute-[0-9]+$` is tight enough that injection names like `execute-;rm-rf` or `verify-99` (wrong phase, intentionally) return `false`. Four-case unit test in Task 2 acceptance gate.
- **jq-based rendering of reviewer fields** — `build_issues_list_markdown` uses `jq -r` so adversarial content in `.issues[].description` or `.suggestion` is safely string-escaped before reaching the execute prompt. Defense-in-depth beyond the existing "Do NOT deviate" prompt rule.
- **REVISE_FEEDBACK_JSON capture before cleanup** — the file it reads is scheduled for sweeping, but cleanup_runtime_artifacts only runs after `_run_revise_loop` returns. Captured in-memory as belt-and-suspenders against any future reordering.
- **Default stays 0** — no user-visible behavior change for anyone who doesn't opt in. Non-breaking across the board.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan's jq asserts referenced `.phase` but schema uses `.name`**

- **Found during:** Task 4 authoring
- **Issue:** Plan's example `jq -e '.phases | map(.phase) == [...]'` would have false-failed against the real `state.json` schema, which records phase name under `.name` (see `lib/co-evolution.sh:667-672`).
- **Fix:** Test uses `map(.name)` throughout. Documented in the test's deviation note and in the Task 4 commit message.
- **Files modified:** `tests/revise-loop-simulation.sh`
- **Commit:** `fc08304`

No architectural deviations. Plan executed as specified otherwise.

## Issues Encountered

- **CRLF warning on Windows** when committing `tests/revise-loop-simulation.sh`. Git's `core.autocrlf` will normalize it at next touch; file runs correctly as-is (confirmed post-commit). No action needed.

## Threat Model Compliance

| Threat | Mitigation | Verified by |
|--------|-----------|-------------|
| T-02-01: injection via numbered phase name | `phase_is_writable ^execute-[0-9]+$` anchored regex | Task 2 unit tests (execute-2=true, verify-2=false, `";rm-rf /"`=false) |
| T-02-02: injection via reviewer content | jq -r rendering in `build_issues_list_markdown` | Task 3 retry-pass rendering test (HIGH bullet renders safely) |
| T-02-03: unbounded cost | Option parser rejects non-integers; budget = N+1 total passes | Task 1 validation tests |
| T-02-05: numbered phase repudiation | `write_state_phase` called per pass with unique name + timestamps | Task 4 scenarios S1 & S3 |
| T-02-06: stale verdict after cleanup | Capture before cleanup; cleanup only fires after loop exits | Code inspection + S1 REVISE→APPROVED test |

## User Setup Required

None. Feature is opt-in via `--revise-loop N` flag or `REVISE_LOOP_MAX` env var; default 0 preserves existing behavior.

## Follow-ups / Known Limits

- **Capped-REVISE exits with code 1.** When the loop exhausts its budget on a REVISE verdict, the last `VERIFY_EXIT=2` flows through the existing exit-code logic and the script exits with 1 (standard error). The verdict itself is recorded in `state.json.verify_verdict = "REVISE"`, so callers can distinguish "capped-out with REVISE verdict" from other failure modes. Acceptable for v1.1; a dedicated exit code (e.g., 3) could be added later if needed.
- **Phase 8 eval scorer awareness.** The scorer currently consumes `state.json.phases[].name`; numbered retry entries (`execute-2`, `verify-2`) will appear as additional passes. Not a breaking change — the scorer just sees extra attempts — but the scoring logic might want to treat repeated passes on the same logical phase as one run with extra attempts rather than N independent runs.
- **Simulation test coupling.** `tests/revise-loop-simulation.sh` extracts `_run_revise_loop` via a `sed` range. If the function layout changes (different opening/closing brace style) the extraction will silently miss the body. Mitigation: test has an explicit `declare -F _run_revise_loop` guard that exits early if extraction failed.

## Next Phase Readiness

- **Phase 2 closes RTUX-03.** One of three RTUX requirements in v1.1; RTUX-01 (Phase 3, visible live mode) and RTUX-02 (Phase 4, worktree management) remain.
- **No blockers for Phase 3.** Phase 3 touches the invoke layer, not the retry loop, so these two can land independently.

---
*Phase: 02-revise-auto-loop*
*Plan: 01*
*Completed: 2026-04-17*
