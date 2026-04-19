---
phase: 07-runner-parity
plan: 02
subsystem: runner-state
tags: [state-json, delta-tracking, hash-manifest, eval-ground-truth, RNPT-03, RNPT-04]
requires: [phase-06, 07-01]
provides: [per-run-state-json, pre-post-execute-delta, phase-8-ground-truth]
affects:
  - lib/co-evolution.sh
  - dev-review/codex/dev-review.sh
tech-stack:
  added: [jq (already present, now used for state writes)]
  patterns: [incremental-json-writes, hash-manifest-snapshot, jq-or-fallback]
key-files:
  created: []
  modified:
    - lib/co-evolution.sh
    - dev-review/codex/dev-review.sh
decisions:
  - state.json has no leading dot → survives cleanup_runtime_artifacts sweep
  - Intermediate hash manifests are dot-prefixed → swept automatically
  - Delta is sorted arrays (deterministic output for Phase 8 scorer)
  - Incremental writes (not atomic) — crash-mid-phase still yields a partial record
  - Plan-only exit path also records completed_at (run is terminated, not crashed)
  - Post-execute delta runs regardless of "no changes" branch (empty delta > missing field)
metrics:
  duration: 18min
  tasks_completed: 3
  commits: 2
  completed: 2026-04-17
requirements: [RNPT-03, RNPT-04]
---

# Phase 7 Plan 2: state.json + Delta Tracking Summary

One-liner: Added five helpers (`snapshot_workdir_hashes`, `compute_execute_delta`, `init_state_json`, `write_state_phase`, `write_state_field`) to `lib/co-evolution.sh` and wired them through every phase of `dev-review.sh` so each run now produces a machine-readable `$RUN_DIR/state.json` consumable as ground truth by Phase 8's eval scorer.

## What Landed

### Task 1: Five helpers in `lib/co-evolution.sh`

All appended after `parse_verdict`; all source-safe; jq-preferred with fallbacks:

| Helper | Purpose |
|--------|---------|
| `snapshot_workdir_hashes` | Walks `$workdir`, skips `.git/` + `runs/` + `.co-evolution/`, emits flat `{path: sha256}` JSON |
| `compute_execute_delta` | Baseline + current manifests → `{modified, added, deleted}` sorted arrays |
| `init_state_json` | Writes skeleton with run_id, task, agents, ISO-8601 started_at |
| `write_state_phase` | Appends phase entry with name/status/exit_code/timestamps |
| `write_state_field` | Generic jq-path setter: string/number/bool/null/rawfile |

Commit: `69d0350`

### Task 2: Nine state.json hook points in `dev-review.sh`

| # | Location | Purpose |
|---|----------|---------|
| 1 | Globals (line 28) | Declare STATE_JSON, BASELINE_HASHES_JSON, CURRENT_HASHES_JSON, EXECUTE_DELTA_JSON, RUN_ID |
| 2 | Run-setup (after PLAN_PATH) | `init_state_json` with run_id=dev-review-TIMESTAMP |
| 3 | Main flow (compose) | Start/end timestamps + `write_state_phase "compose"` |
| 4 | Main flow (bounce) | Start timestamp + marker-count writes after the loop |
| 5 | Inside `run_bounce_phase` loop | Per-pass `write_state_phase "bounce-NN"` with zero-padded NN |
| 6 | Inside `run_execute_phase` (pre) | `snapshot_workdir_hashes` → `.baseline_hashes` rawfile |
| 7 | Inside `run_execute_phase` (post) | `snapshot_workdir_hashes` + `compute_execute_delta` → `.execute_delta` rawfile |
| 8 | Main flow (execute) | Start/end timestamps + `write_state_phase "execute"` |
| 9 | Main flow (verify) | Timestamps + `write_state_phase "verify"` + `.verify_verdict` string |
| 10 | Before `cleanup_runtime_artifacts` | `.completed_at` ISO-8601 UTC |
| 11 | `--plan-only` exit branch | `.completed_at` recorded for terminated plan-only runs |

`cleanup_runtime_artifacts` itself was NOT modified — its existing `-maxdepth 1 -type f -name '.*'` guard already spares `state.json` (no leading dot). Intermediate `.baseline-hashes.json`, `.current-hashes.json`, `.execute-delta.json` are dot-prefixed so they get swept.

Commit: `f3bb0f5`

### Task 3: End-to-end simulation

`/tmp/rnpt-03-04-sim.sh` drives the full state.json lifecycle with no real agent calls:

1. Creates scratch workdir with a.txt/b.txt/c.txt
2. `init_state_json` → compose phase → bounce-01 phase → baseline snapshot
3. Mutates workdir (modify a, add d, delete c) → execute phase → delta computation
4. verify phase → APPROVED verdict → completion timestamp
5. Asserts full schema: phases length=4, phase names, ISO-8601 timestamps, delta arrays (a in modified, d in added, c in deleted, b untouched), baseline_hashes (3 files, no d.txt), marker_counts, verdict=APPROVED, completed_at format

Result: `RNPT-03/04 SIM: OK`

Also verified `cleanup_runtime_artifacts` does NOT delete `state.json` (tested with the exact `find ... -maxdepth 1 -type f -name '.*' -delete` pattern).

## Commit Chain

```
f3bb0f5  feat(07-02): wire state.json lifecycle into dev-review runner
69d0350  feat(07-02): add state.json + delta helpers
```

Both pushed to `feat/unification-absorb`.

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| RNPT-03 | Complete | Pre-execute `snapshot_workdir_hashes` called with baseline path; post-execute snapshot + `compute_execute_delta` emit sorted {modified/added/deleted} arrays; delta written to state.json via `rawfile` field. Simulation confirms all three categories populate correctly. |
| RNPT-04 | Complete | Every run writes `$RUN_DIR/state.json` with run_id, task, composer/executor/reviewer, phases[], marker_counts, baseline_hashes, execute_delta, verify_verdict, started_at, completed_at. Incremental writes per phase. Survives cleanup (no leading dot). |

## Schema Fields Populated Per Phase

| Phase | Fields Updated |
|-------|----------------|
| Run setup | run_id, task, composer, executor, reviewer, started_at (all via `init_state_json`) |
| compose | `phases[] += {name: "compose", status, exit_code, started_at, completed_at}` |
| bounce-NN (per pass) | `phases[] += {name: "bounce-01"|"bounce-02"|..., status, exit_code, started_at, completed_at}` |
| After bounce | `marker_counts.contested`, `marker_counts.clarify` |
| Pre-execute | `baseline_hashes` (rawfile) |
| Post-execute | `execute_delta` (rawfile with modified/added/deleted) |
| execute | `phases[] += {name: "execute", ...}` |
| verify | `phases[] += {name: "verify", ...}`, `verify_verdict` |
| Completion | `completed_at` |

## Deviations

**1. [Rule 2 - Defensive Guards] Added `[[ -n "${STATE_JSON:-}" ... ]]` guards around state writes inside `run_execute_phase` and `run_bounce_phase`.**

These helpers may theoretically be called before the main flow initializes `STATE_JSON`. Under `set -euo pipefail`, unset-var expansion would crash. The guards make the helpers safe to call in isolation (useful for testing) without changing the production path where `STATE_JSON` is always set by run-setup. Zero behavioral change in normal runs.

**2. [Rule 2 - Resilience] Post-execute delta runs even on the "no changes detected" branch.**

Plan specifies writing delta before the "no changes" check. Implemented as specified: snapshot + delta run first, then the `return 2` check. Rationale: Phase 8 scorer expects `.execute_delta` to exist in every state.json; an empty `{modified:[], added:[], deleted:[]}` is far better than a missing field.

**3. [Rule 2 - Lifecycle consistency] Added `write_state_field ".completed_at"` to the `--plan-only` exit branch.**

Plan specifies completion timestamp only at the main tail. Plan-only runs exit earlier and would leave `completed_at: null` — looks like a crash to the scorer. Added the timestamp write before cleanup on that branch too.

## Verification Summary

```
bash -n lib/co-evolution.sh            → OK
bash -n dev-review/codex/dev-review.sh → OK
5 helpers in lib/                      → all 1 each (5 total)
STATE_JSON var                         → OK
init_state_json call                   → OK
snapshot_workdir_hashes (pre+post)     → 2 calls
compute_execute_delta                  → 1 call
write_state_phase (compose/bounce/execute/verify) → all present
write_state_field (.verify_verdict/.completed_at/.marker_counts.*) → all present
cleanup_runtime_artifacts guard        → unchanged (state.json preserved)
ISO-8601 UTC format                    → 12 occurrences (plan: ≥7)
bash /tmp/rnpt-03-04-sim.sh            → RNPT-03/04 SIM: OK
state.json survives cleanup (real find)→ OK
```

## Known Stubs

None. All schema fields are populated at the appropriate lifecycle points.

## Self-Check: PASSED

- `lib/co-evolution.sh` — FOUND (5 new helpers present)
- `dev-review/codex/dev-review.sh` — FOUND (10 hook points present)
- Commit `69d0350` — FOUND
- Commit `f3bb0f5` — FOUND
- Simulation: PASS (RNPT-03/04 SIM: OK, full schema validated with jq)
- Cleanup preservation: VERIFIED (state.json survives `find -maxdepth 1 -type f -name '.*'`)
