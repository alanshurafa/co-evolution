#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

RUN_ID=""
CONDITIONS="A,B,C"
TASK_LIMIT=1
TASK=""
SHARD_SPEC=""
MODEL_TIER=$(code_model_tier)
MAX_CLAUDE=""
DRY_RUN=false
SUITE=$(code_suite_id)

while (( $# > 0 )); do
  case "$1" in
    --run-id) RUN_ID="${2:?--run-id needs a value}"; shift 2 ;;
    --conditions) CONDITIONS="${2:?--conditions needs a value}"; shift 2 ;;
    --task-limit) TASK_LIMIT="${2:?--task-limit needs a value}"; shift 2 ;;
    --task) TASK="${2:?--task needs a value}"; shift 2 ;;
    --shard) SHARD_SPEC="${2:?--shard needs N/M}"; shift 2 ;;
    --models) MODEL_TIER="${2:?--models needs a tier}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) code_die "unknown canary option: $1"; exit 2 ;;
  esac
done

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "--run-id is required and must be filesystem-safe"; exit 2; }
[[ "$TASK_LIMIT" =~ ^[1-9][0-9]*$ ]] || { code_die "--task-limit must be positive"; exit 2; }
[[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches is required"; exit 2; }
code_tier_is_valid "$MODEL_TIER" \
  || { code_die "--models must be frontier, max, or light: $MODEL_TIER"; exit 2; }
code_apply_model_tier "$MODEL_TIER" || exit 2

# --shard N/M splits the subset across M processes that run at the same time.
# Shards take disjoint instances, so their cell directories never collide, and
# each writes its own prediction file because concurrent appends to one file
# interleave. Wall clock falls by roughly M; provider concurrency rises by M,
# which is the real limit on how far this can be pushed.
SHARD_INDEX=0
SHARD_COUNT=1
if [[ -n "$SHARD_SPEC" ]]; then
  [[ "$SHARD_SPEC" =~ ^[0-9]+/[0-9]+$ ]] || { code_die "--shard must look like N/M"; exit 2; }
  SHARD_INDEX="${SHARD_SPEC%%/*}"
  SHARD_COUNT="${SHARD_SPEC##*/}"
  (( SHARD_COUNT >= 1 )) || { code_die "--shard M must be at least 1"; exit 2; }
  (( SHARD_INDEX < SHARD_COUNT )) || { code_die "--shard N must be less than M"; exit 2; }
fi

suite_json=$(code_suite_json "$SUITE")
subset=$(code_subset_path "$suite_json")

# --task names one instance from the suite instead of taking the first N. It is
# how a single cell is re-run after a provider failure, and how a proof-of-
# concept run pins the cheapest task without editing the subset.
if [[ -n "$TASK" ]]; then
  jq -e --arg id "$TASK" 'any(.instances[]; .instance_id == $id)' "$subset" >/dev/null \
    || { code_die "task is outside suite $SUITE: $TASK"; exit 1; }
  TASK_LIMIT=1
fi

bash "$CODE_DIR/estimate-compute.sh" --suite "$SUITE" \
  --conditions "$CONDITIONS" --task-limit "$TASK_LIMIT" \
  --max-claude-dispatches "$MAX_CLAUDE"

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN: no repositories cloned and no providers invoked.\n'
  exit 0
fi

pred_dir="$CODE_BENCH_RESULTS_ROOT/predictions/$RUN_ID"
mkdir -p "$pred_dir"

runs_root="$CODE_BENCH_RESULTS_ROOT/runs/$RUN_ID"
failed_cells=0
done_cells=0
skipped_cells=0

task_index=0
while IFS= read -r instance; do
  task_index=$((task_index + 1))
  (( task_index <= TASK_LIMIT )) || break
  (( (task_index - 1) % SHARD_COUNT == SHARD_INDEX )) || continue
  for condition in $(printf '%s' "$CONDITIONS" | tr ',' ' '); do
    cell="$runs_root/$instance/$condition"
    if (( SHARD_COUNT > 1 )); then
      pred_file="$pred_dir/$condition.s$SHARD_INDEX.jsonl"
    else
      pred_file="$pred_dir/$condition.jsonl"
    fi
    # A fifty-task batch is hours long, so it has to be restartable. A cell that
    # already holds a prediction is finished and is left alone; a cell without
    # one is an abandoned clone from an interrupted attempt, and re-preparing it
    # is the only way forward because prepare refuses an existing directory.
    # Reusing a cell built by a different model tier would put two experiments
    # in one prediction file, and nothing downstream could tell them apart. Stop
    # rather than resume: a tier change needs its own run id.
    if [[ -f "$cell/run-manifest.json" ]]; then
      cell_tier=$(jq -r '.model_tier // "frontier"' "$cell/run-manifest.json" | tr -d '\r')
      if [[ "$cell_tier" != "$MODEL_TIER" ]]; then
        code_die "cell $instance/$condition was run at tier $cell_tier, not $MODEL_TIER; use a new --run-id"
        exit 1
      fi
    fi
    if [[ -f "$cell/prediction.json" ]]; then
      # The cell is the record of truth; the prediction file is a projection of
      # it. Re-link a finished cell whose line is missing, so a resume under a
      # different shard layout still yields complete prediction files.
      if ! jq -e --arg id "$instance" 'select(.instance_id == $id)' "$pred_file" \
           >/dev/null 2>&1; then
        jq -c . "$cell/prediction.json" >> "$pred_file"
      fi
      printf 'SKIP: %s/%s already has a prediction\n' "$instance" "$condition"
      skipped_cells=$((skipped_cells + 1)); continue
    fi
    [[ ! -d "$cell" ]] || rm -rf "$cell"
    if ! input=$(bash "$CODE_DIR/scripts/prepare-swebench-instance.sh" "$instance" "$RUN_ID" "$condition"); then
      printf 'CELL FAILED: could not prepare %s/%s\n' "$instance" "$condition" >&2
      failed_cells=$((failed_cells + 1)); continue
    fi
    tier=$(jq -r --arg id "$condition" '.conditions[] | select(.id == $id) | .tier' \
      "$CODE_DIR/conditions.json" | tr -d '\r')
    # Single-shot cells have no agent loop, so they take the other driver. The
    # tier decides, not a hardcoded condition list: a new single-shot arm routes
    # itself the moment conditions.json declares its tier.
    #
    # A cell that produces no patch is a zero for that arm, not a reason to
    # abandon the batch: the subset is the denominator either way, and an abort
    # here used to throw away every remaining cell in the run.
    cell_rc=0
    if [[ "$tier" == "single-shot" ]]; then
      agent=$(jq -r --arg id "$condition" \
        '.conditions[] | select(.id == $id) | .dispatches | to_entries
         | map(select(.value > 0)) | .[0].key' \
        "$CODE_DIR/conditions.json" | tr -d '\r')
      bash "$CODE_DIR/drivers/run-single-shot.sh" --input "$input" \
        --predictions "$pred_file" --agent "$agent" || cell_rc=$?
    else
      per_condition=$(jq -r --arg id "$condition" '.conditions[] | select(.id == $id) | .dispatches.claude' \
        "$CODE_DIR/conditions.json" | tr -d '\r')
      bash "$CODE_DIR/drivers/run-workflow.sh" --input "$input" \
        --predictions "$pred_file" \
        --max-claude-dispatches "$per_condition" || cell_rc=$?
    fi
    if (( cell_rc != 0 )); then
      printf 'CELL FAILED: %s/%s produced no prediction (rc=%s)\n' "$instance" "$condition" "$cell_rc" >&2
      failed_cells=$((failed_cells + 1))
    else
      done_cells=$((done_cells + 1))
    fi
  done
done < <(if [[ -n "$TASK" ]]; then printf '%s\n' "$TASK"
         else jq -r '.instances[].instance_id' "$subset" | tr -d '\r'; fi)

# Validate only this shard's own files. A sibling shard is still appending to
# its own, and validating a file mid-write reports a failure that is not real.
shopt -s nullglob
if (( SHARD_COUNT > 1 )); then
  validate_glob=("$pred_dir"/*.s"$SHARD_INDEX".jsonl)
else
  validate_glob=("$pred_dir"/*.jsonl)
fi
for predictions in "${validate_glob[@]}"; do
  bash "$CODE_DIR/validate-predictions.sh" "$predictions" "$SUITE"
done
printf 'COMPLETE: %s cell(s) generated, %s reused, %s failed -> %s\n' \
  "$done_cells" "$skipped_cells" "$failed_cells" "$pred_dir"
if (( failed_cells > 0 )); then
  printf 'INCOMPLETE: %s cell(s) produced no prediction. They score zero against the\n' "$failed_cells" >&2
  printf 'subset; rerun the same command to retry only those cells.\n' >&2
fi
