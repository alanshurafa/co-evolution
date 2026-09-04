#!/usr/bin/env bash
# The headless runbook for one benchmark phase. Any orchestrator drives it.
#
# A phase is the same six stages whoever supervises it: preflight, dispatch,
# watch, evaluate, aggregate, gate. This script owns those stages and a single
# state file, and is safe to re-invoke at any stage: every stage is idempotent
# and reports where the phase stands. A Claude Code session, a Codex session, a
# cron job or a person are all thin adapters over it; none of them reads a raw
# log, and the one that started the phase is recorded as the state file's
# writer so a second orchestrator is refused instead of interleaved.
#
# Two kinds of gate, deliberately different:
#   mechanical  every shard exited, every arm has an evaluator report, the
#               prediction files validate, the site rebuilt, the gold canary
#               is still 1/1. A rule decides these; the orchestrator reports.
#   spend       dispatching model calls, and advancing to the next phase. These
#               need a human go, delivered as --approve-spend on the dispatch
#               stage and recorded with a timestamp. No orchestrator infers it.
#
#   phase-runner.sh --phase-id 1 --run-id base50-light --suite swebench-verified-random50 \
#       --models light --conditions D,C,H,I,J,K,L,F,G --shards 2 --max-claude-dispatches 550 \
#       --stage preflight|dispatch|watch|evaluate|aggregate|gate|all [--approve-spend] [--dry-run]
#
# State: $CODE_BENCH_RESULTS_ROOT/phases/<phase-id>-<run-id>/phase-state.json
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

PHASE_ID=""
RUN_ID=""
SUITE="${CODE_BENCH_SUITE:-}"
MODEL_TIER="${CODE_BENCH_MODEL_TIER:-}"
CONDITIONS=""
SHARDS=1
MAX_CLAUDE=""
STAGE="all"
APPROVE=false
DRY_RUN=false
SITE_OUTPUT=""
ALSO=()
while (( $# > 0 )); do
  case "$1" in
    --phase-id) PHASE_ID="${2:?--phase-id needs a value}"; shift 2 ;;
    --run-id) RUN_ID="${2:?--run-id needs a value}"; shift 2 ;;
    --suite) SUITE="${2:?--suite needs a value}"; shift 2 ;;
    --models) MODEL_TIER="${2:?--models needs a tier}"; shift 2 ;;
    --conditions) CONDITIONS="${2:?--conditions needs a list}"; shift 2 ;;
    --shards) SHARDS="${2:?--shards needs a count}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --stage) STAGE="${2:?--stage needs a name}"; shift 2 ;;
    --site-output) SITE_OUTPUT="${2:?--site-output needs a path}"; shift 2 ;;
    --also) ALSO+=("${2:?--also needs LABEL=HREF}"); shift 2 ;;
    --approve-spend) APPROVE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) code_die "unknown phase-runner option: $1"; exit 2 ;;
  esac
done
[[ "$PHASE_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "--phase-id is required and must be filesystem-safe"; exit 2; }
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "--run-id is required and must be filesystem-safe"; exit 2; }
[[ -n "$SUITE" ]] || { code_die "--suite (or CODE_BENCH_SUITE) is required"; exit 2; }
[[ -n "$CONDITIONS" ]] || { code_die "--conditions is required"; exit 2; }
[[ "$SHARDS" =~ ^[1-9][0-9]*$ ]] || { code_die "--shards must be a positive integer"; exit 2; }
[[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches is required"; exit 2; }
[[ -n "$MODEL_TIER" ]] || MODEL_TIER=frontier
code_tier_is_valid "$MODEL_TIER" || { code_die "--models must be frontier, max, or light"; exit 2; }
case "$STAGE" in preflight|dispatch|watch|evaluate|aggregate|gate|all) ;; *) code_die "unknown stage: $STAGE"; exit 2 ;; esac
export CODE_BENCH_SUITE="$SUITE"

ORCHESTRATOR=$(code_orchestrator)
PHASE_DIR="$CODE_BENCH_RESULTS_ROOT/phases/$PHASE_ID-$RUN_ID"
STATE="$PHASE_DIR/phase-state.json"
STATUS="$PHASE_DIR/phase-status.txt"
PRED_DIR="$CODE_BENCH_RESULTS_ROOT/predictions/$RUN_ID"
mkdir -p "$PHASE_DIR"
[[ -n "$SITE_OUTPUT" ]] || SITE_OUTPUT="$CODE_BENCH_REPO_ROOT/benchmarks/site/public/leaderboard.json"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The state file has one writer: the orchestrator that created it. The status
# text file follows the harness's one-writer rule too, so a second orchestrator
# attaching to a running phase is refused with the owner's name.
init_state() {
  if [[ ! -f "$STATE" ]]; then
    jq -n --arg phase "$PHASE_ID" --arg run "$RUN_ID" --arg suite "$SUITE" --arg tier "$MODEL_TIER" \
      --arg conditions "$CONDITIONS" --argjson shards "$SHARDS" --argjson cap "$MAX_CLAUDE" \
      --arg orchestrator "$ORCHESTRATOR" --arg at "$(now)" \
      '{schema:"code-bench-phase/1.0",phase_id:$phase,run_id:$run,suite:$suite,model_tier:$tier,
        conditions:($conditions|split(",")),shards:$shards,max_claude_dispatches:$cap,
        orchestrator:$orchestrator,created_at:$at,stage:"created",
        spend_approved:null,stages:{},gate:null}' > "$STATE"
  fi
  local owner
  owner=$(jq -r '.orchestrator' "$STATE" | tr -d '\r')
  [[ "$owner" == "$ORCHESTRATOR" ]] || {
    code_die "phase $PHASE_ID-$RUN_ID belongs to orchestrator $owner; this session is $ORCHESTRATOR. Set CODE_BENCH_ORCHESTRATOR=$owner only if you are continuing that run."
    exit 1
  }
  code_status_init "$STATUS" "$(printf '%s' "$ORCHESTRATOR" | tr ':' '.')" >/dev/null 2>&1 || true
}

set_stage() { # set_stage NAME STATE [DETAIL-JSON]
  local name="$1" state="$2" detail="${3:-null}"
  local tmp="$STATE.tmp"
  jq --arg name "$name" --arg state "$state" --arg at "$(now)" --argjson detail "$detail" \
    '.stage = $name | .stages[$name] = {state:$state, at:$at, detail:$detail}' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  code_status_append "$STATUS" "$(printf '%s' "$ORCHESTRATOR" | tr ':' '.')" "stage=$name state=$state" >/dev/null 2>&1 || true
  printf 'PHASE %s: %s %s\n' "$PHASE_ID-$RUN_ID" "$name" "$state"
}

conditions_list() { printf '%s' "$CONDITIONS" | tr ',' ' '; }

needs_seat() { # needs_seat glm|kimi|codex|claude
  local seat="$1" c
  for c in $(conditions_list); do
    if jq -e --arg id "$c" --arg s "$seat" '.conditions[] | select(.id == $id) | .dispatches[$s] > 0' \
         "$CODE_DIR/conditions.json" >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

# --- preflight ---------------------------------------------------------------
stage_preflight() {
  local problems=() estimate
  bash "$CODE_DIR/code-bench.sh" check >/dev/null 2>&1 || problems+=("manifests fail check")
  if needs_seat claude; then command -v claude >/dev/null 2>&1 || problems+=("claude CLI missing"); fi
  if needs_seat codex; then command -v codex >/dev/null 2>&1 || problems+=("codex CLI missing"); fi
  if needs_seat glm; then ( code_load_env_key ZAI_API_KEY; [[ -n "${ZAI_API_KEY:-}" ]] ) || problems+=("ZAI_API_KEY absent"); fi
  if needs_seat kimi; then ( code_load_env_key KIMI_API_KEY; [[ -n "${KIMI_API_KEY:-}" ]] ) || problems+=("KIMI_API_KEY absent"); fi
  [[ -f "$(code_metadata_path)" ]] || problems+=("public metadata absent for $SUITE (run fetch-metadata)")
  [[ -z "${ANTHROPIC_API_KEY:-}" ]] || problems+=("ANTHROPIC_API_KEY is set; the driver refuses to bill API credits")
  estimate=$(bash "$CODE_DIR/estimate-compute.sh" --suite "$SUITE" --conditions "$CONDITIONS" --json 2>/dev/null) \
    || problems+=("compute estimate failed")
  local claude_needed
  claude_needed=$(printf '%s' "$estimate" | jq -r '.declared_dispatches.claude // 0' 2>/dev/null)
  if [[ -n "$claude_needed" ]] && (( claude_needed > MAX_CLAUDE )); then
    problems+=("cap $MAX_CLAUDE below the $claude_needed declared Claude dispatches")
  fi
  local probe="$CODE_BENCH_RESULTS_ROOT/probes/probe-workspace-write.json" sandbox_note="unprobed"
  if [[ -f "$probe" ]]; then
    sandbox_note=$(jq -r '"codex \(.codex_version): workspace-write wrote=\(.wrote) reported=\(.sandbox_reported)"' "$probe")
  fi
  local detail
  detail=$(jq -cn --argjson problems "$(printf '%s\n' "${problems[@]+"${problems[@]}"}" | jq -R . | jq -sc 'map(select(length > 0))')" \
    --argjson estimate "${estimate:-null}" --arg sandbox "$sandbox_note" --arg mode "$(code_codex_sandbox)" \
    '{problems:$problems,estimate:$estimate,codex_sandbox_probe:$sandbox,codex_sandbox_mode:$mode}')
  if (( ${#problems[@]} > 0 )); then
    set_stage preflight failed "$detail"
    printf 'PREFLIGHT PROBLEMS:\n' >&2; printf '  - %s\n' "${problems[@]}" >&2
    return 1
  fi
  set_stage preflight passed "$detail"
}

# --- dispatch ------------------------------------------------------------------
stage_dispatch() {
  if [[ "$DRY_RUN" == true ]]; then
    bash "$CODE_DIR/code-bench.sh" run-canary --run-id "$RUN_ID" --models "$MODEL_TIER" \
      --conditions "$CONDITIONS" --task-limit "$(suite_size)" --max-claude-dispatches "$MAX_CLAUDE" --dry-run
    set_stage dispatch dry-run
    return 0
  fi
  # The spend gate. A phase dispatches model calls only on an explicit human go,
  # passed as a flag by whoever is orchestrating and recorded with a timestamp.
  if [[ "$APPROVE" != true ]] && ! jq -e '.spend_approved != null' "$STATE" >/dev/null 2>&1; then
    set_stage dispatch blocked '{"reason":"spend not approved; re-run with --approve-spend after a human go"}'
    printf 'SPEND GATE: dispatch needs --approve-spend (a human go). Nothing was dispatched.\n' >&2
    return 3
  fi
  if [[ "$APPROVE" == true ]] && jq -e '.spend_approved == null' "$STATE" >/dev/null 2>&1; then
    local tmp="$STATE.tmp"
    jq --arg at "$(now)" --arg by "$ORCHESTRATOR" '.spend_approved = {at:$at, recorded_by:$by}' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  fi
  if jq -e '.stages.dispatch.state == "running"' "$STATE" >/dev/null 2>&1 && shards_alive; then
    printf 'DISPATCH: shards already running\n'
    return 0
  fi
  local pids=() s size
  size=$(suite_size)
  export CODE_BENCH_MODEL_TIER="$MODEL_TIER"
  for (( s = 0; s < SHARDS; s++ )); do
    local shard_arg=()
    (( SHARDS > 1 )) && shard_arg=(--shard "$s/$SHARDS")
    nohup bash "$CODE_DIR/code-bench.sh" run-canary --run-id "$RUN_ID" --models "$MODEL_TIER" \
      --conditions "$CONDITIONS" --task-limit "$size" ${shard_arg[@]+"${shard_arg[@]}"} \
      --max-claude-dispatches "$MAX_CLAUDE" \
      > "$PHASE_DIR/shard$s.log" 2>&1 < /dev/null &
    pids+=("$!")
  done
  local detail
  detail=$(jq -cn --argjson pids "$(printf '%s\n' "${pids[@]}" | jq -R 'tonumber' | jq -sc .)" \
    --argjson shards "$SHARDS" '{pids:$pids,shards:$shards}')
  set_stage dispatch running "$detail"
}

suite_size() {
  local suite_json subset
  suite_json=$(code_suite_json "$SUITE")
  subset=$(code_subset_path "$suite_json")
  jq '.instances | length' "$subset" | tr -d '\r'
}

shards_alive() {
  local pid alive=1
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then alive=0; fi
  done < <(jq -r '.stages.dispatch.detail.pids[]? // empty' "$STATE" 2>/dev/null)
  return $alive
}

# --- watch ---------------------------------------------------------------------
# Reports progress from the cells themselves and says whether the shards are
# still alive. Exit 0 when dispatch has finished, 4 while it is still running.
stage_watch() {
  local size c total_done=0 total_expected=0 detail per_arm='[]' alive=false
  size=$(suite_size)
  for c in $(conditions_list); do
    local preds nopatch
    preds=$(ls -d "$CODE_BENCH_RESULTS_ROOT/runs/$RUN_ID"/*/"$c"/prediction.json 2>/dev/null | wc -l | tr -d ' ')
    nopatch=$(ls -d "$CODE_BENCH_RESULTS_ROOT/runs/$RUN_ID"/*/"$c"/outcome.json 2>/dev/null | xargs -r grep -l '"empty-patch"\|"no-applicable-patch"' 2>/dev/null | wc -l | tr -d ' ')
    per_arm=$(jq -c --arg c "$c" --argjson p "$preds" --argjson n "$nopatch" --argjson size "$size" \
      '. + [{condition:$c,predictions:$p,no_patch:$n,done:($p+$n),expected:$size}]' <<<"$per_arm")
    total_done=$((total_done + preds + nopatch)); total_expected=$((total_expected + size))
  done
  shards_alive && alive=true
  detail=$(jq -cn --argjson arms "$per_arm" --argjson done "$total_done" --argjson expected "$total_expected" \
    --argjson alive "$alive" '{arms:$arms,cells_done:$done,cells_expected:$expected,shards_alive:$alive}')
  if [[ "$alive" == true ]]; then
    set_stage watch running "$detail"
    printf 'WATCH: %s of %s cells done, shards alive\n' "$total_done" "$total_expected"
    return 4
  fi
  if (( total_done < total_expected )); then
    set_stage watch incomplete "$detail"
    printf 'WATCH: shards exited with %s of %s cells done; rerun dispatch to retry failed cells\n' "$total_done" "$total_expected" >&2
    return 5
  fi
  set_stage watch complete "$detail"
  printf 'WATCH: all %s cells done\n' "$total_expected"
}

# --- evaluate ------------------------------------------------------------------
# One prediction file per arm (shards merged), validated, then scored under the
# run label. An arm whose report already covers every prediction is skipped, so
# the stage can be re-run without re-scoring.
stage_evaluate() {
  local c merged failures=0 scored='[]'
  for c in $(conditions_list); do
    merged="$PRED_DIR/$c.jsonl"
    if (( SHARDS > 1 )) || [[ ! -f "$merged" ]]; then
      cat "$PRED_DIR/$c".s*.jsonl > "$merged.tmp" 2>/dev/null && mv "$merged.tmp" "$merged" || rm -f "$merged.tmp"
    fi
    if [[ ! -s "$merged" ]]; then
      printf 'EVALUATE: %s has no predictions (every cell scored zero?)\n' "$c" >&2
      scored=$(jq -c --arg c "$c" '. + [{condition:$c,state:"no-predictions"}]' <<<"$scored"); continue
    fi
    local lines report_count
    lines=$(grep -c . "$merged" | tr -d ' ')
    report_count=$(latest_report_submitted "$c")
    if [[ -n "$report_count" ]] && (( report_count >= lines )); then
      scored=$(jq -c --arg c "$c" --argjson n "$lines" '. + [{condition:$c,state:"already-scored",predictions:$n}]' <<<"$scored"); continue
    fi
    if ! bash "$CODE_DIR/validate-predictions.sh" "$merged" "$SUITE" >/dev/null 2>&1; then
      failures=$((failures + 1)); scored=$(jq -c --arg c "$c" '. + [{condition:$c,state:"invalid"}]' <<<"$scored"); continue
    fi
    if bash "$CODE_DIR/scripts/evaluate-swebench.sh" predictions "$merged" --label "$RUN_ID" > "$PHASE_DIR/evaluate-$c.log" 2>&1; then
      scored=$(jq -c --arg c "$c" --argjson n "$lines" '. + [{condition:$c,state:"scored",predictions:$n}]' <<<"$scored")
    else
      failures=$((failures + 1)); scored=$(jq -c --arg c "$c" '. + [{condition:$c,state:"evaluator-failed"}]' <<<"$scored")
    fi
  done
  local detail
  detail=$(jq -cn --argjson arms "$scored" '{arms:$arms}')
  if (( failures > 0 )); then set_stage evaluate failed "$detail"; return 1; fi
  set_stage evaluate complete "$detail"
}

latest_report_submitted() { # submitted_instances of the newest report for COND under RUN_ID
  local c="$1" f
  f=$(ls "$CODE_BENCH_RESULTS_ROOT/evaluation/co-evolution-condition-$c.$RUN_ID-"*.json 2>/dev/null | sort | tail -1)
  [[ -n "$f" ]] || return 0
  jq -r '.submitted_instances // 0' "$f" | tr -d '\r'
}

# --- aggregate -----------------------------------------------------------------
stage_aggregate() {
  local also_args=() link
  for link in ${ALSO[@]+"${ALSO[@]}"}; do also_args+=(--also "$link"); done
  if CODE_BENCH_RESULTS_ROOT="$CODE_BENCH_RESULTS_ROOT" bash "$CODE_BENCH_REPO_ROOT/benchmarks/site/aggregate.sh" \
       --suite "$SUITE" --output "$SITE_OUTPUT" ${also_args[@]+"${also_args[@]}"} > "$PHASE_DIR/aggregate.log" 2>&1; then
    set_stage aggregate complete "$(jq -cn --arg out "$SITE_OUTPUT" '{output:$out}')"
  else
    set_stage aggregate failed "$(jq -cn --arg log "$PHASE_DIR/aggregate.log" '{log:$log}')"
    return 1
  fi
}

# --- gate ----------------------------------------------------------------------
# Mechanical checks only. The verdict says whether the phase's numbers are ready
# to be judged; it never approves spend or advances a phase.
stage_gate() {
  local site="$SITE_OUTPUT" checks='[]' ok=true c
  add_check() { # add_check NAME PASS DETAIL
    checks=$(jq -c --arg n "$1" --argjson p "$2" --arg d "$3" '. + [{check:$n,pass:$p,detail:$d}]' <<<"$checks")
    [[ "$2" == true ]] || ok=false
  }
  if jq -e '.stages.watch.state == "complete"' "$STATE" >/dev/null 2>&1; then add_check "every cell ran" true ""; else add_check "every cell ran" false "watch stage not complete"; fi
  if jq -e '.stages.evaluate.state == "complete"' "$STATE" >/dev/null 2>&1; then add_check "every arm scored" true ""; else add_check "every arm scored" false "evaluate stage not complete"; fi
  if [[ -f "$site" ]] && jq -e '.schema == "code-bench-site/2.0"' "$site" >/dev/null 2>&1; then
    add_check "site rebuilt" true "$site"
    for c in $(conditions_list); do
      local row
      row=$(jq -c --arg id "$c@$RUN_ID" '.rows[] | select(.id == $id) | {complete, cost_is_complete:.telemetry.cost_is_complete, rank:.rank_ub, n:.score.n, k:.score.resolved}' "$site" 2>/dev/null)
      if [[ -z "$row" ]]; then add_check "row $c present" false "no row $c@$RUN_ID in $site"; continue; fi
      if jq -e '.complete == true' <<<"$row" >/dev/null; then add_check "row $c complete" true "$row"; else add_check "row $c complete" false "$row"; fi
      if jq -e '.cost_is_complete == true' <<<"$row" >/dev/null; then add_check "row $c priced" true ""; else add_check "row $c priced" false "a seat is unpriced; the cost column shows incomplete"; fi
    done
    local gold
    gold=$(jq -r '.gold_canary | "\(.resolved)/\(.submitted)"' "$site" 2>/dev/null)
    if [[ "$gold" == "1/1" ]]; then add_check "gold canary 1/1" true ""; else add_check "gold canary 1/1" false "$gold"; fi
  else
    add_check "site rebuilt" false "no schema-2.0 JSON at $site"
  fi
  local primary
  primary=$(jq -c '.methodology.phases[] | select(.observed != null) | {phase:.id, contrast:.observed.contrast, only_a:.observed.only_a, only_b:.observed.only_b, p:.observed.mcnemar_exact_p}' "$site" 2>/dev/null | jq -sc .)
  local verdict detail
  if [[ "$ok" == true ]]; then verdict=ready; else verdict=not-ready; fi
  detail=$(jq -cn --argjson checks "$checks" --arg verdict "$verdict" --argjson primary "${primary:-[]}" \
    '{verdict:$verdict,checks:$checks,primary_contrasts:$primary,spend:"next phase needs a human go; this gate never grants it"}')
  local tmp="$STATE.tmp"
  jq --argjson g "$detail" '.gate = $g' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  set_stage gate "$verdict" "$detail"
  printf '%s\n' "$detail" | jq .
  [[ "$verdict" == ready ]]
}

init_state
case "$STAGE" in
  preflight) stage_preflight ;;
  dispatch) stage_dispatch ;;
  watch) stage_watch ;;
  evaluate) stage_evaluate ;;
  aggregate) stage_aggregate ;;
  gate) stage_gate ;;
  all)
    stage_preflight && stage_dispatch && {
      if [[ "$DRY_RUN" == true ]]; then exit 0; fi
      # Detached shards: "all" stops here and returns 4; re-invoke with
      # --stage watch (then evaluate, aggregate, gate) as they finish.
      stage_watch; rc=$?
      if (( rc == 4 )); then exit 4; fi
      (( rc == 0 )) && stage_evaluate && stage_aggregate && stage_gate
    } ;;
esac
