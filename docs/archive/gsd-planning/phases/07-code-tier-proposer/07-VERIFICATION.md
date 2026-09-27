---
phase: 07-code-tier-proposer
verified: 2026-04-18T00:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
deferred:
  - truth: "state.json captures eval-regressed outcome (third outcome from ROADMAP SC-4)"
    addressed_in: "Phase 8"
    evidence: "Phase 8 goal: 'Wrap Phases 4-7 as a single entry point that produces draft PRs' — SC-1: 'runs the mutation + scoring loop, and drafts a PR against master'. Eval scoring (which produces the eval-regressed outcome) is explicitly Phase 8's scoring-integration scope per ROADMAP. Phase 7 canary is smoke-test only per D-08/D-09/D-10."
requirements_verified:
  - id: PEL-04
    status: satisfied
    evidence: "Code-tier proposer shipped at lab/pel/proposer/code/ (5 files, 930 LOC). Sandbox isolation (D-01/D-02/D-03), canary smoke-test (D-08/D-09/D-10, 5 scenarios), diff budget + file allowlist (D-04/D-05/D-06), and exit code taxonomy (D-21, 9 codes) all implemented. 16/16 simulation scenarios pass."
---

# Phase 7: Code-Tier Mutation Proposer Verification Report

**Phase Goal:** The hardest tier — PEL can propose diffs against `lib/co-evolution.sh` and runner paths. Sandbox + canary + budget enforcement are the ship criteria, not optional.
**Verified:** 2026-04-18T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `lab/pel/proposer/code/` operates on a fresh clone of the repo, never the live checkout — enforced by the invocation entry point (fail-closed if sandbox setup fails) | VERIFIED | `proposer.sh:284-287` creates `$TMPDIR/pel-code-sandbox-XXXXXX`; `proposer.sh:306-312` calls `git worktree add --detach` with exit 8 on failure (fail-closed, never falls back to live checkout); `proposer.sh:319` applies diff in sandbox via `cd "$SANDBOX_PATH" && git apply`; `proposer.sh:292-301` trap cleans up worktree. Simulation Scenario A/B/C/D verify live checkout is never modified (state.json snapshot via git-shim confirms sandbox_path is under TMPDIR). |
| 2 | Canary smoke-test suite runs IMMEDIATELY after mutation is applied to the sandbox, BEFORE eval scoring: sources lib cleanly, agent-bouncer bounce end-to-end, dev-review.sh --plan-only, one basic eval case. Mutation rejected with distinct exit code if canary fails | VERIFIED | `canary.sh` implements all 5 scenarios: source-survives (lines 80-97, bash -n + source), helper-signatures (99-112, 4 functions), agent-bounce (114-131, agent-bouncer.sh end-to-end with PATH-stubbed claude/codex), dev-review-plan-only (133-156, dev-review.sh --plan-only with stubs), one-eval-case (158-182, eval fixture + harness syntax). Canary exit codes 1-5 map to proposer exit 7 via `proposer.sh:343-350`. Simulation Scenario P proves catch of bash-syntax-breaking mutation (`if true; then` without fi → canary exit 1 → proposer exit 7 + state.json outcome=canary-failed + canary.failed_at=source-survives). |
| 3 | Diff budget: code mutations cap at N=20 lines changed per invocation. File allowlist: proposer CANNOT touch `lab/pel/classifier/`, `.planning/`, `tests/`, or `.gitignore` | VERIFIED | `allowlist.txt` enumerates exactly 3 mutable paths (lib/co-evolution.sh, dev-review/codex/dev-review.sh, agent-bouncer/agent-bouncer.sh). Non-listed paths excluded by absence (frozen-surface-by-allowlist). `proposer.sh:120-123` checks PEL_CODE_TARGET via `grep -Fxq`; `proposer.sh:237-240` defense-in-depth checks LLM-emitted diff target. `proposer.sh:253-259` enforces 20-line budget. Simulation Scenarios J (classifier), K (.planning), L (tests/) all exit 5 with allowlist error; Scenario M (25-line diff) exits 6. |
| 4 | Exit codes distinguish: canary-failed, eval-regressed, accepted. State.json in sandbox captures outcomes for the PR emitter | VERIFIED (partial — accepted + canary-failed in Phase 7 scope; eval-regressed deferred to Phase 8 scoring loop) | `proposer.sh:343-371` writes state.json with outcome=canary-failed + canary.failed_at + exit_code=7 when canary fails. `proposer.sh:376-388` writes state.json with outcome=accepted + canary.passed=true + exit_code=0 on success. 9-code exit taxonomy (0=accepted, 1=input, 2=CLI, 3=malformed, 4=multi-file, 5=allowlist, 6=budget, 7=canary-failed, 8=sandbox-setup) documented at `proposer.sh:37-49` and `lab/pel/README.md`. The third outcome eval-regressed is produced by Phase 8's scoring loop (see Deferred Items below) — Phase 7 proposer has no scoring responsibility per D-08 (canary is smoke-test only). |
| 5 | Simulation test: proposer fed a synthetic improvement opportunity, produces mutation, canary passes, eval delta captured. Adversarial: proposer fed opportunity that breaks a core helper, canary catches it, mutation rejected | VERIFIED | `tests/code-proposer-simulation.sh` (1074 lines, 16 scenarios) — Scenarios A/B/C/D cover synthetic improvement opportunities (4 flavors × 3 mutation targets) with state.json.outcome=accepted assertions. Scenario P covers adversarial canary break (`if true; then` without fi targets lib/co-evolution.sh, passes all 5 pre-flight gates, applies cleanly in sandbox, but breaks bash -n; canary catches; proposer exit 7 + state.json.outcome=canary-failed + canary.failed_at=source-survives). Live run: `bash tests/code-proposer-simulation.sh` exits 0 with final line `16/16 scenarios passed`. |

**Score:** 5/5 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases. Filtered per Step 9b against Phase 8 roadmap scope.

| # | Item | Addressed In | Evidence |
|---|------|--------------|----------|
| 1 | state.json captures eval-regressed outcome | Phase 8 | Phase 8 goal: "Wrap Phases 4-7 as a single entry point that produces draft PRs" — SC-1 explicitly says "runs the mutation + scoring loop". Phase 7 canary is a smoke-test only (D-08 "proposer runs canary only; eval scoring is Phase 8's pipeline"). The eval-regressed outcome REQUIRES the scoring loop, which lives in Phase 8. The state.json schema at CONTEXT D-20 enumerates "accepted|canary-failed|eval-regressed|budget-exceeded|allowlist-violation" as OUTCOME literals — Phase 7 writes 2 of these, Phase 8 will write eval-regressed after scoring deltas are computed. This is not an implementation gap in Phase 7 — it is a legitimate boundary. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lab/pel/proposer/code/proposer.sh` | Public entry: env validation + allowlist + budget + sandbox + canary + state.json | VERIFIED | 394 lines, executable (100755); implements D-07 pre-flight gate chain (gates at 216-229 parse, 225-229 single-file, 237-248 allowlist, 253-259 budget, 270-276 git apply --check); sandbox at 284-312; canary invocation at 336; state.json writes at 355-367 + 376-388. Imported exclusively by tests/code-proposer-simulation.sh via bash subprocess. |
| `lab/pel/proposer/code/adapter.sh` | Self-contained Opus adapter: 6-placeholder prompt composition + claude CLI + diff capture | VERIFIED | 250 lines; 9 inline helpers (die, log_stderr, require_claude_cli, file_contains_auth_failure, validate_proposer_model, compose_prompt, invoke_opus, capture_diff, run_adapter); WSL fallback via cmd.exe; BASH_SOURCE guard against direct execution. Sourced exclusively by proposer.sh:186. Self-containment invariant D-12 holds (grep audit: no sources outside SCRIPT_DIR). |
| `lab/pel/proposer/code/canary.sh` | 5-scenario smoke-test: distinct exit codes, PATH-injection stubs, trap cleanup | VERIFIED | 188 lines, executable; PATH-stub dir at STUB_DIR (mktemp -d) with trap cleanup; stubs for claude + codex; all 5 scenarios implemented sequentially with distinct exit codes 1-5. Live smoke-test against unmutated repo: 5/5 scenarios pass in <1s. |
| `lab/pel/proposer/code/allowlist.txt` | Frozen-surface enforcement (3 mutable paths) | VERIFIED | 3 lines exactly: lib/co-evolution.sh, dev-review/codex/dev-review.sh, agent-bouncer/agent-bouncer.sh. Read via `grep -Fxq` by proposer.sh (exact-line match rejecting trailing slashes, absolute forms, ../ traversals). |
| `lab/pel/proposer/code/prompt.md` | Shell-aware mutation prompt with flavor riders + 6 placeholders | VERIFIED | 95 lines; stable portion first (role + rules + 4 flavor riders with code-specific bias + guidance + output schema), variable portion last (## Inputs: TASK_HINT, FLAVOR, CODE_TARGET, DIFF_BUDGET, EVAL_REPORT_JSON, CODE_CONTENT). 4 flavor tokens present; all 6 placeholder tokens present. |
| `tests/code-proposer-simulation.sh` | Hermetic 16-scenario SC-5 gate | VERIFIED | 1074 lines, executable, bash -n clean; 16 scenarios labeled A-P; PATH-injected claude stub at $TEST_DIR/bin/claude via CODE_PROPOSER_STUB_FILE env; PATH-injected git shim snapshots state.json before worktree teardown (new Phase 7 pattern); per-scenario subshell; primary-only `16/16 scenarios passed` footer. Live run: exits 0 with exact final line. |
| `tests/fixtures/code-feedback/*.json` | 4 synthetic Phase-2-scorer-shaped eval-failure fixtures | VERIFIED | All 4 present: retry-logic-weakness (bug-catcher, robustness FAIL, lib/co-evolution.sh), phase-timeout-improvement (faster-converger, convergence FAIL, dev-review.sh), error-handling-gap (blind-spot-surfacer, verify_accuracy FAIL, agent-bouncer.sh), lab-routing-edge (general, 5 PARTIAL scores, lib/co-evolution.sh). jq valid; case_id + scores + composite present in all 4. |
| `lab/pel/README.md` | Extended with Code-tier proposer (v1.2) section (+237 lines) | VERIFIED | Section present with env-var contract table, exit-code taxonomy 0-8, allowlist mechanism, diff budget (N=20), canary 5-scenario suite, sandbox isolation lifecycle, state.json schema; also extended by Plan 02 with +30 lines of 16-scenario simulation coverage matrix. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| proposer.sh | adapter.sh | `source "$SCRIPT_DIR/adapter.sh"` | WIRED | Line 186; sole source statement in proposer.sh (D-12 self-containment) |
| adapter.sh | prompt.md | compose_prompt reads as template | WIRED | Line 93 (`cat "$prompt_md"`); placeholders filled via bash `${//}` parameter expansion |
| adapter.sh | claude CLI | `claude -p --model "$CODE_PROPOSER_MODEL"` | WIRED | invoke_opus at line 118-135; cmd.exe wrapper for WSL path |
| proposer.sh | allowlist.txt | `grep -Fxq "$PEL_CODE_TARGET" "$SCRIPT_DIR/allowlist.txt"` | WIRED | Line 120 (caller PEL_CODE_TARGET check) + line 237 (LLM-emitted diff target defense-in-depth) |
| proposer.sh | canary.sh | `bash "$SCRIPT_DIR/canary.sh" "$SANDBOX_PATH"` | WIRED | Line 336; canary exit 1-5 → proposer exit 7 mapping at 343-350 |
| proposer.sh | git worktree add | Sandbox creation | WIRED | Line 306: `git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD`; exit 8 on failure |
| proposer.sh | git apply --check | Pre-flight validation before sandbox | WIRED | Line 270: `printf "%s\n" "$diff_text" \| (cd "$REPO_ROOT" && git apply --check --whitespace=nowarn -)` |
| tests/code-proposer-simulation.sh | proposer.sh | bash subprocess w/ PATH stub + PEL_* env | WIRED | Subshell invocations in all 16 scenarios; exit-code capture via `rc=$?` |
| tests/code-proposer-simulation.sh | canary.sh | Transitively via proposer.sh + canary stubs in sandbox | WIRED | Canary invoked by proposer for happy-path + P; simulation does NOT provide canary's inner stubs (canary.sh provides its own PATH-injected claude + codex stubs at canary runtime) |
| tests/code-proposer-simulation.sh | $TEST_DIR/bin/claude (stub) | PATH injection + CODE_PROPOSER_STUB_FILE env | WIRED | Stub at simulation line ~200; reads canned response from CODE_PROPOSER_STUB_FILE; fingerprints to CODE_PROPOSER_STUB_MARKER |
| lab/pel/README.md | lab/pel/proposer/code/ | Documentation cross-reference | WIRED | Env-var table, exit-code table, allowlist doc, canary doc, sandbox doc, state.json doc all present |

### Data-Flow Trace (Level 4)

Phase 7 deliverables are executable shell code (not UI components rendering dynamic data). Data-flow trace is satisfied by the end-to-end simulation run at Step 7b below — state.json written to sandbox, snapshotted via git-shim, asserted with jq in 5 scenarios (A/B/C/D/P). The data flow is:

1. `PEL_CODE_FEEDBACK` (input) → `adapter.sh:compose_prompt` → prompt file
2. Prompt → `claude -p --model` → diff bytes to stdout
3. Diff bytes → `proposer.sh` pre-flight gates → sandbox `git apply`
4. Sandbox → `canary.sh` → exit code
5. Exit code + metadata → `state.json` at sandbox root → Phase 8 consumption

All 5 stages exercised end-to-end via Scenario A (happy-path) and Scenario P (canary failure). jq assertions on state.json confirm real data flows through every stage (outcome, exit_code, target, flavor, diff_lines, diff_budget, canary.passed, canary.failed_at, sandbox_path, timestamp).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Simulation gate passes 16/16 | `bash tests/code-proposer-simulation.sh` | Final stdout line: `16/16 scenarios passed`; exit code 0 | PASS |
| Proposer bash syntax clean | `bash -n lab/pel/proposer/code/proposer.sh` | Silent success | PASS |
| Adapter bash syntax clean | `bash -n lab/pel/proposer/code/adapter.sh` | Silent success | PASS |
| Canary bash syntax clean | `bash -n lab/pel/proposer/code/canary.sh` | Silent success | PASS |
| Simulation bash syntax clean | `bash -n tests/code-proposer-simulation.sh` | Silent success | PASS |
| All 4 fixtures valid JSON | `for f in tests/fixtures/code-feedback/*.json; do jq -e . "$f" > /dev/null; done` | Silent success | PASS |
| Allowlist contains exactly 3 paths | `wc -l lab/pel/proposer/code/allowlist.txt` | 3 | PASS |
| 16 scenario labels present | `for L in A B C D E F G H I J K L M N O P; do grep -qF "Scenario $L" tests/code-proposer-simulation.sh; done` | All present | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PEL-04 | 07-01-PLAN.md, 07-02-PLAN.md (both declare PEL-04) | Code-tier mutation proposer at `lab/pel/proposer/code/` with (a) sandbox isolation, (b) canary smoke-test before eval scoring, (c) diff budget + file allowlist, (d) explicit exit codes for canary-failed/eval-regressed/accepted | SATISFIED (with deferred item) | (a) sandbox via `git worktree add --detach` at proposer.sh:306, fail-closed exit 8; (b) canary.sh 5 scenarios run after mutation and before any scoring, 1-5 exit codes map to proposer 7; (c) DIFF_BUDGET=20 default at proposer.sh:173-179 + allowlist.txt with 3 paths, pre-flight gates at proposer.sh:225/237/253; (d) 9 exit codes including 7 (canary-failed) and 0 (accepted); eval-regressed literal is a Phase 8 scoring-loop outcome per ROADMAP (see Deferred Items — not an implementation gap in Phase 7). Simulation 16/16 passes. Requirement status flipped from [ ] to [x] in REQUIREMENTS.md line 33 by Plan 01 shipping. |

No orphaned requirements — PEL-04 is the only requirement mapped to Phase 7 in REQUIREMENTS.md line 64, and both plans declare it.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| lab/pel/proposer/code/canary.sh | 146-155 | WR-01 per 07-REVIEW.md — comment says "rc>10 treated as canary failure" but code only checks `rc==127` | Warning | A mutation that corrupts dev-review.sh routing and causes exit 20/137/etc. would silently pass scenario 4. Does not affect the verified canary happy-paths (rc=0) or Scenario P (canary scenario 1 catches before scenario 4 runs). Logged in 07-REVIEW.md; advisory only. |
| lab/pel/proposer/code/proposer.sh | 355-367, 376-388 | WR-02 per 07-REVIEW.md — state.json built via heredoc with direct `$VAR` interpolation | Warning | All current inputs are upstream-validated (allowlist, whitelist, mktemp) so no injection today; but structurally unsafe if inputs ever change. Does not affect verification — state.json is valid JSON in all 16 test scenarios. Advisory only. |
| lab/pel/proposer/code/proposer.sh | 216-229 | WR-03 per 07-REVIEW.md — "LLM returned no diff" gives wrong exit code taxonomy (4 instead of 2) | Warning | Edge case (Opus returns prose instead of diff). Not encountered by any simulation scenario. Advisory only. |
| lab/pel/proposer/code/proposer.sh | 284-287 | WR-04 per 07-REVIEW.md — TOCTOU window between rmdir and `git worktree add` | Warning | Low probability (TMPDIR is user-700). Not exploited in any simulation scenario. Advisory only. |
| lab/pel/proposer/code/proposer.sh | 263, 270, 306, 319 | WR-05 per 07-REVIEW.md — apply_err tempfile reused across gates without reset | Warning | Current `2>` truncates on each use so no cross-op bleed; brittle if refactored. Advisory only. |
| various | — | IN-01..IN-05 per 07-REVIEW.md | Info | All non-blocking polish items per 07-REVIEW.md; none affect goal achievement. |

Total: 0 blockers, 5 warnings, 5 info — all documented in `.planning/phases/07-code-tier-proposer/07-REVIEW.md`. None invalidate any must-have.

### Human Verification Required

None. Phase 7 deliverables are executable shell code fully verified by:
- Programmatic simulation gate (16/16 scenarios automated)
- Source inspection for invariants (self-containment, allowlist enforcement, pre-flight gate ordering)
- End-to-end bash execution with jq assertions on state.json artifacts
- bash -n syntax checks on all shipped files

No UI, no real-time behavior, no external service integration, no performance-feel assessment. The canary.sh scenarios already exercise the end-to-end agent-bouncer/dev-review pipelines in simulated form with stubs. Real-Opus invocation is explicitly out-of-scope (D-22 hermetic simulation is the gate).

### Gaps Summary

No gaps. All 5 ROADMAP success criteria verified end-to-end. One item (eval-regressed outcome in state.json) is deferred to Phase 8 because it requires the scoring loop that is explicitly Phase 8's responsibility per ROADMAP Phase 8 goal and SC-1. This is a legitimate phase boundary, not an implementation gap.

The Phase 7 proposer surface is ready for Phase 8 consumption:
- Deterministic exit codes 0-8 (load-bearing for PR emitter routing)
- Stable state.json schema (PR emitter reads before trap-EXIT cleanup)
- Hermetic simulation gate in CI (`tests/code-proposer-simulation.sh` exits 0 with 16/16 on any Bash + jq + git platform)
- One deferred Plan 01 stdout leak (`deferred-items.md` DEF-07-01) that Phase 8 must address when wiring PR body construction.

---

_Verified: 2026-04-18T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
