#!/usr/bin/env bash
set -euo pipefail

# benchmarks/run-panel.sh — benchmark condition C (panel).
#
#   compose (Fable) → codex + glm + kimi critique, no rewrite → synthesis (Fable)
#
# Usage:
#   bash benchmarks/run-panel.sh --task-file FILE --out-dir DIR \
#        [--reviewers codex,glm,kimi] [--composer-model claude-fable-5]
#
# Exit codes (contract with run-benchmark.sh — do not change):
#   0  final.md written
#   1  compose or synthesis failed (or every critique failed)
#   4  retryable quota/auth failure; re-run to resume
#
# Artifacts in --out-dir: compose-output.md, critique-<reviewer>.md (or
# critique-kimi.SKIPPED), final.md, panel-state.json (schema bench-panel/1.0).
# Resume is artifact-driven: any existing non-empty artifact that passes
# validate_agent_artifact is reused and its phase is not re-invoked. Phases that
# fail on auth DELETE their artifact so the resume path retries them rather than
# treating an error page as a plan.
#
# Design notes:
# - The critique prompt is templates/panel-critic.md with {TASK}/{PLAN_CONTENT}
#   substituted. The template's leading HTML comment is stripped first: it names
#   the benchmark and this script, and a critic that knows it is scoring a
#   benchmark is a different critic. The corpus linter budgets Kimi's prompt
#   against the WHOLE template file, so stripping only widens that margin.
# - The synthesis prompt labels critiques "Reviewer N" in --reviewers order and
#   never names a vendor: the synthesis must stay blind to who said what, and
#   vendor strings must not reach final.md where the judge would see them.
# - The frozen benchmark design caps Kimi critique prompts at 11500 bytes. The
#   direct Kimi API no longer has the old Windows argv ceiling, but preserving
#   the registered gate keeps previously linted cells comparable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/benchmark-lib.sh
source "$SCRIPT_DIR/lib/benchmark-lib.sh"

# --- Defaults ---
TASK_FILE=""
OUT_DIR=""
REVIEWERS_CSV="codex,glm,kimi"
COMPOSER_MODEL_ARG="fable"

# Registered Kimi prompt ceiling; the corpus linter uses the same number.
: "${PANEL_KIMI_MAX_BYTES:=11500}"

PANEL_EXIT_OK=0
PANEL_EXIT_FAIL=1
PANEL_EXIT_RETRY=4

usage() {
  cat <<'USAGE'
usage: run-panel.sh --task-file FILE --out-dir DIR
                    [--reviewers codex,glm,kimi] [--composer-model MODEL]

  --task-file FILE       corpus task (YAML frontmatter optional; the body is used)
  --out-dir DIR          artifact directory; created if absent, reused on resume
  --reviewers LIST       comma-separated subset of codex,glm,kimi (order is kept)
  --composer-model M     Claude model or alias for compose + synthesis (default: fable)

exit: 0 final.md written | 1 compose/synthesis failed | 4 retryable auth/quota
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file)
      [[ $# -gt 1 ]] || die "--task-file requires a value"
      TASK_FILE="$2"; shift 2 ;;
    --out-dir)
      [[ $# -gt 1 ]] || die "--out-dir requires a value"
      OUT_DIR="$2"; shift 2 ;;
    --reviewers)
      [[ $# -gt 1 ]] || die "--reviewers requires a value"
      REVIEWERS_CSV="$2"; shift 2 ;;
    --composer-model)
      [[ $# -gt 1 ]] || die "--composer-model requires a value"
      COMPOSER_MODEL_ARG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage >&2
      die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "run-panel.sh requires jq"
[[ -n "$TASK_FILE" ]] || die "--task-file is required"
[[ -f "$TASK_FILE" ]] || die "--task-file not found: $TASK_FILE"
[[ -n "$OUT_DIR" ]] || die "--out-dir is required"

mkdir -p "$OUT_DIR" || die "could not create --out-dir: $OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# Reviewer seats: order is the label order ("Reviewer 1" is the first entry).
REVIEWERS=()
_seen_reviewers=""
IFS=',' read -r -a _reviewer_fields <<< "$REVIEWERS_CSV"
for _r in ${_reviewer_fields[@]+"${_reviewer_fields[@]}"}; do
  [[ -n "$_r" ]] || die "--reviewers contains an empty entry: $REVIEWERS_CSV"
  case "$_r" in
    codex|glm|kimi) ;;
    *) die "--reviewers accepts codex, glm, kimi; got: $_r" ;;
  esac
  case " $_seen_reviewers " in
    *" $_r "*) die "--reviewers lists '$_r' twice: $REVIEWERS_CSV" ;;
  esac
  _seen_reviewers="$_seen_reviewers $_r"
  REVIEWERS+=("$_r")
done
(( ${#REVIEWERS[@]} > 0 )) || die "--reviewers must name at least one reviewer"

# GLM and Kimi are direct HTTP seats. Fail before compose spends anything if
# their shared transport is unavailable; otherwise invoke_* would die inside a
# reviewer phase and the panel could misclassify a missing dependency as an
# invalid critique.
case ",${REVIEWERS_CSV}," in
  *,glm,*|*,kimi,*)
    command -v curl >/dev/null 2>&1 || die "glm/kimi panel reviewers require curl"
    ;;
esac

COMPOSER_MODEL="$(resolve_claude_model_alias "$COMPOSER_MODEL_ARG")"

# COMPOSE-PROMPT PARITY: conditions A, B and D compose from `<cell>/in.md`,
# built by run-benchmark.sh's write_cell_input from the same bench_task_body
# transform used here — one shared implementation, so C's compose prompt stays
# byte-identical by construction. `$(...)` then strips trailing newlines the
# same way the bouncer's own task read does.
TASK_BODY="$(bench_task_body "$TASK_FILE")" \
  || die "could not read task body from $TASK_FILE"
[[ -n "${TASK_BODY//[[:space:]]/}" ]] || die "task file has an empty body: $TASK_FILE"

CRITIC_TEMPLATE="$SCRIPT_DIR/templates/panel-critic.md"
[[ -f "$CRITIC_TEMPLATE" ]] || die "panel-critic template not found: $CRITIC_TEMPLATE"

COMPOSE_OUTPUT="$OUT_DIR/compose-output.md"
FINAL_OUTPUT="$OUT_DIR/final.md"
PANEL_STATE="$OUT_DIR/panel-state.json"

PANEL_PHASES=()
PANEL_SURVIVORS=()
PANEL_DEGRADED=false

# --- Small helpers -----------------------------------------------------------

panel_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

panel_bytes() {
  local file="$1"
  if [[ -f "$file" ]]; then
    LC_ALL=C wc -c < "$file" | tr -d '[:space:]'
  else
    printf '0'
  fi
}

# panel_reviewer_model AGENT → the concrete model id the seat will use. Mirrors
# the defaults in lib/co-evolution.sh so panel-state.json never reports an
# ambiguous seat. Codex inherits its model from the Codex CLI config unless
# CODEX_MODEL is set, which is exactly what condition B's bouncer run does.
panel_reviewer_model() {
  case "$1" in
    codex) printf '%s' "${CODEX_MODEL:-(inherit:CLI-config)}" ;;
    glm)   printf '%s' "${GLM_MODEL:-glm-5.3-flash}" ;;
    kimi)  printf '%s' "${KIMI_MODEL:-kimi-k3}" ;;
    *)     printf '%s' "unknown" ;;
  esac
}

# panel_phase_add PHASE AGENT MODEL STATUS STARTED FINISHED BYTES_IN BYTES_OUT SKIP_REASON
panel_phase_add() {
  local json
  json=$(jq -n \
    --arg phase "$1" --arg agent "$2" --arg model "$3" --arg status "$4" \
    --arg started "$5" --arg finished "$6" \
    --argjson bytes_in "${7:-0}" --argjson bytes_out "${8:-0}" \
    --arg skip "${9:-}" \
    '{
       phase: $phase, agent: $agent, model: $model, status: $status,
       started_at: $started, finished_at: $finished,
       bytes_in: $bytes_in, bytes_out: $bytes_out,
       skip_reason: (if $skip == "" then null else $skip end)
     }') || die "panel_phase_add: could not render the $1 phase record"
  PANEL_PHASES+=("$json")
}

# panel_tokens_json → the `tokens` block run-benchmark.sh copies into meta.json.
# Same shape collect_token_usage (lib/co-evolution.sh:1856) writes for bouncer
# cells, so report.sh can sum conditions B, C and D identically. It is rebuilt
# from the sidecars on disk rather than accumulated in memory, so a resumed run
# still reports the phases it reused.
#
# Direct-provider sidecars remain phase-level provenance. Claude totals include
# only the compose and synthesis calls; GLM and Kimi retain their own source
# labels so they cannot be misreported as Anthropic usage.
panel_tokens_json() {
  local phases='{}' tmp sidecar phase tokens_val i
  local -a sidecar_phases=(compose critique-glm critique-kimi synthesis)
  local -a sidecar_files=(
    "$OUT_DIR/compose-output.md.usage.json"
    "$OUT_DIR/critique-glm.md.usage.json"
    "$OUT_DIR/critique-kimi.md.usage.json"
    "$OUT_DIR/.synthesis-output.md.usage.json"
  )

  for i in "${!sidecar_phases[@]}"; do
    sidecar="${sidecar_files[$i]}"
    phase="${sidecar_phases[$i]}"
    [[ -f "$sidecar" ]] || continue
    if tmp=$(jq --arg p "$phase" --slurpfile s "$sidecar" \
               '. + {($p): $s[0]}' <<<"$phases" 2>/dev/null); then
      phases="$tmp"
    fi
  done

  # Codex has no usage sidecar; its CLI prints a "tokens used" line to stderr.
  # Same awk collect_token_usage uses.
  local codex_stderr="$OUT_DIR/.critique-codex-stderr.log"
  if [[ -f "$codex_stderr" ]]; then
    tokens_val=$(awk '/^tokens used$/{getline; gsub(",",""); print; exit}' "$codex_stderr" 2>/dev/null) || tokens_val=""
    if [[ "$tokens_val" =~ ^[0-9]+$ ]]; then
      if tmp=$(jq --argjson t "$tokens_val" \
                 '. + {"critique-codex": {source: "codex-stderr", total_tokens: $t}}' \
                 <<<"$phases" 2>/dev/null); then
        phases="$tmp"
      fi
    fi
  fi

  jq -n --argjson phases "$phases" '
    ($phases | to_entries) as $entries |
    def num($x): ($x // 0);
    {
      phases: $phases,
      totals: {
        claude_input:       ([$entries[] | select(.value.source == "claude-json") | num(.value.input_tokens)] | add // 0),
        claude_output:      ([$entries[] | select(.value.source == "claude-json") | num(.value.output_tokens)] | add // 0),
        claude_cache_read:  ([$entries[] | select(.value.source == "claude-json") | num(.value.cache_read_input_tokens)] | add // 0),
        claude_cost_usd:    ([$entries[] | select(.value.source == "claude-json") | num(.value.total_cost_usd)] | add // 0),
        codex_total_tokens: ([$entries[] | select(.value.source == "codex-stderr") | num(.value.total_tokens)] | add // 0)
      }
    }' 2>/dev/null
}

# panel_state_write STATUS — render panel-state.json atomically (tmp + rename in
# the same directory) so a killed run never leaves a half-parsed state file for
# the orchestrator to read.
panel_state_write() {
  local status="$1"
  local phases_json tmp tokens_json
  local reviewers_json

  if (( ${#PANEL_PHASES[@]} == 0 )); then
    phases_json='[]'
  else
    phases_json=$(printf '%s\n' "${PANEL_PHASES[@]}" | jq -s '.') \
      || die "panel_state_write: could not assemble the phase list"
  fi
  reviewers_json=$(printf '%s\n' "${REVIEWERS[@]}" | jq -R . | jq -s '.') \
    || die "panel_state_write: could not assemble the reviewer list"

  # Token capture must never take a run down: an unreadable sidecar costs the
  # cost line in the report, not the cell.
  tokens_json=$(panel_tokens_json) || tokens_json=""
  [[ -n "$tokens_json" ]] || tokens_json='{"phases":{},"totals":{}}'

  tmp="$OUT_DIR/.panel-state.json.tmp.$$"
  jq -n \
    --arg schema "bench-panel/1.0" \
    --arg status "$status" \
    --arg task_file "$TASK_FILE" \
    --arg composer_model "$COMPOSER_MODEL" \
    --argjson degraded "$PANEL_DEGRADED" \
    --argjson reviewers "$reviewers_json" \
    --argjson phases "$phases_json" \
    --argjson tokens "$tokens_json" \
    '{
       schema: $schema,
       status: $status,
       task_file: $task_file,
       composer_model: $composer_model,
       reviewers: $reviewers,
       degraded: $degraded,
       # run-benchmark.sh reads .kimi_status straight into meta.json, so the
       # panel-specific seat outcome is surfaced at the top level too.
       kimi_status: ([$phases[] | select(.phase == "critique-kimi") | .status] | last
                     | if . == null then null
                       elif . == "complete" or . == "reused" then "ok"
                       else . end),
       phases: $phases,
       tokens: $tokens
     }' > "$tmp" || die "panel_state_write: could not render $PANEL_STATE"
  mv -f "$tmp" "$PANEL_STATE" || die "panel_state_write: could not install $PANEL_STATE"
}

# panel_exit CODE STATE_STATUS [MESSAGE] — every exit path writes panel-state
# first; the orchestrator reads the state file, not this script's stdout.
panel_exit() {
  local code="$1" state_status="$2" message="${3:-}"

  if [[ -n "$message" ]]; then
    log "$message"
  fi
  panel_state_write "$state_status"
  exit "$code"
}

# panel_reusable FILE AGENT → 0 when FILE is a usable artifact from a prior run.
# The probe's own logging is suppressed: a stale auth page on disk is a resume
# decision, not an error to report.
panel_reusable() {
  local file="$1" agent="$2"

  [[ -s "$file" ]] || return 1
  validate_agent_artifact "$file" "" "$agent" >/dev/null 2>&1
}

# panel_stderr_is_retryable FILE → 0 when the seat's stderr names an auth or
# quota condition. Empty output plus one of these means "come back later",
# which is exit 4, not a failed critique.
panel_stderr_is_retryable() {
  local file="$1"

  [[ -s "$file" ]] || return 1
  file_contains_auth_failure "$file" && return 0
  grep -qiE 'rate.?limit|quota|too many requests|429|usage limit|overloaded' "$file"
}

# panel_word_target → the task's own word-target sentence, repeated verbatim in
# the synthesis prompt so the revision stays length-comparable with conditions
# A, B and D. Falls back to the frontmatter value, then to nothing.
panel_word_target() {
  local line words

  line=$(printf '%s\n' "$TASK_BODY" \
    | grep -iE 'produce a plan of roughly [0-9]+ words' | tail -1) || line=""
  if [[ -n "$line" ]]; then
    printf '%s' "$line"
    return 0
  fi

  # bench_fm_get requires mikefarah yq and dies without it; the word target is
  # a nicety, not a reason to abort a run on a machine that has no yq.
  if command -v yq >/dev/null 2>&1; then
    words=$(bench_fm_get "$TASK_FILE" expected_plan_words 2>/dev/null) || words=""
    if [[ "$words" =~ ^[0-9]+$ ]]; then
      printf 'Produce a plan of roughly %s words.' "$words"
    fi
  fi
}

# --- Phase 1: compose --------------------------------------------------------

panel_compose() {
  local prompt_file="$OUT_DIR/compose-prompt.md"
  local stderr_file="$OUT_DIR/.compose-stderr.log"
  local started finished rc=0

  started=$(panel_now)
  if panel_reusable "$COMPOSE_OUTPUT" claude; then
    log "compose: reusing $COMPOSE_OUTPUT"
    panel_phase_add compose claude "$COMPOSER_MODEL" reused "$started" "$(panel_now)" \
      "$(panel_bytes "$prompt_file")" "$(panel_bytes "$COMPOSE_OUTPUT")" ""
    return 0
  fi

  bench_compose_prompt "$TASK_BODY" > "$prompt_file" \
    || die "compose: could not write $prompt_file"

  # Dynamically scoped so invoke_claude sees them without rewriting the caller's
  # environment — same technique bench_run_solo_cell uses for condition A.
  local CLAUDE_MODEL="$COMPOSER_MODEL"
  local CO_EVOLVE_TOKEN_CAPTURE=1

  log "compose: $COMPOSER_MODEL"
  : > "$stderr_file"
  invoke_claude "$prompt_file" "$COMPOSE_OUTPUT" "$stderr_file" false claude || true

  validate_agent_artifact "$COMPOSE_OUTPUT" "$stderr_file" claude || rc=$?
  finished=$(panel_now)

  if (( rc == 2 )) || { (( rc != 0 )) && panel_stderr_is_retryable "$stderr_file"; }; then
    rm -f "$COMPOSE_OUTPUT"
    panel_phase_add compose claude "$COMPOSER_MODEL" retryable "$started" "$finished" \
      "$(panel_bytes "$prompt_file")" 0 "auth or quota failure; artifact removed so resume retries"
    panel_exit "$PANEL_EXIT_RETRY" retryable \
      "compose: authentication/quota failure; no artifact written. Re-run to resume."
  fi
  if (( rc != 0 )); then
    rm -f "$COMPOSE_OUTPUT"
    panel_phase_add compose claude "$COMPOSER_MODEL" failed "$started" "$finished" \
      "$(panel_bytes "$prompt_file")" 0 "composer returned no usable document"
    panel_exit "$PANEL_EXIT_FAIL" failed \
      "compose: composer returned no usable document (rc=$rc); see $stderr_file"
  fi

  panel_phase_add compose claude "$COMPOSER_MODEL" complete "$started" "$finished" \
    "$(panel_bytes "$prompt_file")" "$(panel_bytes "$COMPOSE_OUTPUT")" ""
}

# --- Phase 2: critiques ------------------------------------------------------

# panel_critic_prompt PLAN_FILE → the assembled critique prompt on stdout.
panel_critic_prompt() {
  local plan_file="$1"
  local template plan_content

  # Drop the leading HTML comment (see the header note) and any blank lines it
  # leaves behind, so the persona starts at its first instruction line.
  template=$(awk '
    NR == 1 && $0 ~ /^[[:space:]]*<!--/ { in_comment = 1 }
    in_comment { if ($0 ~ /-->/) { in_comment = 0 } ; next }
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$CRITIC_TEMPLATE")

  plan_content=$(cat "$plan_file")

  # patsub_replacement is unset by benchmark-lib.sh, so `&` in the replacement
  # is literal and the plan text cannot corrupt itself.
  template="${template//\{TASK\}/$TASK_BODY}"
  template="${template//\{PLAN_CONTENT\}/$plan_content}"
  printf '%s\n' "$template"
}

panel_run_critique() {
  local reviewer="$1"
  local artifact="$OUT_DIR/critique-${reviewer}.md"
  local skip_marker="$OUT_DIR/critique-${reviewer}.SKIPPED"
  local prompt_file="$OUT_DIR/.critique-prompt-${reviewer}.md"
  local stderr_file="$OUT_DIR/.critique-${reviewer}-stderr.log"
  local model started finished prompt_bytes rc=0

  model=$(panel_reviewer_model "$reviewer")
  started=$(panel_now)

  if panel_reusable "$artifact" "$reviewer"; then
    rm -f "$skip_marker"
    PANEL_SURVIVORS+=("$artifact")
    log "critique/${reviewer}: reusing $artifact"
    panel_phase_add "critique-${reviewer}" "$reviewer" "$model" reused "$started" "$(panel_now)" \
      "$(panel_bytes "$prompt_file")" "$(panel_bytes "$artifact")" ""
    return 0
  fi

  panel_critic_prompt "$COMPOSE_OUTPUT" > "$prompt_file" \
    || die "critique/${reviewer}: could not write $prompt_file"
  prompt_bytes=$(panel_bytes "$prompt_file")

  # Registered size gate — Kimi only, before the direct API call.
  if [[ "$reviewer" == "kimi" ]] && (( prompt_bytes > PANEL_KIMI_MAX_BYTES )); then
    local reason="prompt is ${prompt_bytes} bytes (limit ${PANEL_KIMI_MAX_BYTES})"
    printf 'SKIPPED: kimi critique not attempted.\nreason: size\ndetail: %s\n' "$reason" \
      > "$skip_marker"
    PANEL_DEGRADED=true
    log "critique/kimi: SKIPPED — $reason"
    panel_phase_add "critique-kimi" kimi "$model" skipped "$started" "$(panel_now)" \
      "$prompt_bytes" 0 "size: $reason"
    return 0
  fi

  # Pre-flight the two conditions the lib's adapters die() on, so a missing
  # credential is a recorded retryable exit rather than an unlogged abort.
  if [[ "$reviewer" == "glm" && -z "${ZAI_API_KEY:-}" ]]; then
    panel_phase_add "critique-glm" glm "$model" retryable "$started" "$(panel_now)" \
      "$prompt_bytes" 0 "ZAI_API_KEY is not set"
    panel_exit "$PANEL_EXIT_RETRY" retryable \
      "critique/glm: ZAI_API_KEY is not set; re-run once the seat is configured."
  fi
  if [[ "$reviewer" == "kimi" && -z "${KIMI_API_KEY:-}" ]]; then
    panel_phase_add "critique-kimi" kimi "$model" retryable "$started" "$(panel_now)" \
      "$prompt_bytes" 0 "KIMI_API_KEY is not set"
    panel_exit "$PANEL_EXIT_RETRY" retryable \
      "critique/kimi: KIMI_API_KEY is not set; re-run once the seat is configured."
  fi

  log "critique/${reviewer}: $model (${prompt_bytes} bytes)"
  : > "$stderr_file"
  case "$reviewer" in
    codex)
      # Contain any stray write: codex exec runs --full-auto, and pointing it at
      # the repo or the cell root would let a critique pass touch real files.
      local WORKDIR="$OUT_DIR/.codex-workdir"
      mkdir -p "$WORKDIR"
      invoke_codex "$prompt_file" "$artifact" "$stderr_file" || true
      ;;
    glm)
      local CO_EVOLVE_TOKEN_CAPTURE=1
      invoke_glm "$prompt_file" "$artifact" "$stderr_file" false || true
      ;;
    kimi)
      local CO_EVOLVE_TOKEN_CAPTURE=1
      invoke_kimi "$prompt_file" "$artifact" "$stderr_file" || true
      ;;
  esac

  validate_agent_artifact "$artifact" "$stderr_file" "$reviewer" || rc=$?
  finished=$(panel_now)

  if (( rc == 2 )) || { (( rc != 0 )) && panel_stderr_is_retryable "$stderr_file"; }; then
    rm -f "$artifact"
    panel_phase_add "critique-${reviewer}" "$reviewer" "$model" retryable "$started" "$finished" \
      "$prompt_bytes" 0 "auth or quota failure; artifact removed so resume retries"
    panel_exit "$PANEL_EXIT_RETRY" retryable \
      "critique/${reviewer}: authentication/quota failure; re-run to resume."
  fi
  if (( rc != 0 )); then
    # A reviewer that returns garbage is one lost critique, not a lost panel:
    # the synthesis proceeds on the survivors and the cell is marked degraded.
    rm -f "$artifact"
    PANEL_DEGRADED=true
    log "critique/${reviewer}: invalid output (rc=$rc); continuing without it"
    panel_phase_add "critique-${reviewer}" "$reviewer" "$model" invalid "$started" "$finished" \
      "$prompt_bytes" 0 "reviewer returned no usable critique"
    return 0
  fi

  rm -f "$skip_marker"
  PANEL_SURVIVORS+=("$artifact")
  panel_phase_add "critique-${reviewer}" "$reviewer" "$model" complete "$started" "$finished" \
    "$prompt_bytes" "$(panel_bytes "$artifact")" ""
}

# --- Phase 3: synthesis ------------------------------------------------------

# panel_synthesis_prompt → prompt on stdout. Reviewers are numbered 1..N over
# the SURVIVORS in --reviewers order: a gap ("Reviewer 1, Reviewer 3") would
# itself tell the synthesizer that a critique was dropped.
panel_synthesis_prompt() {
  local i=0 file word_target

  printf '%s\n' "You wrote the plan below in response to the task below. Independent reviewers then critiqued it. Revise the plan."
  printf '\n## TASK\n\n%s\n' "$TASK_BODY"
  printf '\n## YOUR DRAFT PLAN\n\n%s\n' "$(cat "$COMPOSE_OUTPUT")"
  printf '\n## CRITIQUES\n'
  for file in "${PANEL_SURVIVORS[@]}"; do
    i=$((i + 1))
    printf '\n### Reviewer %d\n\n%s\n' "$i" "$(cat "$file")"
  done

  printf '\n## INSTRUCTIONS\n\n'
  printf '%s\n' "Work through every point the reviewers raised and decide each one on its merits. Accept a point because it is right, not because a reviewer made it; reject a point that is wrong, out of scope for the task, or would make the plan worse. Then rewrite the plan so it incorporates everything you accepted."

  word_target=$(panel_word_target)
  if [[ -n "$word_target" ]]; then
    printf '\n%s\n' "$word_target"
  fi

  printf '\n%s\n' "Output ONLY the revised plan. No preamble, no meta-commentary, no acknowledgments section, no list of what you changed or rejected, no closing note. What you return must read as a standalone plan and nothing else."
}

panel_synthesize() {
  local prompt_file="$OUT_DIR/.synthesis-prompt.md"
  local stderr_file="$OUT_DIR/.synthesis-stderr.log"
  local raw_output="$OUT_DIR/.synthesis-output.md"
  local started finished rc=0

  started=$(panel_now)
  if panel_reusable "$FINAL_OUTPUT" claude; then
    log "synthesis: reusing $FINAL_OUTPUT"
    panel_phase_add synthesis claude "$COMPOSER_MODEL" reused "$started" "$(panel_now)" \
      "$(panel_bytes "$prompt_file")" "$(panel_bytes "$FINAL_OUTPUT")" ""
    return 0
  fi

  panel_synthesis_prompt > "$prompt_file" || die "synthesis: could not write $prompt_file"

  local CLAUDE_MODEL="$COMPOSER_MODEL"
  local CO_EVOLVE_TOKEN_CAPTURE=1

  log "synthesis: $COMPOSER_MODEL over ${#PANEL_SURVIVORS[@]} critique(s)"
  : > "$stderr_file"
  rm -f "$raw_output"
  invoke_claude "$prompt_file" "$raw_output" "$stderr_file" false claude || true

  validate_agent_artifact "$raw_output" "$stderr_file" claude || rc=$?
  finished=$(panel_now)

  if (( rc == 2 )) || { (( rc != 0 )) && panel_stderr_is_retryable "$stderr_file"; }; then
    rm -f "$raw_output"
    panel_phase_add synthesis claude "$COMPOSER_MODEL" retryable "$started" "$finished" \
      "$(panel_bytes "$prompt_file")" 0 "auth or quota failure; final.md not written"
    panel_exit "$PANEL_EXIT_RETRY" retryable \
      "synthesis: authentication/quota failure; final.md not written. Re-run to resume."
  fi
  if (( rc != 0 )); then
    rm -f "$raw_output"
    panel_phase_add synthesis claude "$COMPOSER_MODEL" failed "$started" "$finished" \
      "$(panel_bytes "$prompt_file")" 0 "synthesis returned no usable document"
    panel_exit "$PANEL_EXIT_FAIL" failed \
      "synthesis: returned no usable document (rc=$rc); see $stderr_file"
  fi

  # final.md is the completion marker: install it last, by rename, so a killed
  # run never leaves a partial final.md for the judge to read.
  mv -f "$raw_output" "$FINAL_OUTPUT" || die "synthesis: could not install $FINAL_OUTPUT"
  panel_phase_add synthesis claude "$COMPOSER_MODEL" complete "$started" "$finished" \
    "$(panel_bytes "$prompt_file")" "$(panel_bytes "$FINAL_OUTPUT")" ""
}

# --- Run ---------------------------------------------------------------------

log "panel: task=$TASK_FILE out=$OUT_DIR reviewers=$(IFS=,; printf '%s' "${REVIEWERS[*]}")"

panel_compose

for _reviewer in "${REVIEWERS[@]}"; do
  panel_run_critique "$_reviewer"
done

if (( ${#PANEL_SURVIVORS[@]} == 0 )); then
  panel_exit "$PANEL_EXIT_FAIL" failed \
    "panel: every reviewer failed; there is nothing to synthesize from."
fi

panel_synthesize

if [[ "$PANEL_DEGRADED" == "true" ]]; then
  log "panel: complete (DEGRADED — ${#PANEL_SURVIVORS[@]}/${#REVIEWERS[@]} critiques survived)"
else
  log "panel: complete — $FINAL_OUTPUT"
fi
panel_state_write complete
exit "$PANEL_EXIT_OK"
