#!/usr/bin/env bash
# evals/report-bounce.sh — HUMAN-REPORT.md generator (v1.3 Phase 5).
#
# Renders a bounce run for a NON-EXPERT: what happened, pass by pass, what
# happened to every disagreement marker, the deterministic scorecard, the
# blind-judge verdict with its quotes — and an honest section on what these
# measurements cannot tell you.
#
#   bash evals/report-bounce.sh --run-dir <dir>            # standalone
#
# Reads state.json / bounce-scores.json / judge-verdict.json when present;
# runs the scorer itself if scores are missing (deterministic, no LLM cost).
# Works on historical runs. Never exits nonzero for an ugly run — the report
# IS the product; only operational errors fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"

command -v jq >/dev/null 2>&1 || die "jq is required for report-bounce.sh"

RUN_DIR=""
OUTPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:?--run-dir needs a value}"; shift 2 ;;
    --output)  OUTPUT_FILE="${2:?--output needs a value}"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done
[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || die "--run-dir <existing dir> is required"
[[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="$RUN_DIR/HUMAN-REPORT.md"

SCORES="$RUN_DIR/bounce-scores.json"
if [[ ! -f "$SCORES" ]]; then
  bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$RUN_DIR" --output "$SCORES" >/dev/null 2>&1 || true
fi
[[ -f "$SCORES" ]] || die "could not produce bounce-scores.json for $RUN_DIR"

STATE="$RUN_DIR/state.json"
VERDICT_FILE="$RUN_DIR/judge-verdict.json"

s() { jq -r "$1" "$SCORES"; }

MODE=$(s '.mode')
PASS_COUNT=$(s '.pass_count')
OVERALL=$(s '.overall_pass')
RUN_STATUS=$(s '.run_status')

yn() { [[ "$1" == "true" ]] && printf 'PASS' || printf 'FAIL'; }

{
  printf '# Bounce Run Report — %s\n\n' "$(basename "$RUN_DIR")"

  # --- What happened -----------------------------------------------------
  printf '## What happened\n\n'
  case "$MODE" in
    compose)       printf 'A draft was composed from the task, then two AI agents took turns reviewing and revising it.\n' ;;
    bounce-only)   printf 'An existing document was passed back and forth between two AI agents, each reviewing and revising the other'\''s work.\n' ;;
    chain)         printf 'The document went through a three-step critique, defend, tighten sequence between AI agents.\n' ;;
    agent-bouncer) printf 'The document was bounced between two AI agents using the legacy agent-bouncer runner.\n' ;;
    *)             printf 'A document refinement run of mode "%s".\n' "$MODE" ;;
  esac
  printf 'The run completed %s pass(es)' "$PASS_COUNT"
  [[ "$RUN_STATUS" == "aborted" ]] && printf ' and was ABORTED before finishing'
  printf '. Behavior gate: **%s**.\n\n' "$(yn "$OVERALL")"
  if [[ "$OVERALL" != "true" ]]; then
    printf 'Because the behavior gate failed, no claim is made about whether the document got better. The failed checks below say what went wrong mechanically.\n\n'
  fi

  # --- Pass-by-pass table --------------------------------------------------
  printf '## Pass by pass\n\n'
  if [[ -f "$STATE" ]] && jq -e '.passes | length > 0' "$STATE" >/dev/null 2>&1; then
    printf '| Pass | Role | Agent | Open markers after | Words |\n'
    printf '|------|------|-------|--------------------|-------|\n'
    jq -r '.passes[] | "| \(.pass) | \(.role) | \(.agent) | \(.total_markers) | \(.word_count) |"' "$STATE"
  else
    printf '_No state.json — pass table reconstructed from artifacts._\n\n'
    printf '| Pass | Edit ratio vs previous |\n|------|------------------------|\n'
    jq -r '.dimensions.material_engagement.pass_edit_ratios[]? | "| \(.pass) | \(.edit_ratio) |"' "$SCORES"
  fi
  printf '\n'

  # --- Marker ledger --------------------------------------------------------
  printf '## What happened to each disagreement\n\n'
  printf 'Markers are the agents'\'' recorded disagreements ([CONTESTED]) and open questions ([CLARIFY]). Each one'\''s fate:\n\n'
  if [[ "$(s '.marker_ledger | length')" == "0" ]]; then
    printf '_No markers were raised in this run._\n'
  else
    printf '| Type | Section | Disagreement | Fate |\n'
    printf '|------|---------|--------------|------|\n'
    jq -r '.marker_ledger[] | "| \(.type) | \(.heading) | \(.text | .[0:60]) | **\(.fate)** |"' "$SCORES"
    printf '\n'
    printf 'Fates: **resolved** = addressed with the section intact; **deleted-with-section** = the disagreement vanished because its whole section was deleted (this fails the run); **expired** = carried unresolved until the pass limit forced it out; **unresolved** = still live in the final document.\n'
  fi
  printf '\n'

  # --- Scorecard -------------------------------------------------------------
  printf '## Scorecard (deterministic checks)\n\n'
  printf '| Dimension | Result | Details |\n'
  printf '|-----------|--------|---------|\n'
  jq -r '
    .dimensions | to_entries[] |
    "| \(.key | gsub("_"; " ")) | \(if .value.pass then "PASS" else "FAIL" end) | \([.value.checks[]? | select(.ok == false) | .detail] | if length == 0 then "all checks green" else join("; ") end) |"
  ' "$SCORES"
  printf '\n'

  # --- Judge verdict -----------------------------------------------------------
  printf '## Independent quality judgment\n\n'
  if [[ -f "$VERDICT_FILE" ]] && jq -e '.schema == "bounce-judge/1.0"' "$VERDICT_FILE" >/dev/null 2>&1; then
    v=$(jq -r '.verdict' "$VERDICT_FILE")
    ev=$(jq -r '.evidence_verified' "$VERDICT_FILE")
    case "$v" in
      improved)        printf 'A blind judge (shown the before/after as anonymous documents, twice, in both orders) found the final version **better** than the input.\n' ;;
      regressed)       printf 'A blind judge found the final version **worse** than the input.\n' ;;
      tie)             printf 'A blind judge could not separate the two versions (**tie**).\n' ;;
      position_biased) printf 'The judge contradicted itself when the document order was swapped (**position bias**) — no quality claim is made.\n' ;;
      invalid-evidence) printf 'The judge'\''s cited quotes could not be found in the documents (**invalid evidence**) — the verdict is not trusted.\n' ;;
    esac
    printf '\n'
    if jq -e '.self_preference_risk == true' "$VERDICT_FILE" >/dev/null; then
      printf '_Caveat: the judge is the same model family as one of the bounce agents (self-preference risk)._\n\n'
    fi
    if [[ "$ev" == "true" ]] && jq -e '.evidence | length > 0' "$VERDICT_FILE" >/dev/null; then
      printf 'Evidence the judge cited (verified verbatim):\n\n'
      jq -r '.evidence[] | select(.verified) | "> \(.quote)\n"' "$VERDICT_FILE"
    fi
  else
    printf '_Not judged yet. Run:_ `bash evals/judge-bounce.sh --run-dir %s`\n' "$RUN_DIR"
  fi
  printf '\n'

  # --- Honest limits -------------------------------------------------------------
  printf '## What we cannot measure\n\n'
  printf -- '- The deterministic checks confirm the loop **behaved** correctly — they cannot confirm the output is **genuinely better**. That needs the blind judge (above) and periodic human spot-checks.\n'
  printf -- '- The blind judge is an LLM: it can be wrong, and when it is the same model family as a bounce agent it may favor its own style (flagged above when applicable).\n'
  printf -- '- Convergence is partly forced: the final pass is instructed to remove remaining markers, so "0 markers" alone never proves agreement — that is why the marker-fate ledger exists.\n'
  printf -- '- Thresholds are initial estimates pending calibration against human judgments (`evals/bounce-thresholds.yaml`).\n'
} > "$OUTPUT_FILE"

log "INFO: report written -> $OUTPUT_FILE"
