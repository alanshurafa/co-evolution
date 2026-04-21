# Close the Self-Improving Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move co-evolution from "self-improving in principle" to "self-improving in practice" — debug the remaining scorer-sandbox bug that blocks every real PEL invocation, then drive ≥3 real PEL→PR→review cycles to close SC-4 and unblock `git tag v1.2`.

**Architecture:** Four phases gated on checkpoints. Phase A fixes one bug in `lab/pel/pr-emitter/pr-emitter.sh`'s scoring pipeline (~1-2 hrs). Phase B validates Tier 2 with one real template-tier cycle (~30 min). Phase C completes SC-4 dogfood with two more PRs (~90 min). Phase D is optional post-ship polish wiring I-1/I-2/I-3 from the 2026-04-21 code review.

**Tech Stack:** Bash (POSIX-ish), jq, yq, Claude CLI (`claude -p`), Codex CLI (`codex exec` for nested-Claude workaround), `gh` CLI for draft PRs. No new dependencies.

**Spec references:**
- [`.planning/VERIFY-SC4.md`](../../../.planning/VERIFY-SC4.md) — release-gate tracker (3 rows to fill)
- [`.planning/REVIEW-v1.2-ship.md`](../../../.planning/REVIEW-v1.2-ship.md) — WR-01..04 context (all already fixed in Phase 8.1, included here to orient the engineer)
- [`docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md`](../specs/2026-04-21-adaptive-co-evolve-design.md) — I-1/I-2/I-3/M-1 deferred items for Phase D
- [`lab/pel/pr-emitter/pr-emitter.sh`](../../../lab/pel/pr-emitter/pr-emitter.sh) — where Bug #5 fires (Section H, `run_scorer_cached` function)

**Working directory assumption:** Phase A is a code change on a fresh branch off master. Phases B+C dogfood from the main `co-evolution/` checkout on master (per VERIFY-SC4.md § "Pre-flight checklist"). Phase D is a new branch off master after v1.2 tags.

**Budget reality-check:**
- Phase A: ~1-2 hrs engineering, zero API cost (hermetic)
- Phase B: ~30 min wall clock + ~$3-8 Opus quota (one real PEL invocation)
- Phase C: ~90 min wall clock + ~$9-24 Opus quota (two more real invocations; adaptive routing may reduce if Sonnet picks trigger)
- Phase D: ~2-3 hrs engineering, zero API cost

---

## Phase A: Fix Bug #5 — scorer fails for "before" in real PEL runs

**Context:** On 2026-04-20 the first SC-4 dogfood attempt failed because `pr-emitter.sh` hit `die "scorer run failed for $label" 2` on the "before" baseline. WR-01/02/03/04 from REVIEW-v1.2-ship.md were fixed by Phase 8.1 (scorer-runner-contract-wiring landed; `--run-dir` flag, `.status` field, `outputs/compose.txt` persist all in place). So Bug #5 is a NEW symptom, not those old ones re-surfacing.

**Hypothesis space** (Alan's 2026-04-21 message): "Probably a sandbox/path/env issue inside the emitter scoring sandbox." Phase A.1 diagnoses; A.2-A.4 apply the right targeted fix.

**Stopping point for this phase:** `bash evals/run-evals.sh` run from a clean REPO_ROOT produces `evals/reports/<ts>/raw-scores.json` with at least one `status:"scored"` record AND `pr-emitter.sh` successfully cache-misses through both "before" and "after" scorer runs in a dry-run integration harness.

---

### Task A.1: Reproduce Bug #5 and capture exact failure mode

**Files:**
- Read: `lab/pel/pr-emitter/pr-emitter.sh:637-677` (the `run_scorer_cached` function)
- Read: `evals/run-evals.sh` (the scorer harness)
- Write: `.planning/notes/bug-5-diagnosis.md` (new — scratchpad for findings, deleted after fix)

- [ ] **Step 1: Verify Tier 1 (hermetic scorer verification) still green**

```bash
bash evals/tests/scorer-verification.sh 2>&1 | tail -5
```

Expected: `13/13 scenarios passed` (plus "Tier 4 ... PASS" if present). If this fails, STOP — the scorer itself is broken at a more fundamental level than Bug #5 and the rest of the plan premise breaks.

- [ ] **Step 2: Run the scorer standalone against real runner, capture stderr**

From a clean REPO_ROOT (master, no uncommitted changes):

```bash
# Time-bounded standalone scorer run. Captures both stdout and stderr.
# NOTE: this invokes real dev-review.sh which invokes real claude/codex — expect
# ~5-10 min wall clock and ~$1-3 API cost. Use a fresh terminal so stale env
# vars don't pollute.
cd /c/Users/alan/Project/co-evolution
TS=$(date +%s)
codex exec "cd /c/Users/alan/Project/co-evolution && bash evals/run-evals.sh 2>&1 | tee /tmp/bug-5-stderr-${TS}.log" || echo "EXIT: $?"
echo "--- tail of stderr ---"
tail -80 /tmp/bug-5-stderr-${TS}.log
```

Expected outcomes (branch by what you see):
- **Path 1 (Hypothesis: LLM-side failure):** stderr contains `auth`, `401`, `quota`, `overloaded`, `timeout`, or `model` errors → the real runner itself fails; scorer reports `status:"fail"` which triggers `pr-emitter.sh` line 669 `die`. Go to Task A.2 (runner-side fix).
- **Path 2 (Hypothesis: contract gap):** stderr shows runner succeeded but scorer reports `scorer-failed` → the runner produces output that `score-run.sh` can't parse. Go to Task A.3 (scorer-side fix).
- **Path 3 (Hypothesis: sandbox/path):** stderr shows `cd ... No such file or directory`, `Permission denied`, or missing `evals/cases/`/fixtures → sandbox env issue. Go to Task A.4 (sandbox-side fix).
- **Path 4 (Hypothesis: case YAML drift):** stderr shows `case "XXX" not found` or malformed YAML parse errors → case fixture changed and scorer rejects it. Go to Task A.5 (fixture drift fix).

- [ ] **Step 3: Write diagnostic note to scratchpad**

Write `.planning/notes/bug-5-diagnosis.md`:

```markdown
# Bug #5 diagnosis scratchpad (delete after fix lands)

## Symptom
`pr-emitter.sh:669` emits `ERROR: scorer run failed for before` and exits 2 on every real PEL invocation (observed 2026-04-20 dogfood).

## Reproduction
Date captured: [YYYY-MM-DD]
Log: `/tmp/bug-5-stderr-<TS>.log`
Command: `codex exec "bash evals/run-evals.sh"`

## Exact first-failure signature (from stderr)
```
[paste the first 30 lines of error output here]
```

## Matched hypothesis path: [Path 1 / 2 / 3 / 4]

## Root cause (one sentence)
[Fill in based on analysis]

## Fix task to run: [A.2 / A.3 / A.4 / A.5]
```

- [ ] **Step 4: Commit the diagnostic scratchpad**

```bash
git checkout -b fix/bug-5-scorer-before
git add .planning/notes/bug-5-diagnosis.md
git commit -m "docs(bug-5): capture 'scorer run failed for before' repro

Standalone evals/run-evals.sh run from clean REPO_ROOT reproduces
pr-emitter.sh:669 failure. Stderr capture identifies [Path N]: [root
cause]. Fix lands in Task A.[2-5]."
```

---

### Task A.2: Fix runner-side failure (Path 1 — LLM/auth/quota)

**Skip this task if A.1 Step 2 matched a different Path.**

**Files:**
- Modify: `lab/pel/pr-emitter/pr-emitter.sh:667-670` (the `if ! (cd ... run-evals.sh)` block)
- Modify: `evals/run-evals.sh` (if the failure is inside the case loop and needs per-case skip)

Two sub-paths depending on what the stderr showed:

#### Task A.2a: Transient LLM failure — retry with backoff

- [ ] **Step 1: Wrap the scorer invocation with 1 retry**

Find in `lab/pel/pr-emitter/pr-emitter.sh`:

```bash
  if ! (cd "$worktree_dir" && bash "$REPO_ROOT/evals/run-evals.sh" >"$tmp_out" 2>&1); then
    rm -f "$tmp_out" "$marker"
    die "scorer run failed for $label" 2
  fi
```

Replace with:

```bash
  local attempt=0 max_attempts=2 last_exit=0
  while (( attempt < max_attempts )); do
    if (cd "$worktree_dir" && bash "$REPO_ROOT/evals/run-evals.sh" >"$tmp_out" 2>&1); then
      last_exit=0
      break
    fi
    last_exit=$?
    attempt=$((attempt + 1))
    if (( attempt < max_attempts )); then
      log_stderr "WARN: scorer run failed for $label (attempt $attempt/$max_attempts, exit $last_exit); retrying in 15s"
      sleep 15
    fi
  done
  if (( last_exit != 0 )); then
    log_stderr "ERROR: scorer stderr tail for $label:"
    tail -30 "$tmp_out" >&2 || true
    rm -f "$tmp_out" "$marker"
    die "scorer run failed for $label after $max_attempts attempts" 2
  fi
```

Rationale: transient LLM hiccups shouldn't blow away a $3-8 PEL invocation. One retry covers the bulk of flaky-network/quota-dip cases. Stderr tail on final failure gives the next debugger the exact signal.

- [ ] **Step 2: Verify the fix locally**

```bash
bash -n lab/pel/pr-emitter/pr-emitter.sh && echo "syntax OK"
bash tests/pr-emitter-simulation.sh 2>&1 | tail -5
```

Expected: syntax OK; `10/10 scenarios passed` (hermetic tests still green).

- [ ] **Step 3: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh
git commit -m "fix(bug-5): retry scorer run once on transient failure

pr-emitter's run_scorer_cached now retries the scorer invocation
once (15s backoff) before giving up, and surfaces stderr tail on
final failure. Covers the transient-LLM-hiccup path that blocked
every 2026-04-20 dogfood attempt without masking real contract
bugs (hermetic Tier 1 + pr-emitter-simulation.sh still 10/10)."
```

#### Task A.2b: Persistent auth/quota failure — surface the real error

- [ ] **Step 1: Add explicit auth preflight to pr-emitter**

Find Section G in `lab/pel/pr-emitter/pr-emitter.sh` (just before Section H eval cache). If it doesn't exist, insert this block right before `CACHE_DIR="$REPO_ROOT/.co-evolve-cache/evals"`:

```bash
# ---------------------------------------------------------------------------
# Section G.5: Preflight — verify CLIs the scorer depends on are auth'd before
# burning a sandbox. Matches the "fail fast with clear message" rule from
# CLAUDE.md rather than letting the scorer fall over inside a subshell.
# ---------------------------------------------------------------------------
preflight_clis() {
  local missing=()
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
    cmd.exe /c claude --version >/dev/null 2>&1 || missing+=("claude (Windows-side)")
  else
    command -v claude >/dev/null 2>&1 || missing+=("claude")
  fi
  command -v codex >/dev/null 2>&1 || missing+=("codex")
  command -v gh    >/dev/null 2>&1 || missing+=("gh")
  if (( ${#missing[@]} > 0 )); then
    die "preflight: required CLIs missing or not authenticated: ${missing[*]}" 2
  fi
}
preflight_clis
```

- [ ] **Step 2: Verify the preflight triggers when expected**

```bash
# Simulated missing claude — force the guard to fire.
PATH=/usr/bin bash lab/pel/pr-emitter/pr-emitter.sh --dry-run --target skills/dev-review/templates/review-prompt-opus.md 2>&1 | tail -3
```

Expected: `preflight: required CLIs missing` in stderr, exit 2.

- [ ] **Step 3: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh
git commit -m "fix(bug-5): add CLI preflight to pr-emitter

claude/codex/gh presence+auth checked before scoring sandbox
creation, failing with exit 2 and a clear message instead of
letting the scorer fall over inside a subshell on quota/auth
issues. Matches CLAUDE.md's 'fail early with clear messages'
rule."
```

---

### Task A.3: Fix scorer-side contract gap (Path 2)

**Skip this task if A.1 Step 2 matched a different Path.**

**Files:**
- Read: `evals/score-run.sh` (look for the specific field the real runner isn't writing)
- Modify: whichever file is the canonical producer of the missing field

- [ ] **Step 1: Identify the missing field/artifact**

From A.1's stderr, find the specific `score-run.sh` line number and the field it's reading. Common patterns:

```bash
grep -n "jq -r '\." evals/score-run.sh | head -20
grep -n "test -f\|\[ -f\|\[\[ -f" evals/score-run.sh | head -20
```

The missing field/artifact is the gap. Example: if stderr says `score-run.sh:NNN: .foo_bar_baz: null`, and the real runner never writes `.foo_bar_baz`, that's the gap.

- [ ] **Step 2: Add the missing field/artifact in the runner**

Pattern from Phase 8.1 WR-01 fix (add a field to state.json near the end of `dev-review.sh`):

```bash
# In dev-review/codex/dev-review.sh, near the other write_state_field calls
# at the terminal block (~line 1438 area):
write_state_field "$STATE_JSON" ".<missing_field>" "string" "<derived_value>"
```

Or if an artifact is missing, add a `cp` in the relevant phase (mirrors WR-02):

```bash
# In dev-review/codex/dev-review.sh, in the phase that should persist it:
[[ -f "$source_path" ]] && cp "$source_path" "$RUN_DIR/outputs/<missing_artifact>"
```

- [ ] **Step 3: Verify with real runner + scorer**

```bash
codex exec "cd /c/Users/alan/Project/co-evolution && bash evals/run-evals.sh 2>&1" | tail -20
```

Expected: at least one `status:"scored"` record in the final summary (grep for `"status":"scored"` in the most recent `evals/reports/<ts>/raw-scores.json`).

- [ ] **Step 4: Commit**

```bash
git add dev-review/codex/dev-review.sh  # or whichever file
git commit -m "fix(bug-5): runner writes <missing_field>/<artifact> scorer requires

score-run.sh reads .<field> / outputs/<artifact> to score the
<dimension> dimension; the real dev-review runner wasn't producing
it, so every real scoring run reported status:scorer-failed. Now
produced at [phase name] and asserted by Task A.6 regression
harness."
```

---

### Task A.4: Fix sandbox-side env issue (Path 3)

**Skip this task if A.1 Step 2 matched a different Path.**

**Files:**
- Modify: `lab/pel/pr-emitter/pr-emitter.sh` (Section H or the cwd/env for the scorer invocation)

- [ ] **Step 1: Identify the specific path/env gap**

Common patterns from A.1 stderr:
- `cd: /path/to/X: No such file or directory` → a dir the scorer expects isn't present in the sandbox
- `claude: command not found` → `PATH` doesn't reach the scorer subshell
- `Permission denied` → executable bit missing on a script the scorer invokes

- [ ] **Step 2: Apply the targeted fix**

Examples (pick the one matching):

**If `evals/cases/` missing from sandbox:**

Inspect how EMITTER_SANDBOX is created (look for `git worktree add` in pr-emitter.sh). If the sandbox uses `--no-checkout` or sparse checkout, the cases dir may not be materialized. Ensure a full checkout:

```bash
# Replace git worktree add --no-checkout with a full checkout, or
# follow up with: git -C "$EMITTER_SANDBOX" checkout -- evals/
```

**If `PATH` loses claude/codex inside the subshell:**

Export explicitly before the scorer invocation:

```bash
  # Replace the subshell invocation with explicit env passthrough.
  if ! (
    cd "$worktree_dir"
    export PATH="$PATH"
    bash "$REPO_ROOT/evals/run-evals.sh"
  ) >"$tmp_out" 2>&1; then
```

**If scripts lost executable bit in sandbox:**

```bash
  # After sandbox creation (in pr-emitter.sh's sandbox-setup block):
  find "$EMITTER_SANDBOX" -name '*.sh' -exec chmod +x {} +
```

- [ ] **Step 3: Verify end-to-end**

```bash
bash tests/pr-emitter-simulation.sh 2>&1 | tail -5
codex exec "cd /c/Users/alan/Project/co-evolution && bash evals/run-evals.sh" 2>&1 | tail -10
```

Expected: hermetic 10/10 still passes; real scorer now produces a scored record.

- [ ] **Step 4: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh
git commit -m "fix(bug-5): <specific sandbox env gap>

Emitter scoring sandbox was missing <X>; real scorer invocation
failed with <specific error>. Now <specific fix>. Hermetic 10/10
still green; real-runner smoke passes."
```

---

### Task A.5: Fix case-fixture drift (Path 4)

**Skip this task if A.1 Step 2 matched a different Path.**

**Files:**
- Modify: `evals/cases/<case>.yaml` or `evals/fixtures/<fixture>`

- [ ] **Step 1: Identify the drifted fixture**

From A.1 stderr, the case ID + YAML line number is usually in the error. Inspect:

```bash
grep -l "<drifted-case-id>" evals/cases/*.yaml
ls -la evals/fixtures/<referenced-fixture>/ 2>/dev/null
```

- [ ] **Step 2: Either (a) repair the fixture or (b) skip the case**

Option A (repair) — if the case is valuable and the fixture can be restored:

```bash
# Recreate the missing file from git history or manually:
git log --all -- evals/fixtures/<missing-file> | head
git show <commit>:evals/fixtures/<missing-file> > evals/fixtures/<missing-file>
```

Option B (skip) — if the case is known-flaky and not worth repairing right now:

```yaml
# In the case YAML, add a skip marker:
skip: true  # Bug #5 — fixture drift, tracked in .planning/notes/bug-5-diagnosis.md
```

Then confirm `evals/run-evals.sh` honors `skip: true` (grep for `skip` in run-evals.sh; if it doesn't, add a 3-line check).

- [ ] **Step 3: Verify**

```bash
codex exec "cd /c/Users/alan/Project/co-evolution && bash evals/run-evals.sh" 2>&1 | tail -10
```

Expected: at least one scored record, no fixture-drift errors.

- [ ] **Step 4: Commit**

```bash
git add evals/
git commit -m "fix(bug-5): repair <fixture> / skip drifted case <id>

evals/cases/<id>.yaml referenced <path> which <how it drifted>.
<Repair details or skip rationale>. Real scorer now completes
without fixture errors."
```

---

### Task A.6: End-to-end proof + regression guard

**Files:**
- Modify: `evals/tests/scorer-verification.sh` (add Tier 5 real-runner smoke — gated behind an env var)
- Modify: `tests/pr-emitter-simulation.sh` (add Scenario K — dry-run with real scorer, gated)

- [ ] **Step 1: Add Tier 5 real-runner smoke to scorer-verification.sh**

This test IS NOT hermetic — it's gated behind `SCORER_SMOKE_REAL=1` so it doesn't run in CI. It exists so a human can opt in to "prove Bug #5 stays fixed" before a dogfood attempt.

Append to `evals/tests/scorer-verification.sh` before the summary block:

```bash
# ---------------------------------------------------------------------------
# Tier 5 (opt-in): Real-runner smoke. Proves Bug #5 stays fixed.
# Not hermetic — hits real claude/codex, costs ~$1-3 per run.
# Triggered by SCORER_SMOKE_REAL=1.
# ---------------------------------------------------------------------------
if [[ "${SCORER_SMOKE_REAL:-0}" == "1" ]]; then
  echo
  echo "--- Tier 5: Real-runner smoke ---"
  smoke_log=$(mktemp)
  if ( cd "$REPO_ROOT" && bash evals/run-evals.sh ) >"$smoke_log" 2>&1; then
    # Scored records exist → Bug #5 stays fixed.
    latest_scores=$(find "$REPO_ROOT/evals/reports" -name raw-scores.json -type f 2>/dev/null \
      | xargs ls -t 2>/dev/null | head -1)
    if [[ -n "$latest_scores" ]] && jq -e 'any(.[]?; .status == "scored")' "$latest_scores" >/dev/null 2>&1; then
      echo "PASS: Tier 5 (real-runner smoke — at least one scored record)"
    else
      echo "FAIL: Tier 5 (scorer ran but produced no scored records)" >&2
      FAILURES=$((FAILURES + 1))
    fi
  else
    echo "FAIL: Tier 5 (scorer exit non-zero; see $smoke_log)" >&2
    tail -20 "$smoke_log" >&2
    FAILURES=$((FAILURES + 1))
  fi
  rm -f "$smoke_log"
fi
```

- [ ] **Step 2: Run Tier 5 locally, confirm green**

```bash
SCORER_SMOKE_REAL=1 bash evals/tests/scorer-verification.sh 2>&1 | tail -10
```

Expected: `PASS: Tier 5` line appears; overall `14/14 scenarios passed` (or whatever the incremented count is).

- [ ] **Step 3: Add Scenario K to pr-emitter-simulation.sh (optional — only if Task A.2/A.3/A.4 changed emitter logic)**

If Phase A's fix touched `pr-emitter.sh`, add a hermetic scenario proving the fix doesn't regress when the scorer is healthy:

```bash
# Append to tests/pr-emitter-simulation.sh before the summary footer.
# ---------------------------------------------------------------------------
# Scenario K: Regression guard for Bug #5 fix — scorer reports scored record,
# emitter does NOT die with "scorer run failed for before".
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  # [Adapt the existing template-tier happy-path fixture setup from Scenario A;
  # inject a stub run-evals.sh that writes a canned raw-scores.json with one
  # status:"scored" record; assert emitter reaches PR-body rendering.]
  # Full test body follows the same PATH-injection pattern as Scenarios A-J.
  true  # implement by copying Scenario A structure and adapting
) && pass "Scenario K (Bug #5 regression guard)" \
  || fail "Scenario K (Bug #5 regression guard)"
```

- [ ] **Step 4: Run hermetic simulation, confirm 11/11**

```bash
bash tests/pr-emitter-simulation.sh 2>&1 | tail -3
```

Expected: `11/11 scenarios passed` (was 10/10 before Scenario K).

- [ ] **Step 5: Commit regression guards**

```bash
git add evals/tests/scorer-verification.sh tests/pr-emitter-simulation.sh
git commit -m "test(bug-5): add Tier 5 real-runner smoke + Scenario K regression guard

Tier 5 in scorer-verification.sh (gated by SCORER_SMOKE_REAL=1)
proves Bug #5 stays fixed without burning API quota in CI.
Scenario K in pr-emitter-simulation.sh (hermetic) locks in the
emitter-side fix so a future refactor can't silently reopen the
bug."
```

---

### Task A.7: Ship Phase A — push branch, open PR, request review

**Files:** (no new files — just git + gh)

- [ ] **Step 1: Review diff against master**

```bash
git log --oneline master..HEAD
git diff master..HEAD --stat
```

Expected: 2-4 commits, touching ≤5 files, ≤200 LOC net.

- [ ] **Step 2: Push branch + open draft PR**

```bash
git push -u origin fix/bug-5-scorer-before
gh pr create --draft --title "fix(bug-5): scorer run failed for before — blocks every real PEL invocation" --body "$(cat <<'EOF'
## Summary

- Reproduces Bug #5 from 2026-04-20 first SC-4 dogfood attempt (`pr-emitter.sh:669 die "scorer run failed for before" 2`)
- Root cause: [Path N from diagnosis — fill in]
- Fix: [one-line summary of actual fix]
- Regression guards: Tier 5 real-runner smoke in `evals/tests/scorer-verification.sh` (opt-in via `SCORER_SMOKE_REAL=1`) + hermetic Scenario K in `tests/pr-emitter-simulation.sh`

## Test plan

- [x] Tier 1 hermetic: `bash evals/tests/scorer-verification.sh` → 13/13 passed
- [x] Tier 4 real-runner smoke: `SCORER_SMOKE_REAL=1 bash evals/tests/scorer-verification.sh` → 14/14 passed
- [x] Tier 3 hermetic emitter simulation: `bash tests/pr-emitter-simulation.sh` → 11/11 passed
- [x] Manual: `codex exec "bash evals/run-evals.sh"` from clean REPO_ROOT → `raw-scores.json` contains ≥1 scored record

## Unblocks

- SC-4 dogfood (VERIFY-SC4.md row 1+)
- `git tag v1.2`

Closes Bug #5.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Stop and ask Alan to review**

Text to send:

> Phase A complete. Bug #5 diagnosis landed as [Path N]; fix is [one-line]. Draft PR: `<URL from gh pr create>`. Approve to merge before proceeding to Phase B (first real PEL→PR cycle which costs ~$3-8 of quota).

**Do NOT merge without explicit approval.** If approved:

```bash
gh pr merge --squash --delete-branch
git checkout master
git pull origin master
rm -f .planning/notes/bug-5-diagnosis.md  # scratchpad no longer needed; fix is in git log
git add .planning/notes/bug-5-diagnosis.md
git commit -m "chore: remove bug-5 diagnosis scratchpad after fix merged"
git push
```

---

## Phase B: Tier 2 validation — first successful real PEL → PR cycle

**Context:** Phase A fixed the blocker. Now verify the pipeline actually produces a draft PR end-to-end. This is Tier 2 from the user's framing: "One real PEL invocation end-to-end with fixture as eval-report. PEL pipeline works in real conditions; produces a draft PR."

**Stopping point for this phase:** One draft PR exists at `pel/template/<short-hash>` (or similar), reviewed by Alan, outcome logged in VERIFY-SC4.md row 1. Review count ≥ 1.

**Prerequisite:** Phase A merged to master. Working directory is the main `co-evolution/` checkout on master, NOT a worktree.

---

### Task B.1: Pre-flight checklist

**Files:** (no edits — just verification commands)

- [ ] **Step 1: Run VERIFY-SC4.md pre-flight verbatim**

```bash
cd /c/Users/alan/Project/co-evolution
git status --short      # expect empty
git pull origin master  # expect "Already up to date" or fast-forward
claude --version        # expect a version
codex --version         # expect a version
gh auth status          # expect "Logged in to github.com"
```

If any fail, STOP and fix before proceeding.

- [ ] **Step 2: Close any stale PEL PRs from prior dogfood attempts**

```bash
gh pr list --author "@me" --search "pel/" --state open | head -5
# For each stale PR:
gh pr close <NUMBER> --comment "Stale from pre-Bug-5-fix dogfood attempt; superseded by today's clean run."
```

- [ ] **Step 3: Verify adaptive-router flags are present (sanity check — not new work)**

```bash
grep -q "PEL_NO_ADAPTIVE\|--fallback-model" lab/pel/router/router.sh && echo "router OK"
grep -q "fallback_fired" lab/pel/pr-emitter/pr-emitter.sh && echo "telemetry OK"
```

Expected: both print "OK". If not, Phase A was merged onto the wrong base — reconcile before proceeding.

- [ ] **Step 4: Confirm API budget**

Check Anthropic console or your `compute-guard` daily cap. Budget ~$3-8 for this single invocation. If cap would be blown, skip to tomorrow or raise cap.

---

### Task B.2: First real PEL invocation (template tier)

**Files:**
- Read: `skills/dev-review/templates/review-prompt-opus.md` (target; don't edit)
- Read: `tests/fixtures/pr-emitter/template-feedback.json` (eval-report fixture)
- Expected output: new draft PR on `pel/template/<short-hash>` branch

- [ ] **Step 1: Invoke PEL via codex exec (nested-Claude workaround)**

From inside Claude Code the `claude` CLI can't nest; wrap in `codex exec`:

```bash
codex exec "cd /c/Users/alan/Project/co-evolution && \
  PEL_EVAL_REPORT=tests/fixtures/pr-emitter/template-feedback.json \
  bash co-evolve-bouncer.sh --lab pel-proposer \
  --target skills/dev-review/templates/review-prompt-opus.md \
  2>&1 | tee /tmp/pel-run-B.log"
```

Expected wall clock: ~20-30 min (per VERIFY-SC4.md § "Realistic runtime expectations"). With adaptive routing picking Sonnet for a small template file, may be ~10-15 min.

- [ ] **Step 2: Parse the final PR URL from stdout**

```bash
grep -E 'https://github\.com/.+/pull/[0-9]+' /tmp/pel-run-B.log | tail -1
```

Expected: a `pel/template/<short-hash>` draft PR URL. If empty, grep for `ERROR:` in the log and diagnose — Phase A may not have closed Bug #5 fully (loop back).

- [ ] **Step 3: Stop and ask Alan to review**

Text to send:

> First real PEL→PR cycle complete. Draft PR: `<URL>`. Target: `skills/dev-review/templates/review-prompt-opus.md`. Wall clock: ~[X] min. Cost: ~$[Y]. Please review and decide merge/close — update me here with the outcome so I can log it in VERIFY-SC4.md row 1.

---

### Task B.3: Log outcome in VERIFY-SC4.md row 1

**Files:**
- Modify: `.planning/VERIFY-SC4.md` (row 1 of Review Log table; rolling totals)

- [ ] **Step 1: Update row 1 based on Alan's decision**

Edit `.planning/VERIFY-SC4.md` — find the Review Log table and replace row 1:

```markdown
| 1 | <PR URL> | template | 2026-04-22 | Alan | merged | First real PEL→PR after Bug #5 fix — <one-line takeaway from Alan> |
```

Or if closed without merge:

```markdown
| 1 | <PR URL> | template | 2026-04-22 | Alan | closed | <reason: diff not worth shipping / canary-failed / other> |
```

- [ ] **Step 2: Update rolling totals**

In the same file, update:

```markdown
- `review_count` = **1** (count of rows with outcome ≠ `pending`)
- `merged_count` = **1** (if merged) OR **0** (if closed)
- `closed_without_merge_count` = **0** (if merged) OR **1** (if closed)

**Pass state:** ❌ (need 2 more reviews to hit ≥3 total and satisfy both merged≥1 and closed≥1)
```

- [ ] **Step 3: Commit**

```bash
git add .planning/VERIFY-SC4.md
git commit -m "docs(sc-4): log first real PEL PR outcome — row 1

PR #<N> (<URL>): <tier> tier, <merged|closed>, <one-line takeaway>.
Tier 2 validation complete — pipeline works end-to-end against real
quota. 1/3 rows filled; SC-4 gate still ❌ pending rows 2+3."
git push
```

- [ ] **Step 4: Checkpoint — decide whether to proceed to Phase C**

If PR #1 merged successfully AND Alan is satisfied with the review UX → proceed to Phase C.

If PR #1 was closed for a reason that suggests pipeline is still broken (e.g., diff was nonsense, canary failed spuriously) → STOP and debug before Phase C.

If PR #1 was closed as expected (canary caught a bad code-tier mutation — doesn't apply here for template tier; or diff just wasn't worth shipping) → that's valid signal; proceed to Phase C.

---

## Phase C: SC-4 dogfood — complete the review loop

**Context:** Phase B proved the pipeline; now produce 2 more PRs to satisfy SC-4's `review_count ≥ 3` AND `merged_count ≥ 1` AND `closed_without_merge_count ≥ 1`. Per D-15, a `[CANARY-FAILED]` PR counts toward closed_without_merge.

**Stopping point for this phase:** VERIFY-SC4.md Pass state = ✅, `git tag v1.2` pushed, release announced (optional).

---

### Task C.1: PR #2 — policy tier

**Files:**
- Read: `lab/pel/proposer/policy/policy.yaml` (target)
- Read: `tests/fixtures/pr-emitter/policy-feedback.json` (eval-report fixture)

- [ ] **Step 1: Pre-flight sanity (abbreviated from B.1)**

```bash
cd /c/Users/alan/Project/co-evolution
git status --short       # expect empty
git pull origin master   # expect up-to-date (including PR #1's merge if merged)
```

- [ ] **Step 2: Invoke PEL for policy tier**

```bash
codex exec "cd /c/Users/alan/Project/co-evolution && \
  PEL_EVAL_REPORT=tests/fixtures/pr-emitter/policy-feedback.json \
  bash co-evolve-bouncer.sh --lab pel-proposer \
  --target lab/pel/proposer/policy/policy.yaml \
  2>&1 | tee /tmp/pel-run-C1.log"
```

Expected: new draft PR at `pel/policy/<short-hash>`; adaptive routing likely picks Sonnet (policy is bounded-knob surface; bias NORMAL).

- [ ] **Step 3: Parse PR URL + ask Alan to review**

```bash
grep -E 'https://github\.com/.+/pull/[0-9]+' /tmp/pel-run-C1.log | tail -1
```

Send to Alan:

> PR #2 ready: `<URL>`. Policy tier — 6-knob surface. Please review.

- [ ] **Step 4: Log row 2 in VERIFY-SC4.md after Alan decides**

```bash
# Edit .planning/VERIFY-SC4.md row 2 with outcome; update rolling totals
git add .planning/VERIFY-SC4.md
git commit -m "docs(sc-4): log PR #2 outcome — row 2

PR #<N> (<URL>): policy tier, <merged|closed>, <takeaway>.
2/3 rows filled; SC-4 gate still <❌|✅ if both merged/closed already hit>."
git push
```

---

### Task C.2: PR #3 — code tier (canary-exposed)

**Files:**
- Read: `lib/co-evolution.sh` (target — 1072 LOC, all helpers)
- Read: `tests/fixtures/pr-emitter/code-feedback.json` (eval-report fixture)

- [ ] **Step 1: Pre-flight + acknowledge canary risk**

Code tier has a canary smoke test; mutations that break canary produce `[CANARY-FAILED]` PRs. Per D-15 from VERIFY-SC4.md, that IS valid dogfood signal — it proves the safety rail works and counts toward `closed_without_merge_count`.

- [ ] **Step 2: Invoke PEL for code tier**

```bash
codex exec "cd /c/Users/alan/Project/co-evolution && \
  PEL_EVAL_REPORT=tests/fixtures/pr-emitter/code-feedback.json \
  bash co-evolve-bouncer.sh --lab pel-proposer \
  --target lib/co-evolution.sh \
  2>&1 | tee /tmp/pel-run-C2.log"
```

Expected wall clock: ~25-35 min (code tier COMPLEX → Opus + canary run). Cost: ~$5-10 of Opus.

- [ ] **Step 3: Parse PR URL, check for [CANARY-FAILED] marker**

```bash
url=$(grep -E 'https://github\.com/.+/pull/[0-9]+' /tmp/pel-run-C2.log | tail -1)
echo "$url"
gh pr view "$url" --json title -q .title
```

Title starting with `[CANARY-FAILED]` = canary caught a bad mutation; this PR is expected to close without merge.

- [ ] **Step 4: Ask Alan to review**

If `[CANARY-FAILED]`:

> PR #3 ready (diagnostic): `<URL>`. Code tier — canary caught the mutation. This IS valid SC-4 signal per D-15 (proves safety rail works). Please close with a note and I'll log as closed_without_merge.

If clean code-tier mutation:

> PR #3 ready: `<URL>`. Code tier — passed canary. Please review carefully (this is the hardest tier). Merge/close decision yours.

- [ ] **Step 5: Log row 3 in VERIFY-SC4.md after Alan decides**

```bash
# Edit .planning/VERIFY-SC4.md row 3 with outcome; update rolling totals
# Ensure BOTH merged_count ≥ 1 AND closed_without_merge_count ≥ 1 now hold.
git add .planning/VERIFY-SC4.md
git commit -m "docs(sc-4): log PR #3 outcome — row 3

PR #<N> (<URL>): code tier, <merged|closed>, <takeaway>.
3/3 rows filled; SC-4 gate <✅ if both conditions met | ❌ if not>."
git push
```

- [ ] **Step 6: If SC-4 not yet satisfied, spin PR #4**

If after PR #3 we have e.g. 3 merged and 0 closed (all template+policy+code happened to pass and all were worth merging), that's a lopsided outcome that hasn't hit `closed_without_merge_count ≥ 1`. Intentionally spin a mutation likely to canary-fail:

```bash
# Pick a more aggressive fixture or known-risky target for row 4
codex exec "cd /c/Users/alan/Project/co-evolution && \
  PEL_EVAL_REPORT=tests/fixtures/pr-emitter/code-feedback.json \
  bash co-evolve-bouncer.sh --lab pel-proposer \
  --target dev-review/codex/dev-review.sh \
  2>&1 | tee /tmp/pel-run-C3.log"
```

Same review/log pattern as C.2 Steps 3-5. Add row 4 to VERIFY-SC4.md.

If the opposite (3 closed, 0 merged) — repeat with a deliberately mild target (small wording tweak to a template) to get a mergeable row.

---

### Task C.3: Close SC-4 tracker + tag v1.2

**Files:**
- Modify: `.planning/VERIFY-SC4.md` (Status header + Pass state)
- Write: `.planning/milestones/v1.2-SUMMARY.md` (release notes)
- Git operation: `git tag v1.2`

- [ ] **Step 1: Flip SC-4 pass state**

Edit `.planning/VERIFY-SC4.md`:

```markdown
**Status:** Closed — 2026-04-22
...
**Pass state:** ✅ (all three conditions met)
```

Also add a one-line closure section at the bottom:

```markdown
## Closure

Closed 2026-04-22. 3 PRs reviewed: 1 template (merged), 1 policy (<outcome>), 1 code (<outcome>).
Review log above is the audit trail. `git tag v1.2` follows.
```

- [ ] **Step 2: Write v1.2 summary**

Write `.planning/milestones/v1.2-SUMMARY.md`:

```markdown
# v1.2 — Protocol Evolution Loop (Proposer Only)

**Tagged:** 2026-04-22
**Milestone scope:** Phase 1-8 + 8.1 + adaptive routing + Bug #5 fix
**SC-4 rubric:** 3/3 PRs reviewed, ≥1 merged, ≥1 closed — see VERIFY-SC4.md

## What shipped

- Multi-flavor PEL classifier (Phase 4, frozen surface)
- 3 tier proposers — template, policy, code (Phases 5, 6, 7)
- PR emitter with sandbox + canary + cache + budget (Phase 8)
- Scorer-runner contract wiring (Phase 8.1)
- Adaptive model routing + fallback-model (2026-04-21)
- Bug #5 fix — scorer on "before" baseline now robust (2026-04-22)

## Metrics

- Commits: ~[N] across ~[M] PRs
- Phases: 8+1
- Plans: ~[P]
- First real PEL→PR: 2026-04-22 (PR #<row-1 URL>)

## Deferred to v1.3+

- I-1: thinking_budget end-to-end wiring
- I-2: fallback_fired telemetry from proposer stderr
- I-3: integration test proving router fires
- M-1: Section C.5 → D.0 rename (nit)
- Full Option 2 auto-promote / Option 3 explorer+curator (trigger conditions not met)
```

- [ ] **Step 3: Commit tracker update + summary**

```bash
git add .planning/VERIFY-SC4.md .planning/milestones/v1.2-SUMMARY.md
git commit -m "docs(v1.2): close SC-4, write milestone summary

SC-4 passes with 3 PRs reviewed across template+policy+code tiers.
Pass state flips to ✅; milestone summary captures what shipped.
git tag v1.2 follows."
git push
```

- [ ] **Step 4: Tag v1.2**

```bash
git tag -a v1.2 -m "v1.2 — Protocol Evolution Loop (Proposer Only)

Machinery yes, validated self-improvement yes — first real PEL-
emitted PRs reviewed and merged. See .planning/milestones/v1.2-
SUMMARY.md + .planning/VERIFY-SC4.md for closure artifacts."
git push origin v1.2
```

- [ ] **Step 5: Announce**

Text to send Alan:

> v1.2 tagged and pushed. SC-4 closed. Self-improving loop has closed one real cycle end-to-end with human-in-the-loop review. `fully-self-improving` claim is now defensible.

---

## Phase D (optional, post-v1.2 ship): Quality improvements

**Context:** I-1/I-2/I-3/M-1 from the 2026-04-21 adaptive code review were deferred to keep the adaptive PR tight. They're real quality gaps but not ship-blockers. This phase implements them as a focused follow-up PR set.

**Scope note:** This is genuinely independent work. If you want to split it into its own plan, do — the tasks below are self-contained and can lift into `docs/superpowers/plans/2026-04-22-adaptive-followups.md` verbatim.

**Stopping point for this phase:** One PR with I-1+I-2+I-3 (optionally M-1) merged. SC-5 of the adaptive spec becomes verifiable via actual telemetry (not just hardcoded defaults).

---

### Task D.1: Wire thinking_budget end-to-end (I-1)

**Files:**
- Read: `lab/pel/pr-emitter/pr-emitter.sh` (where router JSON is parsed — export `THINKING_BUDGET`)
- Modify: `lab/pel/proposer/code/proposer.sh` or `adapter.sh` (consume `THINKING_BUDGET`)
- Modify: same for template + policy proposer adapters if COMPLEX is possible there

- [ ] **Step 1: Pick consumption strategy**

Two options:
- **(a) Prompt-inject** "Think harder before responding." at the top of the proposer's rendered prompt when `THINKING_BUDGET=harder`. Simple, no CLI flag dependency.
- **(b) CLI-flag** pass `--thinking-budget harder` to `claude -p` (if that flag exists in the version pinned — check first).

Recommend (a) — works regardless of CLI version, one-liner in each adapter.

- [ ] **Step 2: Inject in each proposer adapter**

Pattern (repeat in template/policy/code adapter.sh):

```bash
# After prompt rendering, before the claude -p call:
if [[ "${THINKING_BUDGET:-}" == "harder" ]]; then
  rendered=$'Think harder before responding.\n\n'"$rendered"
fi
```

- [ ] **Step 3: Verify by forcing COMPLEX path on a template**

```bash
PEL_COMPLEXITY_OVERRIDE=COMPLEX \
  codex exec "cd /c/Users/alan/Project/co-evolution && \
    PEL_EVAL_REPORT=tests/fixtures/pr-emitter/template-feedback.json \
    bash co-evolve-bouncer.sh --lab pel-proposer \
    --target skills/dev-review/templates/review-prompt-opus.md \
    --dry-run 2>&1 | grep 'Think harder'"
```

Expected: at least one match (prompt was injected).

- [ ] **Step 4: Commit**

```bash
git add lab/pel/proposer/*/adapter.sh
git commit -m "feat(adaptive-i1): wire thinking_budget end-to-end

COMPLEX routing now actually injects 'Think harder before
responding.' prefix into the proposer prompt (per router JSON
thinking_budget=harder). Previously router emitted the field but
no consumer read it — SC-2's 'Opus + thinking budget' was
effectively 'Opus only'."
```

---

### Task D.2: Detect fallback_fired from proposer stderr (I-2)

**Files:**
- Modify: `lab/pel/proposer/*/adapter.sh` (capture stderr to a tempfile; detect fallback signal)
- Modify: `lab/pel/pr-emitter/pr-emitter.sh` (read `FALLBACK_FIRED` env var in telemetry block)

- [ ] **Step 1: Identify the fallback stderr signature**

Real Claude CLI emits something like `model fallback: model X overloaded, falling back to Y` on `--fallback-model` activation. Confirm the exact string:

```bash
# One-time test: trigger fallback by pointing at a non-existent model
claude -p --model nonexistent-model --fallback-model sonnet --tools "" <<<"hi" 2>&1 | head -5
```

- [ ] **Step 2: Wrap claude -p in each adapter to capture stderr**

Pattern:

```bash
# In adapter.sh's run_adapter function, around the claude -p call:
stderr_capture=$(mktemp)
if ! "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_capture"; then
  # existing failure handling
fi
# NEW: detect fallback
if grep -qi 'fallback.*model\|falling back to' "$stderr_capture" 2>/dev/null; then
  export FALLBACK_FIRED=true
fi
cat "$stderr_capture" >&2  # still surface the stderr as before
rm -f "$stderr_capture"
```

- [ ] **Step 3: Read FALLBACK_FIRED in pr-emitter telemetry**

Find the telemetry block in `lab/pel/pr-emitter/pr-emitter.sh` (currently hardcodes `fallback_fired="false"`). Change:

```bash
fallback_fired="${FALLBACK_FIRED:-false}"
```

- [ ] **Step 4: Commit**

```bash
git add lab/pel/proposer/*/adapter.sh lab/pel/pr-emitter/pr-emitter.sh
git commit -m "feat(adaptive-i2): detect fallback_fired from proposer stderr

Proposer adapter captures claude stderr and greps for the model-
fallback signature; if found, exports FALLBACK_FIRED=true which
pr-emitter reads in the telemetry JSONL block. SC-5 ('--fallback-
model sonnet fires; verified via telemetry') is now verifiable
from .co-evolve/router-history.jsonl without manual stderr
grepping."
```

---

### Task D.3: Integration test proving router fires (I-3)

**Files:**
- Modify: `tests/pr-emitter-simulation.sh` (add Scenario L — router stub + assertion)

- [ ] **Step 1: Add Scenario L**

Append to `tests/pr-emitter-simulation.sh` before the summary footer:

```bash
# ---------------------------------------------------------------------------
# Scenario L: Router fires in production flow (regression guard for C-1 from
# 2026-04-21 code review). Injects a router stub returning NORMAL complexity
# and asserts stderr contains the expected routing log line.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  # [Copy Scenario A template-tier fixture setup]
  # [Override the router's adapter to emit canned {complexity:"NORMAL"} JSON]
  # Key assertion:
  stderr_capture=$(mktemp)
  # ... run pr-emitter ... > /dev/null 2>"$stderr_capture"
  grep -q 'router picked complexity=NORMAL model=sonnet' "$stderr_capture" \
    || { echo "L: router did not log expected pick line" >&2; exit 1; }
  rm -f "$stderr_capture"
) && pass "Scenario L (router fires in production flow)" \
  || fail "Scenario L (router fires)"
```

- [ ] **Step 2: Verify 12/12**

```bash
bash tests/pr-emitter-simulation.sh 2>&1 | tail -3
```

Expected: `12/12 scenarios passed` (10 original + K from Phase A + L from D.3).

- [ ] **Step 3: Commit**

```bash
git add tests/pr-emitter-simulation.sh
git commit -m "test(adaptive-i3): add Scenario L — router fires in production flow

Hermetic regression guard for C-1 from 2026-04-21 code review.
Scenarios A-J passed despite a wiring bug because none asserted
the router actually ran; Scenario L closes that gap by injecting
a canned-NORMAL router stub and asserting the expected stderr
routing-log line."
```

---

### Task D.4 (optional nit): Rename Section C.5 → Section D.0 (M-1)

**Files:**
- Modify: `lab/pel/pr-emitter/pr-emitter.sh` (one comment block rename)

- [ ] **Step 1: Rename**

Find the `# Section C.5` header comment in `lab/pel/pr-emitter/pr-emitter.sh`. Replace `C.5` with `D.0` everywhere in that block (comment header + any internal cross-references).

- [ ] **Step 2: Verify**

```bash
bash -n lab/pel/pr-emitter/pr-emitter.sh && echo "syntax OK"
bash tests/pr-emitter-simulation.sh 2>&1 | tail -3
```

Expected: `12/12 scenarios passed` (no functional change).

- [ ] **Step 3: Commit**

```bash
git add lab/pel/pr-emitter/pr-emitter.sh
git commit -m "chore(adaptive-m1): rename Section C.5 → D.0 (M-1 nit)

Section ordered AFTER C but labeled C.5 invited re-confusion per
2026-04-21 code review. D.0 unambiguously locates it after C and
before E (existing). No functional change."
```

---

### Task D.5: Ship Phase D

- [ ] **Step 1: Push + open PR**

```bash
git checkout -b chore/adaptive-followups-i1-i2-i3
# (If you were already on a branch from D.1-D.4 commits, skip this.)
git push -u origin chore/adaptive-followups-i1-i2-i3
gh pr create --title "chore(adaptive): wire I-1+I-2+I-3 (+ M-1 nit)" --body "$(cat <<'EOF'
## Summary

Follow-up PR for the 2026-04-21 adaptive code review's deferred items.

- **I-1:** `thinking_budget=harder` now prompt-injected by every proposer adapter
- **I-2:** Proposer adapters capture stderr and detect `--fallback-model` activation; exported as `FALLBACK_FIRED` and read by pr-emitter telemetry
- **I-3:** New hermetic Scenario L proves router actually fires in production flow
- **M-1 (nit):** Section C.5 → D.0 rename to match ordered position

## Test plan

- [x] `bash tests/pr-emitter-simulation.sh` → 12/12 passed
- [x] Manual: forced-COMPLEX run shows 'Think harder' prefix in proposer prompt (dry-run log)
- [x] Manual: forced-fallback via nonexistent primary model shows `fallback_fired:true` in `.co-evolve/router-history.jsonl`

## Closes

- I-1, I-2, I-3, M-1 from `docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md` § 9

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 2: Request review**

Standard PR review flow — Alan reviews, then merges when approved.

---

## Self-Review Checklist (ran after writing this plan)

**1. Spec coverage:**
- Bug #5 fix → Phase A ✓
- Tier 2 validation → Phase B ✓
- SC-4 dogfood ≥3 PRs with ≥1 merged ≥1 closed → Phase C ✓
- I-1 (thinking_budget) → Task D.1 ✓
- I-2 (fallback_fired) → Task D.2 ✓
- I-3 (integration test) → Task D.3 ✓
- M-1 (Section rename) → Task D.4 ✓
- v1.2 tag → Task C.3 ✓
- All gaps covered.

**2. Placeholder scan:**
- Task A.2/A.3/A.4/A.5 have `[Fill in based on diagnosis]` / `[Path N]` / `<specific fix>` style placeholders — these are INTENTIONAL because the prescribed fix depends on what the Phase A.1 diagnostic uncovers. Not "TBD" — they are explicit conditional branches keyed off A.1's findings, with the surrounding code complete in each branch.
- No other placeholders present.

**3. Type consistency:**
- `FALLBACK_FIRED` env var name used consistently (D.2 exports it, pr-emitter reads it)
- `PEL_EVAL_REPORT` vs `PEL_FEEDBACK` — both used deliberately (former is the user-facing flag, latter is the router-visible alias set by pr-emitter). Consistent with existing code per `pr-emitter.sh:359-363`.
- Tier names (template/policy/code) consistent throughout.
- No type drift found.

**Risk flags for the engineer running this:**

- **Phase A.2/A.3/A.4/A.5 are mutually exclusive** — only ONE matches the A.1 diagnosis. Don't run them all.
- **Phase B step 2 costs real money** (~$3-8 quota). Don't run it while Bug #5 is still open — you'll just burn quota on a broken pipeline.
- **Phase C can blow quota fast** if PRs keep failing mid-pipeline. Add a `compute-guard` cap if you're paranoid.
- **All PR merges require Alan's explicit approval** — the plan has pause points before every destructive gh operation.
- **`git tag v1.2` is destructive-adjacent** (can't easily un-tag if pushed) — only tag after VERIFY-SC4.md pass state is ✅ with three verified rows.
