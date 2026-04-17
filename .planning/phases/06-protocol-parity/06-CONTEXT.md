# Phase 6: Protocol Parity - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous, infrastructure phase — refactor of Claude adapter)

<domain>
## Phase Boundary

Bring the Bash runner's Claude adapter and verification layer in line with the MUST-items from `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (items 3-6; items 1-2 landed in P0). This is a refactor of existing code in `dev-review/codex/dev-review.sh` plus a template reconciliation under `runners/codex-ps/`. No new features, no new files (except possibly small helper logic).

</domain>

<decisions>
## Implementation Decisions

### Claude Adapter Tool Gating
- Text-producing phases (compose, bounce, review, arbitrate) MUST pass `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"` to `claude -p`
- Write-producing phases (execute, fix) MUST pass `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir <workdir>`
- NEVER pass `--json-schema` to Claude (confirmed broken on Windows in `-p` mode 2026-04-17)
- Rationale: upstream evals showed without these, Claude silently used its Write tool to "save the plan" and emitted empty stdout — runner captured garbage as the plan

### Structural Bounce Verification
- Verification layer MUST check for `outputs/bounce-NN.txt` files (or equivalent phase history entries `^bounce-\d+$`) to distinguish "bounce converged in 0 passes" from "bounce step was skipped entirely"
- Semantic signal (marker count → 0) alone is insufficient

### Bounce Protocol Reconciliation
- `runners/codex-ps/templates/bounce-protocol.md` is missing the main repo's stronger clauses ("You MUST output the COMPLETE document" + SCOPE CONTROL section)
- Reconciliation: overwrite the codex-ps copy with the main repo's version (from `skills/dev-review/templates/bounce-protocol.md`)
- Runners/codex-ps/ is flagged read-only per CXPS-02 BUT this one-time reconciliation is explicitly called out in the upstream message and is within scope for Phase 6

### Claude's Discretion
- How to structure the text-phase vs write-phase detection inside `run_compose_phase`, `run_bounce_phase`, `run_review_phase` — choose the least-invasive pattern (conditional flags assembled inline vs helper function)
- Where to add the structural bounce check (in the bounce loop end or in a post-run verification helper)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `dev-review/codex/dev-review.sh` already dispatches by `COMPOSER`/`REVIEWER`/`EXECUTOR` provider — adapter patterns exist
- `invoke_agent()` helper exists in `lib/co-evolution.sh` — likely the touch point for adapter changes
- `runners/codex-ps/` has the reference PS adapter patterns to mirror in Bash

### Established Patterns
- Bash compose prompt is built inline as a double-quoted string (see dev-review.sh:387+) — Phase 0 Required-Section blocks are already there
- Agent invocation is provider-dispatched; adding flags should flow through one function

### Integration Points
- `lib/co-evolution.sh` — shared helpers; Claude/Codex invocation logic
- `dev-review/codex/dev-review.sh` — phase runners (compose, bounce, execute, verify)
- `skills/dev-review/templates/bounce-protocol.md` — canonical source for reconciliation
- `runners/codex-ps/templates/bounce-protocol.md` — reconciliation target

</code_context>

<specifics>
## Specific Ideas

Upstream message `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` items 3-6 are the exact contract. Plans should cite items by number.

Specific flag patterns (verbatim from upstream):
- Text phase: `--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch"`
- Write phase: `--permission-mode bypassPermissions --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)" --add-dir <workdir>`
- Explicitly NOT: `--tools ""` (commander.js variadic eats next argument) or `--permission-mode plan` (silently produces empty stdout in -p mode)

</specifics>

<deferred>
## Deferred Ideas

- Agent dispatcher pattern (one function routes by provider) — deferred to Phase 7 RNPT-01
- Writable-phase flag as explicit parameter — deferred to Phase 7 RNPT-02
- Structured state.json — deferred to Phase 7 RNPT-04

</deferred>
