---
phase: 07-runner-parity
plans: [07-01, 07-02, 07-03]
subsystem: runner-parity
tags: [agent-dispatcher, writable-phase, state-json, delta-tracking, per-phase-timeout, upstream-parity]
requires: [phase-06]
provides: [runner-parity-with-codex-ps, hang-protection, phase-8-ground-truth]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
tech-stack:
  added: [coreutils-timeout (already available), jq (already available, now used for state writes)]
  patterns: [single-entry-dispatcher, fail-safe-writable-fallback, incremental-state-writes, hash-manifest-snapshot, timeout-foreground-kill]
metrics:
  duration: 50min
  tasks_completed: 9
  commits: 6
  completed: 2026-04-17
requirements: [RNPT-01, RNPT-02, RNPT-03, RNPT-04, RNPT-05]
---

# Phase 7: Runner Parity Summary

One-liner: Ported the five features the Bash runner lacked relative to the Codex PS reference — single-entry agent dispatcher (RNPT-01), writable-phase as a first-class abstraction (RNPT-02), pre/post-execute delta tracking with SHA-256 manifests (RNPT-03), per-run `state.json` as machine-readable ground truth (RNPT-04), and per-phase `timeout --foreground` wrapper that actually kills hangs (RNPT-05).

## What Landed Per Plan

### Plan 07-01: Agent Dispatcher + Writable-Phase Abstraction (RNPT-01, RNPT-02)

- `WRITABLE_PHASES=(execute execute-retry fix)` and `phase_is_writable <name>` added to `lib/co-evolution.sh`
- Unknown phase names fail-safe to "false" (text-phase posture — refuses elevation)
- Six `invoke_agent` call sites in `dev-review.sh` now derive writable from `phase_is_writable "<name>"`:
  - compose (false), bounce (false), execute (true), execute-retry (true), review (false), retry-via-calling_phase (variable)
- Verify-phase opus branch refactored from direct `invoke_claude` to `invoke_agent` (single entry point)
- `invoke_codex_schema` retained as documented exception (schema-output semantics)
- `ensure_valid_plan_output` gained 8th arg (calling_phase) so retry inherits writable posture cleanly
- Zero hard-coded `"true"`/`"false"` literals as the 5th `invoke_agent` arg anywhere in the file
- Mocked smoke test: `RNPT-01/02 SMOKE: OK`

Commits: `cf59338` (helper), `fb2e142` (call sites)

### Plan 07-02: state.json + Delta Tracking (RNPT-03, RNPT-04)

- Five helpers added to `lib/co-evolution.sh`:
  - `snapshot_workdir_hashes` — walks workdir, emits `{path: sha256}` JSON (skips `.git/`, `runs/`, `.co-evolution/`)
  - `compute_execute_delta` — baseline + current manifests → `{modified, added, deleted}` sorted arrays
  - `init_state_json` — writes schema skeleton with ISO-8601 started_at
  - `write_state_phase` — appends phase entry with name/status/exit_code/timestamps
  - `write_state_field` — generic jq-path setter for string/number/bool/null/rawfile
- `dev-review.sh` wired with 10+ state.json hook points: init at run-setup, per-phase compose/bounce-NN/execute/verify wrappers with start/end timestamps, pre/post-execute snapshot+delta, marker-count writes, verify-verdict capture, completed_at on both main-flow exit and `--plan-only` exit branches
- `cleanup_runtime_artifacts` untouched — its `-maxdepth 1 -type f -name '.*'` guard naturally spares `state.json` (no leading dot)
- Intermediate manifests deliberately dot-prefixed so they get swept
- jq-or-fallback pattern throughout (graceful degradation; warnings not crashes)
- End-to-end simulation: `RNPT-03/04 SIM: OK` with full schema validation (phases length=4, delta arrays correct, baseline hashes present, verdict=APPROVED, completed_at ISO-8601)

Commits: `69d0350` (helpers), `f3bb0f5` (wiring)

### Plan 07-03: Per-Phase Timeout (RNPT-05)

- Upstream's "single most painful gap" (1h 39min Claude hang) now bounded
- `PHASE_TIMEOUT=1800` (30min) default at top of `lib/co-evolution.sh` via source-safe `:` no-op
- `invoke_agent_with_timeout` wraps claude/codex in `timeout --foreground "${N}s"` — signal handling stays with the invoking shell so SIGTERM actually reaches network-blocked CLI children
- `LAST_INVOKE_EXIT_CODE` global: 124 = timeout fired, 0 = ok, else agent exit code
- Re-sources `lib/co-evolution.sh` inside `bash -c` subshell (safer than `export -f` on MINGW64)
- `--timeout SECONDS` CLI flag validates positive integer (rejects `-5`, `abc`, `0`), exports PHASE_TIMEOUT
- `abort_on_timeout <phase> <start>` helper: records timeout entry in state.json with `status: "timeout"` + `exit_code: 124`, sets `.completed_at`, logs ERROR, cleans up, exits 1
- All six agent call sites wrapped (6 invoke_agent sites + inline wrap on invoke_codex_schema verify branch)
- Runner exits 1 on timeout (fatal); 124 lives only in state.json.phases[].exit_code for observability
- Startup log now reports effective PHASE_TIMEOUT
- **Hang-kill smoke test (MANDATORY):** Test A proves `sleep 5` is killed by 2s timeout in 2.07s wall-clock with exit 124. Test B proves fast path (0.09s, exit 0). Test C proves state.json records the timeout entry. `RNPT-05 SMOKE: OK`.

Commits: `987f484` (wrapper + default), `d31819e` (CLI flag + wiring)

## Commit Chain

```
d31819e  feat(07-03): thread --timeout flag + abort_on_timeout through runner
987f484  feat(07-03): add invoke_agent_with_timeout + PHASE_TIMEOUT default
f3bb0f5  feat(07-02): wire state.json lifecycle into dev-review runner
69d0350  feat(07-02): add state.json + delta helpers
fb2e142  refactor(07-01): route all invoke_agent call sites through phase_is_writable
cf59338  feat(07-01): add phase_is_writable helper + WRITABLE_PHASES array
```

All commits pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Plan | Status |
|-----|------|--------|
| RNPT-01 | 07-01 | Complete |
| RNPT-02 | 07-01 | Complete |
| RNPT-03 | 07-02 | Complete |
| RNPT-04 | 07-02 | Complete |
| RNPT-05 | 07-03 | Complete |

## Wave Order Executed

Strict sequential execution per execution context (each wave touches dev-review.sh + lib/co-evolution.sh):

- **Wave 1 (no deps):** 07-01
- **Wave 2 (depends on 07-01):** 07-02
- **Wave 3 (depends on 07-01 + 07-02):** 07-03

Executed: 07-01 T1 → T2 → T3 → 07-02 T1 → T2 → T3 → 07-03 T1 → T2 → T3.

## Files Modified (Phase-Level)

- `lib/co-evolution.sh`
  - Added `WRITABLE_PHASES` array + `phase_is_writable` helper (07-01)
  - Added `snapshot_workdir_hashes`, `compute_execute_delta`, `init_state_json`, `write_state_phase`, `write_state_field` (07-02)
  - Added `PHASE_TIMEOUT` default + `invoke_agent_with_timeout` (07-03)
- `dev-review/codex/dev-review.sh`
  - Refactored 6 agent call sites through `phase_is_writable` (07-01)
  - `run_verify_phase` opus branch now goes through dispatcher (07-01)
  - `ensure_valid_plan_output` gained `calling_phase` arg (07-01)
  - STATE_JSON + hash-manifest globals + `init_state_json` at run-setup (07-02)
  - Per-phase wrappers with ISO-8601 timestamps around compose/bounce/execute/verify (07-02)
  - Per-pass `bounce-NN` state.json entries inside the bounce loop (07-02)
  - Pre/post-execute snapshot + delta inside `run_execute_phase` (07-02)
  - Marker-count, verdict, completed_at field writes (07-02)
  - LAST_INVOKE_EXIT_CODE global + `abort_on_timeout` helper (07-03)
  - `--timeout SECONDS` CLI flag + parser validation (07-03)
  - All 6 agent calls replaced with `invoke_agent_with_timeout` (07-03)
  - `invoke_codex_schema` verify branch timeout-wrapped inline (07-03)
  - Startup log reports PHASE_TIMEOUT (07-03)

## Deviations

All deviations documented in per-plan SUMMARYs. High-level:

- **07-01:** Retry call in `ensure_valid_plan_output` now uses `phase_is_writable "$calling_phase"` instead of hard-coded `"false"`. Strictly better than plan (Rule 2 — preserves RNPT-02 invariant at the retry site too).
- **07-02:** Added defensive `[[ -n "${STATE_JSON:-}" ... ]]` guards around state writes inside phase functions; added `.completed_at` to `--plan-only` exit branch (Phase 8 scorer sees terminated run, not crashed); post-execute delta runs even on "no changes" branch (empty delta > missing field).
- **07-03:** Rejected `--timeout 0` at parse time (timeout 0 means "no limit" on some coreutils — confusing); timeout-wrapped `invoke_codex_schema` inline as well (same hang vector as invoke_agent); renamed main-flow phase-start vars to phase-specific names (`_compose_phase_start`, etc.) so `abort_on_timeout` reads the right timestamp; `abort_on_timeout` also writes `.completed_at` (Phase-8 fidelity win).

## Planner Warnings Resolved

1. Plan 07-01 expected 5 `phase_is_writable` call sites; final count is 6 because the retry site was also refactored for consistency. Verified all 5 distinct phase-name literals (compose, bounce, execute, execute-retry, review) appear in the file.
2. Plan 07-02 described cleanup behavior; confirmed with real `find -maxdepth 1 -type f -name '.*' -delete` that state.json (no leading dot) survives while dot-prefixed intermediates are swept.
3. Plan 07-03 description of `invoke_agent_with_timeout` re-sourcing — tested and confirmed on MINGW64 Git Bash with coreutils `timeout` 8.32; `--foreground` flag accepted and SIGTERM reaches the child within budget.

## Verification Summary

Final end-to-end verification (all gates pass):

**Plan 07-01:**
- `bash -n lib/co-evolution.sh` — OK
- `bash -n dev-review/codex/dev-review.sh` — OK
- `WRITABLE_PHASES=(execute execute-retry fix)` def — 1
- `phase_is_writable()` def — 1
- Direct `invoke_(claude|codex)` call count — 2 (dispatcher body)
- `invoke_agent ... phase_is_writable` count — 6
- Hard-coded `"true"`/`"false"` as 5th arg — 0
- All 5 phase names grep-able
- `bash /tmp/rnpt-01-02-smoke.sh` — `RNPT-01/02 SMOKE: OK`

**Plan 07-02:**
- 5 helpers in `lib/` — all present (1 each)
- STATE_JSON var — OK
- init_state_json call — OK
- snapshot_workdir_hashes calls — 2 (pre+post)
- compute_execute_delta call — 1
- write_state_phase per phase — compose, bounce-NN, execute, verify all present
- write_state_field per field — .verify_verdict, .completed_at, .marker_counts.{contested,clarify}, .baseline_hashes, .execute_delta all present
- cleanup_runtime_artifacts guard unchanged — OK (state.json survives real find)
- ISO-8601 UTC occurrences — 12 (≥7 required)
- `bash /tmp/rnpt-03-04-sim.sh` — `RNPT-03/04 SIM: OK`

**Plan 07-03:**
- `invoke_agent_with_timeout()` def — 1
- `PHASE_TIMEOUT` default via `:` — OK
- Source-safe — OK
- Env var override — OK (PHASE_TIMEOUT=42 source → 42)
- `timeout(1)` available — OK
- `--timeout SECONDS` usage doc — OK
- Parser validation — rejects -5/abc/0 with clear error
- `export PHASE_TIMEOUT=` in parser — OK
- `invoke_agent_with_timeout` call count — 7 (≥6 required)
- Bare `invoke_agent` call sites — 0
- `abort_on_timeout()` def — 1
- `abort_on_timeout ` call count — 12 (≥5 required)
- Startup log "Timeout: …" — OK
- `LAST_INVOKE_EXIT_CODE=0` global — OK
- `bash /tmp/rnpt-05-timeout-smoke.sh` — `RNPT-05 SMOKE: OK`
  - **Test A: 5s sleep killed in 2.07s wall-clock, exit 124** (hang-kill proven)
  - **Test B: fast path 0.09s, exit 0** (fast-path working)
  - **Test C: state.json records `{name: compose, status: timeout, exit_code: 124}`**

## Known Stubs

None. All code paths are wired; all acceptance criteria pass; all five requirements complete.

## Next Phase

Phase 8 (Evals Absorbed) — elevate portable eval assets (`evals/cases/*.yaml`, `evals/fixtures/`, `evals/VERIFICATION-PLAN.md`, `schemas/review-verdict.json`) to top-level `evals/`; keep runner-specific PS harness under `runners/codex-ps/`; document `pwsh` as optional dependency. Phase 8 now has `$RUN_DIR/state.json` as machine-readable ground truth per run.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND (all Phase 7 additions present)
- `dev-review/codex/dev-review.sh` — FOUND (all wiring present)
- Commits `cf59338`, `fb2e142`, `69d0350`, `f3bb0f5`, `987f484`, `d31819e` — all FOUND
- `/tmp/rnpt-01-02-smoke.sh` — PASS
- `/tmp/rnpt-03-04-sim.sh` — PASS
- `/tmp/rnpt-05-timeout-smoke.sh` — PASS (timeout actually fires — 2.07s wall-clock kill proven)
- All 9 tasks across 3 plans complete
