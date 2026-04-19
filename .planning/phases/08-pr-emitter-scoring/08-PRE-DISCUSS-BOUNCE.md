# Phase 8 Scope Stress-Test — Dialectic Analysis

## Q1: SC-4 as Gate vs Post-Ship Verify?

**Claude:** SC-4 is post-ship verification for Phase 8 closure because it depends on real human review cadence, not code completeness. Phase 8 should close when SC-1, SC-2, SC-3, and SC-5 pass. SC-4 should instead be tracked as release evidence: v1.2 should not be tagged until three real PEL-emitted PRs have been reviewed, with at least one merged and at least one closed without merge.

**Codex [CONFIRMED]:** This cleanly separates phase integrity from release integrity. Keeping Phase 8 open for weeks would blur engineering scope with human scheduling, but waiving SC-4 would make the release claim weaker than the roadmap promised. Track SC-4 in `VERIFY-SC4.md`; if dogfood reveals blocking defects, fix them before the v1.2 tag rather than reopening Phase 8 for bookkeeping.

**Convergence:** SC-4 is post-ship verify for Phase 8 closure and a release gate for the v1.2 tag.

---

## Q2: `--dry-run` Placement — Top-Level or Per-Proposer?

**Claude:** `--dry-run` should be a top-level `co-evolve` flag only. The wrapper sets `CO_EVOLVE_DRY_RUN=1`, prepends a stub `gh` binary earlier in `PATH`, and then runs the normal proposer flow. Proposers should not parse their own `--dry-run`; they should honor the env var anywhere they would trigger external side effects beyond assembling the PR body.

**Codex [CONFIRMED]:** This keeps the CLI simple while still exercising the real proposer path. The env var is the primary contract for suppressing non-`gh` side effects, and the PATH stub is a targeted safety net for `gh pr create`. SC-3 should explicitly verify that the stubbed `gh` resolves first under Git Bash/MINGW64.

**Convergence:** `--dry-run` is top-level only, implemented through `CO_EVOLVE_DRY_RUN=1` plus a PATH-shadowed `gh` stub. No per-proposer CLI flag.

---

## Q3: DEF-07-01 Fix Placement

**Claude:** Fix DEF-07-01 in Phase 8 Plan 01 as the first commit. The bug was known in Phase 7, but it becomes blocking only because Phase 8 depends on clean stdout for PR-body markdown. Reopening Phase 7 for a one-line redirect adds bookkeeping without improving ownership or traceability.

**Codex [CONFIRMED]:** Keep Phase 7 closed, reference DEF-07-01 in the Phase 8 commit, and immediately rerun the Phase 7 simulation suite after the redirect. The expected result is still 16/16; if anything fails, repair the sim harness before continuing.

**Convergence:** Fix DEF-07-01 in Phase 8 Plan 01 first, rerun the Phase 7 sim suite, and do not create a Phase 7.1.

---

## Q4: Tier Routing from `--target` to Proposer Choice

**Claude:** Choose auto-detect plus optional `--tier` override. For v1.2, auto-detect should use repo-specific path rules, not broad extension regexes: known template paths route to template, known policy paths to policy, and known shell/code paths to code. If the target has no rule, matches multiple tier rules, or a glob resolves across tiers, hard-error and require `--tier`.

**Codex [CONFIRMED]:** This satisfies SC-1 without false positives like `README.md`, and it keeps the heuristic small enough to test. `--tier` should be an escape hatch, not the default interface. When `--tier` is supplied for a single target, it wins; mixed-tier globs still hard-error because one invocation must stay within one proposer tier.

**Convergence:** Use auto-detect with `--tier` override. Auto-detect is path-rule based, and the wrapper hard-errors on no match, ambiguous match, or mixed-tier glob.

---

## Q5: Scoring Loop Compute Budget

**Claude:** Ship option (c): cache eval results and enforce a hard budget cap. The cache key should be the fixture content hash plus a hash of the executable eval scripts under `evals/`, so cache entries invalidate automatically when either the fixture or scoring logic changes. For v1.2, keep scoring reproducible: use the full fixture set within budget and do not rely on random sampling.

**Codex [CONFIRMED]:** Add `--budget` with a default hard cap of `$25` and exit code `6` on exhaustion. Show a preflight cost estimate only in interactive mode, using a checked-in pricing table, and allow `--yes` to skip the prompt. If subset scoring is needed later, require explicit fixture names rather than random sampling.

**Convergence:** Use cache plus a hard budget cap. Default to full-fixture scoring with a `$25` cap, exit `6` on exhaustion, and keep v1.2 deterministic by avoiding random sampling.

---

## Decision List for Phase 8 Discuss-Phase

- SC-4 is post-ship verification for Phase 8 closure and a release gate for the v1.2 tag; track it in `VERIFY-SC4.md`.
- `--dry-run` is a top-level wrapper flag only; set `CO_EVOLVE_DRY_RUN=1`, stub `gh` via `PATH`, and verify the stub resolves first on Git Bash/MINGW64.
- Fix DEF-07-01 in Phase 8 Plan 01 as the first commit, then rerun the Phase 7 simulation suite.
- Use auto-detect with optional `--tier` override; implement auto-detect with repo path rules and hard-error on no match, ambiguous match, or mixed-tier glob.
- Use cached evals plus a hard budget cap; cache by fixture hash plus executable eval-script hash, default budget to `$25`, exit `6` on exhaustion, and keep v1.2 scoring deterministic.

