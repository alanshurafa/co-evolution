---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Protocol Evolution Loop — Proposer Only
status: executing
stopped_at: Completed Phase 08 Plan 02 (08-02-PLAN.md) — full PEL pipeline + 10/10 SC-3 sim + README docs; Phase 7 still 16/16; ready for Plan 03 (VERIFY-SC4.md dogfood tracker)
last_updated: "2026-04-19T15:13:57.803Z"
last_activity: 2026-04-19
progress:
  total_phases: 8
  completed_phases: 7
  total_plans: 17
  completed_plans: 17
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-17 for v1.2 kickoff)

**Core value:** Cross-AI workflows can be executed from local CLIs with clear artifact trails, reusable prompt contracts, and enough control to course-correct between steps. From v1.2 onward co-evolution becomes self-improving via PEL (living in `lab/`) proposing protocol mutations for human review.
**Current focus:** Phase 08 — pr-emitter-scoring

## Current Position

Phase: 08 (pr-emitter-scoring) — EXECUTING
Plan: 3 of 3
Next: Phase 7 (Code-Tier Mutation Proposer) — requires discuss → plan → execute
Status: Ready to execute
Last activity: 2026-04-19
Working directory: `C:/Users/alan/Project/co-evolution-v12/` (branch `feat/v1.2-pel-proposer`)

Progress: milestone v1.2 at 6/8 phases; 13/? plans (Phase 7-8 plan counts TBD)

## Performance Metrics

**Velocity:**

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 02-bash-eval-harness-port | 01 | 4min 30s | 2 | 2 |
| 02-bash-eval-harness-port | 02 | 20min 53s | 2 | 1 |
| 02-bash-eval-harness-port | 03 | 18min 12s | 4 | 5 |
| 03-lab-scaffold | 01 | ~8 min | 2 | 3 |
| 03-lab-scaffold | 02 | ~9 min | 4 | 5 |
| 04-mode-classifier-frozen | 01 | ~11 min | 4 | 4 |

*Reset at milestone boundary. Historical velocity preserved in `.planning/milestones/v1.1-SUMMARY.md`.*
| Phase 04-mode-classifier-frozen P02 | 9 min | 1 tasks | 1 files |
| Phase 07-code-tier-proposer P01 | 15min 49s | 6 tasks | 6 files |
| Phase 07-code-tier-proposer P02 | 27min 32s | 2 tasks | 6 files |
| Phase 08-pr-emitter-scoring P01 | 15min 13s | 3 tasks | 9 files |
| Phase 08-pr-emitter-scoring P02 | 37min 2s | 3 tasks | 7 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work (v1.2 kickoff):

- [v1.2 kickoff] PEL machinery lives entirely in `lab/pel/` — default runner (`co-evolve`, `dev-review`) stays byte-parity-invisible to users who never opt into `--lab pel-proposer`
- [v1.2 kickoff] Multi-flavor fitness (bug-catcher / faster / blind-spot / general) with auto-select + transparent override — classifier frozen in v1.2
- [v1.2 kickoff] Both-layer specialization: bounce-step × GSD-phase → ~3×3 matrix of mode combinations, flavors on top; eval harness must run bounces IN CONTEXT, not as isolated fixtures
- [v1.2 kickoff] Mutable surface = templates + policy + code → LLM proposer only for code tier (random mutation of shell produces syntax errors)
- [v1.2 kickoff] v1.2 ships Option 1 (Proposer Only); Options 2 + 3 (Auto-Promote, Explorer+Curator) stay seeded until trigger conditions met
- [v1.2 kickoff] Fold WR-04/WR-05 (v1.1 review non-blockers) into v1.2 Phase 1 rather than shipping a separate v1.1.1 patch — keeps release cadence tidy
- [v1.2 kickoff] Bash port of PS eval harness (BASH-EVAL-01) is a hard prerequisite for PEL — becomes Phase 2 of v1.2
- [Phase 02-bash-eval-harness-port]: evals/lib/co-evolution-evals.sh ports PS Yaml+Report+Fixture helpers to a single idempotent-sourceable Bash library; render_report uses {{TOKEN}} not {TOKEN}; merge_yaml_defaults uses jq * for PS Merge-HashtablesDeep semantics
- [Phase 02-bash-eval-harness-port]: evals/score-run.sh ports PS 7-dimension scorer to 675-LOC Bash with jq-based ISO8601 TZ parsing, awk-based Levenshtein with 4000-char cap and BOM strip, and MINGW grep -iF workaround via awk tolower+index()
- [Phase 02-bash-eval-harness-port]: evals/run-evals.sh (383 LOC) + evals/compare-reports.sh (154 LOC) + evals/tests/fake-runner.sh (177 LOC) + evals/tests/scorer-verification.sh (234 LOC) complete the Bash harness; --runner-path flag enables hermetic Tier 2 via fake-runner test double; scorer-verification.sh wires Tier 1 (10 fixtures) + Tier 2 (PASS + FAIL scenarios exercising robust_fails>0 branch) + Tier 3 (determinism) into a single '13/13 scenarios passed' gate on any Bash+jq+yq platform without pwsh — closes SC-3
- [Phase 02-bash-eval-harness-port]: fake-runner banner is ASCII 'FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION' (double-hyphen) not em-dash to dodge Git Bash Windows stdout quirks; state.json carries mode=fake-runner tag; lives under evals/tests/ (explicit test path per T-02-03-11)
- [Phase 03-lab-scaffold-01]: lab/README.md is the user-facing contract (127 lines) encoding 16 verbatim items from the concept-note PRD — 6 graduation criteria (L-06), 4 anti-criteria with cause+consequence anchors (L-07), 5 lab-worthy qualifiers (L-08), 3 disambiguation items (L-01) — plus sandbox guarantee (L-05), --lab invocation + unknown-mode fail-fast (L-02/L-04), first-inhabitants table with v1.3+ placeholders NOT-created callout (L-09), and the v1.2 argv contract (W-3: entry point receives full task string as $1 — single argument) in the How-to-add section
- [Phase 03-lab-scaffold-01]: AGENTS.md lab callout placed AFTER final <!-- GSD:profile-end --> marker (not before first -start) so it survives regeneration; README.md lab subsection placed between Claude Code Skill and Picking-the-right-entrypoint (orthogonal opt-in dimension, not a row in the default-runner routing table)
- [Phase 03-lab-scaffold-01]: Verbatim-copy-with-grep-pinning pattern established: when a downstream artifact MUST mirror an upstream spec, pin each distinctive phrase with grep acceptance — all 48 Task 1 pins + 5 Task 2 pins passed on first run
- [Phase 03-lab-scaffold-02]: Shared lib/co-evolution.sh helpers (validate_lab_mode / list_available_lab_modes / dispatch_lab_mode) are the single-point-of-truth for --lab routing in BOTH runners — inline duplication rejected because future changes to the unknown-mode message, validation regex, or dispatch-argv order must touch only one file
- [Phase 03-lab-scaffold-02]: GNU-find feature detection (find --version | grep GNU) rather than OS detection in list_available_lab_modes — Git Bash for Windows and Linux take the fast -printf path; macOS falls through to -exec basename. Doesn't assume anything about $OSTYPE
- [Phase 03-lab-scaffold-02]: Argv-position invariant pinned by line-number comparison — --lab) arm must precede --) argv-terminator arm in both runners; simulation asserts this via grep -n | cut. A future refactor that moves the arm fails the gate
- [Phase 03-lab-scaffold-02]: W-3 argv-contract comment symmetric at BOTH dispatch sites — 'single argv slot' substring + 'lab/README.md' cross-reference. Symmetric (not just one runner) because both dispatch sites share the same constraint; future executor reading either runner or the README lands on the same contract
- [Phase 03-lab-scaffold-02]: Bash 5.2 set -e + $() + die-via-exit quirk — when a library function that calls exit is invoked under set -e inside command substitution, wrap the inner expression in an explicit extra subshell: out=$( (dispatch_lab_mode ...) 2>&1 || true ). Relevant for future verify blocks
- [Phase 04-mode-classifier-frozen]: Phase 4 Plan 01: Self-contained PEL classifier shipped as lab/pel/classifier/** (4 files, zero lib/co-evolution.sh imports). classifier.sh public entry + adapter.sh inline-helpers Haiku adapter + frozen prompt.md + lab/pel/README.md env-var contract. D-05 self-containment + D-11 path-based freeze both hold under grep audit. Override fast-path emits canonical D-08 JSON without invoking Haiku; all 6 high-severity STRIDE threats have grep-checkable mitigations. Deviations: 1 Rule-3 comment rewording (grep false positive), 1 plan-verifier regex escape bug noted not patched (functional tests prove correctness).
- [Phase 04-mode-classifier-frozen]: Phase 4 Plan 02: Hermetic classifier simulation gate shipped at tests/classifier-simulation.sh (429 lines, 8 scenarios: 6 primary SC-5 + 2 bonus). PATH-injection stub pattern (fake claude CLI at $TEST_DIR/bin/claude echoing canned JSON from $CLASSIFIER_STUB_FILE) + fingerprint-marker proof that PEL_FLAVOR_OVERRIDE bypasses Haiku + structural grep frozen-surface invariant for D-11. Primary/bonus counter split keeps tail -1 stable at 6/6 scenarios passed per v1.2 phase-gate convention while surfacing 2/2 bonus scenarios passed on the line above. Cross-platform (Git Bash Windows + Linux + macOS) hermetic, no new dependencies, zero classifier-surface modifications.
- [Phase 07-code-tier-proposer]: Phase 7 Plan 01: code-tier proposer shipped at lab/pel/proposer/code/** (5 files, 930 lines). D-07 pre-flight gate chain (parse -> single-file -> allowlist -> budget -> git apply --check) runs BEFORE sandbox creation; cheap syntactic rejections avoid the expensive worktree+canary cycle. Sandbox via git worktree add --detach HEAD at $TMPDIR/pel-code-sandbox-XXXXXX with defense-in-depth cleanup (git worktree remove --force + rm -rf in trap EXIT). Canary.sh runs 5 scenarios (source-survives/helper-signatures/agent-bounce/dev-review-plan-only/one-eval-case) with PATH-injected stubs for claude+codex; distinct canary exit codes 1-5 map to proposer exit 7 with scenario name in state.json. Allowlist ordering fix (Rule 3): string-only allowlist check runs BEFORE PEL_CODE_FEEDBACK readability so frozen-target violations surface even with stale feedback paths. DIFF_BUDGET integer regex validation added (Rule 2) to block shell-metachar injection into the arithmetic comparison. Live 5/5 canary pass against current unmutated repo.
- [Phase 07-code-tier-proposer]: Phase 7 Plan 02: 16-scenario hermetic SC-5 gate shipped at tests/code-proposer-simulation.sh (1074 lines, 4 happy-paths + 5 text-pipeline edge cases + 7 adversarial rejections). PATH-injected git shim pattern introduced (intercepts git worktree remove --force to snapshot state.json before teardown) — enables post-exec state.json assertions without modifying Plan 01 proposer.sh. 4 Phase-2-scorer-shaped JSON fixtures under tests/fixtures/code-feedback/. All text-pipeline edge cases (E-I: empty-line context marker, trailing newline, CRLF, shell metachars, patch-vs-git-apply divergence) from phase-7-simulation-lessons.md pass on first run against Plan 01 surface — confirms Plan 01's capture_diff narrow-regex and --whitespace=nowarn wiring work. Plan 01 stdout leak ('HEAD is now at...' from git worktree add) logged to deferred-items.md as DEF-07-01 for Phase 8 to fix. Final line 16/16 scenarios passed matches v1.2 phase-gate convention.
- [Phase 08-pr-emitter-scoring]: Phase 8 Plan 01: DEF-07-01 fix landed (proposer.sh:306 stdout suppression) — Phase 7 sim 16/16 re-verified; 7 PEL wrapper flags wired symmetrically on co-evolve-bouncer.sh + dev-review.sh with byte-parity defaults (SC-5 preserved); lab/pel/pr-emitter/ skeleton shipped with D-04 tier auto-detect + D-17 exit 10 + D-20 double-brace placeholder template; Rule 3 deviation — added lab/pel-proposer/entry.sh one-line flat-namespace dispatch resolver to reconcile plan's three joint constraints (dispatch via --lab pel-proposer, artifact at lab/pel/pr-emitter/entry.sh, dispatch_lab_mode unchanged)
- [Phase 08-pr-emitter-scoring]: Phase 8 Plan 02: Full PEL Option 1 pipeline shipped — pr-emitter.sh expanded from 224 to 644 LOC (Sections A-J) replacing Plan 01 scoring stub with classifier invoke + proposer dispatch via PATH-injected git shim for state.json capture + tier-aware apply (git apply for template/code; yq -i per mutation for policy) + emitter-owned scoring sandbox + cache with fixture+scripts+worktree+dirty hash + budget enforcement + render_pr_body with 13 double-brace placeholders + gh pr create --draft. Hermetic SC-3 gate: tests/pr-emitter-simulation.sh 10 scenarios (A template, B policy, C code+canary, D dry-run, E CANARY-FAILED, F budget exit 6, G hard-error exit 10, H override, I byte-parity, J cache hit) 10/10 green + idempotent. Phase 7 sim still 16/16. 4 auto-fixed deviations (gh stub argv-capture order bug, policy_path verbatim contract documentation, sim branch-name cleanup, cleanup-trap registry pattern). Self-containment D-07 holds. Plan 03 (VERIFY-SC4.md dogfood tracker) ready to ship.

### Pending Todos

- Create `C:/Users/alan/Project/co-evolution-v12/` worktree on `feat/v1.2-pel-proposer` branch before executing Phase 1
- Archive old local branches: `feat/v1.1-polish` (merged + remote deleted; local branch in co-evolution-v11 + co-evolution-clean can be safely deleted)
- Future: Re-evaluate seed `pel-auto-promote-and-explorer.md` when trigger conditions met (Option 1 ≥4 weeks production data + canary suite + Goodhart findings + lab conventions)

### Blockers/Concerns

- **PEL economics depend on platform upgrades:** Haiku 4.5 for verify-at-scale (~10× cheaper than Opus), prompt caching on stable bounce prompts (unlocks ≥100-run eval budgets), `/compute-guard` paired with any autonomous mode. Captured in `C:/Users/alan/.claude/projects/.../memory/future_tools.md`. Treat as assumed infrastructure, not stretch goals.
- **Goodhart's law is the default outcome** of optimizing any proxy metric hard enough. v1.2's mitigation is "human review gate on every mutation PR." v1.3+ needs deeper mitigations (RQ-001 in `.planning/research/questions.md`).
- **v1.1 code review warnings carried forward:** WR-04 (INITIAL_GIT_DIRTY captured before WORKDIR reassigned in worktree mode) and WR-05 (missing `--` argv terminators on git calls). Folded into v1.2 Phase 1 as FIX-WR-04 and FIX-WR-05.

## Session Continuity

Last session: 2026-04-19T15:13:57.797Z
Stopped at: Completed Phase 08 Plan 02 (08-02-PLAN.md) — full PEL pipeline + 10/10 SC-3 sim + README docs; Phase 7 still 16/16; ready for Plan 03 (VERIFY-SC4.md dogfood tracker)
Resume file: None
Active PR: None yet on v1.2 branch (not yet created)
Reference docs: v1.0 `.planning/milestones/v1.0-SUMMARY.md`, v1.1 `.planning/milestones/v1.1-SUMMARY.md`; upstream contract at `runners/codex-ps/evals/UPSTREAM-MESSAGE.md` (all v1.0 items closed); Phase 2 final: `.planning/phases/02-bash-eval-harness-port/02-03-SUMMARY.md`; Phase 3 finals: `.planning/phases/03-lab-scaffold/03-01-SUMMARY.md` + `.planning/phases/03-lab-scaffold/03-02-SUMMARY.md`
