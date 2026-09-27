# Phase 3: Visible Live Mode - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous)

<domain>
## Phase Boundary

Give the runner a `--live` CLI flag. When set on Windows, each agent invocation (compose, bounce, execute, verify) runs in a new visible Windows Terminal window so the user can watch the bouncer/executor in real time. Main runner still waits for completion and records `state.json` normally. On non-Windows environments, `--live` logs a warning and falls back to inline execution. (RTUX-01)

</domain>

<decisions>
## Implementation Decisions

### CLI + Defaults
- New flag: `--live` (boolean, default off)
- New env var: `LIVE_MODE=true` (if CLI flag not set)
- Default off = no behavior change for existing callers

### Platform Detection
- Windows detection priorities (first match wins):
  1. `$OSTYPE == msys*` or `cygwin*` — Git Bash / MSYS / Cygwin
  2. `command -v wt.exe` available — Windows Terminal installed
  3. Fallback: `command -v cmd.exe` — always available on Windows
- On non-Windows: log warning "`--live` is Windows-only, falling back to inline execution" and proceed normally (no error)

### Invocation Strategy
- Wrap the per-agent call (currently `invoke_agent` → `invoke_claude` / `invoke_codex`) with a live-window launcher when `LIVE_MODE=true`
- Prefer `wt.exe new-tab --title "phase:<name>" bash -c '<invoke command>'` when available
- Fall back to `cmd.exe /c start "phase:<name>" cmd /k bash -c '<invoke command>'` (keeps window open after exit)
- Keep main runner synchronized — the launcher command should BLOCK until the invoked process exits (use `--startup-tab 0` or wait mechanism), so state.json records accurate timestamps
- Alternatively (simpler): just tail the stderr/stdout file in a new window while the phase runs inline
  - Launch `wt.exe new-tab --title "phase:<name> output" bash -c 'tail -f <stderr_file>'` as a side effect
  - Main runner keeps inline invocation (no IPC complexity)
  - Tail window auto-close on phase complete: hard (tail -f doesn't exit); acceptable to leave it open for user review

### Recommended: tail-window approach (simpler, safer)
- Main runner invokes agent inline as today (no IPC, no exit code forwarding)
- When `LIVE_MODE=true`: before invoke, launch a detached `wt.exe` / `cmd.exe` window that runs `tail -f <stderr_file>` (stdout_file if applicable)
- After invoke, send a sentinel to the window (e.g., write "### PHASE COMPLETE ###" to the stderr file) so the tailing user sees the end
- Window stays open; user closes manually or it auto-closes on next phase if we choose to wire that up
- This is additive: if the launch fails, inline execution still completes correctly

### Per-Phase Wrapping
- Wrap only these phases: compose, bounce (per pass), execute, verify
- Skip wrapping: retry passes (already noisy), state-update phases
- Decision: add `maybe_launch_live_window <phase-name> <stderr_file>` helper, call it before each agent invocation

### Windows-Specific Paths
- `wt.exe` may not be on PATH in all Windows shells (Git Bash picks it up, cmd.exe direct path)
- Under WSL: `cmd.exe /c wt.exe ...` works
- Absolute path fallback: `"$WINDIR/System32/cmd.exe"` or `"$LOCALAPPDATA/Microsoft/WindowsApps/wt.exe"`

### Claude's Discretion
- Whether to show stdout or stderr in the tail window (stderr catches more interesting data — agent invocations redirect progress there)
- Whether to wrap bounce passes or just the outer bounce phase (inner pass visibility is higher value if one bounce is slow)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `invoke_agent` is the central dispatcher (since Phase 7 RNPT-01) — one place to add the live-window launch
- `$LIVE_MODE` will join other CLI-parsed globals (`VERIFY`, `PLAN_ONLY`, etc.)
- stderr file paths already standardized: `$RUN_DIR/<phase>-stderr.log`, etc.

### Established Patterns
- CLI flag parsing inline in main option-parsing loop
- Platform detection already exists for WSL via `WSL_DISTRO_NAME` check
- `log` function handles all user-visible output

### Integration Points
- `dev-review/codex/dev-review.sh` — option parser + wrap point inside `invoke_agent` OR as a hook before each phase
- `lib/co-evolution.sh` — new helper `maybe_launch_live_window` lives here

</code_context>

<specifics>
## Specific Ideas

**Must-not-break invariant:** when `--live` is absent, behavior is bit-identical to v1.0. All live-mode code lives behind a `[[ "$LIVE_MODE" == "true" ]]` guard.

**Must-not-block invariant:** if live-window launch fails (wt.exe missing, permissions denied, etc.), main runner logs a warning and continues inline. No phase ever fails because of live-mode.

**Testability:** include a smoke test that sets `LIVE_MODE=true` on a non-Windows simulated env (or just with `wt.exe`/`cmd.exe` stubbed) and confirms:
1. Warning logged, execution proceeds inline
2. No state.json corruption
3. No hanging processes

</specifics>

<deferred>
## Deferred Ideas

- Interactive controls in live window (pause, skip, abort) — v1.2+
- Multi-phase parallel live windows — v1.2+
- Terminal-agnostic live mode (iTerm, kitty, tmux split) — future, needs design

</deferred>
