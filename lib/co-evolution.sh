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

# RNPT-05: Default per-phase timeout in seconds. Override via --timeout flag
# or by exporting PHASE_TIMEOUT before running. Upstream hit a 1h 39min hang;
# 1800s (30min) is generous enough for legitimate long phases, tight enough
# to surface hangs within a coffee-break window.
: "${PHASE_TIMEOUT:=1800}"

# RTUX-01: LIVE_MODE default. Set by --live CLI flag or LIVE_MODE env var.
# Default "false" preserves byte-parity with Phase 2 behavior (invariant).
: "${LIVE_MODE:=false}"
# Guard so we only log the non-Windows fallback warning once per run.
LIVE_MODE_WARNING_LOGGED=false

# RTUX-02: Branch + worktree env-var defaults. Empty = unset (no setup).
# CLI flags --branch / --worktree override these; both non-empty = die.
: "${DEV_REVIEW_BRANCH:=}"
: "${DEV_REVIEW_WORKTREE:=}"

# RNPT-02: Authoritative list of phases that require write access to the workdir.
# Phase code MUST NOT pass a hard-coded "true"/"false" to invoke_agent; it must
# call `phase_is_writable "<phase-name>"` instead. To add a new writable phase
# (e.g. a future `fix` phase), append its name to this array.
#
# RTUX-03: execute-2..execute-N are the REVISE auto-loop retry passes. Rather
# than enumerate every possible pass number here, `phase_is_writable` carries
# a second regex gate that accepts ^execute-[0-9]+$ specifically. The anchor
# is tight so names like `execute-;rm-rf` or `verify-99` cannot slip through.
WRITABLE_PHASES=(execute execute-retry fix)

# phase_is_writable <phase-name> → prints "true" or "false" on stdout.
# Fail-safe: unknown phase names return "false" (downgrade to text-phase posture)
# so an attacker-controlled phase name cannot escalate to write permissions.
phase_is_writable() {
  local phase_name="${1:?phase_is_writable requires a phase name}"
  local candidate
  for candidate in "${WRITABLE_PHASES[@]}"; do
    if [[ "$phase_name" == "$candidate" ]]; then
      printf '%s' "true"
      return 0
    fi
  done
  # RTUX-03: REVISE-loop numbered retry passes (execute-2, execute-3, ...).
  # Anchored regex prevents command-injection-style phase names from matching.
  if [[ "$phase_name" =~ ^execute-[0-9]+$ ]]; then
    printf '%s' "true"
    return 0
  fi
  printf '%s' "false"
  return 0
}

# RTUX-01: Detect whether we are running on a Windows host (or a shell that can
# reach Windows binaries). Returns "true"/"false" on stdout. First match wins.
# No side effects — safe to call repeatedly.
is_windows_host() {
  # 1. MSYS/Cygwin shell indicator (Git Bash, MSYS2, Cygwin)
  if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
    printf '%s' "true"
    return 0
  fi
  # 2. Windows Terminal binary present (covers most modern Windows setups)
  if command -v wt.exe >/dev/null 2>&1; then
    printf '%s' "true"
    return 0
  fi
  # 3. cmd.exe present (covers WSL and bare Windows shells without wt.exe)
  if command -v cmd.exe >/dev/null 2>&1; then
    printf '%s' "true"
    return 0
  fi
  printf '%s' "false"
  return 0
}

# RTUX-01: Launch a visible tail window for the given phase's stderr file.
# No-op when LIVE_MODE is not "true". Always returns 0 — failures log a
# warning but never block the main phase (must-not-break invariant).
maybe_launch_live_window() {
  local phase_name="${1:?maybe_launch_live_window requires a phase name}"
  local stderr_file="${2:?maybe_launch_live_window requires a stderr file path}"

  [[ "${LIVE_MODE:-false}" == "true" ]] || return 0

  if [[ "$(is_windows_host)" != "true" ]]; then
    if [[ "${LIVE_MODE_WARNING_LOGGED}" != "true" ]]; then
      log "WARNING: --live is Windows-only (OSTYPE=${OSTYPE:-unknown}); falling back to inline execution."
      LIVE_MODE_WARNING_LOGGED=true
    fi
    return 0
  fi

  # Pre-touch the stderr file so tail -f has something to follow.
  # The phase's own 2>"$stderr_file" redirection will truncate on first write.
  : > "$stderr_file" 2>/dev/null || true

  local title="phase:${phase_name}"
  local tail_cmd
  printf -v tail_cmd 'tail -f %q' "$stderr_file"

  # Preferred: Windows Terminal new-tab. Fall back to cmd.exe /c start.
  # Both are backgrounded + disowned so we do not wait on them.
  if command -v wt.exe >/dev/null 2>&1; then
    ( wt.exe new-tab --title "$title" bash -c "$tail_cmd" >/dev/null 2>&1 & disown ) 2>/dev/null \
      && return 0
    log "WARNING: wt.exe launch failed for phase '${phase_name}'; trying cmd.exe fallback."
  fi

  if command -v cmd.exe >/dev/null 2>&1; then
    ( cmd.exe /c start "$title" bash -c "$tail_cmd" >/dev/null 2>&1 & disown ) 2>/dev/null \
      && return 0
    log "WARNING: cmd.exe live-window launch failed for phase '${phase_name}'; continuing inline."
  else
    log "WARNING: no live-window launcher available for phase '${phase_name}'; continuing inline."
  fi

  return 0
}

# RTUX-02: Portable check for "is this dir inside a git repo?" Used as the
# gate for --branch / --worktree so non-git workdirs no-op cleanly.
is_git_repo() {
  local dir="${1:?is_git_repo requires a directory}"
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
  return 0
}

# RTUX-02: Compose an auto branch name `dev-review/auto-<TIMESTAMP>-<slug>`.
# Reuses $TIMESTAMP from the main runner when present; falls back to a fresh
# stamp so this helper is safely callable from tests that source lib alone.
derive_auto_branch_name() {
  local task="${1:-}"
  local ts="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  local slug=""
  if [[ -n "$task" ]]; then
    # First 5 words → lowercase → non-alnum becomes '-' → collapse → trim
    slug=$(printf '%s' "$task" \
      | awk '{for(i=1;i<=NF && i<=5;i++) printf "%s%s",$i,(i<NF && i<5?" ":"")}' \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//')
    slug="${slug:0:30}"
    slug="${slug%-}"
  fi
  if [[ -n "$slug" ]]; then
    printf 'dev-review/auto-%s-%s' "$ts" "$slug"
  else
    printf 'dev-review/auto-%s' "$ts"
  fi
}

# RTUX-02: Compose a sibling-dir worktree path relative to WORKDIR.
# e.g. /c/repos/myrepo → /c/repos/myrepo-dr-20260417-210830
derive_auto_worktree_path() {
  local workdir="${1:?derive_auto_worktree_path requires a workdir}"
  local ts="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
  local parent base
  parent="$(cd "$workdir" && cd .. && pwd)"
  base="$(basename "$workdir")"
  printf '%s/%s-dr-%s' "$parent" "$base" "$ts"
}

# RTUX-02: Create a dedicated branch off HEAD and switch into it.
# No-op + WARNING when branch_spec is empty OR workdir is not a git repo.
# On git failure, log WARNING and return empty — main run continues inline.
# On success, log the branch name and print it on stdout for the caller to
# capture (caller writes it to state.json via write_state_field).
maybe_setup_branch() {
  local workdir="${1:?maybe_setup_branch requires a workdir}"
  local branch_spec="${2:-}"
  local task_desc="${3:-}"

  if [[ -z "$branch_spec" ]]; then
    # Route log to stderr so the caller's stdout-capture stays clean (no-op = empty stdout).
    log "WARNING: --branch ignored: value is empty" >&2
    return 0
  fi
  if [[ "$(is_git_repo "$workdir")" != "true" ]]; then
    log "WARNING: --branch ignored: ${workdir} is not a git repo" >&2
    return 0
  fi

  local name
  if [[ "$branch_spec" == "auto" ]]; then
    name="$(derive_auto_branch_name "$task_desc")"
  else
    name="$branch_spec"
  fi

  # FIX-WR-05: reject branch names that look like CLI flags. Git's own ref
  # validation would usually catch this, but failing fast with a clear message
  # beats git's "invalid ref" error for the reader.
  if [[ "$name" == -* ]]; then
    log "WARNING: branch setup failed: branch name '${name}' cannot start with '-'" >&2
    return 0
  fi

  local err_output
  if err_output=$(git -C "$workdir" checkout -b "$name" 2>&1); then
    # log to stderr so stdout carries only the branch name for the caller.
    log "Branch created: ${name}" >&2
    printf '%s' "$name"
    return 0
  else
    log "WARNING: branch setup failed for '${name}': ${err_output}" >&2
    return 0
  fi
}

# RTUX-02: Create a dedicated worktree and return its absolute path.
# No-op + WARNING on empty spec or non-git-repo workdir. On git failure,
# log WARNING and return empty — main run continues inline with original WORKDIR.
maybe_setup_worktree() {
  local workdir="${1:?maybe_setup_worktree requires a workdir}"
  local worktree_spec="${2:-}"
  local task_desc="${3:-}"

  if [[ -z "$worktree_spec" ]]; then
    # Route log to stderr so caller's stdout-capture stays clean (no-op = empty stdout).
    log "WARNING: --worktree ignored: value is empty" >&2
    return 0
  fi
  if [[ "$(is_git_repo "$workdir")" != "true" ]]; then
    log "WARNING: --worktree ignored: ${workdir} is not a git repo" >&2
    return 0
  fi

  local path
  if [[ "$worktree_spec" == "auto" ]]; then
    path="$(derive_auto_worktree_path "$workdir")"
  else
    path="$worktree_spec"
  fi

  # FIX-WR-05: `--` argv terminator prevents `$path` from being misinterpreted
  # as a flag if the user supplies something like `--quiet` as the path value.
  local err_output
  if err_output=$(git -C "$workdir" worktree add -- "$path" 2>&1); then
    # Resolve to absolute once the dir exists.
    local abs_path
    abs_path="$(cd "$path" && pwd)"
    # log to stderr so stdout carries only the worktree path for the caller.
    log "Worktree created: ${abs_path}" >&2
    printf '%s' "$abs_path"
    return 0
  else
    log "WARNING: worktree setup failed for '${path}': ${err_output}" >&2
    return 0
  fi
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

# RNPT-03: Hash every file in $workdir (excluding .git/ and runs/) and write
# a flat JSON object of {path: sha256} to $output_path. Used for pre/post-execute
# delta tracking; feeds compute_execute_delta.
snapshot_workdir_hashes() {
  local workdir="${1:?snapshot_workdir_hashes requires a workdir}"
  local output_path="${2:?snapshot_workdir_hashes requires an output path}"
  local tmp_list
  tmp_list=$(mktemp)

  (
    cd "$workdir" && find . -type f \
      -not -path './.git/*' \
      -not -path './runs/*' \
      -not -path '*/.co-evolution/*' \
      -print0
  ) > "$tmp_list"

  if command -v jq >/dev/null 2>&1; then
    (
      cd "$workdir" && \
      xargs -0 -I{} sh -c 'printf "%s\t%s\n" "$(sha256sum "$1" | cut -d" " -f1)" "${1#./}"' _ {} < "$tmp_list" \
        | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {(.[1]): .[0]}) | add // {}'
    ) > "$output_path"
  else
    # Fallback: printf-based JSON. Pathological filenames (quotes/backslashes)
    # are out of scope — workdir is a code repo.
    printf '{\n' > "$output_path"
    local first=1
    local rel hash clean_path
    while IFS= read -r -d '' rel; do
      hash=$(cd "$workdir" && sha256sum "$rel" | cut -d' ' -f1)
      clean_path="${rel#./}"
      if (( first )); then first=0; else printf ',\n' >> "$output_path"; fi
      printf '  "%s": "%s"' "$clean_path" "$hash" >> "$output_path"
    done < "$tmp_list"
    printf '\n}\n' >> "$output_path"
  fi

  rm -f "$tmp_list"
}

# RNPT-03: Read two manifest JSON files and emit
# {modified: [...], added: [...], deleted: [...]} sorted arrays.
compute_execute_delta() {
  local baseline="${1:?baseline required}"
  local current="${2:?current required}"
  local output="${3:?output required}"

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --slurpfile b "$baseline" \
      --slurpfile c "$current" \
      '
      ($b[0] // {}) as $B |
      ($c[0] // {}) as $C |
      {
        modified: [ ($B | keys[]) | select(($C[.] // null) != null and $C[.] != $B[.]) ] | sort,
        added:    [ ($C | keys[]) | select(($B[.] // null) == null) ] | sort,
        deleted:  [ ($B | keys[]) | select(($C[.] // null) == null) ] | sort
      }' > "$output"
  else
    log "WARNING: jq unavailable — execute_delta fallback produces empty arrays"
    printf '{"modified":[],"added":[],"deleted":[]}\n' > "$output"
  fi
}

# RNPT-04: Write the initial state.json skeleton for a run.
# All phase arrays empty, all deltas empty, no verdict, started_at=now.
init_state_json() {
  local state_path="${1:?state path required}"
  local run_id="${2:?run_id required}"
  local task="${3:?task required}"
  local composer="${4:?composer required}"
  local executor="${5:?executor required}"
  local reviewer="${6:?reviewer required}"
  local started_at
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg run_id    "$run_id" \
      --arg task      "$task" \
      --arg composer  "$composer" \
      --arg executor  "$executor" \
      --arg reviewer  "$reviewer" \
      --arg started   "$started_at" \
      '{
        run_id: $run_id,
        task: $task,
        composer: $composer,
        executor: $executor,
        reviewer: $reviewer,
        phases: [],
        marker_counts: {contested: 0, clarify: 0},
        baseline_hashes: {},
        execute_delta: {modified: [], added: [], deleted: []},
        verify_verdict: null,
        started_at: $started,
        completed_at: null
      }' > "$state_path"
  else
    local escaped_task
    escaped_task=$(printf '%s' "$task" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\r\n')
    cat > "$state_path" <<EOF
{
  "run_id": "$run_id",
  "task": "$escaped_task",
  "composer": "$composer",
  "executor": "$executor",
  "reviewer": "$reviewer",
  "phases": [],
  "marker_counts": {"contested": 0, "clarify": 0},
  "baseline_hashes": {},
  "execute_delta": {"modified": [], "added": [], "deleted": []},
  "verify_verdict": null,
  "started_at": "$started_at",
  "completed_at": null
}
EOF
  fi
}

# RNPT-04: Append a phase entry to state.phases with timestamps + status + exit code.
write_state_phase() {
  local state_path="${1:?state path required}"
  local phase_name="${2:?phase name required}"
  local status="${3:?status required}"
  local exit_code="${4:?exit code required}"
  local started_at="${5:?started_at required}"
  local completed_at="${6:?completed_at required}"

  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp)
    # FIX-WR-02: clean up $tmp on any exit path (jq failure, script interrupt).
    # Without this, failed jq invocations leak mktemp files in $TMPDIR indefinitely.
    if jq --arg name "$phase_name" \
       --arg status "$status" \
       --argjson exit_code "$exit_code" \
       --arg started "$started_at" \
       --arg completed "$completed_at" \
       '.phases += [{
         name: $name,
         started_at: $started,
         completed_at: $completed,
         status: $status,
         exit_code: $exit_code
       }]' "$state_path" > "$tmp"; then
      mv "$tmp" "$state_path"
    else
      rm -f "$tmp"
      log "WARNING: jq failed in write_state_phase ($phase_name) — state.json unchanged"
    fi
  else
    log "WARNING: jq unavailable — write_state_phase skipping ($phase_name)"
  fi
}

# RNPT-04: Generic jq-path field setter. Supports string|number|bool|null|rawfile.
# Usage: write_state_field state.json '.verify_verdict' string APPROVED
#        write_state_field state.json '.execute_delta' rawfile path/to/delta.json
write_state_field() {
  local state_path="${1:?state path required}"
  local jq_path="${2:?jq path required}"
  local value_type="${3:?value type required (string|number|bool|null|rawfile)}"
  local value="${4-}"

  command -v jq >/dev/null 2>&1 || {
    log "WARNING: jq unavailable — write_state_field skipping ($jq_path)"
    return 0
  }

  local tmp
  tmp=$(mktemp)
  local jq_exit
  case "$value_type" in
    string)
      jq --arg v "$value" "$jq_path = \$v"              "$state_path" > "$tmp"; jq_exit=$? ;;
    number)
      jq --argjson v "$value" "$jq_path = \$v"          "$state_path" > "$tmp"; jq_exit=$? ;;
    bool)
      jq --argjson v "$value" "$jq_path = \$v"          "$state_path" > "$tmp"; jq_exit=$? ;;
    null)
      jq "$jq_path = null"                              "$state_path" > "$tmp"; jq_exit=$? ;;
    rawfile)
      jq --slurpfile v "$value" "$jq_path = \$v[0]"     "$state_path" > "$tmp"; jq_exit=$? ;;
    *)
      rm -f "$tmp"
      die "Unsupported value_type: $value_type"
      ;;
  esac
  # FIX-WR-02: clean up $tmp on jq failure so we don't leak files to $TMPDIR.
  if [[ $jq_exit -eq 0 ]]; then
    mv "$tmp" "$state_path"
  else
    rm -f "$tmp"
    log "WARNING: jq failed in write_state_field ($jq_path, $value_type) — state.json unchanged"
    return $jq_exit
  fi
}

# RNPT-05: invoke_agent_with_timeout — same signature as invoke_agent but wrapped
# in `timeout(1)`. Sets the global $LAST_INVOKE_EXIT_CODE for the caller to
# inspect (124 = timeout fired, 0 = ok, other = underlying agent exit code).
#
# Design notes:
#   - `--foreground` leaves signal handling with the invoking shell so kills
#     reach the claude/codex child (normal timeout puts child in its own pgroup
#     where SIGTERM to a network-blocked read is easy to miss).
#   - Re-sourcing lib/co-evolution.sh inside `bash -c` is safer than `export -f`
#     (MINGW64 has been known to mishandle exported functions).
#   - Wrapper returns 0 always (unless die fires); exit status flows through
#     the global LAST_INVOKE_EXIT_CODE. Matches the || true pattern used by
#     invoke_claude/invoke_codex (agent errors are data, not runner crashes).
invoke_agent_with_timeout() {
  local agent="${1:?agent required}"
  local prompt_file="${2:?prompt file required}"
  local output_file="${3:?output file required}"
  local stderr_file="${4:?stderr file required}"
  local writable="${5:-false}"

  local effective_timeout="${PHASE_TIMEOUT:-1800}"

  if ! [[ "$effective_timeout" =~ ^[0-9]+$ ]] || (( effective_timeout < 1 )); then
    die "PHASE_TIMEOUT must be a positive integer (got: $effective_timeout)"
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    log "WARNING: timeout(1) not found - invoke_agent_with_timeout degrading to direct dispatch"
    invoke_agent "$agent" "$prompt_file" "$output_file" "$stderr_file" "$writable"
    LAST_INVOKE_EXIT_CODE=0
    return 0
  fi

  local exit_code=0
  case "$agent" in
    codex)
      timeout --foreground "${effective_timeout}s" \
        bash -c 'source "$1"; invoke_codex "$2" "$3" "$4"' _ \
        "${BASH_SOURCE[0]}" "$prompt_file" "$output_file" "$stderr_file" \
        || exit_code=$?
      ;;
    opus)
      timeout --foreground "${effective_timeout}s" \
        bash -c 'source "$1"; invoke_claude "$2" "$3" "$4" "$5"' _ \
        "${BASH_SOURCE[0]}" "$prompt_file" "$output_file" "$stderr_file" "$writable" \
        || exit_code=$?
      ;;
    *)
      die "Unsupported agent: $agent"
      ;;
  esac

  LAST_INVOKE_EXIT_CODE="$exit_code"

  if (( exit_code == 124 )); then
    log "WARNING: agent ${agent} timed out after ${effective_timeout}s (exit 124)"
  fi

  return 0
}
