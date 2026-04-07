#!/usr/bin/env bash

log() {
  local message="${1:-}"

  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "$message" | tee -a "$LOG_FILE"
  else
    echo "$message"
  fi
}

die() {
  local message="${1:-Fatal error}"
  log "ERROR: $message"
  exit 1
}

invoke_claude() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local -a cmd

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    # Under WSL, reuse the Windows Claude session because WSL and Windows keep separate auth state.
    cmd=(cmd.exe /c claude -p --output-format text --model claude-opus-4-6)
  else
    cmd=(claude -p --output-format text --model claude-opus-4-6 --tools "")
  fi

  "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_file" || true
}

invoke_codex() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local windows_workdir
  local windows_output

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    windows_workdir=$(wslpath -w "$workdir")
    windows_output=$(wslpath -w "$output_file")
    cmd=(cmd.exe /c codex exec --full-auto --skip-git-repo-check -C "$windows_workdir")
  else
    cmd=(codex exec --full-auto --skip-git-repo-check -C "$workdir")
  fi

  if [[ -n "${CODEX_MODEL:-}" ]]; then
    cmd+=(-c "model=${CODEX_MODEL}")
  fi

  if [[ -n "${windows_output:-}" ]]; then
    cmd+=(-o "$windows_output")
  else
    cmd+=(-o "$output_file")
  fi

  "${cmd[@]}" < "$prompt_file" > /dev/null 2>"$stderr_file" || true
}

file_contains_auth_failure() {
  local file_path="$1"

  [[ -s "$file_path" ]] || return 1

  grep -qiE 'Failed to authenticate|authentication_error|Not authenticated|Unauthorized|login required|Please run .* login' "$file_path"
}

count_markers() {
  local file_path="$1"
  local marker="$2"

  awk -v marker="$marker" '
    BEGIN { count = 0; in_fence = 0 }
    /^```/ { in_fence = !in_fence; next }
    !in_fence {
      gsub(/`[^`]*`/, "")
      if (index($0, marker) > 0) {
        count++
      }
    }
    END { print count }
  ' "$file_path" | tr -d '\r\n '
}

strip_human_summary() {
  local input_file="$1"
  local output_file="$2"

  awk '/^## HUMAN SUMMARY/{found=1} !found{print}' "$input_file" > "$output_file"
}

size_sanity_check() {
  local input_file="$1"
  local output_file="$2"
  local threshold="${3:-30}"
  local input_words
  local output_words

  input_words=$(wc -w < "$input_file" | tr -d '\r\n ')
  output_words=$(wc -w < "$output_file" | tr -d '\r\n ')

  if (( input_words <= 50 )); then
    return 0
  fi

  if (( output_words * 100 / input_words < threshold )); then
    return 1
  fi

  return 0
}

validate_output() {
  local input_file="$1"
  local output_file="$2"
  local agent_name="$3"
  local retry_function="$4"
  local prompt_file="$5"
  local retry_stderr_file="$6"
  local threshold="${7:-30}"
  local input_words
  local output_words

  if [[ ! -s "$output_file" ]]; then
    log " ERROR: ${agent_name} returned empty output. Retrying once..."
    "$retry_function" "$prompt_file" "$output_file" "$retry_stderr_file"

    if [[ ! -s "$output_file" ]]; then
      log " ERROR: ${agent_name} returned empty output on retry. Aborting."
      return 1
    fi
  fi

  input_words=$(wc -w < "$input_file" | tr -d '\r\n ')
  output_words=$(wc -w < "$output_file" | tr -d '\r\n ')

  if ! size_sanity_check "$input_file" "$output_file" "$threshold"; then
    log " WARNING: ${agent_name} returned ${output_words} words (input was ${input_words}). Likely a summary, not the full document. Retrying..."
    "$retry_function" "$prompt_file" "$output_file" "$retry_stderr_file"

    if [[ ! -s "$output_file" ]]; then
      log " ERROR: ${agent_name} returned empty output on retry after a short-output warning. Aborting."
      return 1
    fi

    output_words=$(wc -w < "$output_file" | tr -d '\r\n ')

    if ! size_sanity_check "$input_file" "$output_file" "$threshold"; then
      log " WARNING: Retry also returned ${output_words} words. Using it anyway - check the output."
    fi
  fi

  return 0
}

fill_template() {
  local template_path="$1"
  shift
  local rendered
  local pair
  local key
  local value

  rendered=$(cat "$template_path")

  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    rendered="${rendered//\{$key\}/$value}"
  done

  printf '%s' "$rendered"
}

strip_conditional() {
  local block_name="$1"
  local start_tag="{IF_${block_name}}"
  local end_tag="{END_IF_${block_name}}"

  awk -v start_tag="$start_tag" -v end_tag="$end_tag" '
    index($0, start_tag) { skip = 1; next }
    index($0, end_tag) { skip = 0; next }
    !skip { print }
  '
}

fill_conditional() {
  local block_name="$1"
  shift
  local start_tag="{IF_${block_name}}"
  local end_tag="{END_IF_${block_name}}"
  local rendered
  local pair
  local key
  local value

  rendered=$(
    awk -v start_tag="$start_tag" -v end_tag="$end_tag" '
    index($0, start_tag) || index($0, end_tag) { next }
    { print }
  '
  )

  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    rendered="${rendered//\{$key\}/$value}"
  done

  printf '%s' "$rendered"
}

parse_verdict() {
  local json_file="$1"
  local verdict=""
  local confidence=""
  local summary=""

  if command -v jq >/dev/null 2>&1; then
    verdict=$(jq -r '.verdict // ""' "$json_file" 2>/dev/null)
    confidence=$(jq -r '.confidence // ""' "$json_file" 2>/dev/null)
    summary=$(jq -r '.summary // ""' "$json_file" 2>/dev/null)
  else
    verdict=$(grep -o '"verdict"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" | head -1 | sed 's/.*"verdict"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    confidence=$(grep -o '"confidence"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "$json_file" | head -1 | sed 's/.*"confidence"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/')
    summary=$(grep -o '"summary"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" | head -1 | sed 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  fi

  printf 'VERDICT=%q\n' "$verdict"
  printf 'CONFIDENCE=%q\n' "$confidence"
  printf 'SUMMARY=%q\n' "$summary"
}
