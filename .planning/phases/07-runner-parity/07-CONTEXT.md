# Phase 7: Runner Parity - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous, infrastructure phase — parity port)

<domain>
## Phase Boundary

Port the 5 features the Bash runner (`dev-review/codex/dev-review.sh` + `lib/co-evolution.sh`) lacks relative to the Codex PS reference implementation at `runners/codex-ps/scripts/run-co-evolution.ps1`. Goal is that both runners can pass the same eval case suite after Phase 8 lands the eval harness.

The features:
1. **Agent dispatcher pattern** (RNPT-01) — one function routes by provider; phase code calls a single entrypoint
2. **Writable-phase flag as top-level abstraction** (RNPT-02) — builds on Phase 6's threading, makes it a first-class runner concept
3. **Delta tracking with baseline snapshot** (RNPT-03) — pre-execute file hashes; post-execute `{modified, added, deleted}` delta
4. **Structured state.json per run** (RNPT-04) — phase history, marker counts, changed files, verify verdict as ground truth
5. **Per-phase timeout** (RNPT-05) — upstream's "single most painful gap" (one PS case hung 1h 39min)

</domain>

<decisions>
## Implementation Decisions

### Agent Dispatcher (RNPT-01)
- Build on `invoke_agent()` (already exists at `dev-review/codex/dev-review.sh:79-104` from Phase 6) — promote this to the single public entry point
- Caller code should be `invoke_agent "$PROVIDER" "$prompt_file" "$output_file" "$stderr_file" "$writable"` — no more direct `invoke_claude`/`invoke_codex` calls outside the dispatcher
- Acceptance: `grep -c 'invoke_claude\|invoke_codex' dev-review/codex/dev-review.sh` only matches the dispatcher itself (≤2 occurrences, both inside `invoke_agent`)

### Writable-Phase Flag (RNPT-02)
- Already threaded in Phase 6 — this phase makes it authoritative. Add explicit `WRITABLE_PHASES=(execute fix)` array and a helper `phase_is_writable(phase_name) -> bool`
- Each call site derives writable from the phase name, not hard-coded strings
- Acceptance: no "false"/"true" literals passed directly to `invoke_agent` — all derived from `phase_is_writable`

### Delta Tracking (RNPT-03)
- Pre-execute: hash every tracked file via `git ls-files | xargs git hash-object` (or equivalent for non-git workdirs — fall back to `find + sha256sum`)
- Store baseline as `state.json#baseline_hashes` (path → sha)
- Post-execute: same hash pass; produce `{modified: [paths], added: [paths], deleted: [paths]}` delta
- Write to `state.json#execute_delta`
- Acceptance: delta matches `git status --porcelain` equivalent when workdir is a git repo

### State.json (RNPT-04)
- One JSON file per run at `$RUN_DIR/state.json`
- Schema:
  ```json
  {
    "run_id": "dev-review-YYYYMMDD-HHMMSS",
    "task": "...",
    "composer": "codex",
    "executor": "codex",
    "reviewer": "opus",
    "phases": [
      {"name": "compose", "started_at": "...", "completed_at": "...", "status": "ok|timeout|error", "exit_code": 0},
      {"name": "bounce-1", ...},
      {"name": "execute", ...},
      {"name": "verify", ...}
    ],
    "marker_counts": {"contested": 0, "clarify": 0},
    "baseline_hashes": {"path/to/file": "sha256..."},
    "execute_delta": {"modified": [], "added": [], "deleted": []},
    "verify_verdict": "APPROVED|REVISE|null",
    "started_at": "2026-04-17T...",
    "completed_at": "2026-04-17T..."
  }
  ```
- Use `jq` for JSON manipulation (already a reasonable shell dependency); if `jq` unavailable, use inline bash with `printf` + careful escaping
- Incremental writes after each phase completes (not atomic, but recoverable from a crash mid-phase)

### Per-Phase Timeout (RNPT-05)
- Use bash `timeout` command (coreutils — universally available in Git Bash) wrapped around each `invoke_agent` call
- Default: 1800s (30 min) per phase — generous but prevents the 1h 39min hang upstream saw
- Configurable via `--timeout SECONDS` flag or `PHASE_TIMEOUT` env var
- If phase times out: record `{"status": "timeout", "exit_code": 124}` in state.json and abort the run with clear error
- Acceptance: simulated hang (use `sleep 9999` as a mock) must be killed within timeout window, state.json records timeout

### Claude's Discretion
- Exact order of the 5 tasks / split into plans — planner decides (likely 2-3 plans based on cohesion)
- Whether to use `jq` vs inline JSON — favor `jq` if available (check with `command -v jq`)
- How to structure the hashing pass — single helper `snapshot_workdir_hashes` that returns JSON

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `invoke_agent()` dispatcher (dev-review.sh:79-104) — already exists from Phase 6, just needs to be THE entry point
- `$RUN_DIR` already exists per run (dev-review.sh uses `runs/<run-id>/` structure)
- Phase 6 Task 06-01 Task 1 added the writable flag threading — RNPT-02 builds directly on this

### Established Patterns
- Phase artifacts go under `$RUN_DIR` (e.g., `compose-stderr.log`, `outputs/bounce-NN.txt`)
- Bash strict mode (`set -euo pipefail`) is the baseline; new helpers should respect this
- `cleanup_runtime_artifacts` already exists — state.json should NOT be cleaned (it's the permanent record)

### Integration Points
- `dev-review/codex/dev-review.sh` — main runner, all phase runners live here
- `lib/co-evolution.sh` — shared helpers (existing); new helpers (snapshot_workdir_hashes, phase_is_writable, etc.) go here
- `$RUN_DIR/state.json` — new artifact

</code_context>

<specifics>
## Specific Ideas

**Per-phase timeout is the highest-priority feature** per upstream: "the single most painful gap — one case stuck 1h 39min on a Claude hang." If any feature gets a retry test, it should be timeout.

**Delta tracking should NOT exclude any paths** — the scorer wants truth ground. Gitignored files that are modified (shouldn't happen but could) should still show in delta.

**state.json must be machine-readable** — Phase 8 eval scorer reads this. Use standard ISO-8601 timestamps, UTF-8, `null` instead of empty string where appropriate.

</specifics>

<deferred>
## Deferred Ideas

- Bash port of PS eval harness (`run-evals.ps1`, etc.) — deferred post-milestone (~2 days)
- Cross-runner eval report format comparison — deferred to Phase 8
- Streaming `state.json` updates (currently write after each phase) — deferred; incremental-write is sufficient for now

</deferred>
