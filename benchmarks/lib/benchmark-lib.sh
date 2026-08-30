#!/usr/bin/env bash

# Shared helpers for the co-evolution benchmark suite (see the plan's
# "File layout" section). Sourceable by run-benchmark.sh, run-panel.sh, and
# judge-matrix.sh; also runnable as `bash benchmark-lib.sh --self-test`.
#
# Contract notes:
# - This file CONSUMES co-evolve-bouncer.sh and lib/co-evolution.sh; it never
#   modifies them. The compose-prompt builder below is a byte-for-byte replica
#   of co-evolve-bouncer.sh:785-787 (string-input arm) and must be re-verified
#   against that code whenever the bouncer's compose phase changes.
# - Lint/leak helpers RETURN nonzero rather than `exit`ing: a sourced library
#   that exits kills its caller mid-batch. Callers turn a nonzero return into
#   their own exit status.

# Double-source guard. Sourcing twice is otherwise harmless but wasteful, and
# re-running the co-evolution.sh source would reset its `: "${VAR:=}"` defaults.
if [[ -n "${BENCH_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
BENCH_LIB_SOURCED=1

# Same bash 5.2 hazard co-evolution.sh guards against: an unescaped `&` in a
# ${var//pat/repl} REPLACEMENT expands to the match and corrupts task text.
shopt -u patsub_replacement 2>/dev/null || true

BENCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_REPO_ROOT="$(cd "$BENCH_LIB_DIR/../.." && pwd)"

# invoke_claude / validate_agent_artifact / file_contains_auth_failure / die /
# log / require_mikefarah_yq all come from the repo's shared lib. Guard on a
# function that only that file defines so an already-sourcing caller pays once.
if ! declare -F invoke_claude >/dev/null 2>&1; then
  # shellcheck source=../../lib/co-evolution.sh
  source "$BENCH_REPO_ROOT/lib/co-evolution.sh"
fi

# MAX_PATH budget. The bouncer's own state.json path blew past the Windows
# 260-char ceiling during planning (jq.exe: "Could not open file") while bash
# happily created the directory, so the orchestrator pre-checks its worst case.
: "${BENCH_MAX_PATH:=240}"

# --- Cell layout -------------------------------------------------------------

# bench_cell_dir BATCH_DIR TASK_ID COND_ID → prints the cell directory path.
# Pure string composition: does not create the directory.
bench_cell_dir() {
  local batch_dir="${1:?bench_cell_dir requires a batch dir}"
  local task_id="${2:?bench_cell_dir requires a task id}"
  local cond_id="${3:?bench_cell_dir requires a condition id}"

  printf '%s/%s/%s' "$batch_dir" "$task_id" "$cond_id"
}

# bench_meta_write CELL_DIR JSON — validate JSON, then write meta.json
# atomically. meta.json is the completion marker for resume, so a half-written
# file would make a crashed cell look finished: write to a tmp file in the SAME
# directory (same filesystem, so mv is a rename) and mv it into place last.
bench_meta_write() {
  local cell_dir="${1:?bench_meta_write requires a cell dir}"
  local json="${2:?bench_meta_write requires a JSON payload}"
  local tmp

  command -v jq >/dev/null 2>&1 || die "bench_meta_write requires jq"
  mkdir -p "$cell_dir" || die "bench_meta_write: could not create $cell_dir"

  printf '%s' "$json" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "bench_meta_write: payload for $cell_dir is not a JSON object"

  tmp="$cell_dir/.meta.json.tmp.$$"
  printf '%s' "$json" | jq . > "$tmp" 2>/dev/null \
    || die "bench_meta_write: could not render meta.json for $cell_dir"
  mv -f "$tmp" "$cell_dir/meta.json" \
    || die "bench_meta_write: could not install meta.json in $cell_dir"
}

# bench_meta_status CELL_DIR → prints `.status`, or "absent" when there is no
# meta.json / no readable status. Never fails: the orchestrator's resume path
# treats every non-"complete" answer the same way.
bench_meta_status() {
  local cell_dir="${1:?bench_meta_status requires a cell dir}"
  local meta="$cell_dir/meta.json"
  local status=""

  [[ -f "$meta" ]] || { printf '%s' "absent"; return 0; }
  if command -v jq >/dev/null 2>&1; then
    status=$(jq -r 'if has("status") and (.status | type == "string") then .status else "absent" end' \
      "$meta" 2>/dev/null) || status=""
  fi
  [[ -n "$status" ]] || status="absent"
  printf '%s' "$status"
}

# --- Corpus frontmatter ------------------------------------------------------

# _bench_frontmatter FILE → prints the YAML between the leading `---` fence and
# the next `---` line. Empty output (rc 1) when the file has no frontmatter.
# CR is stripped so a CRLF corpus file still parses under Git Bash.
_bench_frontmatter() {
  local file="${1:?_bench_frontmatter requires a file}"
  local block

  [[ -f "$file" ]] || return 1
  block=$(awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 ~ /^---[[:space:]]*$/) { infm = 1; next } else { exit } }
    infm && $0 ~ /^---[[:space:]]*$/ { exit }
    infm { print }
  ' "$file")

  [[ -n "$block" ]] || return 1
  printf '%s\n' "$block"
}

# _bench_body FILE → prints everything after the closing frontmatter `---`.
# A file without frontmatter is all body.
_bench_body() {
  local file="${1:?_bench_body requires a file}"

  [[ -f "$file" ]] || return 1
  awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 ~ /^---[[:space:]]*$/ { infm = 1; next }
    infm && $0 ~ /^---[[:space:]]*$/ { infm = 0; body = 1; next }
    infm { next }
    { print }
  ' "$file"
}

# bench_task_body FILE → the canonical task-body transform every condition's
# compose prompt is built from: frontmatter removed, leading/trailing blank
# lines trimmed, interior blank runs kept. A/B/D consume it via <cell>/in.md
# (run-benchmark.sh write_cell_input) and C via run-panel.sh; both MUST use
# this function — a divergent copy is a byte-parity confound in the primary
# comparison, not a style issue.
bench_task_body() {
  local file="${1:?bench_task_body requires a file}"

  _bench_body "$file" \
    | awk 'NF { blank = 0; if (!seen) seen = 1 }
           !NF { if (!seen) next; blank++; next }
           seen { while (blank-- > 0) print ""; print }'
}

# bench_fm_get FILE KEY → prints the frontmatter value for KEY (empty string
# when absent). Returns 1 when the file has no frontmatter at all, so callers
# can distinguish "no frontmatter" from "key missing".
bench_fm_get() {
  local file="${1:?bench_fm_get requires a file}"
  local key="${2:?bench_fm_get requires a key}"
  local block value

  require_mikefarah_yq
  block=$(_bench_frontmatter "$file") || return 1

  value=$(printf '%s\n' "$block" | yq -r ".${key} // \"\"" 2>/dev/null) || return 1
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

# --- GLM quota ledger --------------------------------------------------------
#
# Z.AI's free tier is ~50 requests/day, so a full batch spans days. The ledger
# is `{date, calls}` in UTC: on a date change the counter resets. Known blind
# spot (accepted in the plan): it cannot see Z.AI's server-side window or GLM
# calls made outside the benchmark.

_bench_ledger_write() {
  local ledger="${1:?}" day="${2:?}" calls="${3:?}"
  local tmp="${ledger}.tmp.$$"

  jq -n --arg date "$day" --argjson calls "$calls" '{date: $date, calls: $calls}' > "$tmp" \
    || die "glm ledger: could not render $ledger"
  mv -f "$tmp" "$ledger" || die "glm ledger: could not install $ledger"
}

# _bench_ledger_read BATCH_DIR → prints the current call count for today,
# normalizing the on-disk ledger (creating it, or resetting it on date change).
_bench_ledger_read() {
  local batch_dir="${1:?}"
  local ledger="$batch_dir/glm-ledger.json"
  local today ledger_date calls

  command -v jq >/dev/null 2>&1 || die "glm ledger requires jq"
  today=$(date -u +%Y-%m-%d)
  mkdir -p "$batch_dir" || die "glm ledger: could not create $batch_dir"

  ledger_date=""
  calls=0
  if [[ -f "$ledger" ]]; then
    ledger_date=$(jq -r '.date // ""' "$ledger" 2>/dev/null) || ledger_date=""
    calls=$(jq -r '.calls // 0' "$ledger" 2>/dev/null) || calls=0
  fi
  # A malformed/absent count is treated as 0 rather than aborting the batch;
  # over-counting GLM is a wasted call, under-counting is a hard auth failure
  # that the resume path already handles as a cheap retry.
  [[ "$calls" =~ ^[0-9]+$ ]] || calls=0
  if [[ "$ledger_date" != "$today" ]]; then
    calls=0
  fi

  _bench_ledger_write "$ledger" "$today" "$calls"
  printf '%s' "$calls"
}

# bench_glm_ledger_check BATCH_DIR NEEDED BUDGET → 0 when NEEDED more calls fit
# under BUDGET today, 1 when they do not (caller marks the cell pending-quota).
bench_glm_ledger_check() {
  local batch_dir="${1:?bench_glm_ledger_check requires a batch dir}"
  local needed="${2:?bench_glm_ledger_check requires a needed count}"
  local budget="${3:?bench_glm_ledger_check requires a budget}"
  local calls

  [[ "$needed" =~ ^[0-9]+$ ]] || die "glm ledger: needed must be a non-negative integer, got '$needed'"
  [[ "$budget" =~ ^[0-9]+$ ]] || die "glm ledger: budget must be a non-negative integer, got '$budget'"

  calls=$(_bench_ledger_read "$batch_dir")
  (( calls + needed <= budget ))
}

# bench_glm_ledger_add BATCH_DIR N — record N spent GLM calls. Read-modify-write
# through the same tmp+mv rename as the writer above, so a crash mid-update
# leaves the previous ledger intact rather than a truncated file. The
# orchestrator is single-process by design; this is not a cross-process lock.
bench_glm_ledger_add() {
  local batch_dir="${1:?bench_glm_ledger_add requires a batch dir}"
  local n="${2:?bench_glm_ledger_add requires a count}"
  local calls

  [[ "$n" =~ ^[0-9]+$ ]] || die "glm ledger: increment must be a non-negative integer, got '$n'"
  calls=$(_bench_ledger_read "$batch_dir")
  _bench_ledger_write "$batch_dir/glm-ledger.json" "$(date -u +%Y-%m-%d)" "$(( calls + n ))"
}

# --- MAX_PATH guard ----------------------------------------------------------

# bench_path_guard MAX_EXPECTED_PATH — die when the caller's worst-case path
# string exceeds BENCH_MAX_PATH (240). The caller computes the worst case (e.g.
# the deepest state.json under the deepest cell); this only measures and reports.
bench_path_guard() {
  local candidate="${1:?bench_path_guard requires a candidate path}"
  local length=${#candidate}

  if (( length > BENCH_MAX_PATH )); then
    die "worst-case path is ${length} chars (limit ${BENCH_MAX_PATH}); Windows MAX_PATH will break jq mid-run. Offending path: ${candidate}"
  fi
  return 0
}

# --- Corpus linter -----------------------------------------------------------

# _bench_banned_tokens BANNED_FILE → prints one token per line, dropping `#`
# comments and blank lines and trimming CR / trailing whitespace.
_bench_banned_tokens() {
  local banned_file="${1:?}"

  [[ -f "$banned_file" ]] || return 1
  sed -e 's/\r$//' -e 's/[[:space:]]*$//' "$banned_file" \
    | grep -v '^[[:space:]]*#' \
    | grep -v '^[[:space:]]*$' \
    || true
}

# bench_lint_corpus CORPUS_DIR TEMPLATES_DIR BANNED_FILE
# Reports EVERY violation (never short-circuits on the first) and returns 1 if
# any were found, 0 on a clean corpus. Deliberately a `return`, not an `exit`:
# this is a sourced library and the caller owns the process exit status.
bench_lint_corpus() {
  local corpus_dir="${1:?bench_lint_corpus requires a corpus dir}"
  local templates_dir="${2:?bench_lint_corpus requires a templates dir}"
  local banned_file="${3:?bench_lint_corpus requires a banned-token file}"
  local violations=0
  local persona_bytes task_file task_name id domain difficulty source words
  local body body_words last_line worst_case token
  local -a seen_ids=()
  local seen

  [[ -d "$corpus_dir" ]] || { log "LINT FAIL: corpus dir not found: $corpus_dir"; return 1; }
  local persona="$templates_dir/panel-critic.md"
  [[ -f "$persona" ]] || { log "LINT FAIL: panel-critic template not found: $persona"; return 1; }
  [[ -f "$banned_file" ]] || { log "LINT FAIL: banned-token file not found: $banned_file"; return 1; }

  persona_bytes=$(LC_ALL=C wc -c < "$persona" | tr -d '[:space:]')

  local -a task_files=()
  while IFS= read -r task_file; do
    [[ -n "$task_file" ]] && task_files+=("$task_file")
  done < <(find "$corpus_dir" -maxdepth 1 -type f -name 't*.md' | sort)

  if (( ${#task_files[@]} == 0 )); then
    log "LINT FAIL: no t*.md task files under $corpus_dir"
    return 1
  fi

  local -a banned=()
  while IFS= read -r token; do
    [[ -n "$token" ]] && banned+=("$token")
  done < <(_bench_banned_tokens "$banned_file")

  for task_file in "${task_files[@]}"; do
    task_name=$(basename "$task_file" .md)

    if ! _bench_frontmatter "$task_file" >/dev/null; then
      log "LINT FAIL [$task_name]: no YAML frontmatter (expected a leading '---' fence)"
      violations=$((violations + 1))
      continue
    fi

    id=$(bench_fm_get "$task_file" id)
    domain=$(bench_fm_get "$task_file" domain)
    difficulty=$(bench_fm_get "$task_file" difficulty)
    source=$(bench_fm_get "$task_file" source)
    words=$(bench_fm_get "$task_file" expected_plan_words)

    local key
    for key in id domain difficulty source expected_plan_words; do
      case "$key" in
        id)                  [[ -n "$id" ]]         || { log "LINT FAIL [$task_name]: frontmatter key 'id' is missing or empty"; violations=$((violations + 1)); } ;;
        domain)              [[ -n "$domain" ]]     || { log "LINT FAIL [$task_name]: frontmatter key 'domain' is missing or empty"; violations=$((violations + 1)); } ;;
        difficulty)          [[ -n "$difficulty" ]] || { log "LINT FAIL [$task_name]: frontmatter key 'difficulty' is missing or empty"; violations=$((violations + 1)); } ;;
        source)              [[ -n "$source" ]]     || { log "LINT FAIL [$task_name]: frontmatter key 'source' is missing or empty"; violations=$((violations + 1)); } ;;
        expected_plan_words) [[ -n "$words" ]]      || { log "LINT FAIL [$task_name]: frontmatter key 'expected_plan_words' is missing or empty"; violations=$((violations + 1)); } ;;
      esac
    done

    if [[ -n "$id" && "$id" != "$task_name" ]]; then
      log "LINT FAIL [$task_name]: id '$id' does not match the filename"
      violations=$((violations + 1))
    fi
    if [[ -n "$id" ]]; then
      for seen in ${seen_ids[@]+"${seen_ids[@]}"}; do
        if [[ "$seen" == "$id" ]]; then
          log "LINT FAIL [$task_name]: duplicate id '$id'"
          violations=$((violations + 1))
        fi
      done
      seen_ids+=("$id")
    fi

    body=$(_bench_body "$task_file")
    body_words=$(printf '%s\n' "$body" | wc -w | tr -d '[:space:]')
    if (( body_words > 150 )); then
      log "LINT FAIL [$task_name]: body is $body_words words (max 150)"
      violations=$((violations + 1))
    fi

    if [[ -n "$words" ]]; then
      if ! [[ "$words" =~ ^[0-9]+$ ]]; then
        log "LINT FAIL [$task_name]: expected_plan_words '$words' is not an integer"
        violations=$((violations + 1))
        words=""
      elif (( words < 500 || words > 700 )); then
        log "LINT FAIL [$task_name]: expected_plan_words $words is outside 500-700"
        violations=$((violations + 1))
      fi
    fi

    # The prompt must END with the word target, or condition A/B/C plans are not
    # length-comparable and the report's length-bias check is meaningless.
    last_line=$(printf '%s\n' "$body" | grep -v '^[[:space:]]*$' | tail -1)
    if [[ -n "$words" ]]; then
      if ! printf '%s' "$last_line" | grep -qiE "produce a plan of roughly ${words} words\.?[[:space:]]*$"; then
        log "LINT FAIL [$task_name]: body must end with \"Produce a plan of roughly ${words} words\" (last line: ${last_line:0:80})"
        violations=$((violations + 1))
      fi
    fi

    # Kimi arithmetic (plan's Corpus section): the worst-case critique prompt is
    # persona template + composed plan + slack. The frozen design uses 11500 as
    # its registered ceiling, so preserve that limit after the direct-API move
    # to keep condition C homogeneous with the pre-registered pilot.
    # 7.5 bytes/word is computed as (words * 15 + 1) / 2 to stay in integer bash.
    if [[ -n "$words" ]]; then
      worst_case=$(( (words * 15 + 1) / 2 + persona_bytes + 500 ))
      if (( worst_case > 11500 )); then
        log "LINT FAIL [$task_name]: worst-case Kimi critique prompt is $worst_case bytes (max 11500); lower expected_plan_words or shorten $persona"
        violations=$((violations + 1))
      fi
    fi

    # Leak-token collision: a task whose own prompt contains a banned token
    # would void every judged pair it produces. Matching is done on a
    # lowercased haystack + lowercased needle rather than `grep -iF`: GNU grep
    # 3.0 as shipped with Git Bash ABORTS (SIGABRT) on `-iF` with a
    # multi-word pattern, which would silently skip the check.
    local body_folded
    body_folded=$(printf '%s\n' "$body" | tr '[:upper:]' '[:lower:]')
    for token in ${banned[@]+"${banned[@]}"}; do
      if printf '%s\n' "$body_folded" | grep -qF -- "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"; then
        log "LINT FAIL [$task_name]: body contains banned token '$token' (would void its judged pairs)"
        violations=$((violations + 1))
      fi
    done
  done

  if (( violations > 0 )); then
    log "LINT: $violations violation(s) across ${#task_files[@]} task file(s)"
    return 1
  fi
  log "LINT: ${#task_files[@]} task file(s) OK"
  return 0
}

# --- Condition A (solo) ------------------------------------------------------

# bench_compose_prompt TASK_TEXT → prints the compose prompt.
#
# BYTE-PARITY CONTRACT with co-evolve-bouncer.sh:785-787 (string-input arm):
#     compose_prompt="Respond to the following thoroughly and substantively.
#
#     ${CONTEXT_BLOCK}${INPUT_CONTENT}"
#     printf '%s' "$compose_prompt" > "$compose_prompt_file"
# CONTEXT_BLOCK is empty without --context (:590), and INPUT_CONTENT for a
# string task is `strip_protocol_markers "$TASK"` captured through `$(...)`
# (:477-478), which drops trailing newlines. No trailing newline is written.
bench_compose_prompt() {
  local task_text="${1?bench_compose_prompt requires task text}"
  local input_content

  # Mirrors :477 — command substitution here reproduces the bouncer's own
  # trailing-newline stripping.
  input_content=$(strip_protocol_markers "$task_text")

  printf '%s' "Respond to the following thoroughly and substantively.

${input_content}"
}

# bench_run_solo_cell CELL_DIR TASK_BODY_FILE MODEL
# Condition A: one Claude call with the bouncer's compose prompt. Writes
# compose-prompt.md (the parity test's subject) and, on success, final.md.
# Returns nonzero WITHOUT writing final.md on auth failure or empty output, so
# the orchestrator's resume path retries the cell rather than judging an error
# page as a plan.
bench_run_solo_cell() {
  local cell_dir="${1:?bench_run_solo_cell requires a cell dir}"
  local task_file="${2:?bench_run_solo_cell requires a task body file}"
  local model="${3:?bench_run_solo_cell requires a model}"
  local prompt_file="$cell_dir/compose-prompt.md"
  local output_file="$cell_dir/compose-output.md"
  local stderr_file="$cell_dir/compose-stderr.log"
  local task_text artifact_rc=0

  [[ -f "$task_file" ]] || die "bench_run_solo_cell: task file not found: $task_file"
  mkdir -p "$cell_dir" || die "bench_run_solo_cell: could not create $cell_dir"

  # `$(cat …)` matches the bouncer's own file read (:469) — trailing newlines off.
  task_text=$(cat "$task_file")
  bench_compose_prompt "$task_text" > "$prompt_file"

  # Scoped to this call: `local` is dynamically scoped in bash, so invoke_claude
  # sees these without the caller's environment being rewritten (the same reason
  # invoke_glm runs in a subshell rather than exporting).
  local CLAUDE_MODEL
  CLAUDE_MODEL="$(resolve_claude_model_alias "$model")"
  local CO_EVOLVE_TOKEN_CAPTURE=1

  : > "$stderr_file"
  invoke_claude "$prompt_file" "$output_file" "$stderr_file" false claude

  validate_agent_artifact "$output_file" "$stderr_file" claude || artifact_rc=$?
  if (( artifact_rc != 0 )); then
    log " ERROR: solo cell $cell_dir failed validation (rc=$artifact_rc); final.md not written."
    return 1
  fi
  if file_contains_auth_failure "$output_file" && (( $(wc -w < "$output_file" | tr -d '[:space:]') < 50 )); then
    log " ERROR: solo cell $cell_dir returned an auth banner, not a plan; final.md not written."
    return 1
  fi

  mv -f "$output_file" "$cell_dir/final.md" \
    || die "bench_run_solo_cell: could not install final.md in $cell_dir"
  return 0
}

# --- Bouncer run discovery ---------------------------------------------------

# bench_find_bouncer_final RUN_PARENT → prints the bouncer's final document.
# CO_EVOLVE_RUNS_DIR is pointed at RUN_PARENT per cell, so exactly one run dir
# must exist there — zero or many means the cell is not the deterministic
# one-run-per-cell layout the resume logic assumes, and that is fatal.
#
# The emitted final is `$RUN_DIR/<RUN_LABEL>.md` (co-evolve-bouncer.sh:1306),
# which for a STUCK run additionally carries the CO-EVOLVE:STUCK banner — that
# is the document a human would read, so it is preferred. state.json's
# `.final_file` is initialized to the literal "working.md" (:525) and is used as
# the documented fallback, with a bare working.md as the last resort.
bench_find_bouncer_final() {
  local run_parent="${1:?bench_find_bouncer_final requires a run parent dir}"
  local -a run_dirs=()
  local run_dir base label candidate state_final

  [[ -d "$run_parent" ]] || die "bouncer run parent not found: $run_parent"

  while IFS= read -r run_dir; do
    [[ -n "$run_dir" ]] && run_dirs+=("$run_dir")
  done < <(find "$run_parent" -mindepth 1 -maxdepth 1 -type d | sort)

  if (( ${#run_dirs[@]} == 0 )); then
    die "no bouncer run dir under $run_parent (expected exactly 1)"
  fi
  if (( ${#run_dirs[@]} > 1 )); then
    die "found ${#run_dirs[@]} bouncer run dirs under $run_parent (expected exactly 1); the cell must be re-run from a clean directory"
  fi
  run_dir="${run_dirs[0]}"

  # Run dir name is co-evolve-<RUN_LABEL>-<TIMESTAMP>, TIMESTAMP being
  # generate_run_suffix() = YYYYmmdd-HHMMSS-<6 hex> (lib/co-evolution.sh:940).
  base=$(basename "$run_dir")
  if [[ "$base" =~ ^co-evolve-(.+)-[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$ ]]; then
    label="${BASH_REMATCH[1]}"
    candidate="$run_dir/$label.md"
    if [[ -s "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi

  if command -v jq >/dev/null 2>&1 && [[ -f "$run_dir/state.json" ]]; then
    state_final=$(jq -r '.final_file // ""' "$run_dir/state.json" 2>/dev/null) || state_final=""
    if [[ -n "$state_final" && "$state_final" != "null" ]]; then
      case "$state_final" in
        /*) candidate="$state_final" ;;
        *)  candidate="$run_dir/$state_final" ;;
      esac
      if [[ -s "$candidate" ]]; then
        printf '%s' "$candidate"
        return 0
      fi
    fi
  fi

  if [[ -s "$run_dir/working.md" ]]; then
    printf '%s' "$run_dir/working.md"
    return 0
  fi

  die "no final document in $run_dir (looked for <label>.md, state.json .final_file, working.md)"
}

# --- Self-test ---------------------------------------------------------------
# `bash benchmark-lib.sh --self-test` — tmp files only, no LLM calls, no network.

_bench_selftest() {
  local failures=0
  local work
  work=$(mktemp -d -t bench-lib-selftest-XXXXXX) || { echo "FAIL: mktemp"; return 1; }
  trap 'rm -rf -- "$work"' RETURN

  _check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      return 0
    fi
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  }

  # 1. cell paths
  _check "bench_cell_dir" "/b/t1/A" "$(bench_cell_dir /b t1 A)"

  # 2. meta write/read + absent
  mkdir -p "$work/cell"
  _check "bench_meta_status absent" "absent" "$(bench_meta_status "$work/cell")"
  bench_meta_write "$work/cell" '{"schema":"bench-cell/1.0","status":"complete"}'
  _check "bench_meta_status complete" "complete" "$(bench_meta_status "$work/cell")"
  _check "meta.json is valid json" "complete" "$(jq -r '.status' "$work/cell/meta.json")"

  # 3. frontmatter parse
  cat > "$work/t1.md" <<'TASK'
---
id: t1
domain: logistics
difficulty: easy
source: synthetic
expected_plan_words: 600
---
Plan a two-day offsite for twenty people on a fixed budget.

Produce a plan of roughly 600 words.
TASK
  _check "bench_fm_get id" "t1" "$(bench_fm_get "$work/t1.md" id)"
  _check "bench_fm_get expected_plan_words" "600" "$(bench_fm_get "$work/t1.md" expected_plan_words)"
  _check "bench_fm_get missing key" "" "$(bench_fm_get "$work/t1.md" nope)"

  # 4. GLM ledger: budget arithmetic + date reset
  local batch="$work/batch"
  mkdir -p "$batch"
  if bench_glm_ledger_check "$batch" 1 40; then :; else
    printf 'FAIL: ledger check on empty ledger should fit\n'; failures=$((failures + 1))
  fi
  bench_glm_ledger_add "$batch" 39
  _check "ledger calls after add" "39" "$(jq -r '.calls' "$batch/glm-ledger.json")"
  if bench_glm_ledger_check "$batch" 1 40; then :; else
    printf 'FAIL: 39+1 should fit under budget 40\n'; failures=$((failures + 1))
  fi
  if bench_glm_ledger_check "$batch" 2 40; then
    printf 'FAIL: 39+2 should NOT fit under budget 40\n'; failures=$((failures + 1))
  fi
  # Backdate the ledger: a new UTC day must reset the counter to 0.
  jq -n '{date:"2000-01-01", calls: 40}' > "$batch/glm-ledger.json"
  if bench_glm_ledger_check "$batch" 40 40; then :; else
    printf 'FAIL: stale-date ledger should reset calls to 0\n'; failures=$((failures + 1))
  fi
  _check "ledger reset date" "$(date -u +%Y-%m-%d)" "$(jq -r '.date' "$batch/glm-ledger.json")"
  _check "ledger reset calls" "0" "$(jq -r '.calls' "$batch/glm-ledger.json")"

  # 5. path guard
  if ( bench_path_guard "$(printf 'x%.0s' $(seq 1 100))" ) >/dev/null 2>&1; then :; else
    printf 'FAIL: 100-char path should pass the guard\n'; failures=$((failures + 1))
  fi
  if ( bench_path_guard "$(printf 'x%.0s' $(seq 1 250))" ) >/dev/null 2>&1; then
    printf 'FAIL: 250-char path should trip the guard\n'; failures=$((failures + 1))
  fi

  # 6. corpus linter
  local corpus="$work/corpus" templates="$work/templates" banned="$work/banned.txt"
  mkdir -p "$corpus" "$templates"
  printf 'You are a critic. Produce a numbered critique.\n' > "$templates/panel-critic.md"
  printf '# comment line\nbounce pass\nCONTESTED\n' > "$banned"
  cp "$work/t1.md" "$corpus/t1.md"
  if bench_lint_corpus "$corpus" "$templates" "$banned" >/dev/null 2>&1; then :; else
    printf 'FAIL: clean corpus should lint clean\n'; failures=$((failures + 1))
  fi

  # 6a. oversized body (>150 words)
  {
    printf -- '---\nid: t2\ndomain: ops\ndifficulty: hard\nsource: synthetic\nexpected_plan_words: 600\n---\n'
    for _ in $(seq 1 160); do printf 'word '; done
    printf '\n\nProduce a plan of roughly 600 words.\n'
  } > "$corpus/t2.md"
  local lint_out
  lint_out=$(bench_lint_corpus "$corpus" "$templates" "$banned" 2>&1) && {
    printf 'FAIL: oversized body should fail the linter\n'; failures=$((failures + 1)); }
  printf '%s' "$lint_out" | grep -q 'max 150' || {
    printf 'FAIL: oversized-body violation not reported\n  got: %s\n' "$lint_out"; failures=$((failures + 1)); }
  rm -f "$corpus/t2.md"

  # 6b. banned-token collision
  cat > "$corpus/t3.md" <<'TASK'
---
id: t3
domain: email
difficulty: medium
source: synthetic
expected_plan_words: 600
---
Reduce our newsletter bounce pass rate over the next quarter.

Produce a plan of roughly 600 words.
TASK
  lint_out=$(bench_lint_corpus "$corpus" "$templates" "$banned" 2>&1) && {
    printf 'FAIL: banned-token collision should fail the linter\n'; failures=$((failures + 1)); }
  printf '%s' "$lint_out" | grep -q "banned token 'bounce pass'" || {
    printf 'FAIL: banned-token violation not reported\n  got: %s\n' "$lint_out"; failures=$((failures + 1)); }
  rm -f "$corpus/t3.md"

  # 6c. out-of-range expected_plan_words + missing word-target tail
  cat > "$corpus/t4.md" <<'TASK'
---
id: wrong-id
domain: ops
difficulty: medium
source: synthetic
expected_plan_words: 900
---
Write a migration plan.
TASK
  lint_out=$(bench_lint_corpus "$corpus" "$templates" "$banned" 2>&1) && {
    printf 'FAIL: bad frontmatter should fail the linter\n'; failures=$((failures + 1)); }
  printf '%s' "$lint_out" | grep -q 'outside 500-700' || {
    printf 'FAIL: expected_plan_words range violation not reported\n'; failures=$((failures + 1)); }
  printf '%s' "$lint_out" | grep -q 'does not match the filename' || {
    printf 'FAIL: id/filename mismatch not reported\n'; failures=$((failures + 1)); }
  rm -f "$corpus/t4.md"

  # 7. compose-prompt parity shape (byte-exact against the bouncer's template)
  local expected_prompt actual_prompt
  expected_prompt=$'Respond to the following thoroughly and substantively.\n\nPlan the migration.'
  actual_prompt=$(bench_compose_prompt $'Plan the migration.\n\n')
  _check "bench_compose_prompt" "$expected_prompt" "$actual_prompt"
  actual_prompt=$(bench_compose_prompt 'Plan the [CONTESTED] migration.')
  _check "bench_compose_prompt strips markers" \
    $'Respond to the following thoroughly and substantively.\n\nPlan the  migration.' "$actual_prompt"

  # 8. bouncer final discovery
  local parent="$work/runp"
  mkdir -p "$parent/co-evolve-t1-a-20260829-101530-1a2b3c"
  local rd="$parent/co-evolve-t1-a-20260829-101530-1a2b3c"
  printf 'working\n' > "$rd/working.md"
  jq -n '{final_file:"working.md"}' > "$rd/state.json"
  _check "find_bouncer_final falls back to working.md" "$rd/working.md" "$(bench_find_bouncer_final "$parent")"
  printf 'labelled final\n' > "$rd/t1-a.md"
  _check "find_bouncer_final prefers <label>.md" "$rd/t1-a.md" "$(bench_find_bouncer_final "$parent")"
  mkdir -p "$parent/co-evolve-t1-a-20260829-101531-1a2b3d"
  if ( bench_find_bouncer_final "$parent" ) >/dev/null 2>&1; then
    printf 'FAIL: two run dirs should be fatal\n'; failures=$((failures + 1))
  fi

  if (( failures == 0 )); then
    echo "benchmark-lib.sh self-test: PASS"
    return 0
  fi
  echo "benchmark-lib.sh self-test: $failures FAILURE(S)"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test) _bench_selftest ;;
    *) echo "usage: bash benchmark-lib.sh --self-test   (this file is normally sourced)" >&2; exit 2 ;;
  esac
fi
