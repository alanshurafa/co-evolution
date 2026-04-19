## Summary

v1.2 **Protocol Evolution Loop — Proposer Only** ships the Option 1 vehicle: `co-evolve --lab pel-proposer --target <file>` picks a flavor, mutates against the correct tier (template / policy / code), scores before/after under an eval cap, and drafts a PR with eval deltas in the body. 8 phases + 1 inserted fix phase, 150 commits. Byte-parity invariant locked for non-`--lab` paths (SC-5).

A ship-time cross-phase code review surfaced a runner↔scorer contract gap (4 warnings) that per-phase reviews couldn't see because every pre-ship Tier used `fake-runner.sh`. Phase 8.1 was inserted to close those warnings + land a real-runner Tier 4 regression barrier that prevents this class of drift going forward.

## Phases shipped

| Phase | What | Shipped | Commits |
|-------|------|---------|---------|
| 1 Post-v1.1 Fixes | WR-04/05 from v1.1 review | 2026-04-17 | 5 |
| 2 Bash Eval Harness Port | PowerShell → Bash, scorer-verification green | 2026-04-18 | 4 |
| 3 Lab Scaffold | `lab/` dir + `--lab` wiring + 4-scenario routing sim | 2026-04-18 | 2 |
| 4 Mode Classifier (frozen) | 4 flavors, transparent rationale, 6/6 sim | 2026-04-18 | 12 |
| 5 Template-Tier Proposer | `skills/dev-review/templates/*.md`, 8/8 sim | 2026-04-18 | 11 |
| 6 Policy-Tier Proposer | 6 enumerated YAML/JSON knobs, 8/8 sim | 2026-04-18 | 11 |
| 7 Code-Tier Proposer | `lib/co-evolution.sh` + runners, sandbox + canary + file allowlist, 16/16 sim | 2026-04-18 | 13 |
| 8 PR Emission + Scoring | full pipeline + `gh pr create --draft`, 10/10 SC-3 sim | 2026-04-19 | 37 |
| 8.1 Scorer/Runner Contract Wiring (INSERTED) | `evals/RUNNER-CONTRACT.md` spec + WR-01/02/03/04 fixes + Tier 4 real-runner regression barrier | 2026-04-19 | 13 |

(Total 108 phase-tagged commits; remaining are chore/docs/state.)

## Ship vehicle

`co-evolve --lab pel-proposer --target <file>` runs end-to-end:

1. **Classifier** (Phase 4) picks flavor: bug-catcher / faster / blind-spot / general
2. **Tier auto-detect** from `--target`: templates → template-tier, policy files → policy-tier, `lib/co-evolution.sh` + runners → code-tier
3. **Proposer** (Phases 5/6/7) generates candidate diff under the tier's rails
4. **Sandbox** — mutation applied in isolated worktree; `state.json` captured via git-shim
5. **Canary smoke-test** (code-tier only) before scoring
6. **Scorer** — second hermetic sandbox, eval-cached, `$25` before/after run cap
7. **PR body** rendered from `{{KEY}}` template with eval deltas
8. **`gh pr create --draft`** against master for human review

7 wrapper flags symmetric on both runners: `--target`, `--tier`, `--pr-branch`, `--dry-run`, `--budget`, `--yes`, `--flavor`.

## Quality gates

- **Plan bounce (claude ↔ codex)** caught 3 bugs in Plan 08-02 pre-execution: cache-key collision, policy-tier `git apply` on JSON delta, `set -u` crash in canary-failed path.
- **Per-phase code review (Phase 8)** — 1 critical + 8 warning + 6 info. All 15/15 applied across 14 atomic commits; sims stayed green throughout (REVIEW.md + REVIEW-FIX.md in `.planning/phases/08-pr-emitter-scoring/`).
- **Ship-time cross-phase review** — 0 critical + 4 warning + 5 info at `.planning/REVIEW-v1.2-ship.md`. The 4 warnings all clustered on one runner↔scorer contract gap invisible to per-phase reviews. Phase 8.1 inserted to close them.
- **Phase 8.1 plan-check** — 3 blockers + 6 warnings caught in iteration 1; all fixed in iteration 2; verification passed clean on iteration 2.
- **Regression gate** — 48/48 scenarios green across Phase 4/5/6/7/8 simulations + 14/14 on `scorer-verification.sh` (bumped from 13/13 by Phase 8.1's Tier 4 real-runner barrier).
- **Verification** — 5/5 Phase 8 must-haves verified. SC-4 (human dogfood) scope-separated to post-ship per Phase 8 `CONTEXT.md §D-01`, tracked in [.planning/VERIFY-SC4.md](.planning/VERIFY-SC4.md).
- **Byte-parity invariant (SC-5)** — Scenario I + Phase 8.1 regression check confirm non-`--lab`, no-`--run-dir` invocations remain byte-identical to v1.1.

## Out of scope / deferred

- **SC-4 human dogfood** — ≥3 real PEL-emitted PRs reviewed (≥1 merged, ≥1 closed-without-merge). Blocks `git tag v1.2`, does NOT block this PR.
- **`.changed_files` runtime population** (Phase 8.1 deferral) — structural shape satisfied (`[]` at init); runtime mirror from `execute_delta` deferred to 8.2 or SC-4 prep. Must land before the first real-agent eval round for non-trivial Execution Fidelity scoring.
- **5 Info findings from ship-time review** (IN-01 through IN-05) — deferred to v1.3 cleanup phase.
- **Contract-drift AST-aware lint** — Phase 8.1's Tier 4 grep-pin is the v1.2 poor-man's version; proper lint deferred to v1.3.
- **Classifier evolution** (v1.3+) — classifier remains frozen-surface per Phase 4 invariant.
- **Workspace-agnostic PS ports** — v1.0 Phase 9 deferred item, still deferred.

## Remaining gates before `git tag v1.2`

1. **Merge this PR** — code-complete + verified.
2. **Directory consolidation** — collapse 3 worktrees into canonical `Project/co-evolution/` per `.planning/notes/directory-consolidation.md`. Tracked as seed at `.planning/seeds/directory-consolidation-post-v1.2.md`.
3. **VERIFY-SC4 dogfood** — ≥3 PEL-emitted PRs reviewed per above.

`/gsd-secure-phase 8` (SECURITY.md) and a `/gsd-ship --review` pass were both superseded by the ship-time cross-phase review + Phase 8.1 regression barrier. If security review is still required by your release checklist, run `/gsd-secure-phase 8.1` on the 8.1 surface.

## Review guidance

- High-traffic paths: `lab/pel/pr-emitter/pr-emitter.sh`, `lab/pel/proposer/code/proposer.sh`, `lib/co-evolution.sh` (PEL wrapper flags + state-field helpers), `dev-review/codex/dev-review.sh` (contract writeback + `--run-dir`), `evals/run-evals.sh` (Bash port + `--run-dir` passthrough), `evals/score-run.sh` (scorer).
- Contract spec: [`evals/RUNNER-CONTRACT.md`](evals/RUNNER-CONTRACT.md) — shared runner↔scorer spec introduced in Phase 8.1.
- Simulation entry points: `tests/lab-routing-simulation.sh`, `tests/pr-emitter-simulation.sh`, `tests/code-proposer-simulation.sh`, `evals/tests/scorer-verification.sh` (14/14 — includes Tier 4 real-runner regression barrier).
- Contract docs: `lab/pel/README.md`, `evals/README.md`.
