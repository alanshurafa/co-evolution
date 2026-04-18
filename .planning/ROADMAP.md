# Roadmap: Co-Evolution

## Overview

Co-Evolution is a tooling repo for structured iterative refinement between AI agents and humans. The roadmap tracks milestone cycles; completed milestones are archived to `.planning/milestones/`.

## Completed Milestones

- [x] **v1.0 Unification Absorb** (shipped 2026-04-17) — Codex runtime foundation + absorbed private reference impl + eval harness + runner parity. 9 phases, 27 requirements closed. See [`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) · [`milestones/v1.0-SUMMARY.md`](milestones/v1.0-SUMMARY.md) · [`milestones/v1.0-REQUIREMENTS.md`](milestones/v1.0-REQUIREMENTS.md)
- [x] **v1.1 Polish & Ergonomics** (shipped 2026-04-17) — v1.0 code review fixes (WR-01/02/03) + runtime ergonomics (REVISE auto-loop, visible live mode, branch/worktree management). 4 phases, 6 requirements closed. PR [#2](https://github.com/alanshurafa/co-evolution/pull/2) · See [`milestones/v1.1-ROADMAP.md`](milestones/v1.1-ROADMAP.md) · [`milestones/v1.1-SUMMARY.md`](milestones/v1.1-SUMMARY.md) · [`milestones/v1.1-REQUIREMENTS.md`](milestones/v1.1-REQUIREMENTS.md)

## Active Milestone: v1.2 Protocol Evolution Loop — Proposer Only (2026-04-17)

**Goal:** Ship PEL Option 1 — an LLM-powered proposer that generates protocol-mutation PRs for human review, using the eval harness as fitness signal. PEL machinery lives entirely in `lab/pel/`; the default runner (`co-evolve`, `dev-review`) is unchanged for users who never invoke `--lab pel-proposer`. Accepted mutations merge to master and upgrade the default runner transparently.

- [ ] **Phase 1: Post-v1.1 Fixes** — Fold WR-04 (INITIAL_GIT_DIRTY timing in worktree mode) + WR-05 (missing `--` argv terminator on git commands) — avoids a separate v1.1.1 patch cycle
- [ ] **Phase 2: Bash Eval Harness Port** — Port `run-evals.ps1`, `score-run.ps1`, `compare-reports.ps1` to Bash; eliminate `pwsh` dependency; produce machine-readable eval reports consumable by PEL. Prerequisite for Phases 4+.
- [ ] **Phase 3: Lab Scaffold** — Create `lab/` directory + README documenting default/lab boundary, promotion flow, graduation criteria. First-class beta channel with clear identity.
- [ ] **Phase 4: Mode Classifier (frozen)** — `lab/pel/classifier/` picks flavor (bug-catcher / faster / blind-spot / general) per invocation with transparent rationale and user override. Classifier itself does NOT evolve in v1.2.
- [ ] **Phase 5: Template-Tier Mutation Proposer** — `lab/pel/proposer/template/` proposes diffs against `skills/dev-review/templates/*.md` driven by eval-failure signal. Safest first cut.
- [ ] **Phase 6: Policy-Tier Mutation Proposer** — `lab/pel/proposer/policy/` proposes YAML/JSON config-knob mutations (retry caps, marker-semantics, flavor weights). Composes with Phase 5 independently.
- [ ] **Phase 7: Code-Tier Mutation Proposer** — `lab/pel/proposer/code/` proposes diffs against `lib/co-evolution.sh` and runner paths. LLM-only (random mutation breaks shell). Hard safety rails: sandbox isolation, canary smoke-test before scoring, diff budget + file allowlist.
- [ ] **Phase 8: PR Emission + Scoring Integration** — `lab/pel/pr-emitter/` wraps Phases 4-7 as a single invocation: `co-evolve --lab pel-proposer --target <file>` picks flavor, mutates, scores, drafts PR with eval deltas in body. Exit — human reviews and merges. This IS the Option 1 ship.

## Phase Details

### Phase 1: Post-v1.1 Fixes
**Goal**: Address the two non-blocking warnings carried forward from the v1.1 code review so the codebase is clean before adding PEL's surface area.
**Depends on**: v1.1 shipped (master at tag `v1.1`)
**Requirements**: [FIX-WR-04, FIX-WR-05]
**Success Criteria** (what must be TRUE):
  1. `INITIAL_GIT_DIRTY` / `INITIAL_GIT_STATUS` are captured AFTER `WORKDIR` is reassigned in `--worktree` mode — verify phase no longer silently skips when parent is dirty AND worktree is clean
  2. `git worktree add` and `git checkout -b` calls in `lib/co-evolution.sh` include the `--` argv terminator so pathological path values (e.g., `--no-checkout`) are rejected as paths, not misinterpreted as flags
  3. Worktree-management simulation test extends to cover the dirty-parent + `--worktree auto` scenario, proving the fix
**Plans**: 1 plan

### Phase 2: Bash Eval Harness Port
**Goal**: Port the PowerShell eval harness to Bash so evals run without `pwsh`. This unblocks PEL's scoring loop on any platform the default runner supports.
**Depends on**: Phase 1
**Requirements**: [BASH-EVAL-01]
**Success Criteria** (what must be TRUE):
  1. `evals/scripts/run-evals.sh` (or `evals/bin/run-evals`) produces the same JSON report shape that the PS harness produces, verified by diff against PS output on at least 3 reference cases
  2. Scorer logic from `score-run.ps1` + comparison logic from `compare-reports.ps1` have Bash equivalents; outputs validated against PS references
  3. Bash harness runs end-to-end on Git Bash for Windows + Linux + macOS without `pwsh` installed (CI simulation on at least two of these)
  4. `pwsh`-dependency documentation updated — harness section of `evals/README.md` marks Bash as the default, PS as legacy reference
**Plans**: 2-3 plans (likely split: runner port, scorer port, cross-platform verification)

### Phase 3: Lab Scaffold
**Goal**: Establish the `lab/` subdirectory as a first-class beta channel with documented conventions, so every future opt-in feature (PEL tiers, future experiments) has a clear home.
**Depends on**: Phase 2 (eval harness that lab code can consume)
**Requirements**: [LAB-01]
**Success Criteria** (what must be TRUE):
  1. `lab/` directory exists at repo root with `README.md` encoding the default/lab boundary, promotion flow, graduation criteria, and anti-criteria (from `.planning/notes/co-evolution-lab-concept.md`)
  2. `lab/README.md` lists current and planned inhabitants (`lab/pel/` for v1.2; `lab/pel-auto/` and `lab/pel-explorer/` noted as v1.3+ placeholders not yet created)
  3. `co-evolve` and `dev-review` runners parse a `--lab <mode>` flag that routes into `lab/<mode>/` without any behavior change for users who don't pass the flag (byte-parity for default invocations verified via simulation)
  4. `lab/README.md` documents the sandbox guarantee: any `--lab` mode runs in isolation from the live checkout and cannot modify master directly — only via emitted PRs
**Plans**: 1 plan

### Phase 4: Mode Classifier (frozen)
**Goal**: Build the decision layer that auto-selects a fitness flavor for each PEL invocation while staying interpretable and overridable.
**Depends on**: Phase 3
**Requirements**: [PEL-01]
**Success Criteria** (what must be TRUE):
  1. `lab/pel/classifier/classifier.sh` (or equivalent entry point) accepts task description + bounce-step context + GSD-phase-type context and returns one of `bug-catcher`, `faster-converger`, `blind-spot-surfacer`, `general` along with a rationale string
  2. Classifier uses Haiku 4.5 by default (`claude-haiku-4-5-20251001`) via the shared adapter; Opus fallback documented but off by default for cost
  3. User override via `--flavor <name>` on `co-evolve --lab pel-proposer` takes precedence over classifier's pick and is logged
  4. Classifier itself does NOT mutate in v1.2 — its code and prompts are outside PEL's mutable surface (enforced by file allowlist in Phase 7's code proposer)
  5. Simulation test covers: each of the 4 flavor picks with plausible input, override precedence, frozen-surface invariant
**Plans**: 1-2 plans

### Phase 5: Template-Tier Mutation Proposer
**Goal**: First mutation proposer — the safest tier. Can change only `skills/dev-review/templates/*.md`. This proves the propose-score-emit loop end-to-end before tackling harder tiers.
**Depends on**: Phase 4
**Requirements**: [PEL-02]
**Success Criteria** (what must be TRUE):
  1. `lab/pel/proposer/template/` produces a diff against exactly one template file per invocation (single-mutation constraint in v1.2)
  2. Proposer consumes: an eval-failure report from Phase 2's harness, the current template file, and the flavor pick from Phase 4
  3. Proposer output is a well-formed unified diff that applies cleanly to the current template via `patch` or `git apply`
  4. Simulation test: fed a synthetic eval-failure report pointing at a specific template weakness, proposer produces a diff that addresses the weakness (human-graded in the test — this test isn't fully automatable, but the diff-well-formedness and apply-cleanly checks are)
**Plans**: 1-2 plans

### Phase 6: Policy-Tier Mutation Proposer
**Goal**: Second mutation proposer — tunes numeric/string knobs that shape protocol behavior without touching templates or code.
**Depends on**: Phase 4 (independent from Phase 5; can parallelize if both phases are started after 4)
**Requirements**: [PEL-03]
**Success Criteria** (what must be TRUE):
  1. Policy surface defined as a YAML/JSON file (new or existing) with enumerated mutable knobs: retry caps, marker-semantics flags, writable-phase defaults, arbitrate thresholds, max-passes, flavor weights
  2. `lab/pel/proposer/policy/` produces a proposed delta to the policy file (single knob or a small coherent set) given eval feedback + flavor pick
  3. Proposer output applies via jq/yq deterministically — simulation verifies the resulting policy is syntactically valid and semantically within documented bounds (e.g., retry cap in [0, 10])
  4. Simulation test: proposer takes a synthetic failure, emits a policy delta that would plausibly address it, applies cleanly
**Plans**: 1 plan

### Phase 7: Code-Tier Mutation Proposer
**Goal**: The hardest tier — PEL can propose diffs against `lib/co-evolution.sh` and runner paths. Sandbox + canary + budget enforcement are the ship criteria, not optional.
**Depends on**: Phases 5 AND 6 (pattern reuse; code tier builds on the template/policy infrastructure)
**Requirements**: [PEL-04]
**Success Criteria** (what must be TRUE):
  1. `lab/pel/proposer/code/` operates on a fresh clone of the repo, never the live checkout — enforced by the invocation entry point (fail-closed if sandbox setup fails)
  2. Canary smoke-test suite runs IMMEDIATELY after mutation is applied to the sandbox, BEFORE eval scoring: sources lib cleanly (no syntax errors), `agent-bouncer.sh` completes a trivial bounce end-to-end, `dev-review.sh --plan-only` produces valid output, one basic eval case runs to completion. Mutation rejected with distinct exit code if canary fails.
  3. Diff budget: code mutations cap at N lines changed per invocation (N = 20 for v1.2; tunable later). File allowlist: proposer CANNOT touch `lab/pel/classifier/` (frozen-surface invariant from Phase 4), `.planning/`, `tests/` (test integrity), or `.gitignore`.
  4. Exit codes distinguish: canary-failed (runner broken, mutation rejected), eval-regressed (runner works but scores dropped, mutation rejected), accepted (runner works, scores improved or held steady). State.json in sandbox captures all three outcomes for the PR emitter.
  5. Simulation test: proposer fed a synthetic improvement opportunity in `lib/co-evolution.sh`, produces a mutation, canary passes, eval delta captured. Adversarial simulation: proposer fed an opportunity that would break a core helper, canary catches it, mutation rejected.
**Plans**: 2-3 plans (sandbox setup, canary + scorer integration, proposer itself)

### Phase 8: PR Emission + Scoring Integration
**Goal**: Ship Option 1. Wrap Phases 4-7 as a single entry point that produces draft PRs a human can review and merge.
**Depends on**: Phases 5, 6, 7 (all three proposer tiers integrated)
**Requirements**: [PEL-05]
**Success Criteria** (what must be TRUE):
  1. `co-evolve --lab pel-proposer --target <file-or-pattern>` is a working invocation: picks flavor (Phase 4), chooses the appropriate proposer tier based on `--target` (template / policy / code), runs the mutation + scoring loop, and drafts a PR against master via `gh pr create --draft` with eval deltas in the PR body
  2. PR body includes: mutation diff (inline), eval scores before/after, flavor pick + classifier rationale, canary result (if code tier), diff budget usage, timestamps
  3. Simulation test: `co-evolve --lab pel-proposer --target skills/dev-review/templates/compose-prompt.md --dry-run` walks the full pipeline up to the PR-create step (stubs `gh`) and verifies the body is well-formed
  4. Human-in-the-loop dogfood: at least 3 real PEL-emitted PRs are reviewed by the user during v1.2 verification — at least 1 merged, at least 1 closed-without-merge — proving the review gate is real and the UX works
  5. Default runner byte-parity preserved: running `co-evolve "task"` or `dev-review "task"` without `--lab pel-proposer` produces identical behavior to v1.1 (regression test)
**Plans**: 2 plans (invocation wiring + PR body generation; human-dogfood verification)

## Progress

**Execution Order:**
Phases execute in numeric order with Phases 5 and 6 parallelizable after Phase 4 lands.
Waves:
- Wave 1 → Phase 1 (fixes)
- Wave 2 → Phase 2 (Bash eval port)
- Wave 3 → Phase 3 (lab scaffold)
- Wave 4 → Phase 4 (classifier)
- Wave 5 → Phases 5 + 6 (template + policy proposers, parallel)
- Wave 6 → Phase 7 (code proposer)
- Wave 7 → Phase 8 (PR emission, the Option 1 ship)

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 1. Post-v1.1 Fixes | TBD | Planned | — |
| 2. Bash Eval Harness Port | TBD | Planned | — |
| 3. Lab Scaffold | TBD | Planned | — |
| 4. Mode Classifier (frozen) | TBD | Planned | — |
| 5. Template-Tier Mutation Proposer | TBD | Planned | — |
| 6. Policy-Tier Mutation Proposer | TBD | Planned | — |
| 7. Code-Tier Mutation Proposer | TBD | Planned | — |
| 8. PR Emission + Scoring Integration | TBD | Planned | — |

## Deferred (candidates for v1.3+)

- **PEL Option 2 (Auto-Promote)** — seeded in `.planning/seeds/pel-auto-promote-and-explorer.md`. Trigger: v1.2 Option 1 has ≥4 weeks production data + canary suite mature + Goodhart research findings in place. Lives in `lab/pel-auto/`.
- **PEL Option 3 (Explorer + Curator)** — same seed, same triggers. Lives in `lab/pel-explorer/`.
- **Classifier evolution** — allowing Phase 4's classifier to mutate based on later-tier data. Requires clean attribution signal separating protocol improvement from classifier changes.
- **Automated branch/worktree cleanup utility** — carried forward from v1.1 deferred list; standalone utility.
- **Workspace-agnostic ports of lab PS integration scripts** — v1.0 Phase 9 deferred item.
- **Goodhart mitigations beyond human review** — research question RQ-001 in `.planning/research/questions.md`; becomes critical for Options 2+3 once auto-merge is on the table.
