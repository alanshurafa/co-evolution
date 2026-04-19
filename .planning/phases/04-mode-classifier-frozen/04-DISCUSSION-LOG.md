# Phase 4: Mode Classifier (frozen) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 04-mode-classifier-frozen
**Areas discussed:** Invocation surface, Haiku call path
**Areas locked by documented default:** Output format, Frozen-surface mechanics

---

## Pre-discussion: decisions already locked by prior artifacts

Before the interactive discussion, the following decisions were pre-locked by ROADMAP.md SC-1..SC-5, `.planning/notes/pel-design-decisions.md`, Phase 3 artifacts, and user memory — and surfaced to the user as "carrying forward" rather than re-asked:

- Four flavors: `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` (ROADMAP SC-1, pel-design-decisions.md §1)
- Haiku 4.5 default (`claude-haiku-4-5-20251001`); Opus fallback documented-but-off (ROADMAP SC-2)
- Classifier frozen in v1.2 — not part of PEL's mutable surface (ROADMAP SC-4, PROJECT.md Key Decisions)
- `--flavor <name>` override exists and takes precedence (ROADMAP SC-3)
- Single-argv W-3 contract from Phase 3 must be honored, not modified (lab/README.md + both runners grep-anchored)
- Prompt caching assumed as infrastructure, not stretch goal (user memory `future_tools.md`)

## Pre-discussion: user preamble decided statelessness

User's opening message: *"The pattern-carrying argument is real but weaker than it looks — SUMMARY.md files capture it explicitly. That's their job."*

This resolved a latent gray area (classifier-as-stateful-vs-stateless) before formal discussion. Captured as D-01 in CONTEXT.md without an AskUserQuestion round.

---

## Gray area selection

Four candidate areas were identified from codebase scouting and phase analysis:

1. Invocation surface (how task + bounce-step + phase-type flow in given W-3)
2. Haiku call path (self-contained adapter vs extend runner invoke_claude vs inline)
3. Output format (JSON stdout vs text vs artifact file)
4. Frozen-surface mechanics (prompt location, --flavor bypass, error behavior, frozen anchor)

**User selection:** "Other" → asked for a recommendation first.

**Recommendation delivered:** discuss areas 1 and 2 (architectural — change code across Phases 5-8); lock areas 3 and 4 via documented defaults (obvious choices from codebase patterns). User accepted.

| Area | Decision mechanism |
|------|-------------------|
| Invocation surface | Discussed interactively |
| Haiku call path | Discussed interactively |
| Output format | Locked by default — JSON to stdout, diagnostics to stderr |
| Frozen-surface mechanics | Locked by default — prompt in separate file, `--flavor` bypasses Haiku, fail-fast on error, path-based allowlist anchor |

---

## Invocation surface

**Question:** The classifier needs three inputs (task, bounce-step, GSD-phase-type). The task comes in as the one argument the Phase 3 rule allows. How do the other two reach it?

| Option | Description | Selected |
|--------|-------------|----------|
| Environment variables (Recommended) | `PEL_BOUNCE_STEP` / `PEL_PHASE_TYPE` set by caller; `$1` = task. Preserves W-3. Matches 5 existing env-var precedents (`LIVE_MODE`, `DEV_REVIEW_BRANCH`, `DEV_REVIEW_WORKTREE`, `PHASE_TIMEOUT`, `COMPOSER`/`EXECUTOR`/`REVIEWER`/`CODEX_MODEL`). | ✓ |
| Shell library function | Classifier is a sourced function the proposer calls directly (`classify_flavor task step type`). Cleaner argument passing, but introduces a second kind of lab inhabitant (sourced vs exec'd), splitting Phase 3's dispatch model. | |
| Bend W-3 to multi-argv | Let dispatch pass multiple argv positions. Simplest code, but undoes Phase 3 Plan 02's grep-anchored pin and widens the argv surface for every future lab inhabitant. | |

**User's path to decision:** Asked for pros/cons grounded in existing repo patterns (and explicitly considered co-evolving the decision). Accepted the env-var option after the cross-repo pattern analysis showed 5 existing precedents and zero precedents for the alternatives.

**Reflected-back clarifications captured in D-03 / D-04:**
- `PEL_BOUNCE_STEP` value domain: `{compose, bounce, execute, verify, unknown}`
- `PEL_PHASE_TYPE` value domain: `{scoping, implementation, verification, unknown}`
- Unset = `unknown` (degrades gracefully — not an error)
- Unexpected values log a `WARNING` to stderr and fall back to `unknown`, do NOT die
- Env var stickiness is a real risk — mitigated by having the proposer (Phases 5-8) explicitly export per call, not relying on inheritance

---

## Haiku call path

**Question:** Where does the code that actually talks to Haiku 4.5 live?

| Option | Description | Selected |
|--------|-------------|----------|
| Self-contained adapter in `lab/pel/classifier/` (Recommended) | A small `adapter.sh` owns the Haiku call. Zero dependency on `dev-review/codex/dev-review.sh`'s `invoke_claude` or `lib/co-evolution.sh` runner helpers. Matches Phase 3's lab-isolation principle. | ✓ |
| Extend the main runner's `invoke_claude` with `--model` | Reuse existing adapter. Less duplication, but lab code now depends on runner internals — future lab inhabitants wanting a different adapter either go through shared path or break the pattern. | |
| Inline `claude` call in `entry.sh` | Simplest. No natural home for retries / token logging / cache-tracking if later needed. | |

**User's choice:** Self-contained adapter, selected directly without additional back-and-forth.

**Reflected-back clarifications captured in D-05 / D-06 / D-07:**
- Model ID hardcoded `claude-haiku-4-5-20251001` with `CLASSIFIER_MODEL` env var escape hatch (satisfies ROADMAP SC-2 without needing a dedicated CLI flag)
- Fail-fast on any Haiku failure (missing CLI, auth, rate-limit, malformed response) — lab code must not mask signal

---

## Claude's Discretion

Locked in CONTEXT.md §Decisions → "Claude's Discretion":

- Exact prose of the Haiku classifier prompt (flavor descriptions, few-shot examples, rationale-length cap)
- Prompt-cache anchor placement within `prompt.md`
- Exact adapter exit codes
- Simulation test file location and layout
- Whether to publish `lab/pel/README.md` now or defer to Phase 5

## Deferred Ideas

Captured in CONTEXT.md §Deferred:

- Run-and-log-for-comparison on `--flavor` override (useful only if classifier evolution reaches the roadmap — v1.3+)
- Dedicated `--model` CLI flag on the classifier
- Prompt cache hit/miss telemetry
- Classifier evolution (PEL-META-01)
- Multi-inhabitant lab patterns (sourced vs exec'd)

---

*Phase: 04-mode-classifier-frozen*
*Discussion completed: 2026-04-18*
