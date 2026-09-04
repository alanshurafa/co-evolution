#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"
# shellcheck source=../../../lib/co-evolution.sh
source "$CODE_BENCH_REPO_ROOT/lib/co-evolution.sh"

INPUT_JSON=""
PREDICTIONS=""
MAX_CLAUDE=""
DRY_RUN=false
RESUME=false
CLAUDE_MODEL="${CODE_BENCH_CLAUDE_MODEL:-fable}"
CODEX_MODEL_LOCAL="${CODE_BENCH_CODEX_MODEL:-gpt-5.6-sol}"
# Empty means "let the CLI choose", which is how a tier asks for a model's own
# default effort instead of imposing one that model may not accept.
CLAUDE_EFFORT_LOCAL="${CODE_BENCH_CLAUDE_EFFORT-medium}"
MODEL_TIER=$(code_model_tier)
CODEX_EFFORT_LOCAL="${CODE_BENCH_CODEX_EFFORT:-medium}"
PHASE_TIMEOUT="${CODE_BENCH_PHASE_TIMEOUT:-900}"
CRITIC_MAX_TOKENS="${CODE_BENCH_CRITIC_MAX_TOKENS:-2500}"
GLM_CRITIC_REASONING="${CODE_BENCH_GLM_REASONING_EFFORT:-low}"
KIMI_CRITIC_THINKING="${CODE_BENCH_KIMI_THINKING:-disabled}"
CRITIC_ATTEMPTS="${CODE_BENCH_CRITIC_ATTEMPTS:-3}"
CRITIC_RETRY_DELAY="${CODE_BENCH_CRITIC_RETRY_DELAY:-15}"
CODEX_SANDBOX=$(code_codex_sandbox) || exit 2

while (( $# > 0 )); do
  case "$1" in
    --input) INPUT_JSON="${2:?--input needs a value}"; shift 2 ;;
    --predictions) PREDICTIONS="${2:?--predictions needs a value}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;;
    *) code_die "unknown workflow option: $1"; exit 2 ;;
  esac
done

[[ -f "$INPUT_JSON" ]] || { code_die "--input must name a prepared input.json"; exit 2; }
[[ -n "$PREDICTIONS" ]] || { code_die "--predictions is required"; exit 2; }
[[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches is required and must be an integer"; exit 2; }
[[ "$PHASE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { code_die "CODE_BENCH_PHASE_TIMEOUT must be positive"; exit 2; }
[[ "$CRITIC_MAX_TOKENS" =~ ^[1-9][0-9]*$ ]] || { code_die "CODE_BENCH_CRITIC_MAX_TOKENS must be positive"; exit 2; }
[[ "$CRITIC_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || { code_die "CODE_BENCH_CRITIC_ATTEMPTS must be positive"; exit 2; }
[[ "$CRITIC_RETRY_DELAY" =~ ^[0-9]+$ ]] || { code_die "CODE_BENCH_CRITIC_RETRY_DELAY must be a non-negative integer"; exit 2; }

instance=$(jq -r '.instance_id' "$INPUT_JSON" | tr -d '\r')
condition=$(jq -r '.condition' "$INPUT_JSON" | tr -d '\r')
workspace=$(jq -r '.workspace' "$INPUT_JSON" | tr -d '\r')
task_file=$(jq -r '.task_file' "$INPUT_JSON" | tr -d '\r')
[[ -d "$workspace/.git" && -f "$task_file" ]] || { code_die "prepared workspace or task file is missing"; exit 1; }

results_root=$(cd "$CODE_BENCH_RESULTS_ROOT" && pwd -P)
input_dir=$(cd "$(dirname "$INPUT_JSON")" && pwd -P)
input_abs="$input_dir/$(basename "$INPUT_JSON")"
workspace_abs=$(cd "$workspace" && pwd -P)
task_dir=$(cd "$(dirname "$task_file")" && pwd -P)
task_abs="$task_dir/$(basename "$task_file")"
case "$input_abs" in "$results_root"/runs/*/*/*/input.json) ;; *) code_die "input.json is outside the benchmark run sandbox"; exit 1 ;; esac
[[ "$workspace_abs" == "$input_dir/workspace" ]] || { code_die "workspace does not belong to the prepared cell"; exit 1; }
[[ "$task_abs" == "$input_dir/task.md" ]] || { code_die "task file does not belong to the prepared cell"; exit 1; }
mkdir -p "$(dirname "$PREDICTIONS")"
pred_dir=$(cd "$(dirname "$PREDICTIONS")" && pwd -P)
pred_abs="$pred_dir/$(basename "$PREDICTIONS")"
case "$pred_abs" in "$results_root"/predictions/*) ;; *) code_die "predictions path is outside the benchmark prediction sandbox"; exit 1 ;; esac

condition_json=$(jq -ce --arg id "$condition" '.conditions | map(select(.id == $id)) | if length == 1 then .[0] else empty end' "$CODE_DIR/conditions.json") \
  || { code_die "unknown condition: $condition"; exit 1; }
claude_needed=$(printf '%s' "$condition_json" | jq -r '.dispatches.claude' | tr -d '\r')
if (( claude_needed > MAX_CLAUDE )); then
  printf 'REFUSED: condition %s declares %s Claude dispatches; cap is %s.\n' "$condition" "$claude_needed" "$MAX_CLAUDE" >&2
  exit 75
fi

# critics is the ordered reviewer roster. One list drives the critique loop, the
# repair prompt, and the manifest, so a condition cannot declare one panel in
# conditions.json and then run another.
case "$condition" in
  A) phases="fable-implement"; critics="" ;;
  B) phases="fable-implement,codex-repair"; critics="" ;;
  C) phases="fable-implement,codex-critique,glm-critique,kimi-critique,fable-repair"; critics="codex,glm,kimi" ;;
  D) phases="fable-implement,fable-self-repair"; critics="" ;;
  E) phases="codex-implement"; critics="" ;;
  H) phases="fable-implement,glm-critique,fable-repair"; critics="glm" ;;
  I) phases="fable-implement,kimi-critique,fable-repair"; critics="kimi" ;;
  F|G) code_die "single-shot conditions run through run-single-shot.sh"; exit 2 ;;
esac
# jq -R reads no lines from empty input and would emit nothing at all, so the
# roster is built from an argument rather than from stdin.
critics_json=$(jq -cn --arg roster "$critics" \
  'if $roster == "" then [] else ($roster | split(",")) end')
if [[ "$DRY_RUN" == true ]]; then
  jq -n --arg instance "$instance" --arg condition "$condition" --arg phases "$phases" \
    --argjson critics "$critics_json" --argjson claude "$claude_needed" \
    '{instance:$instance,condition:$condition,phases:($phases|split(",")),critics:$critics,declared_claude_dispatches:$claude,executed:false}'
  exit 0
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  code_die "ANTHROPIC_API_KEY is set; refusing because this would bill API credits instead of the Max plan"
  exit 1
fi
command -v claude >/dev/null 2>&1 || { code_die "claude CLI is required"; exit 1; }
command -v codex >/dev/null 2>&1 || { code_die "codex CLI is required"; exit 1; }

code_load_env_key ZAI_API_KEY
code_load_env_key KIMI_API_KEY
# The GLM and Kimi adapters write a token-usage sidecar next to each artifact
# only when asked. Cost on the results page is priced from those sidecars, so a
# cell without them is an unpriced seat and an incomplete cost figure.
export CO_EVOLVE_TOKEN_CAPTURE=1

cell="$input_dir"
logs="$cell/logs"
reviews="$cell/reviews"
mkdir -p "$logs" "$reviews"
jq -n --arg instance "$instance" --arg condition "$condition" \
  --arg claude_model "$CLAUDE_MODEL" --arg claude_effort "$CLAUDE_EFFORT_LOCAL" \
  --arg codex_model "$CODEX_MODEL_LOCAL" --arg codex_effort "$CODEX_EFFORT_LOCAL" \
  --arg glm_model "${GLM_MODEL:-glm-5.3-flash}" --arg kimi_model "${KIMI_MODEL:-kimi-k3}" \
  --arg codex_sandbox "$CODEX_SANDBOX" --argjson critics "$critics_json" \
  --arg model_tier "$MODEL_TIER" \
  --argjson phase_timeout "$PHASE_TIMEOUT" --argjson declared_claude "$claude_needed" \
  '{schema:"code-bench-run/1.0",instance:$instance,condition:$condition,
    model_tier:$model_tier,
    models:{claude:$claude_model,codex:$codex_model,glm:$glm_model,kimi:$kimi_model},
    effort:{claude:$claude_effort,codex:$codex_effort},
    sandbox:{codex:$codex_sandbox},critics:$critics,
    phase_timeout_seconds:$phase_timeout,declared_claude_dispatches:$declared_claude}' \
  > "$cell/run-manifest.json"

write_implement_prompt() {
  local out="$1"
  {
    printf '%s\n\n' "You are solving a repository issue in the current working directory."
    printf '%s\n' "Inspect the code, implement the smallest correct fix, and run the most relevant tests available."
    printf '%s\n' "Do not read outside the repository. Do not commit. Do not modify tests merely to make a failure disappear."
    printf '\n## ISSUE\n\n'
    cat "$task_file"
  } > "$out"
}

run_fable() {
  local phase="$1" prompt="$2"
  local -a cmd=(claude -p --model "$CLAUDE_MODEL")
  [[ -n "$CLAUDE_EFFORT_LOCAL" ]] && cmd+=(--effort "$CLAUDE_EFFORT_LOCAL")
  cmd+=(--safe-mode --permission-mode auto --tools "Bash,Read,Edit,Write,Glob,Grep"
    --no-session-persistence --output-format json)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  (cd "$workspace" && "${cmd[@]}" < "$prompt") \
    > "$logs/$phase.json" 2> "$logs/$phase.stderr.log"
  jq -e '.type == "result" and .is_error == false and (.result | type == "string")' \
    "$logs/$phase.json" >/dev/null || { code_die "$phase did not produce a successful Claude result"; return 1; }
}

# A writing Codex phase (implement or repair). Codex prints one total under
# "tokens used" on stderr and no input/output split, which is not enough to
# price the seat exactly. With --json the transcript on stdout is a JSONL
# event stream that carries the split, so the results page can price the phase
# at list rate; the final message is kept separately with -o so it stays
# readable.
run_codex_phase() {
  local phase="$1" prompt="$2"
  local -a cmd=(codex exec -C "$workspace" -m "$CODEX_MODEL_LOCAL" --sandbox "$CODEX_SANDBOX"
    --ephemeral --ignore-user-config -c approval_policy="never"
    -c model_reasoning_effort="$CODEX_EFFORT_LOCAL" --json -o "$logs/$phase.last.md" -)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  "${cmd[@]}" \
    < "$prompt" > "$logs/$phase.log" 2> "$logs/$phase.stderr.log"
}

run_codex_repair() { run_codex_phase codex-repair "$1"; }
run_codex_implement() { run_codex_phase codex-implement "$1"; }

# GLM and Kimi both reason by default and bill reasoning against max_tokens, so
# the capped critic seats must bound reasoning too or they return an empty
# content string. Bounded retries absorb a transient provider hang without
# letting a structurally invalid artifact reach the final repair.
run_direct_critic() {
  local agent="$1" out="$2" err="$3" attempt=1
  while (( attempt <= CRITIC_ATTEMPTS )); do
    rm -f "$out"
    case "$agent" in
      glm) GLM_MAX_TOKENS="$CRITIC_MAX_TOKENS" GLM_REASONING_EFFORT="$GLM_CRITIC_REASONING" invoke_glm "$cell/critique-prompt.md" "$out" "$err" false ;;
      kimi) KIMI_MAX_TOKENS="$CRITIC_MAX_TOKENS" KIMI_THINKING="$KIMI_CRITIC_THINKING" invoke_kimi "$cell/critique-prompt.md" "$out" "$err" ;;
      *) code_die "unknown direct critic: $agent"; return 1 ;;
    esac
    if validate_agent_artifact "$out" "$err" "$agent" >/dev/null 2>&1; then
      return 0
    fi
    printf 'RETRY: %s critique attempt %s produced an invalid artifact\n' "$agent" "$attempt" >&2
    attempt=$((attempt + 1))
    # Moonshot enforces org concurrency 1 and answers an overlapping call
    # instantly, so an immediate retry just collides again. Back off first.
    if (( attempt <= CRITIC_ATTEMPTS )); then sleep "$CRITIC_RETRY_DELAY"; fi
  done
  return 1
}

run_codex_critique() {
  local prompt="$1" out="$2"
  local -a cmd=(codex exec -C "$workspace" -m "$CODEX_MODEL_LOCAL" --sandbox read-only
    --ephemeral --ignore-user-config -c approval_policy="never"
    -c model_reasoning_effort="$CODEX_EFFORT_LOCAL" --json -o "$out" -)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  "${cmd[@]}" < "$prompt" > "$logs/codex-critique.log" 2> "$logs/codex-critique.stderr.log"
}

write_implement_prompt "$cell/implement-prompt.md"
if [[ "$condition" == E ]]; then
  if [[ "$RESUME" == true && -n "$(git -C "$workspace" diff --name-only)" ]]; then
    printf 'REUSED: codex-implement\n'
  else
    run_codex_implement "$cell/implement-prompt.md"
  fi
elif [[ "$RESUME" == true ]] \
   && jq -e '.type == "result" and .is_error == false' "$logs/fable-implement.json" >/dev/null 2>&1 \
   && [[ -n "$(git -C "$workspace" diff --name-only)" ]]; then
  printf 'REUSED: fable-implement\n'
else
  run_fable fable-implement "$cell/implement-prompt.md"
fi

case "$condition" in
  B)
    {
      printf '%s\n' "Review the current uncommitted implementation for the issue below. Inspect the diff and repository, correct defects, and run relevant tests. Do not commit."
      printf '\n## ISSUE\n\n'; cat "$task_file"
    } > "$cell/codex-repair-prompt.md"
    run_codex_repair "$cell/codex-repair-prompt.md"
    ;;
  C|H|I)
    git -C "$workspace" diff --binary > "$cell/candidate.patch"
    {
      printf '%s\n' "Critique the candidate patch for correctness, regressions, missing cases, and scope. Do not edit files. Return concrete findings only."
      printf '\n## ISSUE\n\n'; cat "$task_file"
      printf '\n## CANDIDATE PATCH\n\n'; head -c 120000 "$cell/candidate.patch"
    } > "$cell/critique-prompt.md"
    review_files=()
    reviewer_index=0
    for critic in $(printf '%s' "$critics" | tr ',' ' '); do
      reviewer_index=$((reviewer_index + 1))
      review="$reviews/reviewer-$reviewer_index.md"
      critic_err="$logs/$critic-critique.stderr.log"
      case "$critic" in
        codex)
          if [[ "$RESUME" == true && -s "$review" ]] \
             && ! output_is_provider_failure "$review"; then
            printf 'REUSED: codex-critique\n'
          else
            run_codex_critique "$cell/critique-prompt.md" "$review"
          fi
          ;;
        glm|kimi)
          case "$critic" in
            glm) key_name=ZAI_API_KEY; key_value="${ZAI_API_KEY:-}" ;;
            kimi) key_name=KIMI_API_KEY; key_value="${KIMI_API_KEY:-}" ;;
          esac
          [[ -n "$key_value" ]] || { code_die "condition $condition requires $key_name"; exit 1; }
          if [[ "$RESUME" != true ]] || ! validate_agent_artifact "$review" "$critic_err" "$critic" >/dev/null 2>&1; then
            run_direct_critic "$critic" "$review" "$critic_err" || true
          else
            printf 'REUSED: %s-critique\n' "$critic"
          fi
          validate_agent_artifact "$review" "$critic_err" "$critic" >/dev/null \
            || { code_die "$critic critique is not a valid artifact"; exit 1; }
          ;;
        *) code_die "unknown critic in roster: $critic"; exit 1 ;;
      esac
      review_files+=("$review")
    done
    code_write_repair_prompt "$cell/fable-repair-prompt.md" "$task_file" "${review_files[@]}"
    run_fable fable-repair "$cell/fable-repair-prompt.md"
    ;;
  D)
    {
      printf '%s\n' "Review your current uncommitted implementation for the issue below. Find and repair correctness or regression risks and run relevant tests. Do not commit."
      printf '\n## ISSUE\n\n'; cat "$task_file"
    } > "$cell/fable-self-repair-prompt.md"
    run_fable fable-self-repair "$cell/fable-self-repair-prompt.md"
    ;;
esac

patch="$cell/final.patch"
git -C "$workspace" diff --binary > "$patch"
[[ -s "$patch" ]] || { code_die "workflow produced an empty patch"; exit 1; }
record="$cell/prediction.json"
jq -n --arg instance_id "$instance" --arg model "co-evolution-condition-$condition" \
  --rawfile model_patch "$patch" \
  '{instance_id:$instance_id,model_name_or_path:$model,model_patch:$model_patch}' > "$record"
jq -c . "$record" >> "$PREDICTIONS"
printf 'WROTE: %s\n' "$record"
