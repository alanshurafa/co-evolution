---
phase: 07-runner-parity
plan: 01
subsystem: runner-dispatcher
tags: [agent-dispatcher, writable-phase, runner-abstraction, RNPT-01, RNPT-02]
requires: [phase-06]
provides: [authoritative-writable-phase-helper, single-entry-dispatcher]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
tech-stack:
  added: []
  patterns: [writable-phase-derivation, single-entry-dispatcher, fail-safe-fallback]
key-files:
  created: []
  modified:
    - lib/co-evolution.sh
    - dev-review/codex/dev-review.sh
decisions:
  - Unknown phase names fail-safe to "false" (text-phase posture) — refuses elevation
  - ensure_valid_plan_output gained 8th positional (calling_phase) so retry inherits writable posture via phase_is_writable
  - invoke_codex_schema kept outside the dispatcher (schema-bound output has distinct semantics)
metrics:
  duration: 12min
  tasks_completed: 3
  commits: 2
  completed: 2026-04-17
requirements: [RNPT-01, RNPT-02]
---

# Phase 7 Plan 1: Agent Dispatcher + Writable-Phase Abstraction Summary

One-liner: Promoted `invoke_agent` to the sole entry point for all free-text agent calls and replaced every hard-coded writable literal at call sites with `phase_is_writable "<name>"`, backed by a `WRITABLE_PHASES` array in `lib/co-evolution.sh`.

## What Landed

### Task 1: Helper + array in `lib/co-evolution.sh`

- `WRITABLE_PHASES=(execute execute-retry fix)` declared at top level
- `phase_is_writable <name>` prints "true"/"false" on stdout
- Fail-safe: unknown phase names return "false" (downgrade, not elevate)
- Source-safe: no side effects beyond function + array definitions

Commit: `cf59338`

### Task 2: Call-site refactor in `dev-review/codex/dev-review.sh`

Six `invoke_agent` call sites now derive writable from `phase_is_writable`:

| # | Line | Phase | Writable | Context |
|---|------|-------|----------|---------|
| 1 | 370 | (retry, calling_phase arg) | via variable | `ensure_valid_plan_output` retry |
| 2 | 439 | compose | false | `run_compose_phase` |
| 3 | 515 | bounce | false | `run_bounce_phase` loop |
| 4 | 587 | execute | true | `run_execute_phase` initial |
| 5 | 595 | execute-retry | true | `run_execute_phase` retry |
| 6 | 694 | review | false | `run_verify_phase` opus branch |

`run_verify_phase` opus branch: refactored from a direct `invoke_claude` call to `invoke_agent "$verifier" ... "$(phase_is_writable review)"` — RNPT-01 dispatcher posture enforced. `invoke_codex_schema` retained as explicit exception with inline comment (schema-output semantics are not a free-text dispatch).

`ensure_valid_plan_output` signature extended with an 8th positional `calling_phase` (default: "bounce"). Callers in `run_compose_phase` and `run_bounce_phase` pass "compose" / "bounce" explicitly.

Commit: `fb2e142`

### Task 3: End-to-end smoke test

Mocked `invoke_claude` + `invoke_codex` to log invocations. Extracted `invoke_agent` via `awk` from the real `dev-review.sh` and sourced the real `lib/co-evolution.sh`. Drove the dispatcher with all five canonical phases plus one unknown-phase fallback check. Asserted the mock log shows:

- compose → `claude ... writable=false`
- bounce → `claude ... writable=false`
- execute → `codex ... writable=<n/a>` (codex dispatch ignores writable)
- execute-retry → `claude ... writable=true`
- review → `claude ... writable=false`

Output: `RNPT-01/02 SMOKE: OK`

Test script lives in `/tmp/rnpt-01-02-smoke.sh` (transient — not committed).

## Commit Chain

```
fb2e142  refactor(07-01): route all invoke_agent call sites through phase_is_writable
cf59338  feat(07-01): add phase_is_writable helper + WRITABLE_PHASES array
```

Both pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| RNPT-01 | Complete | Zero direct `invoke_claude`/`invoke_codex` calls outside dispatcher body (grep == 2, both inside `invoke_agent`). `invoke_codex_schema` remains as documented exception with inline comment. |
| RNPT-02 | Complete | `WRITABLE_PHASES` array + `phase_is_writable` helper present in `lib/co-evolution.sh`. 6 call sites derive writable from `phase_is_writable`. 0 hard-coded `true`/`false` literals as the 5th `invoke_agent` arg. |

## Deviations

**1. [Rule 2 - Critical Functionality] Retry call in `ensure_valid_plan_output` uses `phase_is_writable "$calling_phase"` (variable) instead of hard-coded `"false"`.**

The plan anticipated 5 explicit-phase-name call sites; the final audit shows 6 sites using `phase_is_writable` because the retry call now derives its writable flag from the calling phase's name (passed as the 8th positional) instead of hard-coding "false". This is strictly better than the plan: it preserves RNPT-02's invariant ("zero hard-coded literals") at the retry site too. Verification:

- Direct `invoke_claude`/`invoke_codex` calls outside dispatcher: 2 (inside `invoke_agent` body) — plan target met
- `invoke_agent ... "$(phase_is_writable` call sites: 6 (plan expected ≥5; one extra is the retry improvement)
- Hard-coded `"true"`/`"false"` as 5th positional: 0 — plan target met
- Each of the 5 distinct phase names (`compose`, `bounce`, `execute`, `execute-retry`, `review`) appears in the file as a `phase_is_writable <name>` argument

All plan assertions verified; the extra refactor site is a clean Rule 2 win.

## Verification Summary

```
bash -n lib/co-evolution.sh            → OK
bash -n dev-review/codex/dev-review.sh → OK
WRITABLE_PHASES= def count             → 1
phase_is_writable() def count          → 1
invoke_(claude|codex) call count       → 2 (dispatcher body)
invoke_agent ... phase_is_writable     → 6
invoke_agent ... "true|false" literal  → 0
bash /tmp/rnpt-01-02-smoke.sh          → RNPT-01/02 SMOKE: OK
```

## Known Stubs

None.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND
- `dev-review/codex/dev-review.sh` — FOUND
- Commit `cf59338` — FOUND
- Commit `fb2e142` — FOUND
- Smoke test: PASS (RNPT-01/02 SMOKE: OK)
