#!/usr/bin/env bash
# Read-only status of a benchmark phase, for whichever orchestrator asks.
#
#   phase-status.sh [--json] PHASE_ID-RUN_ID | --list
#
# Exit codes let a caller branch without parsing: 0 the phase is at a resting
# state (gate ready, or a stage complete), 4 shards are still running, 5 a
# stage failed or is blocked, 6 no such phase. Never reads a raw log.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

JSON=false
LIST=false
TARGET=""
while (( $# > 0 )); do
  case "$1" in
    --json) JSON=true; shift ;;
    --list) LIST=true; shift ;;
    *) TARGET="$1"; shift ;;
  esac
done
PHASES="$CODE_BENCH_RESULTS_ROOT/phases"

if [[ "$LIST" == true ]]; then
  for f in "$PHASES"/*/phase-state.json; do
    [[ -f "$f" ]] || continue
    jq -r '"\(.phase_id)-\(.run_id)\t\(.stage)\t\(.stages[.stage].state // "-")\t\(.orchestrator)"' "$f"
  done
  exit 0
fi
[[ -n "$TARGET" ]] || { code_die "usage: phase-status.sh [--json] PHASE_ID-RUN_ID | --list"; exit 2; }
STATE="$PHASES/$TARGET/phase-state.json"
[[ -f "$STATE" ]] || { printf 'no phase %s under %s\n' "$TARGET" "$PHASES" >&2; exit 6; }

alive=false
while IFS= read -r pid; do
  [[ -n "$pid" ]] || continue
  kill -0 "$pid" 2>/dev/null && alive=true
done < <(jq -r '.stages.dispatch.detail.pids[]? // empty' "$STATE" 2>/dev/null)

summary=$(jq -c --argjson alive "$alive" '{
  phase: "\(.phase_id)-\(.run_id)", suite, model_tier, orchestrator, conditions,
  stage, stage_state: (.stages[.stage].state // null), shards_alive: $alive,
  spend_approved, stages: (.stages | with_entries(.value = .value.state)),
  progress: (.stages.watch.detail // null | if . then {cells_done, cells_expected} else null end),
  gate: (.gate.verdict // null)}' "$STATE")

if [[ "$JSON" == true ]]; then printf '%s\n' "$summary" | jq .
else printf '%s\n' "$summary" | jq -r '"phase \(.phase) · \(.suite) · \(.model_tier) · orchestrator \(.orchestrator)\nstage \(.stage) (\(.stage_state)) · shards alive: \(.shards_alive) · spend approved: \(.spend_approved != null)\nprogress: \(.progress // "n/a") · gate: \(.gate // "not run")"'
fi

state=$(printf '%s' "$summary" | jq -r '.stage_state')
if [[ "$alive" == true ]]; then exit 4; fi
case "$state" in
  failed|blocked|incomplete|not-ready) exit 5 ;;
  *) exit 0 ;;
esac
