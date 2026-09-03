#!/usr/bin/env bash
# What a running batch is doing right now, and whether it is still moving.
#
# A long batch fails in two ways that look identical from outside: it finishes,
# or it wedges on a provider call that never returns. Cell counts alone cannot
# tell those apart, so this reports the age of the most recent write as well as
# the totals, and says STALLED when nothing has changed for a while.
#
# Usage: bash bench-status.sh RUN_ID [SUITE]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

RUN_ID="${1:?usage: bench-status.sh RUN_ID [SUITE]}"
SUITE="${2:-$(code_suite_id)}"
STALL_SECONDS="${CODE_BENCH_STALL_SECONDS:-900}"

RUNS="$CODE_BENCH_RESULTS_ROOT/runs/$RUN_ID"
[[ -d "$RUNS" ]] || { printf 'run %s has not started\n' "$RUN_ID"; exit 0; }

suite_json=$(code_suite_json "$SUITE") || exit 1
subset=$(code_subset_path "$suite_json")
total=$(jq '.instances | length' "$subset" | tr -d '\r')

now=$(date +%s)
newest=0
printf 'run %s · suite %s · %s\n' "$RUN_ID" "$SUITE" "$(date '+%Y-%m-%d %H:%M:%S')"

# One line per arm: finished cells, and how many of those actually produced a
# patch. A cell that ran and produced nothing is progress too, just not a patch.
for cond_dir in "$RUNS"/*/*/; do :; done
conditions=$(ls -d "$RUNS"/*/*/ 2>/dev/null | awk -F/ '{print $(NF-1)}' | sort -u)
for cond in $conditions; do
  # Done means a prediction exists. A prepared directory only means a workspace
  # was cloned, which is not progress a reader should count as a finished task.
  preds=$(ls -d "$RUNS"/*/"$cond"/prediction.json 2>/dev/null | wc -l | tr -d ' ')
  nopatch=$(ls -d "$RUNS"/*/"$cond"/outcome.json 2>/dev/null | wc -l | tr -d ' ')
  pct=$(( total > 0 ? preds * 100 / total : 0 ))
  printf '  %s  %3s/%s done (%s%%)  %s ran without a patch\n' \
    "$cond" "$preds" "$total" "$pct" "$nopatch"
done

# Newest write among the cells' own metadata. The cloned workspaces are pruned:
# they hold tens of thousands of files each and walking them takes minutes,
# which would make the status check slower than the thing it reports on.
while IFS= read -r stamp; do
  (( stamp > newest )) && newest=$stamp
done < <(find "$RUNS" -name workspace -prune -o -type f \
           \( -name 'prediction.json' -o -name 'run-manifest.json' \
              -o -name 'outcome.json' -o -name '*.log' -o -name '*.json' \) \
           -printf '%T@\n' 2>/dev/null | cut -d. -f1)

if (( newest == 0 )); then
  printf 'activity: none in the last 6 hours\n'
  exit 0
fi
age=$(( now - newest ))
if (( age > STALL_SECONDS )); then
  printf 'activity: STALLED - last write %ss ago (threshold %ss)\n' "$age" "$STALL_SECONDS"
else
  printf 'activity: running - last write %ss ago\n' "$age"
fi

# Git Bash's ps reports the interpreter, not the script, so counting shard
# scripts by name finds nothing. The model CLIs are what an active cell is
# actually waiting on, and those do show up under their own names.
live=$(ps 2>/dev/null | grep -cE '/claude$|/codex$|claude-code' || true)
printf 'model processes in flight: %s\n' "$live"
