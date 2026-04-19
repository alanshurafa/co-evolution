#!/usr/bin/env bash
# evals/tests/fake-runner.sh
# Hermetic test double for dev-review/codex/dev-review.sh.
# Produces a deterministic `.co-evolution/runs/<id>/` subtree in the CWD so the
# evals harness can be exercised end-to-end WITHOUT paying LLM cost.
#
# Usage:
#   FAKE_MODE=pass|fail-robustness \
#     bash evals/tests/fake-runner.sh --composer STR --executor STR --bounces N \
#                                     [--verify] [--autonomous] -- "task string"
#
# FAKE_MODE controls the scorer outcome downstream of this runner:
#   pass             (default) — state.status=completed, empty outputs/runner.log.
#                     Scorer emits robustness=PASS, harness exits 0.
#   fail-robustness  — state.status=failed + outputs/runner.log contains
#                     UnhandledException. Scorer emits robustness=FAIL,
#                     harness exits 1 via the run-evals.sh robust_fails>0 branch.
#
# Security (T-02-03-11):
#   This file MUST stay under evals/tests/ (explicit test path). Every invocation
#   emits 'FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION' on stderr so any
#   accidental production use is immediately visible. The generated state.json
#   carries a "mode": "fake-runner" tag so any downstream consumer can detect
#   synthetic data.
#
# Dependencies: bash, coreutils, jq. No network. No LLM binary. No external tools.

set -euo pipefail

# Banner (T-02-03-11) -- emitted on EVERY invocation (greppable in source for
# acceptance). ASCII double-hyphen variant chosen over em-dash to dodge Git
# Bash for Windows stdout-encoding quirks; source + acceptance grep align.
echo 'FAKE RUNNER -- DO NOT INVOKE IN PRODUCTION' >&2

FAKE_MODE="${FAKE_MODE:-pass}"
case "$FAKE_MODE" in
  pass|fail-robustness) ;;
  *) echo "fake-runner: unknown FAKE_MODE '$FAKE_MODE' (want: pass | fail-robustness)" >&2; exit 2 ;;
esac

# Parse the run-evals.sh -> dev-review.sh flag surface. Accept and silently
# discard unknown flags so future orchestrator changes don't break the double.
COMPOSER=""
EXECUTOR=""
BOUNCES="0"
TASK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --composer)   COMPOSER="${2:-}"; shift 2 ;;
    --executor)   EXECUTOR="${2:-}"; shift 2 ;;
    --bounces)    BOUNCES="${2:-0}"; shift 2 ;;
    --verify)     shift ;;
    --autonomous) shift ;;
    --)           shift; TASK="${*:-}"; break ;;
    *)            shift ;;   # forward-compat: ignore unknown flags
  esac
done

# Deterministic constants -- no date calls, no $RANDOM, no $$.
# Same FAKE_MODE + same argv -> byte-identical output (after scrubbing FAKE_TS
# if a test ever compares across invocations).
FAKE_TS="19700101-000000"
RUN_ID="fake-${FAKE_TS}"
RUN_DIR=".co-evolution/runs/${RUN_ID}"
mkdir -p "${RUN_DIR}/outputs"

# Mode-dependent status.
if [[ "$FAKE_MODE" == "pass" ]]; then
  STATUS="completed"
else
  STATUS="failed"
fi

# ---------------------------------------------------------------------------
# state.json -- scorer reads .status, .run_id, .history[], .started_at,
# .updated_at (for wall-clock), .changed_files. "mode" is a fake-runner tag.
# ---------------------------------------------------------------------------

jq -n \
  --arg run_id  "$RUN_ID" \
  --arg status  "$STATUS" \
  --arg started "1970-01-01T00:00:00Z" \
  --arg ended   "1970-01-01T00:00:01Z" \
  --arg composer "$COMPOSER" \
  --arg executor "$EXECUTOR" \
  --argjson bounces_int 0 \
  --arg mode "fake-runner" \
  '{
    run_id: $run_id,
    task: "fake-runner task",
    composer: $composer,
    reviewer: $composer,
    executor: $executor,
    max_bounces: $bounces_int,
    verify: false,
    autonomous: true,
    status: $status,
    status_detail: "Synthetic fake-runner output.",
    current_phase: "verify",
    marker_counts: { contested: 0, clarify: 0, total: 0 },
    changed_files: [],
    verify_verdict: "APPROVED",
    started_at: $started,
    updated_at: $ended,
    completed_at: $ended,
    mode: $mode,
    history: [
      { phase: "compose",   status: "running", detail: "", timestamp: $started },
      { phase: "execute",   status: "running", detail: "", timestamp: $ended   },
      { phase: "verify",    status: "running", detail: "", timestamp: $ended   }
    ]
  }' > "${RUN_DIR}/state.json"

# ---------------------------------------------------------------------------
# plan.md -- must contain default plan_quality heading groups:
#   (Plan|Approach|Strategy) + (Risks|Concerns|Caveats)
# plus enough words to clear min_word_count=40 (01-trivial-task's override).
# No leading whitespace on the heading lines -- scorer's ^#+[[:space:]]+ regex
# is anchored.
# ---------------------------------------------------------------------------

cat > "${RUN_DIR}/plan.md" <<'PLAN_EOF'
# Fake Runner Plan

## Approach

This is a hermetic test plan emitted by evals/tests/fake-runner.sh. It is NOT
a real plan; it satisfies the plan_quality heading and word-count expectations
so the eval harness orchestrator can be exercised end-to-end without LLM cost.

## Implementation

1. Emit state.json describing the synthetic run.
2. Emit a verdict.json matching schemas/review-verdict.json required fields.
3. Return exit 0 regardless of FAKE_MODE.

## Files to Change

- (no file changes)

## Risks

- This artifact must never ship to production. The calling script emits a
  stderr banner on every invocation so accidental use is visible.
- Do not confuse fake-runner output with real dev-review runs: state.json
  carries a "mode": "fake-runner" tag downstream consumers can detect.
PLAN_EOF

# ---------------------------------------------------------------------------
# verdict.json -- matches schemas/review-verdict.json required fields:
#   verdict, confidence, summary, issues, scope_creep_detected, iteration_notes
# ---------------------------------------------------------------------------

jq -n '{
  verdict: "APPROVED",
  confidence: 90,
  summary: "Fake verdict produced by evals/tests/fake-runner.sh.",
  issues: [],
  scope_creep_detected: false,
  iteration_notes: ""
}' > "${RUN_DIR}/verdict.json"

# ---------------------------------------------------------------------------
# outputs/runner.log -- empty in pass mode; contains exception marker in
# fail-robustness mode (triggers scorer robustness grep).
# ---------------------------------------------------------------------------

if [[ "$FAKE_MODE" == "fail-robustness" ]]; then
  cat > "${RUN_DIR}/outputs/runner.log" <<'LOG_EOF'
FAKE RUNNER log
Simulated failure: UnhandledException: synthetic error for Tier 2 FAIL scenario
LOG_EOF
else
  : > "${RUN_DIR}/outputs/runner.log"
fi

exit 0
