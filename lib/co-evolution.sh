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
  local writable="${4:-false}"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local -a tool_flags

  # Upstream MUST (UPSTREAM-MESSAGE.md item 4): Claude in -p mode must either
  # have tools disabled (text phases) or have an explicit allow-list + bypass
  # permission mode + dir-scope flag (write phases). The empty-string variant of
  # the older tools flag does NOT work (commander.js variadic eats the next arg)
  # and the plan-mode value for permission-mode silently emits empty stdout.
  # Do NOT pass any schema flag to Claude (PRTP-03; hangs on Windows in -p mode
  # as of 2026-04-17).
  if [[ "$writable" == "true" ]]; then
    tool_flags=(
      --permission-mode bypassPermissions
      --allowedTools "Edit,Write,Read,Glob,Grep,Bash(git status),Bash(git diff)"
      --add-dir "$workdir"
    )
  else
    tool_flags=(--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch")
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    # Under WSL, reuse the Windows Claude session because WSL and Windows keep separate auth state.
    cmd=(cmd.exe /c claude -p --output-format text --model claude-opus-4-6 "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model claude-opus-4-6 "${tool_flags[@]}")
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

file_contains_error_payload() {
  local file_path="$1"

  [[ -s "$file_path" ]] || return 1

  grep -qiE '^(Error|ERROR|fatal|Fatal):|^Internal Server Error$|^Bad Gateway$|^Service Unavailable$|rate limit exceeded|context deadline exceeded|timed out|connection (reset|refused)|ECONNREFUSED|ENOTFOUND|Traceback \(most recent call last\):' "$file_path"
}

validate_plan_artifact() {
  local file_path="$1"
  local minimum_words="${2:-60}"
  local minimum_nonempty_lines="${3:-5}"
  local minimum_structural_lines="${4:-2}"
  local word_count
  local nonempty_lines
  local structural_lines

  [[ -s "$file_path" ]] || {
    printf '%s' "plan output was empty"
    return 1
  }

  word_count=$(wc -w < "$file_path" | tr -d '\r\n ')
  nonempty_lines=$(grep -cve '^[[:space:]]*$' "$file_path" || true)
  structural_lines=$(grep -cE '^[[:space:]]*(#|- |\* |[0-9]+\.)|^[[:space:]]*[A-Z][A-Za-z0-9 /()-]{2,40}:[[:space:]]*$' "$file_path" || true)

  if (( word_count < minimum_words )); then
    printf 'plan output was too short (%s words)' "$word_count"
    return 1
  fi

  if (( nonempty_lines < minimum_nonempty_lines )); then
    printf 'plan output was too short (%s non-empty lines)' "$nonempty_lines"
    return 1
  fi

  if (( structural_lines < minimum_structural_lines )); then
    printf '%s' "plan output did not look like a structured plan"
    return 1
  fi

  return 0
}

normalize_json_artifact() {
  local input_file="$1"
  local output_file="$2"
  local -a lines=()
  local first_nonempty=-1
  local last_nonempty=-1
  local current_line=""
  local index=0
  local opening_fence_pattern='^```[[:space:]]*([A-Za-z0-9_-]+)?[[:space:]]*$'
  local closing_fence_pattern='^```[[:space:]]*$'

  [[ -s "$input_file" ]] || {
    printf '%s' "verifier output was empty"
    return 1
  }

  mapfile -t lines < "$input_file"

  for index in "${!lines[@]}"; do
    current_line="${lines[$index]%$'\r'}"
    if [[ "$current_line" =~ [^[:space:]] ]]; then
      first_nonempty=$index
      break
    fi
  done

  if (( first_nonempty < 0 )); then
    printf '%s' "verifier output was empty"
    return 1
  fi

  for (( index=${#lines[@]}-1; index>=0; index-- )); do
    current_line="${lines[$index]%$'\r'}"
    if [[ "$current_line" =~ [^[:space:]] ]]; then
      last_nonempty=$index
      break
    fi
  done

  if [[ "${lines[$first_nonempty]%$'\r'}" =~ $opening_fence_pattern ]]; then
    if [[ ! "${lines[$last_nonempty]%$'\r'}" =~ $closing_fence_pattern ]]; then
      printf '%s' "verifier output mixed a fenced JSON block with extra prose"
      return 1
    fi

    : > "$output_file"
    for (( index=first_nonempty+1; index<last_nonempty; index++ )); do
      printf '%s\n' "${lines[$index]%$'\r'}" >> "$output_file"
    done
    return 0
  fi

  for current_line in "${lines[@]}"; do
    current_line="${current_line%$'\r'}"
    if [[ "$current_line" =~ $closing_fence_pattern ]]; then
      printf '%s' "verifier output mixed code fences with extra prose"
      return 1
    fi
  done

  cp "$input_file" "$output_file"
  return 0
}

validate_review_verdict() {
  local json_file="$1"
  local verdict=""
  local confidence=""
  local summary=""
  local high_severity_count=0
  local compact_json=""

  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "object"' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "verdict was not a JSON object"
      return 1
    }

    jq -e 'has("verdict") and has("confidence") and has("summary") and has("issues")' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "verdict was missing one or more required fields"
      return 1
    }

    verdict=$(jq -r '.verdict' "$json_file" 2>/dev/null)
    if [[ "$verdict" != "APPROVED" && "$verdict" != "REVISE" ]]; then
      printf 'unsupported verdict value: %s' "$verdict"
      return 1
    fi

    jq -e '(.confidence | type) == "number"' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "confidence was not numeric"
      return 1
    }

    confidence=$(jq -r '.confidence' "$json_file" 2>/dev/null)
    if ! [[ "$confidence" =~ ^[0-9]+$ ]] || (( confidence < 0 || confidence > 100 )); then
      printf 'confidence was out of range: %s' "$confidence"
      return 1
    fi

    jq -e '(.summary | type) == "string"' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "summary was not a string"
      return 1
    }
    summary=$(jq -r '.summary' "$json_file" 2>/dev/null)

    jq -e '.issues | type == "array"' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "issues was not an array"
      return 1
    }

    jq -e '.issues | all(.[]?; type == "object" and (.severity? | type == "string") and (.description? | type == "string"))' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "issues entries were missing severity or description"
      return 1
    }

    jq -e '.issues | all(.[]?; .severity == "CRITICAL" or .severity == "HIGH" or .severity == "MEDIUM" or .severity == "LOW")' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "issues contained an unsupported severity"
      return 1
    }

    jq -e 'if has("scope_creep_detected") then (.scope_creep_detected | type) == "boolean" else true end' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "scope_creep_detected was not a boolean"
      return 1
    }

    jq -e 'if has("iteration_notes") then (.iteration_notes | type) == "string" else true end' "$json_file" >/dev/null 2>&1 || {
      printf '%s' "iteration_notes was not a string"
      return 1
    }

    high_severity_count=$(jq '[.issues[]? | select(.severity == "CRITICAL" or .severity == "HIGH")] | length' "$json_file" 2>/dev/null)
  else
    compact_json=$(tr -d '\r\n\t ' < "$json_file")

    if [[ -z "$compact_json" || "${compact_json:0:1}" != "{" || "${compact_json: -1}" != "}" ]]; then
      printf '%s' "verdict was not a JSON object"
      return 1
    fi

    verdict=$(grep -o '"verdict"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" | head -1 | sed 's/.*"verdict"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    confidence=$(grep -o '"confidence"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "$json_file" | head -1 | sed 's/.*"confidence"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/')
    summary=$(grep -o '"summary"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" | head -1 | sed 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -z "$verdict" || -z "$confidence" ]] \
      || ! grep -q '"summary"[[:space:]]*:' "$json_file" \
      || ! grep -q '"issues"[[:space:]]*:[[:space:]]*\[' "$json_file"; then
      printf '%s' "verdict was missing one or more required fields"
      return 1
    fi

    if [[ "$verdict" != "APPROVED" && "$verdict" != "REVISE" ]]; then
      printf 'unsupported verdict value: %s' "$verdict"
      return 1
    fi

    if ! [[ "$confidence" =~ ^[0-9]+$ ]] || (( confidence < 0 || confidence > 100 )); then
      printf 'confidence was out of range: %s' "$confidence"
      return 1
    fi

    high_severity_count=$(grep -o '"severity"[[:space:]]*:[[:space:]]*"\(CRITICAL\|HIGH\)"' "$json_file" | wc -l | tr -d '\r\n ')
  fi

  if [[ "$verdict" == "APPROVED" && "$confidence" -lt 75 ]]; then
    printf 'APPROVED verdict had confidence below 75: %s' "$confidence"
    return 1
  fi

  if [[ "$verdict" == "APPROVED" && "$high_severity_count" -gt 0 ]]; then
    printf 'APPROVED verdict included %s CRITICAL/HIGH issue(s)' "$high_severity_count"
    return 1
  fi

  if [[ "$verdict" == "REVISE" && "$high_severity_count" -eq 0 ]]; then
    printf '%s' "REVISE verdict did not include any CRITICAL or HIGH issues"
    return 1
  fi

  printf 'VERDICT=%q\n' "$verdict"
  printf 'CONFIDENCE=%q\n' "$confidence"
  printf 'SUMMARY=%q\n' "$summary"
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
