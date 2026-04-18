---
phase: 07-runner-parity
plan: 03
subsystem: runner-timeout
tags: [timeout, hang-protection, phase-ceiling, RNPT-05]
requires: [phase-06, 07-01, 07-02]
provides: [per-phase-timeout, hang-kill-protection, timeout-state-accounting]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
tech-stack:
  added: [coreutils-timeout]
  patterns: [timeout-foreground-kill, re-source-in-subshell, global-exit-code-propagation]
key-files:
  created: []
  modified:
    - lib/co-evolution.sh
    - dev-review/codex/dev-review.sh
decisions:
  - `--foreground` flag required (keeps signal handling with invoking shell)
  - Re-source lib in `bash -c` subshell (safer than `export -f` on MINGW64)
  - Runner exits 1 on timeout (fatal), NOT 124 (124 lives in state.json.phases[].exit_code)
  - Default 1800s (30min) — generous but catches the 1h 39min hang category
  - Wrapper returns 0 always; exit flows through LAST_INVOKE_EXIT_CODE global
  - Zero-value timeout rejected at parse time (would mean "no wrapping" — confusing)
  - invoke_codex_schema (verify phase) also timeout-wrapped inline for parity
metrics:
  duration: 20min
  tasks_completed: 3
  commits: 2
  completed: 2026-04-17
requirements: [RNPT-05]
---

# Phase 7 Plan 3: Per-Phase Timeout Summary

One-liner: Wrapped every agent invocation in `timeout --foreground ${PHASE_TIMEOUT}s` so the runner can never hang indefinitely — upstream's 1h 39min Claude-hang category now deterministically aborts within a configurable window with a machine-readable timeout entry in state.json.

## What Landed

### Task 1: `invoke_agent_with_timeout` + `PHASE_TIMEOUT` default (`lib/co-evolution.sh`)

- Top-of-file default: `: "${PHASE_TIMEOUT:=1800}"` (source-safe, env-overridable)
- End-of-file wrapper: `invoke_agent_with_timeout <agent> <prompt> <output> <stderr> [writable]`
- Uses `timeout --foreground` so signal delivery reaches the CLI child (a must for claude in `-p` mode blocked on network reads)
- Re-sources `lib/co-evolution.sh` inside `bash -c` for subshell execution (safer than `export -f` on MINGW64)
- Sets global `LAST_INVOKE_EXIT_CODE`: 124 = timeout fired, 0 = ok, else agent exit code
- Degrades gracefully with WARNING log if `timeout(1)` missing (cosmetic on Git Bash — coreutils ships timeout)
- Wrapper returns 0 always (matches existing `invoke_claude`/`invoke_codex` `|| true` posture)

Commit: `987f484`

### Task 2: `--timeout` CLI + `abort_on_timeout` helper + 6 call-site replacements

| Change | Location |
|--------|----------|
| Usage doc line | `--timeout SECONDS   Per-phase timeout in seconds (default: 1800)` |
| Argv parser case | Validates positive integer (rejects `-5`, `abc`, `0`), `export`s `PHASE_TIMEOUT` |
| `LAST_INVOKE_EXIT_CODE=0` global | Top of script |
| `abort_on_timeout <phase_name> <phase_start>` helper | Near top; writes timeout entry to state.json, sets `completed_at`, logs, cleans up, exits 1 |
| Startup log | ` Timeout:   ${PHASE_TIMEOUT}s per phase` |
| `ensure_valid_plan_output` retry | Timeout-wrapped; propagates as `return 1` on 124 (outer wrapper handles) |
| `run_compose_phase` | `invoke_agent_with_timeout` + `abort_on_timeout "compose" "$_compose_phase_start"` |
| `run_bounce_phase` loop | Per-pass `invoke_agent_with_timeout` + `abort_on_timeout "bounce-NN"` |
| `run_execute_phase` initial | `invoke_agent_with_timeout` + `abort_on_timeout "execute"` |
| `run_execute_phase` retry | `invoke_agent_with_timeout` + `abort_on_timeout "execute-retry"` |
| `run_verify_phase` opus branch | `invoke_agent_with_timeout` + `abort_on_timeout "verify"` |
| `run_verify_phase` codex branch | inline `timeout --foreground` wrap of `invoke_codex_schema` + `abort_on_timeout "verify"` |

Main flow phase start vars renamed to `_compose_phase_start`, `_execute_phase_start`, `_verify_phase_start` so `abort_on_timeout` inside each phase function can refer to the correct timestamp.

Commit: `d31819e`

### Task 3: Three-test hang-kill smoke (MANDATORY)

`/tmp/rnpt-05-timeout-smoke.sh` — results on this run:

| Test | What | Result |
|------|------|--------|
| A | 5-second `sleep 5` killed by 2-second timeout | **elapsed=2.07s, exit=124** — well under 3.5s budget; timeout actually fired |
| B | Fast mock, 10s timeout, should complete fast | **elapsed=0.09s, exit=0, output captured** |
| C | `abort_on_timeout` writes timeout record to state.json | **state.json has `{name: "compose", status: "timeout", exit_code: 124}`**, log reads `ERROR: compose phase timed out after 42s - aborting run`, exit 1 |

Final line: `RNPT-05 SMOKE: OK`

## Commit Chain

```
d31819e  feat(07-03): thread --timeout flag + abort_on_timeout through runner
987f484  feat(07-03): add invoke_agent_with_timeout + PHASE_TIMEOUT default
```

Both pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| RNPT-05 | Complete | Every invoke_agent call site is now timeout-wrapped (6 sites + inline wrap on codex-schema verify). `--timeout SECONDS` CLI flag validates + exports. Default 1800s enforced. Smoke Test A proves: 5s hang killed in 2.07s wall-clock (exit 124). Smoke Test C proves: state.json records `{status: "timeout", exit_code: 124}` on timeout. Runner exits 1 on timeout (fatal); 124 lives only in state.json. |

## Wiring Summary

- 6 agent call sites wrapped (compose, bounce-per-pass, execute, execute-retry, verify-opus, verify-codex-schema)
- 1 retry site (ensure_valid_plan_output) wrapped with return-1 propagation
- 12 `abort_on_timeout` references (5+ distinct call sites; extras are fallback `${var:-default}` literals inside the wrapper)
- 1 CLI flag (`--timeout`)
- 1 env var (`PHASE_TIMEOUT`)
- 1 startup log line

## Deviations

**1. [Rule 2 - Defensive] Zero timeout values rejected at parse time.**

Plan says "positive integer"; implementation explicitly rejects `0` in addition to negative/non-integer. Rationale: `timeout 0s` on coreutils means "no limit at all" on some versions — which defeats the purpose of the flag. Rejecting 0 keeps semantics unambiguous: timeout always bounds.

**2. [Rule 2 - Completeness] `invoke_codex_schema` (verify phase codex branch) also timeout-wrapped inline.**

Plan's call-site list enumerated the six `invoke_agent` sites. But `invoke_codex_schema` is a separate non-dispatcher call (kept as exception per RNPT-01). It's still an agent invocation — leaving it unwrapped would leak the hang vector the feature is designed to prevent. Added an inline `timeout --foreground` wrap around the call with a fallback to direct dispatch when `timeout(1)` is missing. Same exit-code plumbing as the main wrapper.

**3. [Rule 1 - Correctness] Main flow phase start vars renamed to phase-specific names.**

Plan's Edits 3/7/8 use generic `_phase_start`. But `abort_on_timeout` inside each `run_*_phase` function needs to read the start timestamp set by the main-flow wrapper. Generic `_phase_start` gets overwritten by whichever phase runs last, so the compose abort would see the bounce start. Renamed to `_compose_phase_start`, `_execute_phase_start`, `_verify_phase_start` (one per phase) so each phase's abort reads its own start. Bounce uses an internal `bounce_pass_start` already set per iteration.

**4. [Rule 2 - Phase-8 fidelity] `abort_on_timeout` also writes `.completed_at`.**

Plan specifies writing only the phase entry with status=timeout. Added `.completed_at` as well so Phase 8 scorer sees a terminated run (it can distinguish timeout from crash-mid-phase via phase status). Minor addition to the same state write chain, zero behavioral cost.

## Verification Summary

```
bash -n lib/co-evolution.sh              → OK
bash -n dev-review/codex/dev-review.sh   → OK
invoke_agent_with_timeout() def          → 1 in lib
PHASE_TIMEOUT default                    → OK (: "${PHASE_TIMEOUT:=1800}")
Source-safe                              → OK (PHASE_TIMEOUT=1800 after source)
Env override                             → OK (PHASE_TIMEOUT=42 source → 42)
timeout(1) available                     → OK (/usr/bin/timeout)
--timeout usage doc line                 → OK
--timeout argv parse (reject -5/abc/0)   → OK (3/3 rejected)
export PHASE_TIMEOUT                     → OK
invoke_agent_with_timeout call count     → 7 (≥ 6 plan target)
bare invoke_agent CALL SITES             → 0
abort_on_timeout() def                   → 1
abort_on_timeout call count              → 12 (≥ 5 plan target)
Startup log "Timeout: ... per phase"     → OK
LAST_INVOKE_EXIT_CODE global             → OK
bash /tmp/rnpt-05-timeout-smoke.sh       → RNPT-05 SMOKE: OK
  Test A (hang kill, 2s budget)          → elapsed=2.07s, exit=124
  Test B (fast path)                     → elapsed=0.09s, exit=0, output captured
  Test C (state.json timeout record)     → {name:compose, status:timeout, exit_code:124}
```

## Known Stubs

None.

## Phase 7 Wrap-up

RNPT-01..05 all landed:

- RNPT-01 (dispatcher) + RNPT-02 (writable-phase abstraction) → Plan 07-01
- RNPT-03 (delta tracking) + RNPT-04 (state.json) → Plan 07-02
- RNPT-05 (per-phase timeout) → Plan 07-03

The Bash runner now matches the codex-ps reference's feature set and adds one feature PS itself doesn't have (per-phase timeout). Phase 8's eval harness can read `$RUN_DIR/state.json` as machine-readable ground truth.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND (wrapper + default present)
- `dev-review/codex/dev-review.sh` — FOUND (all wiring present)
- Commit `987f484` — FOUND
- Commit `d31819e` — FOUND
- Smoke test A: PASS (timeout actually fired — 2.07s wall-clock, exit 124)
- Smoke test B: PASS (fast path 0.09s, exit 0)
- Smoke test C: PASS (state.json records timeout entry)
