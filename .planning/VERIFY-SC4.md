# VERIFY-SC4: v1.2 Release-Gate Tracker

**Status:** Open — awaiting post-ship dogfood
**Blocks:** `git tag v1.2`
**Does NOT block:** Phase 8 closure (Phase 8 closes on SC-1, SC-2, SC-3, SC-5 per 08-CONTEXT.md §D-01)

## Purpose

Track the human-in-the-loop dogfood verification required by Phase 8 Success Criterion #4. The v1.2 git tag cannot ship until this rubric is satisfied. SC-4 exists because the whole v1.2 ship hypothesis — that PEL-emitted PRs are reviewable and useful in practice — can only be proven by actually reviewing some.

## Scope

**In scope:** Real PEL-emitted PRs produced by `co-evolve --lab pel-proposer --target <file>` during the v1.2 post-ship dogfood period. Draft PRs on `pel/<tier>/<short-hash>` branches created via `gh pr create --draft`.

**Out of scope:** Simulation-produced PRs (these are covered by SC-3 in `tests/pr-emitter-simulation.sh`); PRs on branches that don't match `pel/<tier>/<short-hash>` or explicit `--pr-branch NAME` overrides; PRs pre-dating Phase 8 merge to master.

## Rubric (verbatim from ROADMAP.md Phase 8 SC-4)

> **SC-4** — Human-in-the-loop dogfood: at least 3 real PEL-emitted PRs are reviewed by the user during v1.2 verification — at least 1 merged, at least 1 closed-without-merge — proving the review gate is real and the UX works.

**Concrete pass conditions:**

1. `review_count >= 3` — three or more distinct PR URLs logged below with a review decision.
2. `merged_count >= 1` — at least one PR merged to master.
3. `closed_without_merge_count >= 1` — at least one PR closed without merging (intentionally — either "not worth shipping" or `[CANARY-FAILED]` diagnostic).
4. The counts are checked against this file's Review Log table.

## Review Log

Update this table as PRs land during dogfood. Leave `outcome` as `pending` while review is in flight; update to `merged` or `closed` at resolution.

| # | PR URL | Tier | Opened | Reviewer | Outcome | Notes |
|---|--------|------|--------|----------|---------|-------|
| 1 | _[fill in during dogfood]_ | template/policy/code | YYYY-MM-DD | Alan | pending/merged/closed | _one-line takeaway_ |
| 2 | _[fill in during dogfood]_ | | | Alan | pending | |
| 3 | _[fill in during dogfood]_ | | | Alan | pending | |

**Rolling totals** (update whenever a row changes):

- `review_count` = **0** (count of rows with outcome ≠ `pending`)
- `merged_count` = **0** (count of rows with outcome = `merged`)
- `closed_without_merge_count` = **0** (count of rows with outcome = `closed`)

**Pass state:** ❌ (all three conditions must be ≥1 for the gate to flip to ✅)

## Canary-Failed PR Accounting (D-15)

Per 08-CONTEXT.md §D-15, a `[CANARY-FAILED]` PR IS a useful signal — it proves the canary catches bad mutations before a live rollout would. These PRs:

1. Count toward `review_count` (they were reviewed)
2. Count toward `closed_without_merge_count` (the expected outcome is close)
3. Do NOT count toward `merged_count`

If dogfood produces several `[CANARY-FAILED]` PRs and only `[CANARY-FAILED]` PRs, SC-4's `merged_count >= 1` may be hard to reach. The mitigation is: dogfood deliberately includes at least one "benign" target (a template or policy mutation that should pass canary and is expected to merge) once the code-tier is confirmed working.

## Dogfood Guidance

Recommended approach to collect ≥3 PRs efficiently:

1. **Template tier first** (`--target skills/dev-review/templates/*.md`) — no canary to trip; fast feedback; at least one should be mergeable.
2. **Policy tier second** (`--target lab/pel/proposer/policy/policy.yaml`) — constrained to the 6-knob surface; fitness-knob tweaks are easy to evaluate.
3. **Code tier third** (`--target lib/co-evolution.sh`) — canary is the safety rail; expect some `[CANARY-FAILED]` signal. One successful code-tier merge is strong evidence for the ship.

### Pre-flight checklist (run before each PEL invocation)

- [ ] Master is clean (`git status --short` returns empty)
- [ ] On master at the latest tip (`git pull origin master`)
- [ ] `claude` and `codex` CLIs authenticated (`claude --version` + `codex --version` both succeed)
- [ ] `gh` CLI authenticated and able to push (`gh auth status` shows logged in)
- [ ] `compute-guard` daily cap not exceeded (skip if not installed) — PEL invocations consume Haiku classifier + Opus proposer + Phase 2 scoring; budget several dollars per code-tier run
- [ ] No active PR backlog from prior dogfood runs (close stale PRs first to keep the review log clean)
- [ ] Working directory is the main `co-evolution` checkout, not a worktree

### Concrete candidate targets

Three named targets, one per tier — copy/paste the invocation, review the resulting PR, log the outcome in the table above.

| # | Tier | Target file | Why this target | Expected outcome | Invocation |
|---|------|-------------|-----------------|------------------|------------|
| 1 | template | `skills/dev-review/templates/review-prompt-opus.md` | Reviewer prompt has highest behavioral leverage; small wording tweaks measurably affect bounce convergence. Most likely to produce a mergeable diff. | Merge candidate | `co-evolve --lab pel-proposer --target skills/dev-review/templates/review-prompt-opus.md` |
| 2 | policy | `lab/pel/proposer/policy/policy.yaml` | Bounded 6-knob surface (retry caps, marker semantics, etc.) — proposer can only mutate known-safe knobs within documented bounds. Easy to evaluate. | Merge or close candidate | `co-evolve --lab pel-proposer --target lab/pel/proposer/policy/policy.yaml` |
| 3 | code | `lib/co-evolution.sh` (1072 LOC, all helpers) | Hardest tier; canary smoke-test is the safety rail. Mutation may pass canary and merge (strong signal) or trip canary and produce `[CANARY-FAILED]` PR (also a useful signal — proves the safety rail works). | Either outcome is dogfood-valid | `co-evolve --lab pel-proposer --target lib/co-evolution.sh` |

After each invocation: a draft PR appears at `pel/<tier>/<short-hash>` with the proposed diff + eval scores in the body. Review it, decide merge or close, update the Review Log table above.

### Realistic runtime expectations (revised 2026-04-20)

A single PEL invocation runs **~20-30 minutes** end-to-end under default parameters. Breakdown:

- Classifier (Haiku): ~30 sec
- Proposer (Opus 4.6): ~3-8 min
- Eval cache lookup or miss: instant or full bounce
- Scoring "before" (real bounce against unmutated target): ~5-10 min
- Scoring "after" (real bounce against mutated target): ~5-10 min
- Emitter PR rendering + `gh pr create`: ~30 sec

Budget **~90 minutes** for the full 3-PR dogfood cycle, not "a few minutes" as earlier wording implied. Run during a session where you can afford the wall-clock; don't kick off and walk away expecting completion in 15 min.

Cache hits on the "before" baseline (unchanged target = same hash) cut subsequent invocations on the same target by ~5-10 min, but cross-target invocations re-pay the full cost.

### Pre-invocation gotchas (collected from 2026-04-20 first dogfood run)

- **Eval report required.** Emitter hard-fails if neither `evals/reports/<ts>/raw-scores.json` exists nor `PEL_EVAL_REPORT` is set. Either run `bash evals/run-evals.sh` first, OR for testing set `PEL_EVAL_REPORT=tests/fixtures/pr-emitter/<tier>-feedback.json`. The error message documents both paths.
- **Opus model name drift.** The proposer adapter pins a specific Opus model. If your subscription doesn't have that model, the `claude -p` call hangs silently rather than erroring. Default is currently `claude-opus-4-6`; override via `PROPOSER_MODEL=<model-id>` env var.
- **Codex needed for nested-Claude workaround.** When invoking from inside Claude Code (e.g., orchestrating SC-4 from a session), wrap the bash command in `codex exec "..."` so the inner `claude` CLI calls aren't nested under Claude Code's authentication.

### Failure-mode quick reference

| Symptom | Meaning | Action |
|---------|---------|--------|
| Exit code 6 | Diff exceeded budget | Re-run; the proposer will retry with a tighter mutation |
| Exit code 7 with canary scenario name in stderr | Canary smoke-test caught a bad mutation | PR is created with `[CANARY-FAILED]` prefix — this counts toward `closed_without_merge_count` per D-15 |
| Exit code 10 | Hard infrastructure error (gh failed, sandbox setup failed) | Check `gh auth status`, verify worktree disk space; not a PEL bug |
| No PR created, exit 0 | Proposer found nothing worth mutating | Re-run against a different target; this is a valid outcome |

## Closure Policy

This file is closed when ALL THREE of these hold:
- `review_count >= 3`
- `merged_count >= 1`
- `closed_without_merge_count >= 1`

At closure:
1. Update the **Status** header line to `Closed — YYYY-MM-DD`.
2. Update the **Pass state** to ✅.
3. Proceed with `git tag v1.2` at the head of master.

This file does NOT block Phase 8 closure. Phase 8 closes when SC-1/2/3/5 pass — those are code + hermetic-simulation criteria verifiable at ship time. SC-4 is a release gate, not a phase gate (08-CONTEXT.md §D-01).

## Deferred From This Tracker

Not tracked here (intentionally):
- Dogfood telemetry aggregation — if ≥10 PRs land, consider adding a summary subsection; for ≥3 the table is sufficient.
- Auto-population by scripts reading `gh pr list`. Manual entry is cheap enough at this volume and keeps the gate human-owned.
- v1.3+ trigger evaluation — ROADMAP.md Deferred section captures those criteria separately.

---

**Last updated:** 2026-04-19 (created by Phase 8 Plan 03)
**Owner:** Alan
**Binding decisions:** 08-CONTEXT.md §D-01 (scope separation), §D-15 (canary-failed counting)
