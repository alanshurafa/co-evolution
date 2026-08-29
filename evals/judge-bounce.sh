#!/usr/bin/env bash
# evals/judge-bounce.sh — Layer 2 of the bounce evaluation gate (v1.3 Phase 5).
#
# Blind A/B quality judgment: baseline vs final presented as anonymous
# "Document A" / "Document B" (markers, HUMAN SUMMARY blocks, and provenance
# stripped), two symmetric trials with the order swapped. Agreement produces
# a verdict (improved / regressed / tie); disagreement produces
# position_biased and NO quality claim. Every evidence quote is grep-verified
# against the document it cites — fabricated evidence invalidates the verdict.
#
# Ordering is enforced mechanically: this script REFUSES to run unless the
# run has a bounce-scores.json with overall_pass=true (Layer 1, $0). A run
# that failed the behavior gate gets no quality claim and no judge spend.
#
#   bash evals/judge-bounce.sh --run-dir <dir> [--judge-cmd claude]
#                               [--judge-model claude-fable-5] [--judge-effort high]
#
# Owner decision (2026-06-10): quality judgment is delegated to the strongest
# available model at high effort — Fable 5 today; the flags/envs exist so the
# judge can move (newer Claude, a codex model) without touching this script.
#
# Output: <run-dir>/judge-verdict.json (schema bounce-judge/1.0)
# Exit: 0 verdict written (any verdict incl. tie/position_biased),
#       2 ordering violation (no passing scores), 3 judge CLI failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"
# Blinding, trial loop, and evidence verification live in a shared lib so the
# benchmark judge harness reuses them instead of forking them.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/judge-lib.sh"

command -v jq >/dev/null 2>&1 || die "jq is required for judge-bounce.sh"

RUN_DIR=""
JUDGE_CMD="${JUDGE_CMD:-claude}"
JUDGE_MODEL="${JUDGE_MODEL:-claude-fable-5}"
JUDGE_EFFORT="${JUDGE_EFFORT:-high}"
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)      RUN_DIR="${2:?--run-dir needs a value}"; shift 2 ;;
    --judge-cmd)    JUDGE_CMD="${2:?--judge-cmd needs a value}"; shift 2 ;;
    --judge-model)  JUDGE_MODEL="${2:-}"; shift 2 ;;
    --judge-effort) JUDGE_EFFORT="${2:-}"; shift 2 ;;
    --output)       OUTPUT_FILE="${2:?--output needs a value}"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done

# Model/effort flags only apply to the claude CLI; a future non-claude judge
# (codex etc.) sets its own conventions via --judge-cmd and empty model.
JUDGE_ARGS=()
if [[ "$JUDGE_CMD" == "claude" ]]; then
  [[ -n "$JUDGE_MODEL" ]] && JUDGE_ARGS+=(--model "$JUDGE_MODEL")
  [[ -n "$JUDGE_EFFORT" ]] && JUDGE_ARGS+=(--effort "$JUDGE_EFFORT")
fi

[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || die "--run-dir <existing dir> is required"
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="$RUN_DIR/judge-verdict.json"

# --- Layer-1 ordering gate ---------------------------------------------------
SCORES="$RUN_DIR/bounce-scores.json"
if [[ ! -f "$SCORES" ]]; then
  log "ERROR: no bounce-scores.json in $RUN_DIR — run evals/score-bounce.sh first (Layer 1 before Layer 2)."
  exit 2
fi
if ! jq -e '.schema == "bounce-scores/1.0" and .overall_pass == true' "$SCORES" >/dev/null 2>&1; then
  log "ERROR: bounce-scores.json shows overall_pass != true — a run that failed the behavior gate gets no quality judgment."
  exit 2
fi

MODE=$(jq -r '.mode' "$SCORES")
BASELINE_REL="original-input.md"
[[ "$MODE" == "compose" ]] && BASELINE_REL="compose-output.md"
[[ -f "$RUN_DIR/$BASELINE_REL" ]] || BASELINE_REL="original.md"
BASELINE="$RUN_DIR/$BASELINE_REL"
FINAL="$RUN_DIR/working.md"
[[ -f "$FINAL" ]] || FINAL=$(ls "$RUN_DIR"/*.md 2>/dev/null | head -1)
[[ -f "$BASELINE" && -f "$FINAL" ]] || die "baseline/final artifacts missing in $RUN_DIR"

command -v "$JUDGE_CMD" >/dev/null 2>&1 || { log "ERROR: judge CLI '$JUDGE_CMD' not found"; exit 3; }

WORK=$(mktemp -d -t judge-bounce-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# --- Blinding (judge_blind, evals/lib/judge-lib.sh) ---------------------------
judge_blind "$BASELINE" > "$WORK/doc-baseline.md"
judge_blind "$FINAL"    > "$WORK/doc-final.md"

# --- Blind trials (judge_run_trial, evals/lib/judge-lib.sh) -------------------
log "INFO: blind trial 1/2 (baseline=A, final=B)"
if ! judge_run_trial "$WORK/doc-baseline.md" "$WORK/doc-final.md" "$WORK/trial1.json"; then
  log "ERROR: no verdict — judge trial failed (cause logged above)."
  exit 3
fi
log "INFO: blind trial 2/2 (final=A, baseline=B)"
if ! judge_run_trial "$WORK/doc-final.md" "$WORK/doc-baseline.md" "$WORK/trial2.json"; then
  log "ERROR: no verdict — judge trial failed (cause logged above)."
  exit 3
fi

# --- Decode positions back to baseline/final ----------------------------------
# Trial 1: A=baseline B=final.  Trial 2: A=final B=baseline.
decode() { # $1=trial-file $2=A-meaning $3=B-meaning
  local b
  b=$(jq -r '.better' "$1")
  case "$b" in
    A) printf '%s' "$2" ;;
    B) printf '%s' "$3" ;;
    *) printf 'tie' ;;
  esac
}
T1=$(decode "$WORK/trial1.json" baseline final)
T2=$(decode "$WORK/trial2.json" final baseline)

if [[ "$T1" == "$T2" ]]; then
  case "$T1" in
    final)    VERDICT="improved" ;;
    baseline) VERDICT="regressed" ;;
    tie)      VERDICT="tie" ;;
  esac
else
  VERDICT="position_biased"
fi

# --- Evidence verification (judge_* helpers, evals/lib/judge-lib.sh) -----------
# Each quote must appear in the document it cites (whitespace-normalized
# substring). Fabricated evidence invalidates the verdict.
NORM_T1A=$(judge_norm "$WORK/doc-baseline.md"); NORM_T1B=$(judge_norm "$WORK/doc-final.md")
NORM_T2A=$(judge_norm "$WORK/doc-final.md");    NORM_T2B=$(judge_norm "$WORK/doc-baseline.md")

judge_reset_evidence_state
judge_check_trial_evidence "$WORK/trial1.json" "$NORM_T1A" "$NORM_T1B" 1
judge_check_trial_evidence "$WORK/trial2.json" "$NORM_T2A" "$NORM_T2B" 2

# Invalidate the verdict only when the MAJORITY of quotes fail — that is the
# fabrication signature. Isolated misses keep the verdict but are recorded
# per-quote and surface as evidence_verified=false.
if (( EVIDENCE_TOTAL > 0 && EVIDENCE_FAILED * 2 > EVIDENCE_TOTAL )) && [[ "$VERDICT" != "position_biased" ]]; then
  VERDICT="invalid-evidence"
fi

# Self-preference: the default judge (claude) is the same model family that
# wrote half the passes — flag it; calibration decides if a third-family
# judge is needed.
SELF_PREF=true
[[ "$JUDGE_CMD" != "claude" ]] && SELF_PREF=false

jq -S -n \
  --arg schema "bounce-judge/1.0" \
  --arg judged_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg run_dir "$(basename "$RUN_DIR")" \
  --arg judge_cmd "$JUDGE_CMD" \
  --arg judge_model "${JUDGE_MODEL:-default}" \
  --arg judge_effort "${JUDGE_EFFORT:-default}" \
  --arg verdict "$VERDICT" \
  --argjson self_preference_risk "$SELF_PREF" \
  --argjson evidence_verified "$([[ "$EVIDENCE_OK" == true ]] && echo true || echo false)" \
  --argjson trial1 "$(cat "$WORK/trial1.json")" \
  --argjson trial2 "$(cat "$WORK/trial2.json")" \
  --argjson evidence "$VERIFIED_EVIDENCE" \
  '{
    schema: $schema,
    judged_at: $judged_at,
    run_dir: $run_dir,
    judge_cmd: $judge_cmd,
    judge_model: $judge_model,
    judge_effort: $judge_effort,
    verdict: $verdict,
    self_preference_risk: $self_preference_risk,
    evidence_verified: $evidence_verified,
    trials: [
      {order: "baseline=A final=B", raw: $trial1},
      {order: "final=A baseline=B", raw: $trial2}
    ],
    evidence: $evidence
  }' > "$OUTPUT_FILE"

log "INFO: verdict=$VERDICT (evidence_verified=$EVIDENCE_OK) -> $OUTPUT_FILE"
