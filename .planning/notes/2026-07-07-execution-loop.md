# Execution Loop — 2026-07-07 Improvement Plan

**Plan:** `.planning/notes/2026-07-07-audit-improvement-plan.md` (phases A–F)
**Orchestrator:** Fable session (this file is its working memory; any fresh session resumes from here)
**Authority:** Alan approved autonomous execution incl. Phase E spend (2026-07-07). Hard stops: public publishing (F.2/F.3), anything under `runners/codex-ps/**`, and any git operation that rewrites master history.

## GOAL

All six phases (A–F) merged to master with green 3-OS CI, every phase's done-means checklist independently verified, and the Phase E measurement numbers (κ judge-vs-gold, inter-judge κ, position-bias flip rate, self-consistency rate, canary catch rate, A/B verdict vs its pre-registered criterion) recorded in this file and in `evals/` docs. Terminal state: Phase F publishing artifacts staged and presented to Alan for the one remaining gate.

## LOOP

Repeat until GOAL or a hard stop:

1. **Pick** the next phase whose dependencies are merged (order: A → B → C ∥ D → E → F).
2. **Build wave** — decompose the phase into worker briefs (Goal / Scope / Contract / Done-means, per repo Token Discipline); fan out parallel agents with disjoint file ownership; workers on opus for bash surgery, sonnet for docs/tests, `codex exec` for mechanical sweeps.
3. **Verify wave** (independent of builders — no agent verifies its own work):
   a. `bash tests/run-all.sh` in an isolated subagent (summary only reaches the loop).
   b. Claude adversarial review of the phase diff (adversarial-reviewer agent).
   c. gpt-5.5 cross-vendor review of the same diff (`codex exec -s read-only`) — the repo's own philosophy applied to its own PRs; reviewer disagreements are surfaced, not averaged.
   d. Done-means checklist from the plan, checked item-by-item by a non-builder agent.
4. **Fix loop** — findings from (3) go back to a build agent; one retry with a tighter brief, then escalate to the orchestrator itself. Max 3 fix cycles per phase before the phase is marked BLOCKED here and the loop moves to any non-dependent phase.
5. **Land** — commit (imperative, <72 chars), push branch, open PR citing this file's SHA, wait for 3-OS CI (background monitor, no polling), **merge on green** (pre-authorized), delete branch.
6. **Record** — update the Progress and Measurements sections below; capture lessons to ExoCortex; if context is near compaction or ~2h elapsed, write handoff notes here and continue in a fresh session reading this file.
7. **Regression watch** — after each merge, rerun the full suite on master once and append the result to the trend table. A red master halts the loop and fixes forward immediately.

Loop mechanics: background agents re-invoke the orchestrator on completion (no polling); a ScheduleWakeup heartbeat (~25 min) survives hangs. This file is the single source of truth — sessions are disposable, the loop is not.

## Verification additions (beyond the plan's per-phase done-means)

- **V-1 Cross-vendor PR review** on every phase (loop step 3c) — added because the audit's headline defect (C-1) was a single-reviewer blind spot on a "finished" fix.
- **V-2 Live smoke per protocol-touching phase** (A, C, D): one real, minimal, non-stubbed run (`--bounces 1`, tiny doc; or one dev-review verify on a 5-line diff) — stub-fidelity gaps have bitten this repo twice; hermetic green is necessary, not sufficient. 💰-tiny, codex-guard-capped.
- **V-3 Self-referential dogfood gate** (Phase C done-means, kept prominent): the tool must bounce its own BOUNCE-PROTOCOL.md without tripping the honesty gate; the run becomes a permanent sim fixture.
- **V-4 Sneaky-canary verifier calibration** (Phase E.4): planted plausible-but-wrong diffs; catch rate is the standing rubber-stamp metric.
- **V-5 Pre-registration** (Phase E.3): the A/B success criterion is written into the run manifest before any run executes.
- **V-6 Master trend table** (below): scorer values per merge, so drift is visible across the whole campaign, not just within a phase.

## Progress

| Phase | Status | Branch / PR | Verify (suite / adv / codex / done-means) | Notes |
|-------|--------|-------------|-------------------------------------------|-------|
| A — Correctness closure | PR #47 open, suite 32/32, awaiting CI → merge | claude/nervous-hodgkin-bcf03d → PR #47 | ✓32/32 / ✓(F1 fixed) / ✓(H1,H2,L1 fixed) / ✓ | Cross-vendor review earned its keep: codex found the partial-failure→converged gap (H1) and both vendors independently flagged the bare-banner auth gap (H2→`output_is_auth_failure` in lib, 3 call sites). Claude reviewer caught the Scenario-F grep regression (F1) + missing guard scenario (→Scenario G). Bonus find-along: bounce-scorer-verification.sh had a Windows jq-CRLF bug (5/7→7/7, fixed) before wiring into run-all (C-5). Accepted residual: none remaining — F2/H2 fixed. Sims: auth-gate 28/28, marker-lifecycle 41/41 (byte-parity intact), audit-hardening 18/18, worktree-mgmt green, reliability 17/17. |
| B — Robustness/injection | pending | | | |
| C — Protocol v0.2 | pending | | | includes docs sweep + STACK.md re-check |
| D — Signal quality | pending | | | can start once C's marker changes are stable |
| E — Measurement | pending | | | panel-labeled gold set; spend approved |
| F — Learning loop + distribution | pending | | | F.2/F.3 publishing = HARD STOP for Alan |

## Measurements

| Metric | Value | Date | Source |
|--------|-------|------|--------|
| Inter-judge κ (fable-5 vs gpt-5.5, gold set) | – | | E.1 |
| Judge-vs-gold κ (judge-bounce.sh) | – | | E.2 |
| Position-bias flip rate | – | | E.2 |
| Self-consistency (3-run agreement) | – | | E.2 |
| Verifier canary catch rate (n=3) | – | | E.4 |
| A/B: cross- vs same-vendor (pre-registered criterion) | – | | E.3 |
| Master suite trend | baseline: 27 sims + scorer gate green @ 05d151e | 2026-07-07 | V-6 |

## Handoff notes

(none yet)
