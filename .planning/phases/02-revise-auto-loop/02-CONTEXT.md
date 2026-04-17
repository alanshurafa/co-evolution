# Phase 2: REVISE Auto-Loop - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous)

<domain>
## Phase Boundary

When the verify phase returns a REVISE verdict with issues, the runner automatically loops back through execute+verify, passing the reviewer's feedback into the next execute pass. Loop up to a configurable max-iterations guard. Record each pass in `state.json`. (RTUX-03)

</domain>

<decisions>
## Implementation Decisions

### CLI + Defaults
- New flag: `--revise-loop N` (integer, default 0 = feature disabled for backwards compatibility)
- New env var: `REVISE_LOOP_MAX` (takes effect if CLI flag not set)
- `N=0` → no auto-loop; single execute+verify, current behavior
- `N>=1` → on REVISE verdict, re-execute with feedback + re-verify, up to N extra attempts

### Loop Semantics
- Main flow detects REVISE verdict from `$VERDICT` (already parsed from verify JSON)
- If `VERDICT == "REVISE"` and `current_pass < REVISE_LOOP_MAX`:
  - Parse `issues` array from verdict JSON (reuse existing jq helpers)
  - Build an augmented execute prompt: original plan + reviewer feedback section
  - Run execute again (writable phase, per RNPT-02)
  - Run verify again
  - Record both phases in state.json as `execute-N` / `verify-N` (N = pass number)
- Loop terminates on:
  - `VERDICT == "APPROVED"` — success
  - `current_pass >= REVISE_LOOP_MAX` — capped, exit with REVISE exit code
  - Execute or verify fatal error — exit with that error

### Prompt Assembly
- Reuse existing `build_execution_prompt` but add an optional `{REVISE_FEEDBACK}` placeholder
- Construct feedback block as: "## Reviewer Feedback (prior pass)\n\n{issues_json_pretty}\n\nAddress each issue, then apply the plan."
- Only inject feedback when `current_pass > 1`

### State.json Schema
- Existing `phases[]` array gets new entries per loop pass
- Name scheme: `execute-1`, `verify-1` for first pass; `execute-2`, `verify-2` for second; etc.
- First pass keeps existing names `execute` / `verify` (no breaking change to consumers); numbered suffixes only from pass 2 onward

### Claude's Discretion
- Whether to loop-detect marker-count stability (skip pointless re-runs where no new info)
- How to format `issues` in the feedback block (flat vs nested markdown)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$VERDICT` is already captured from `run_verify_phase` (via eval of JSON parse)
- `write_state_phase` helper exists; supports arbitrary phase names (from Phase 7 RNPT-04)
- `build_execution_prompt` template at `skills/dev-review/templates/dev-prompt-*.md`
- The execute+verify block in main flow is at `dev-review/codex/dev-review.sh:1047-1074`

### Established Patterns
- CLI flags parsed inline in option-parsing block (earlier in main flow)
- Env-var fallback pattern already exists for `PHASE_TIMEOUT` / `CODEX_MODEL`
- State updates via `write_state_phase` + `write_state_field`

### Integration Points
- `dev-review/codex/dev-review.sh` — main flow (around line 1047+ execute block)
- `lib/co-evolution.sh` — if any new helper needed (e.g., `build_revise_feedback`)

</code_context>

<specifics>
## Specific Ideas

**Backwards compatibility:** default `--revise-loop 0` preserves current single-pass behavior exactly. Nobody who doesn't opt in sees any change.

**Test:** simulated REVISE verdict (mock verify that returns REVISE once then APPROVED) should trigger one extra pass and succeed on pass 2.

**State.json consumers (Phase 8 evals):** ensure eval scorer can handle `execute-N`/`verify-N` phase names — or document that it should treat them as additional attempts, not new phases.

</specifics>

<deferred>
## Deferred Ideas

- Loop with human checkpoint between passes — v1.2+
- Reviewer-driven marker injection (fewer markers in revise → faster convergence) — v1.2+
- Max-iterations derived from verdict confidence — future

</deferred>
