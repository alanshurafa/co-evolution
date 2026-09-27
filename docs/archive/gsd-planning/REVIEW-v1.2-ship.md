---
phase: v1.2-pel-proposer-ship
reviewed: 2026-04-19T00:00:00Z
depth: standard
files_reviewed: 31
files_reviewed_list:
  - co-evolve-bouncer.sh
  - dev-review/codex/dev-review.sh
  - evals/compare-reports.sh
  - evals/lib/co-evolution-evals.sh
  - evals/run-evals.sh
  - evals/score-run.sh
  - evals/tests/fake-runner.sh
  - evals/tests/scorer-verification.sh
  - lab/pel/classifier/adapter.sh
  - lab/pel/classifier/classifier.sh
  - lab/pel/pr-emitter/entry.sh
  - lab/pel/pr-emitter/pr-emitter.sh
  - lab/pel/proposer/code/adapter.sh
  - lab/pel/proposer/code/allowlist.txt
  - lab/pel/proposer/code/canary.sh
  - lab/pel/proposer/code/proposer.sh
  - lab/pel/proposer/policy/adapter.sh
  - lab/pel/proposer/policy/bounds.jq
  - lab/pel/proposer/policy/policy.yaml
  - lab/pel/proposer/policy/proposer.sh
  - lab/pel/proposer/template/adapter.sh
  - lab/pel/proposer/template/proposer.sh
  - lab/pel-proposer/entry.sh
  - lib/co-evolution.sh
  - tests/classifier-simulation.sh
  - tests/code-proposer-simulation.sh
  - tests/lab-routing-simulation.sh
  - tests/policy-proposer-simulation.sh
  - tests/pr-emitter-simulation.sh
  - tests/template-proposer-simulation.sh
  - tests/worktree-management-simulation.sh
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# v1.2 PR Ship Review — Protocol Evolution Loop (Proposer Only)

**Reviewed:** 2026-04-19
**Depth:** standard (cross-phase integration pass)
**Branch:** feat/v1.2-pel-proposer → master (PR #3, draft)
**Commits:** 129 across 8 phases

## Summary

Cross-phase integration review of 31 source files composing the PEL (Protocol Evolution Loop) v1.2 milestone. The ship vehicle (`lab/pel/pr-emitter/pr-emitter.sh`), shared library drift (`lib/co-evolution.sh`), tier dispatch correctness, sandbox isolation, shell portability, and argument-parsing symmetry were all examined.

**Overall assessment: ship-eligible with noted follow-ups.** No critical security vulnerabilities or blocking bugs were found. The frozen-surface invariants (classifier, proposer sibling-isolation), sandbox cleanup trap chains, bounds validator (`bounds.jq`), and allowlist enforcement are robust. The 7 new wrapper flags are added symmetrically to both runners and preserve byte-parity for non-`--lab` invocations.

Four warning-level findings cluster around a single failure mode: **the Bash eval harness (`evals/run-evals.sh` + `evals/score-run.sh`) is not wired to the real dev-review runner.** The scorer reads state.json fields (`.status`, `.updated_at`, `.changed_files`) and output artifacts (`outputs/compose.txt`, `outputs/bounce-01.txt`) that the Bash port of `dev-review.sh` never produces. The full test gate passes because the hermetic test harness uses `fake-runner.sh`, which DOES emit those fields — so the failure is masked. This will surface the first time `bash evals/run-evals.sh` is run against the real `dev-review.sh` (scheduled for post-merge). It is not a ship-blocker because PEL itself does not depend on scorer output during v1.2 (the emitter uses scorer-run caching with stub data in dry-run); but it blocks the first real eval round.

Five info-level findings are minor code-quality items (unused variable, TODO tracking, harmless stale globals).

## Warnings

### WR-01: Scorer reads `.status` but init_state_json never writes it

**File:** `lib/co-evolution.sh:870-924` + `evals/score-run.sh:239`
**Issue:** `score-run.sh:239` reads `jq -r '.status // "unknown"' "$state_json_path"` and treats anything other than `"completed"` as robustness=FAIL. `lib/co-evolution.sh::init_state_json` (line 870-924) produces a state.json with `started_at` and `completed_at` but NO `.status` field. Grep confirms `dev-review.sh` never calls `write_state_field "$STATE_JSON" ".status"`. The fake-runner (`evals/tests/fake-runner.sh:68-112`) DOES emit `.status`, which is why Tier 2 hermetic tests pass. The first eval run against the real runner will score every case robustness=FAIL.
**Fix:** Add `.status` to the state.json schema. In `dev-review.sh`, at the end of the run, write one of `"completed"` / `"failed"` / `"partial"` based on `EXECUTE_EXIT` + `VERIFY_EXIT`:
```bash
# After _run_revise_loop, before cleanup_runtime_artifacts (dev-review.sh:1400ish)
if [[ "$EXECUTE_EXIT" -eq 0 && "$VERIFY_EXIT" -eq 0 ]]; then
  _run_status="completed"
elif [[ "$EXECUTE_EXIT" -eq 2 || "$VERIFY_EXIT" -eq 2 ]]; then
  _run_status="partial"
else
  _run_status="failed"
fi
write_state_field "$STATE_JSON" ".status" "string" "$_run_status"
```

### WR-02: Scorer reads `outputs/compose.txt` + `outputs/bounce-01.txt` that dev-review never writes

**File:** `dev-review/codex/dev-review.sh:675` + `evals/score-run.sh:559,563`
**Issue:** `score-run.sh` cross-AI-diversity dimension expects `outputs/compose.txt` (line 559) and `outputs/bounce-*.txt` (line 563). `dev-review.sh` writes bounce outputs to `$RUN_DIR/outputs/bounce-${pass_padded}.txt` (line 675) — that filename format matches `bounce-01.txt`, good. But it never writes `outputs/compose.txt`; compose output lives at `$RUN_DIR/.compose-output.md` (dot-prefixed, deleted by `cleanup_runtime_artifacts`). Result: `cross_ai_diversity=FAIL` on every real run (the scorer's FAIL branch at line 568 fires).
**Fix:** After `run_compose_phase` succeeds, copy the compose output to the persistent path, mirroring how bounce pass files are preserved:
```bash
# In run_compose_phase (dev-review.sh:579), after cp "$compose_output_file" "$PLAN_PATH"
cp "$compose_output_file" "$RUN_DIR/outputs/compose.txt"
```

### WR-03: `run-evals.sh` passes `--autonomous` to `dev-review.sh` which has no such flag

**File:** `evals/run-evals.sh:271,279`
**Issue:** Line 271-279 constructs `--autonomous` flag from `case.runner.autonomous` and passes it to the runner. `dev-review.sh` argv parser (dev-review.sh:944-1096) has no `--autonomous` arm — unknown flags hit `-*) die "Unknown flag: $1"`. Any case YAML with `runner.autonomous: true` will cause the runner to exit 1 before any work happens. Currently the only case file committed is `defaults.yaml` which sets `autonomous: false`, so the bug is latent but will fire the moment a case YAML sets it true.
**Fix:** Either (a) remove the `--autonomous` handling from `run-evals.sh` (no case sets it non-default and the runner has no equivalent), or (b) add `--autonomous` as a no-op-accepted flag in `dev-review.sh`. Prefer (a) for cleanliness:
```bash
# Delete lines 270-271 and strip $autonomous_flag from line 279
```

### WR-04: `run-evals.sh` looks for `.co-evolution/runs/` but `dev-review.sh` writes to `runs/dev-review-<ts>/`

**File:** `evals/run-evals.sh:285-286` + `dev-review/codex/dev-review.sh:1191`
**Issue:** Line 285-286 searches `$fixture/.co-evolution/runs` for the newest run directory. `dev-review.sh:1191` sets `RUN_DIR="${REPO_ROOT}/runs/dev-review-${TIMESTAMP}"` — no `.co-evolution/` prefix, and rooted at `REPO_ROOT` not the fixture. When run-evals invokes `cd "$fixture" && bash "$RUNNER_PATH_ABS"`, the runner still writes to `$REPO_ROOT/runs/...` because `$REPO_ROOT` is resolved at the top of `dev-review.sh` from `$SCRIPT_DIR`. Result: every real eval run triggers the "no run artifacts found" warning at line 293, and the record is recorded as `status:"fail"` (line 318).

Note: fake-runner.sh:64 correctly writes to `.co-evolution/runs/fake-.../` inside the fixture CWD, which is why Tier 2 passes. The real runner's divergent RUN_DIR location is the gap.
**Fix:** Either teach `dev-review.sh` to honor a workdir-local run directory when invoked with `--workdir` that differs from REPO_ROOT, or have `run-evals.sh` look in both locations:
```bash
# Option A (harness-side, safer): search both locations.
newest_run=""
for runs_root in "$fixture/.co-evolution/runs" "$REPO_ROOT/runs"; do
  if [[ -d "$runs_root" ]]; then
    candidate=$(find "$runs_root" -maxdepth 1 -mindepth 1 -type d \
                  -newer "$stdout_path" 2>/dev/null | sort | tail -1)
    [[ -n "$candidate" ]] && newest_run="$candidate" && break
  fi
done
```
Option B (runner-side) is riskier because it changes runner byte-parity with v1.1.

## Info

### IN-01: `--yes` flag parsed but never consumed (known deferred)

**File:** `co-evolve-bouncer.sh:141-144`, `dev-review/codex/dev-review.sh:1063-1066`, `lab/pel/pr-emitter/pr-emitter.sh:88,122-125`
**Issue:** `--yes` (and `AUTO_YES=true`) is accepted and forwarded by both wrappers, but the interactive preflight cost-estimate prompt that it suppresses has not been implemented. The variable is set in the emitter (line 88) but never read. pr-emitter.sh line 84-87 documents this as a v1.3 TODO and references Phase 8 WR-01.
**Fix:** Already tracked. Either wire the prompt before v1.3, or demote the flag to an explicit `--yes (no-op; placeholder for v1.3)` in help text so users aren't surprised when the argument does nothing interactive.

### IN-02: `classifier_override` captured but never read in pr-emitter

**File:** `lab/pel/pr-emitter/pr-emitter.sh:310-311`
**Issue:** `classifier_override=$(printf '%s' "$classifier_json" | jq -r '.override')` parses the field, logs it, but never uses it downstream. If the classifier was overridden, the PR body should probably annotate that fact (for reviewer auditability) — right now the `{{classifier_rationale}}` placeholder carries the rationale but the override bit itself is dropped.
**Fix:** Either remove the parse (dead code) or thread the value into `render_pr_body` as a new placeholder `{{classifier_override}}` with values "user override" / "Haiku pick".

### IN-03: pr-emitter's `render_pr_body` has no defense against user-controlled `$TARGET` containing Markdown

**File:** `lab/pel/pr-emitter/pr-emitter.sh:665`
**Issue:** `rendered="${rendered//\{\{target\}\}/$TARGET}"` substitutes the allowlist-validated target directly into the PR body. Allowlist values are repo-relative paths like `lib/co-evolution.sh` — no Markdown metacharacters — so safe in practice. But if the allowlist ever accepts a path containing backticks or hash, the body rendering would silently malform. Defense-in-depth suggestion.
**Fix:** Optional — assert `[[ "$TARGET" =~ ^[a-zA-Z0-9._/-]+$ ]]` before substitution, or wrap in backticks so any stray backticks in TARGET are escaped by the fence-length logic.

### IN-04: Stale shell-exported `PEL_FLAVOR_OVERRIDE` from pr-emitter scope

**File:** `lab/pel/pr-emitter/pr-emitter.sh:296-298`
**Issue:** `export PEL_FLAVOR_OVERRIDE="$FLAVOR_OVERRIDE"` sets the env var for the classifier subprocess, but the export persists for the remainder of this script's lifetime. The emitter does not re-invoke the classifier later, so this is harmless in v1.2. However, if a future phase calls the classifier a second time AFTER this point, the override would silently re-apply even if the caller did not pass `--flavor`.
**Fix:** Scope the export to the classifier call using a subshell:
```bash
classifier_json=$(
  [[ -n "$FLAVOR_OVERRIDE" ]] && export PEL_FLAVOR_OVERRIDE="$FLAVOR_OVERRIDE"
  bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "${TASK:-mutate $TARGET}"
) || classifier_rc=$?
```
Or `unset PEL_FLAVOR_OVERRIDE` immediately after the classifier returns.

### IN-05: `policy.yaml` comments drift from `bounds.jq` authoritative rules

**File:** `lab/pel/proposer/policy/policy.yaml:13-38` + `lab/pel/proposer/policy/bounds.jq`
**Issue:** The YAML file's header comment says "Each knob's bound is authoritative in bounds.jq — this file's comments describe intent but bounds.jq enforces constraint." The bounds comments inline in the YAML (e.g., `retry_cap: 3` with comment "Bounds [0, 10]") are human-readable paraphrases of bounds.jq rules. There is no programmatic guard ensuring they stay in sync; a future edit to one without the other creates silent documentation drift. Not a bug today, but a future trap.
**Fix:** Either remove inline-bound comments (point readers at bounds.jq), or add a CI check that parses bounds.jq knob enumerations and diff-checks against comment text. Low priority.

## Observations (not filed as findings)

**Frozen-surface invariants hold.** Scenario F in classifier-simulation.sh (line 284-322) structurally verifies no file under `lab/pel/classifier/` sources anything outside its directory. The equivalent self-containment invariants for the three proposer trees (template, policy, code) are asserted by the `# shellcheck source=adapter.sh` discipline — all four adapters define their own `die`, `log_stderr`, `file_contains_auth_failure`, `require_claude_cli`, and model validator inline. Byte-parity for non-`--lab` invocations is held via the early-dispatch gate in both runners (co-evolve-bouncer.sh:186-201, dev-review.sh:1117-1138).

**Sandbox cleanup is defense-in-depth correct.** `lab/pel/proposer/code/proposer.sh::cleanup_sandbox` (line 292-299) runs `git worktree remove --force` AND `rm -rf` on the sandbox path; the trap is registered BEFORE `git worktree add` so a mid-setup failure still cleans. The pr-emitter's `emitter_cleanup_all` (line 215-229) cleans sandbox → workdir → dry-stub → body-file in the right order, with the dry-run branch cleanup gated on `CO_EVOLVE_DRY_RUN=1`.

**Tier dispatch error-propagation is correct.** `pr-emitter.sh:404-421` propagates any proposer non-zero exit (except 7 = canary-failed) verbatim as its own exit code. Exit 7 routes to the `[CANARY-FAILED]` diagnostic-PR branch, which creates an `--allow-empty` commit so `gh pr create` does not choke on "no commits" (WR-04 fix, line 733-741).

**Shell portability is credible.** Bash 3.2 (macOS default) landmines spotted: `mapfile` is used in `evals/run-evals.sh:117` and `lib/co-evolution.sh:471` (inside `normalize_json_artifact`). Both are Bash 4+. macOS ships Bash 3.2; most dev macOS boxes run Bash 4+ via Homebrew, and CI runners are Linux. The shebang `#!/usr/bin/env bash` does not force 4+, but the dependency is de facto OK for the target audience.

**BSD-vs-GNU `find` is handled explicitly.** `list_available_lab_modes` (lib/co-evolution.sh:90-111) and pr-emitter's PEL_EVAL_REPORT auto-discovery (pr-emitter.sh:317-332) both feature-detect via `find --version | grep GNU` and fall back to BSD-compatible paths. Good.

**Argument parsing is symmetric.** Both `co-evolve-bouncer.sh` (81-170) and `dev-review/codex/dev-review.sh` (944-1096) implement the same 7 new flags with matching semantics, validation, and help text. Manual shift loops throughout — no getopts — which is consistent with the existing v1.1 style.

---

_Reviewed: 2026-04-19_
_Reviewer: Claude (gsd-code-reviewer, Opus 4.7 1M)_
_Depth: standard (cross-phase ship-time pass)_
_Known deduplication: Phase 8 per-phase review findings (1 critical + 8 warning + 6 info) are already applied; none are re-raised here._
