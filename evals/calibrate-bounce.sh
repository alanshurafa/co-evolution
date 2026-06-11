#!/usr/bin/env bash
# evals/calibrate-bounce.sh — Layer-3 calibration batch (v1.3 Phase 5).
#
# Scores every bounce run under a runs directory with the deterministic
# scorer (free), optionally judges the passing ones (LLM spend, opt-in),
# and writes evals/reports/bounce-calibration-<date>.md with aggregate
# distributions, a threshold-tuning section, and the human-sampling
# worksheet (Layer 3 needs a person; this script prepares their packet).
#
#   bash evals/calibrate-bounce.sh --runs-dir runs/                # score only
#   bash evals/calibrate-bounce.sh --runs-dir runs/ --judge        # + LLM judge
#   bash evals/calibrate-bounce.sh --runs-dir runs/ --judge --max-judge 10
#
# Scoring artifacts (bounce-scores.json etc.) are written INTO each run dir;
# the report contains only aggregates and run names, no document content —
# safe to commit even when runs/ holds personal documents.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"

command -v jq >/dev/null 2>&1 || die "jq is required"

RUNS_DIR=""
DO_JUDGE=false
MAX_JUDGE=10
REPORT_DIR="$REPO_ROOT/evals/reports"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs-dir)  RUNS_DIR="${2:?}"; shift 2 ;;
    --judge)     DO_JUDGE=true; shift ;;
    --max-judge) MAX_JUDGE="${2:?}"; shift 2 ;;
    --report-dir) REPORT_DIR="${2:?}"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done
[[ -n "$RUNS_DIR" && -d "$RUNS_DIR" ]] || die "--runs-dir <existing dir> is required"
mkdir -p "$REPORT_DIR"

DATE_TAG=$(date -u +%Y-%m-%d)
REPORT="$REPORT_DIR/bounce-calibration-$DATE_TAG.md"
SUMMARY=$(mktemp)
trap 'rm -f "$SUMMARY"' EXIT
printf '[]' > "$SUMMARY"

scored=0
skipped=0
judged=0

for run_dir in "$RUNS_DIR"/*/; do
  [[ -d "$run_dir" ]] || continue
  name=$(basename "$run_dir")
  # A bounce run has a baseline artifact; anything else is skipped.
  if [[ ! -f "$run_dir/original-input.md" && ! -f "$run_dir/original.md" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  rc=0
  bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$run_dir" >/dev/null 2>&1 || rc=$?
  if [[ ! -f "$run_dir/bounce-scores.json" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  scored=$((scored + 1))

  verdict="(not judged)"
  if [[ "$DO_JUDGE" == true && "$rc" -eq 0 && "$judged" -lt "$MAX_JUDGE" ]]; then
    jrc=0
    bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$run_dir" >/dev/null 2>&1 || jrc=$?
    if [[ "$jrc" -eq 0 && -f "$run_dir/judge-verdict.json" ]]; then
      verdict=$(jq -r '.verdict' "$run_dir/judge-verdict.json")
      judged=$((judged + 1))
    fi
  fi

  entry=$(jq -c --arg name "$name" --arg verdict "$verdict" '
    {name: $name,
     mode: .mode, source: .source, pass_count: .pass_count,
     overall: .overall_pass,
     d1: .dimensions.loop_execution.pass,
     d2: .dimensions.structural_preservation.pass,
     d3: .dimensions.scope_discipline.pass,
     d4: .dimensions.material_engagement.pass,
     word_ratio: .dimensions.scope_discipline.word_ratio,
     anchor_retention: .dimensions.structural_preservation.anchor_retention,
     fates: ([.marker_ledger[].fate] | group_by(.) | map({(.[0]): length}) | add // {}),
     judge: $verdict}' "$run_dir/bounce-scores.json")
  jq -c --argjson e "$entry" '. += [$e]' "$SUMMARY" > "$SUMMARY.tmp" && mv "$SUMMARY.tmp" "$SUMMARY"
  log "INFO: scored $name (overall=$(printf '%s' "$entry" | jq -r '.overall'), judge=$verdict)"
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
{
  printf '# Bounce Calibration — %s\n\n' "$DATE_TAG"
  printf 'Scored **%d** runs (skipped %d non-bounce dirs) under `%s`. Judged: %d.\n\n' "$scored" "$skipped" "$RUNS_DIR" "$judged"

  printf '## Gate outcomes\n\n'
  printf '| Outcome | Count |\n|---------|-------|\n'
  jq -r 'group_by(.overall) | map("| overall_pass=\(.[0].overall) | \(length) |") | .[]' "$SUMMARY"
  printf '\n'
  printf '| Dimension | Pass | Fail |\n|-----------|------|------|\n'
  for d in d1 d2 d3 d4; do
    jq -r --arg d "$d" '"| \($d) | \([.[] | select(.[$d] == true)] | length) | \([.[] | select(.[$d] == false)] | length) |"' "$SUMMARY"
  done
  printf '\n'

  printf '## Marker-fate distribution\n\n'
  jq -r '[.[].fates | to_entries[]] | group_by(.key) | map("- **\(.[0].key)**: \(map(.value) | add)") | .[]' "$SUMMARY"
  printf '\n'

  printf '## Distribution inputs for threshold tuning\n\n'
  printf 'Word ratios (sorted): %s\n\n' "$(jq -r '[.[].word_ratio] | sort | @csv' "$SUMMARY")"
  printf 'Anchor retention (sorted): %s\n\n' "$(jq -r '[.[].anchor_retention] | sort | @csv' "$SUMMARY")"
  printf 'Compare these against the bands in `evals/bounce-thresholds.yaml`; a band that fails >30%% of historically-good runs is probably miscalibrated, a band that everything passes is probably toothless.\n\n'

  printf '## Judge verdicts\n\n'
  jq -r 'map(select(.judge != "(not judged)")) | if length == 0 then "_No runs judged in this batch (use --judge)._" else (group_by(.judge) | map("- **\(.[0].judge)**: \(length)") | .[]) end' "$SUMMARY"
  printf '\n'

  printf '## Per-run results\n\n'
  printf '| Run | Mode | Src | Passes | Gate | Judge |\n|-----|------|-----|--------|------|-------|\n'
  jq -r '.[] | "| \(.name) | \(.mode) | \(.source) | \(.pass_count) | \(if .overall then "PASS" else "FAIL" end) | \(.judge) |"' "$SUMMARY"
  printf '\n'

  printf '## Human sampling worksheet (Layer 3)\n\n'
  printf 'Pick %s of the judged runs above (mix of improved/tie/regressed). For each, WITHOUT looking at the judge verdict:\n\n' "5"
  printf '1. Open `<run>/original-input.md` and `<run>/working.md` side by side.\n'
  printf '2. Decide: improved / regressed / tie.\n'
  printf '3. Record your call next to the judge'\''s in the table below.\n\n'
  printf '| Run | Your verdict | Judge verdict | Agree? |\n|-----|--------------|---------------|--------|\n'
  printf '| | | | |\n| | | | |\n| | | | |\n| | | | |\n| | | | |\n\n'
  printf 'Agreement >= 4/5: trust the judge for routine gating. Agreement <= 2/5 (or systematic self-preference): wire a third-family judge (e.g. via OpenRouter, see audit Phase 5 notes) before relying on verdicts.\n'
} > "$REPORT"

log "INFO: calibration report -> $REPORT"
printf '%s\n' "$REPORT"
