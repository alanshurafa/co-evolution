---
phase: 06-protocol-parity
plans: [06-01, 06-02, 06-03]
subsystem: runner-protocol
tags: [claude-adapter, bounce-signal, bounce-protocol, upstream-parity]
requires: [phase-05]
provides: [protocol-parity-with-codex-ps]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
  - runners/codex-ps/templates/bounce-protocol.md
tech-stack:
  added: []
  patterns: [phase-aware-tool-gating, structural-signal-companion, byte-identical-template-sync]
metrics:
  duration: 58min
  tasks_completed: 7
  commits: 5
  completed: 2026-04-17
requirements: [PRTP-01, PRTP-02, PRTP-03, PRTP-04, PRTP-05]
---

# Phase 6: Protocol Parity Summary

One-liner: Brought the Bash runner's Claude adapter and verification layer into parity with UPSTREAM-MESSAGE.md MUST-items 3-6 — phase-aware tool gating, `--json-schema` banished, structural bounce signal persisted, and the codex-ps bounce protocol reconciled with the main repo's stronger version.

## What Landed Per Plan

### Plan 06-01: Claude Adapter Tool Gating (PRTP-01, PRTP-02, PRTP-03)

- `invoke_claude` in `lib/co-evolution.sh` now accepts a 4th positional `writable` arg
- Text phases (compose, bounce, review) get `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"`
- Write phases (execute, execute-retry) get `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir "$WORKDIR"`
- Broken `--tools ""` flag removed from non-WSL branch
- `--json-schema` banned repo-wide (grep-based CI guards confirm 0 occurrences in `lib/co-evolution.sh` and `dev-review/codex/dev-review.sh`)
- Default `writable="false"` — safer posture if a caller forgets the flag
- `invoke_codex` path narrowed with an inline comment explaining codex has no writable analogue
- 5 call sites updated in `dev-review/codex/dev-review.sh`; mocked smoke test exits `PRTP-01/02/03 SMOKE: OK`

Commits: `dab8f76` (lib/co-evolution.sh), `e78bf24` (dev-review.sh threading)

### Plan 06-02: Structural Bounce Signal (PRTP-04)

- `mkdir -p "$RUN_DIR/outputs"` added at run-setup so even 0-pass runs have an empty-dir signal distinct from "never set up"
- Per bounce pass, the final post-`strip_human_summary` plan content is persisted as `$RUN_DIR/outputs/bounce-NN.txt` (zero-padded NN)
- `verify_bounce_ran(run_dir)` helper reports presence (exit code) and count (via `BOUNCE_ARTIFACT_COUNT` side-effect)
- `run_bounce_phase` logs `" Bounce artifacts: N pass file(s) in outputs/"` at the end of the phase
- `cleanup_runtime_artifacts` untouched — its existing `-maxdepth 1` guard already preserves `outputs/`
- 3-scenario simulation test: scenario A (2 passes), scenario B (empty outputs), scenario C (no outputs dir) — all PASS

Commits: `b7abb1e` (write), `ff0c951` (helper + log)

### Plan 06-03: Bounce Protocol Reconciliation (PRTP-05)

- `runners/codex-ps/templates/bounce-protocol.md` overwritten byte-identical with `skills/dev-review/templates/bounce-protocol.md`
- Recovered the missing "You MUST output the COMPLETE document, not a summary of changes" clause and the entire SCOPE CONTROL section
- Line count: 42 → 51 (delta +9)
- CXPS-02 discipline preserved — `git status --porcelain runners/codex-ps/` shows exactly 1 modified file; `REFERENCE-STATUS.md` untouched
- Prior content recoverable via `git show 438e435:runners/codex-ps/templates/bounce-protocol.md`

Commit: `7b76b3a`

## Commit Chain

```
ff0c951  feat(06-02): add verify_bounce_ran helper + end-of-phase log
b7abb1e  feat(06-02): persist structural bounce signal under outputs/
7b76b3a  docs(06-03): reconcile codex-ps bounce protocol with main repo
e78bf24  feat(06-01): thread writable-phase flag through invoke_agent
dab8f76  feat(06-01): gate Claude tools by writable-phase signal
```

All commits pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| PRTP-01 | 06-01 | Complete |
| PRTP-02 | 06-01 | Complete |
| PRTP-03 | 06-01 | Complete |
| PRTP-04 | 06-02 | Complete |
| PRTP-05 | 06-03 | Complete |

## Wave Order Executed

Per execution context, the stated waves were:
- **Wave 1 (parallel-safe, disjoint files):** 06-01, 06-03
- **Wave 2 (depends on 06-01):** 06-02

Executed serially in order: 06-01 Task 1 → 06-01 Task 2 → 06-01 Task 3 (smoke) → 06-03 Task 1 → 06-02 Task 1 → 06-02 Task 2 → 06-02 Task 3 (simulation).

## Files Modified (Phase-Level)

- `lib/co-evolution.sh` — `invoke_claude` rewritten for phase-aware tool gating
- `dev-review/codex/dev-review.sh` — `invoke_agent` threading + 5 call sites + `mkdir outputs` + per-pass `outputs/bounce-NN.txt` write + `verify_bounce_ran` helper + end-of-phase log
- `runners/codex-ps/templates/bounce-protocol.md` — byte-identical to canonical skills/ copy

## Deviations

All deviations are documented in the per-plan SUMMARYs. High-level:

- **06-01 Task 1:** Reworded an explanatory comment to avoid verbatim `--tools ""` / `--json-schema` literals so grep-based CI guards (PRTP-03) stay tight.
- **06-01 Task 3:** Wrote smoke test to `C:/Users/alan/AppData/Local/Temp/` (Git Bash's `/tmp`) so `bash /tmp/...` resolves correctly on MINGW64.
- **06-02 Task 1:** Plan's acceptance-criterion grep literals had escape-sequence issues under nested shell; ran equivalent checks that proved intent. Actual code matches plan verbatim.
- **06-03:** Zero deviations. Single-task plan executed as written.

## Planner Warnings Resolved

1. `ensure_valid_plan_output` retry call at dev-review.sh:355 — explicitly appended `"false"` with an inline comment (chose "explicit" over "comment only" per planner's "pick one").
2. `invoke_codex` narrowing from `"$@"` to explicit positionals — added a one-line comment noting codex has no writable analogue and that Phase 7 may revisit.

## Verification Summary

Final end-to-end verification (all checks pass):

**Plan 06-01:**
- `bash -n lib/co-evolution.sh` — OK
- `bash -n dev-review/codex/dev-review.sh` — OK
- `disallowedTools` exact-list grep — 1
- `permission-mode bypassPermissions` grep — 1
- `allowedTools` exact-list grep — 1
- `add-dir` grep — 1 (in lib)
- `--tools ""` grep — 0
- `json-schema` grep — 0 (both files)
- `invoke_agent ... "false"` (compose) — 1
- `invoke_agent ... "false"` (bounce) — 1
- `invoke_agent ... "true"` (execute) — 2
- `invoke_claude ... "false"` (review) — 1

**Plan 06-02:**
- `mkdir -p "$RUN_DIR/outputs"` — 1
- `outputs/bounce-${pass_padded}.txt` — 1
- `verify_bounce_ran()` def — 1
- `verify_bounce_ran "$RUN_DIR"` call — 1
- `Bounce artifacts:` log lines — 2
- `find "$RUN_DIR" -maxdepth 1 -type f -name` (cleanup unchanged) — 1

**Plan 06-03:**
- `diff -q` on bounce-protocol.md files — exit 0
- `SCOPE CONTROL` clause in codex-ps copy — 1
- `You MUST output the COMPLETE document` clause in codex-ps copy — 1

**Smoke tests:**
- `PRTP-01/02/03 SMOKE: OK`
- `PRTP-04 SIM: OK` (3/3 scenarios pass)

## Known Stubs

None. All code paths are wired; all acceptance criteria pass; all requirements complete.

## Next Phase

Phase 7 (Runner Parity) — port the 5 features the Bash runner lacks relative to the Codex PS reference: agent dispatcher, writable-phase flag as top-level abstraction (building on 06-01's threading), delta tracking, structured `state.json`, per-phase timeout.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND
- `dev-review/codex/dev-review.sh` — FOUND
- `runners/codex-ps/templates/bounce-protocol.md` — FOUND (byte-identical to skills/ source)
- Commits `dab8f76`, `e78bf24`, `7b76b3a`, `b7abb1e`, `ff0c951` — all FOUND
- Smoke tests: both PASS
- All 7 tasks across 3 plans complete
