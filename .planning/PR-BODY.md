## Summary

v1.2 **Protocol Evolution Loop — Proposer Only** ships the Option 1 vehicle: `co-evolve --lab pel-proposer --target <file>` picks a flavor, mutates against the correct tier (template / policy / code), scores before/after under an eval cap, and drafts a PR with eval deltas in the body. 8 phases, 129 commits. Byte-parity invariant locked for non-`--lab` paths (SC-5).

## Phases shipped

| Phase | What | Shipped | Commits |
|-------|------|---------|---------|
| 1 Post-v1.1 Fixes | WR-04/05 from v1.1 review | 2026-04-17 | 5 |
| 2 Bash Eval Harness Port | PowerShell → Bash, 13/13 scorer-verification green | 2026-04-18 | 4 |
| 3 Lab Scaffold | `lab/` dir + `--lab` wiring + 4-scenario routing sim | 2026-04-18 | 2 |
| 4 Mode Classifier (frozen) | 4 flavors, transparent rationale, 6/6 sim | 2026-04-18 | 12 |
| 5 Template-Tier Proposer | `skills/dev-review/templates/*.md`, 8/8 sim | 2026-04-18 | 11 |
| 6 Policy-Tier Proposer | 6 enumerated YAML/JSON knobs, 8/8 sim | 2026-04-18 | 11 |
| 7 Code-Tier Proposer | `lib/co-evolution.sh` + runners, sandbox + canary + file allowlist, 16/16 sim | 2026-04-18 | 13 |
| 8 PR Emission + Scoring | full pipeline + `gh pr create --draft`, 10/10 SC-3 sim | 2026-04-19 | 37 |

(Total 95 phase-tagged commits; remaining are chore/docs/state.)

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
- **Code review** post-execution: 1 critical + 8 warning + 6 info. All 15/15 applied across 14 atomic commits; sims stayed green throughout (REVIEW.md + REVIEW-FIX.md in `.planning/phases/08-pr-emitter-scoring/`).
- **Regression gate** — 48/48 scenarios green across Phases 4/5/6/7/8 simulations.
- **Verification** — 5/5 must-haves verified. SC-4 (human dogfood) scope-separated to post-ship per Phase 8 `CONTEXT.md §D-01`, tracked in [.planning/VERIFY-SC4.md](.planning/VERIFY-SC4.md).
- **Byte-parity invariant (SC-5)** — Scenario I confirms non-`--lab` invocations are byte-identical to v1.1.

## Out of scope / deferred

- **SC-4 human dogfood** — ≥3 real PEL-emitted PRs reviewed (≥1 merged, ≥1 closed-without-merge). Blocks `git tag v1.2`, does NOT block this PR.
- **Classifier evolution** (v1.3+) — classifier remains frozen-surface in v1.2 per Phase 4 invariant.
- **Workspace-agnostic PS ports** — v1.0 Phase 9 deferred item, still deferred.

## Remaining gates before `git tag v1.2`

1. `/gsd-secure-phase 8` — produce SECURITY.md
2. `/gsd-ship --review` — automated code review on this PR
3. VERIFY-SC4 dogfood — ≥3 PEL-emitted PRs reviewed per above

## Review guidance

- High-traffic paths: `lab/pel/pr-emitter/pr-emitter.sh`, `lab/pel/proposer/code/proposer.sh`, `lib/co-evolution.sh` (PEL wrapper flags), `evals/run-evals.sh` (Bash port).
- Simulation entry points: `tests/lab-routing-simulation.sh`, `tests/pr-emitter-simulation.sh`, `tests/code-proposer-simulation.sh`, `evals/tests/scorer-verification.sh`.
- Contract docs: `lab/pel/README.md`, `evals/README.md`.
