#!/usr/bin/env bash

# bash 5.2 enabled `patsub_replacement` by default: an unescaped `&` in the
# REPLACEMENT of ${var//pat/repl} expands to the matched pattern, corrupting
# any substituted document/task content containing `&`. Restore the literal
# pre-5.2 semantics everywhere this file's substitutions run. (No-op on
# older bash, hence the guard.)
shopt -u patsub_replacement 2>/dev/null || true

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
  # F-6: honor an optional exit-code (2nd arg); default to 1 when omitted.
  exit "${2:-1}"
}

# F-1: reject the wrong `yq`. The Debian/Ubuntu `apt install yq` ships the python
# yq (kislyuk), which is NOT compatible with the mikefarah/Go yq v4 syntax this
# project uses. mikefarah prints "mikefarah" in --version; the python yq does not.
# Sites that cannot source this lib (the PEL components, by their self-containment
# invariants) inline the same version check -- keep them in sync.
require_mikefarah_yq() {
  if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -qi mikefarah; then
    die "mikefarah/yq (Go yq v4+) required; the python 'yq' is not compatible. Install: scoop install yq (Windows), brew install yq (macOS), or the binary from https://github.com/mikefarah/yq."
  fi
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

# v1.5 Phase 1 (A-4a): resolve a friendly Claude model alias to its CLI model id.
# `best` and `opus` resolve to the current Opus line (claude-opus-4-8); `fable` is
# retained for back-compat only (currently unreachable). Anything else passes
# through verbatim so explicit ids (claude-opus-4-8[1m], …) and an empty value are
# untouched. Used by the base CLAUDE_MODEL default below, the --claude-model flag,
# and dev-review.sh's per-seat env layer (which sources this lib). This is the
# SINGLE source of the alias table — dev-review.sh no longer defines its own copy.
# Bumping the Claude default to a new model = edit the `best` arm here, one place.
resolve_claude_model_alias() {
  case "$1" in
    best)  echo "claude-opus-4-8" ;;   # strongest supported Claude default for the preset
    opus)  echo "claude-opus-4-8" ;;   # current Opus-line model
    fable) echo "claude-fable-5" ;;    # retained for back-compat; currently unreachable, do not default to it
    *)     echo "$1" ;;
  esac
}

# F-5a: Claude model override. CLAUDE_MODEL env var or --claude-model flag wins.
# v1.5 Phase 1 (A-4a): the base default is now the `best` alias resolved to the
# current Opus line (claude-opus-4-8), replacing the stale claude-opus-4-6 pin.
# Resolving through the alias keeps the "one place to bump" invariant. (CODEX_MODEL
# stays optional/unset by default -- invoke_codex only appends -c model= when set.)
: "${CLAUDE_MODEL:=$(resolve_claude_model_alias best)}"

# v1.5: Per-seat reasoning-effort knobs. Both default empty = OFF, so invoke_*
# omit the effort flag entirely and argv stays byte-identical to today (parity
# invariant). When non-empty, invoke_claude appends `--effort "$CLAUDE_EFFORT"`
# and invoke_codex appends `-c model_reasoning_effort=...`. `--effort high` is
# proven headless in -p mode at evals/judge-bounce.sh:58 (built into JUDGE_ARGS,
# consumed by the `"$JUDGE_CMD" -p ...` call at evals/judge-bounce.sh:139).
: "${CLAUDE_EFFORT:=}"
: "${CODEX_REASONING_EFFORT:=}"

# Document-pipeline seats that use binaries other than their vendor's default
# CLI keep their model/effort state separate. In particular, a GLM pass must
# never rewrite CLAUDE_MODEL for a later plain-Claude pass in the same process.
: "${GLM_MODEL:=glm-5.3-flash}"
: "${GLM_EFFORT:=}"
: "${KIMI_MODEL:=kimi-k3}"

# Classify the supported document-pipeline seat names. Keep this case-driven:
# callers must never treat an unknown future seat as Claude by default.
agent_kind() {
  case "$1" in
    claude) printf 'claude' ;;
    codex)  printf 'codex' ;;
    glm)    printf 'glm' ;;
    kimi)   printf 'kimi' ;;
    *)      return 1 ;;
  esac
}

# Print the Kimi executable to use. PATH is authoritative; the fallback covers
# Kimi Code's current per-user installer without baking in a username or OS.
find_kimi_cli() {
  local candidate

  if command -v kimi >/dev/null 2>&1; then
    command -v kimi
    return 0
  fi

  for candidate in \
    "${HOME:-}/.kimi-code/bin/kimi" \
    "${HOME:-}/.kimi-code/bin/kimi.exe"; do
    if [[ -n "${HOME:-}" && -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

# Non-live prerequisite checks for document seats. The caller can surface the
# specific failure through SEAT_PREREQ_ERROR. Claude/Codex deliberately retain
# their existing invocation-time validation behavior.
SEAT_PREREQ_ERROR=""
seat_prereqs_ok() {
  local agent="$1"
  local kimi_root
  SEAT_PREREQ_ERROR=""

  case "$agent" in
    claude|codex)
      return 0
      ;;
    glm)
      if [[ -z "${ZAI_API_KEY:-}" ]]; then
        SEAT_PREREQ_ERROR="glm seat requires ZAI_API_KEY (set it in the environment or .env.local)"
        return 1
      fi
      if ! command -v curl >/dev/null 2>&1; then
        SEAT_PREREQ_ERROR="glm seat requires curl for the direct Z.AI API"
        return 1
      fi
      if ! command -v jq >/dev/null 2>&1; then
        SEAT_PREREQ_ERROR="glm seat requires jq for Z.AI request and response handling"
        return 1
      fi
      return 0
      ;;
    kimi)
      if [[ -z "${KIMI_API_KEY:-}" ]]; then
        SEAT_PREREQ_ERROR="kimi seat requires KIMI_API_KEY (set it in the environment or .env.local)"
        return 1
      fi
      if ! command -v curl >/dev/null 2>&1; then
        SEAT_PREREQ_ERROR="kimi seat requires curl for the direct Kimi API"
        return 1
      fi
      if ! command -v jq >/dev/null 2>&1; then
        SEAT_PREREQ_ERROR="kimi seat requires jq for Kimi request and response handling"
        return 1
      fi
      return 0
      ;;
    *)
      SEAT_PREREQ_ERROR="Unknown agent: $agent"
      return 1
      ;;
  esac
}

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

# --- Lab routing (Phase 3 LAB-01) ---
#
# Shared helpers used by both runners (co-evolve-bouncer.sh and
# dev-review/codex/dev-review.sh) to parse, validate, and dispatch the
# `--lab <mode>` flag. Contract is locked in lab/README.md; these helpers
# are the single-point-of-truth for the runtime behavior.

# validate_lab_mode <mode> → returns 0 if mode is a safe filesystem segment.
# T-03-02-01 mitigation: rejects path-traversal (../, /) and shell-meta (;,&,|,`,$,<,>).
# Allowed: ASCII alphanumerics plus hyphen and underscore. Empty string → 1.
# Pure function, no side effects, no filesystem access.
validate_lab_mode() {
  local mode="${1:-}"
  [[ -n "$mode" ]] || return 1
  [[ "${#mode}" -le 64 ]] || return 1
  [[ "$mode" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  return 0
}

# list_available_lab_modes <lab_root> → prints comma-separated subdir names sorted.
# Prints "(none)" when <lab_root> absent or empty. Always exits 0 (informational).
# GNU find supports -printf; macOS find does not — we feature-detect and fall back.
list_available_lab_modes() {
  local lab_root="${1:?list_available_lab_modes requires a lab_root}"
  if [[ ! -d "$lab_root" ]]; then
    printf '(none)'
    return 0
  fi
  local modes
  if find --version 2>/dev/null | grep -q GNU; then
    modes=$(find "$lab_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
            | sort | paste -sd, -)
  else
    # macOS fallback — no -printf support on BSD find.
    modes=$(find "$lab_root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
            | sort | paste -sd, -)
  fi
  if [[ -z "$modes" ]]; then
    printf '(none)'
  else
    printf '%s' "$modes"
  fi
  return 0
}

# dispatch_lab_mode <mode> <lab_root> <argv...>
#   Validates mode, resolves <lab_root>/<mode>/entry.sh, exec's it with remaining argv.
#   Never returns on success. Dies on invalid token, unknown mode, or missing entry.sh.
#   T-03-02-01 + T-03-02-03 mitigation: mode token is validated BEFORE any fs op.
dispatch_lab_mode() {
  local mode="${1:?dispatch_lab_mode requires a mode}"
  local lab_root="${2:?dispatch_lab_mode requires a lab_root}"
  shift 2
  if ! validate_lab_mode "$mode"; then
    die "invalid --lab mode: $mode (must match [A-Za-z0-9_-]+)"
  fi
  local entry="$lab_root/$mode/entry.sh"
  if [[ ! -f "$entry" ]]; then
    local available
    available=$(list_available_lab_modes "$lab_root")
    die "unknown --lab mode: $mode. Available: $available"
  fi
  # exec replaces the current process — the lab inhabitant owns stdout/stderr/exit.
  exec bash "$entry" "$@"
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

# normalize_path_for_bash <path> -> path
# Under WSL, convert Windows drive paths (C:/... or C:\...) into POSIX paths
# before handing them to Bash filesystem checks. Script paths still need to be
# valid before Bash starts; this helper is for arguments seen after startup.
# On macOS, Linux, and Git Bash (no WSL), this is a safe pass-through — native
# POSIX paths are returned unchanged and no conversion is attempted.
normalize_path_for_bash() {
  local candidate="${1:-}"

  if [[ -z "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wslpath >/dev/null 2>&1 && [[ "$candidate" =~ ^[A-Za-z]:[\\/].* ]]; then
    wslpath "$candidate"
    return 0
  fi

  printf '%s' "$candidate"
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
  local dispatch="${5:-claude}"
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
  # v1.5: model + optional reasoning effort. CLAUDE_EFFORT defaults empty (OFF)
  # so model_flags is exactly `--model "$CLAUDE_MODEL"` and argv is byte-identical
  # to the prior single-flag form. The --effort element is appended only when set.
  local -a model_flags=(--model "${CLAUDE_MODEL}")
  if [[ -n "${CLAUDE_EFFORT:-}" ]]; then
    model_flags+=(--effort "${CLAUDE_EFFORT}")
  fi

  # v1.5 Phase 4: per-phase token capture, default OFF. Gated behind
  # CO_EVOLVE_TOKEN_CAPTURE=1 AND jq present so the default path stays
  # byte-identical (argv + artifacts). When ON we swap `--output-format text`
  # for `--output-format json`: the JSON envelope (R1) carries `.usage` token
  # counts, and `.result` holds the same text the text path would have emitted.
  # PRTP-03 reminder: this is `--output-format json`, NOT `--output-schema`
  # (the latter hangs claude -p on Windows). The gate keeps it default-off so
  # the Windows precedent is respected unless an operator opts in.
  local capture_json=false
  if [[ "${CO_EVOLVE_TOKEN_CAPTURE:-}" == "1" ]] && command -v jq >/dev/null 2>&1; then
    capture_json=true
  fi

  local output_format=text
  [[ "$capture_json" == "true" ]] && output_format=json

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    # Under WSL, reuse the Windows Claude session because WSL and Windows keep separate auth state.
    cmd=(cmd.exe /c claude -p --output-format "$output_format" "${model_flags[@]}" "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format "$output_format" "${model_flags[@]}" "${tool_flags[@]}")
  fi

  if [[ "$capture_json" == "true" ]]; then
    local envelope_file="${output_file}.envelope.json"
    local usage_file="${output_file}.usage.json"
    # The envelope is emitted on stdout even on failure (R1: is_error=true still
    # carries a body, exit nonzero) — `|| true` matches the text path and we
    # parse regardless. Capture stdout to the envelope, NOT the output file.
    "${cmd[@]}" < "$prompt_file" > "$envelope_file" 2>"$stderr_file" || true
    # Extract `.result` into the output file so the external contract is
    # preserved: callers (validate_agent_artifact, file_contains_auth_failure)
    # only ever read $output_file. On auth failure `.result` is the "Not logged
    # in" banner, so the existing auth gate keeps working. If `.result` is empty
    # or the envelope is unparseable, fall back to copying the raw envelope so
    # validate_agent_artifact sees a non-empty file rather than a silent blank.
    if jq -e 'has("result") and (.result | type == "string") and (.result | length > 0)' \
         "$envelope_file" >/dev/null 2>&1; then
      jq -r '.result // empty' "$envelope_file" > "$output_file"
    else
      cp "$envelope_file" "$output_file"
    fi
    # Usage sidecar (R1 fields). `// null` guards a malformed/partial envelope so
    # the file is always valid JSON for collect_token_usage to slurp. Never
    # fatal — token capture must not break a run.
    jq '{
          input_tokens: (.usage.input_tokens // null),
          output_tokens: (.usage.output_tokens // null),
          cache_read_input_tokens: (.usage.cache_read_input_tokens // null),
          cache_creation_input_tokens: (.usage.cache_creation_input_tokens // null),
          total_cost_usd: (.total_cost_usd // null),
          source: "claude-json"
        }' "$envelope_file" > "$usage_file" 2>/dev/null \
      || printf '{"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null,"total_cost_usd":null,"source":"claude-json"}\n' > "$usage_file"
    return 0
  fi

  "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_file" || true
}

invoke_glm() (
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local writable="${4:-false}"
  local request_file response_file config_file
  local curl_rc=0 message

  [[ -n "${ZAI_API_KEY:-}" ]] || die "glm seat requires ZAI_API_KEY"
  [[ "$writable" == "false" ]] || die "glm seat does not support writable phases"
  command -v curl >/dev/null 2>&1 || die "glm seat requires curl"
  command -v jq >/dev/null 2>&1 || die "glm seat requires jq"

  request_file=$(mktemp -t glm-request-XXXXXX.json)
  response_file=$(mktemp -t glm-response-XXXXXX.json)
  config_file=$(mktemp -t glm-curl-XXXXXX.conf)
  trap 'rm -f "$request_file" "$response_file" "$config_file"' EXIT

  # Send only the protocol prompt. Claude Code's internal system messages are
  # incompatible with this document seat and were observed replacing a valid
  # response with <system-warning>/<system-reminder> metadata. Z.AI's documented
  # Chat Completions endpoint avoids that extra agent layer entirely.
  jq -Rs --arg model "${GLM_MODEL:-glm-5.3-flash}" '{
      model: $model,
      messages: [{role: "user", content: .}],
      stream: false,
      temperature: 0
    }' "$prompt_file" > "$request_file"

  # Keep the bearer token out of argv and logs. curl reads it from a mode-600
  # temporary config file that this adapter removes on every exit path.
  {
    printf 'url = "https://api.z.ai/api/paas/v4/chat/completions"\n'
    printf 'request = "POST"\n'
    printf 'header = "Authorization: Bearer %s"\n' "$ZAI_API_KEY"
    printf 'header = "Content-Type: application/json"\n'
    printf 'header = "Accept-Language: en-US,en"\n'
    printf 'data-binary = "@-"\n'
    printf 'silent\nshow-error\nfail-with-body\nmax-time = 600\n'
  } > "$config_file"
  chmod 600 "$config_file"

  curl --config "$config_file" < "$request_file" > "$response_file" 2> "$stderr_file" || curl_rc=$?
  if (( curl_rc == 0 )) \
     && jq -e '.choices[0].message.content | type == "string" and length > 0' \
          "$response_file" >/dev/null 2>&1; then
    jq -r '.choices[0].message.content' "$response_file" > "$output_file"
    if [[ "${CO_EVOLVE_TOKEN_CAPTURE:-}" == "1" ]]; then
      jq '{
            input_tokens: (.usage.prompt_tokens // null),
            output_tokens: (.usage.completion_tokens // null),
            cache_read_input_tokens: (.usage.prompt_tokens_details.cached_tokens // null),
            cache_creation_input_tokens: null,
            total_cost_usd: null,
            source: "zai-chat-completions"
          }' "$response_file" > "${output_file}.usage.json" 2>/dev/null || true
    fi
    return 0
  fi

  message=$(jq -r '.error.message // .message // empty' "$response_file" 2>/dev/null || true)
  [[ -n "$message" ]] || message="Z.AI request failed (curl exit $curl_rc)"
  printf 'API Error: %s\n' "$message" > "$output_file"
  return 0
)

invoke_kimi() (
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local request_file response_file config_file
  local curl_rc=0 message

  [[ -n "${KIMI_API_KEY:-}" ]] || die "kimi seat requires KIMI_API_KEY"
  command -v curl >/dev/null 2>&1 || die "kimi seat requires curl"
  command -v jq >/dev/null 2>&1 || die "kimi seat requires jq"

  request_file=$(mktemp -t kimi-request-XXXXXX.json)
  response_file=$(mktemp -t kimi-response-XXXXXX.json)
  config_file=$(mktemp -t kimi-curl-XXXXXX.conf)
  trap 'rm -f "$request_file" "$response_file" "$config_file"' EXIT

  # The document seat calls Kimi's model API directly. Kimi Code's -p agent
  # loop auto-runs Read/Write tools, which violates the no-tools seat boundary.
  jq -Rs --arg model "${KIMI_MODEL:-kimi-k3}" '{
      model: $model,
      messages: [{role: "user", content: .}],
      stream: false,
      temperature: 1
    }' "$prompt_file" > "$request_file"

  {
    printf 'url = "https://api.moonshot.ai/v1/chat/completions"\n'
    printf 'request = "POST"\n'
    printf 'header = "Authorization: Bearer %s"\n' "$KIMI_API_KEY"
    printf 'header = "Content-Type: application/json"\n'
    printf 'data-binary = "@-"\n'
    printf 'silent\nshow-error\nfail-with-body\nmax-time = 600\n'
  } > "$config_file"
  chmod 600 "$config_file"

  curl --config "$config_file" < "$request_file" > "$response_file" 2> "$stderr_file" || curl_rc=$?
  if (( curl_rc == 0 )) \
     && jq -e '.choices[0].message.content | type == "string" and length > 0' \
          "$response_file" >/dev/null 2>&1; then
    jq -r '.choices[0].message.content' "$response_file" > "$output_file"
    if [[ "${CO_EVOLVE_TOKEN_CAPTURE:-}" == "1" ]]; then
      jq '{
            input_tokens: (.usage.prompt_tokens // null),
            output_tokens: (.usage.completion_tokens // null),
            cache_read_input_tokens: (.usage.prompt_tokens_details.cached_tokens // null),
            cache_creation_input_tokens: null,
            total_cost_usd: null,
            source: "kimi-chat-completions"
          }' "$response_file" > "${output_file}.usage.json" 2>/dev/null || true
    fi
    return 0
  fi

  message=$(jq -r '.error.message // .message // empty' "$response_file" 2>/dev/null || true)
  [[ -n "$message" ]] || message="Kimi request failed (curl exit $curl_rc)"
  printf 'API Error: %s\n' "$message" > "$output_file"
  return 0
)

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

  # v1.5: optional reasoning effort. Defaults empty (OFF) → no -c append, so argv
  # is byte-identical to today. Appended only when CODEX_REASONING_EFFORT is set.
  if [[ -n "${CODEX_REASONING_EFFORT:-}" ]]; then
    cmd+=(-c "model_reasoning_effort=${CODEX_REASONING_EFFORT}")
  fi

  if [[ -n "${windows_output:-}" ]]; then
    cmd+=(-o "$windows_output")
  else
    cmd+=(-o "$output_file")
  fi

  "${cmd[@]}" < "$prompt_file" > /dev/null 2>"$stderr_file" || true
}

# v1.5 (fixes B2): relocated verbatim from dev-review/codex/dev-review.sh so the
# verify-phase `bash -c 'source lib/co-evolution.sh; invoke_codex_schema ...'`
# child can actually find it (it was defined only in dev-review.sh → exit 127
# whenever a timeout binary exists and verifier=codex). Behavior is identical to
# the prior local copy (--output-schema / -o / --skip-git-repo-check / WSL path
# handling), plus the same conditional model + reasoning-effort appends that
# invoke_codex grew above — both default-off so argv is unchanged when unset.
invoke_codex_schema() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local schema_file="$4"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local windows_workdir=""
  local windows_output=""
  local windows_schema=""

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    windows_workdir=$(wslpath -w "$workdir")
    windows_output=$(wslpath -w "$output_file")
    windows_schema=$(wslpath -w "$schema_file")
    cmd=(cmd.exe /c codex exec --full-auto --skip-git-repo-check -C "$windows_workdir")
  else
    cmd=(codex exec --full-auto --skip-git-repo-check -C "$workdir")
  fi

  if [[ -n "${CODEX_MODEL:-}" ]]; then
    cmd+=(-c "model=${CODEX_MODEL}")
  fi

  # v1.5: optional reasoning effort. Defaults empty (OFF) → no -c append.
  if [[ -n "${CODEX_REASONING_EFFORT:-}" ]]; then
    cmd+=(-c "model_reasoning_effort=${CODEX_REASONING_EFFORT}")
  fi

  if [[ -n "$windows_schema" ]]; then
    cmd+=(--output-schema "$windows_schema" -o "$windows_output")
  else
    cmd+=(--output-schema "$schema_file" -o "$output_file")
  fi

  "${cmd[@]}" < "$prompt_file" > /dev/null 2>"$stderr_file" || true
}

file_contains_auth_failure() {
  local file_path="$1"

  [[ -s "$file_path" ]] || return 1

  # "Not logged in · Please run /login" is the claude CLI's current (2026-06)
  # unauthenticated banner, observed live — the slash defeats 'run .* login'.
  grep -qiE 'Failed to authenticate|authentication_error|Not authenticated|Not logged in|Unauthorized|login required|Please run .* login|Please run /login' "$file_path"
}

# A-2: strict, anchored auth-banner detector for the agent OUTPUT path. The
# broad file_contains_auth_failure above is a loose substring scan (it even
# matches a bare "Unauthorized"), which is right for stderr/empty-output paths
# but wrong for the output document: a legitimate long artifact routinely
# mentions "Unauthorized"/"Not authenticated" mid-sentence. A genuine CLI auth
# failure prints a short banner that STANDS ALONE at the start of a line before
# any work is done. So we scan only the first ~20 non-empty lines and require
# an auth-context banner to be line-leading (leading whitespace/bullet/quote
# punctuation is tolerated — e.g. the CLI's "Not logged in · Please run /login").
# Markdown-QUOTED lines are skipped, not matched: a document about auth
# handling legitimately quotes the banner as an example inside a ``` fence, a
# 4-space/tab indented block, or a > blockquote — a real banner prints at
# column 0 outside any code context. (Bold **...** lead-ins still match: a
# colorized real banner can arrive wrapped; quoting-in-bold is rare.)
# Deliberately excludes a bare "Unauthorized" and a bare "Not authenticated":
# those are prose tokens far more often than banners, and the broad matcher
# still guards the stderr path. This replaces the old whole-file <50-word
# heuristic while preserving deb4669's intent — a long document that merely
# echoes auth phrases mid-body must still pass.
output_contains_auth_banner() {
  local file_path="$1"
  local line eligible=""
  local nonempty=0 in_fence=false
  local fence_re='^[[:space:]]*```'
  local blockquote_re='^[[:space:]]*>'

  [[ -s "$file_path" ]] || return 1

  # Collect the window's match-eligible lines, then run the banner regex once.
  # `|| [[ -n "$line" ]]` keeps a final line that lacks a trailing newline.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue              # blank: not counted
    nonempty=$((nonempty + 1))
    (( nonempty > 20 )) && break                             # window exhausted
    if [[ "$line" =~ $fence_re ]]; then                      # fence marker:
      if [[ "$in_fence" == true ]]; then in_fence=false; else in_fence=true; fi
      continue                                               # counted, never matched
    fi
    [[ "$in_fence" == true ]] && continue                    # inside ``` fence
    [[ "$line" == '    '* || "$line" == $'\t'* ]] && continue # indented code
    [[ "$line" =~ $blockquote_re ]] && continue              # blockquote
    eligible+="$line"$'\n'
  done < "$file_path"

  [[ -n "$eligible" ]] || return 1

  grep -qiE \
    '^[[:space:]>*•[:punct:]]*(Not logged in|You are not logged in|Please run [^[:space:]]*login|Please sign in|Please log ?in|Login required|Authentication failed|Failed to authenticate|authentication_error|Your organization does not have access|Invalid API key|Session (has )?expired)' \
    <<< "$eligible"
}

# C-8 (2026-07-07 cross-vendor review): the anchored banner scan above
# deliberately excludes a bare "Unauthorized"/"Not authenticated", so a CLI
# whose ENTIRE output is such a bare line slipped through once the old
# <50-word ceiling was removed (both reviewers flagged it independently).
# Restore that catch without reopening the long-page hole: the loose matcher
# is consulted only when the whole output is under 50 words — a real work
# product is never that small, and the old heuristic caught exactly this case.
# Output-path callers should use THIS, not output_contains_auth_banner alone.
output_is_auth_failure() {
  local file_path="$1"
  local words

  output_contains_auth_banner "$file_path" && return 0
  [[ -s "$file_path" ]] || return 1
  words=$(wc -w < "$file_path" | tr -d '\r\n ')
  (( words < 50 )) && file_contains_auth_failure "$file_path"
}

file_contains_error_payload() {
  local file_path="$1"

  [[ -s "$file_path" ]] || return 1

  grep -qiE '^(API Error|Error|ERROR|fatal|Fatal):|^Internal Server Error$|^Bad Gateway$|^Service Unavailable$|rate limit exceeded|context deadline exceeded|timed out|connection (reset|refused)|ECONNREFUSED|ENOTFOUND|Traceback \(most recent call last\):' "$file_path"
}

# Provider CLIs sometimes print a short API-error sentence to stdout and still
# exit zero. Without a content gate, the bouncer can install that sentence as
# the document and report false convergence. Keep this deliberately narrow:
# consult the broad error-payload matcher only for short outputs, so a real
# document that discusses or quotes provider errors is not rejected.
output_is_provider_failure() {
  local file_path="$1"
  local words

  [[ -s "$file_path" ]] || return 1
  words=$(wc -w < "$file_path" | tr -d '\r\n ')
  (( words < 50 )) && file_contains_error_payload "$file_path"
}

# R-1/R-2 (v1.3 Phase 1): classify an agent invocation's outcome BEFORE the
# output is accepted as a document. The invoke_* adapters deliberately
# `|| true` their CLI calls, so a missing or unauthenticated CLI surfaces only
# as text in the output/stderr captures — without this gate, an auth-error
# page gets bounced as if it were the document.
#
# Returns:
#   0  output looks like a real artifact — proceed
#   1  output empty, no fatal signature — retryable
#   2  fatal: CLI missing or unauthenticated — retrying cannot help; the
#      caller must abort with the logged message
validate_agent_artifact() {
  local output_file="$1"
  local stderr_file="$2"
  local agent_name="${3:-agent}"

  # Fatal: an auth-failure BANNER in the output. A real CLI auth error prints
  # a short banner that stands alone at the top of its output before doing any
  # work, so we head-scan with a strict, line-anchored matcher (A-2). The old
  # whole-file <50-word ceiling let an auth-error PAGE longer than 50 words fall
  # through to the accept below; anchoring to the head instead catches long
  # error pages while still letting a long legitimate document that merely
  # echoes auth phrases mid-body pass. output_is_auth_failure additionally
  # keeps the short+loose catch for a bare banner the anchor excludes (C-8).
  if output_is_auth_failure "$output_file"; then
    log " ERROR: ${agent_name} returned an authentication failure, not a document. Run \`${agent_name}\` interactively to log in, then re-run."
    return 2
  fi

  if output_is_provider_failure "$output_file"; then
    log " ERROR: ${agent_name} returned a provider/API failure, not a document. Inspect the captured output and provider account status before re-running."
    return 2
  fi

  [[ -s "$output_file" ]] && return 0

  # Output empty — check stderr for a fatal cause before letting the caller
  # burn a retry on a CLI that is not installed or not logged in.
  if [[ -n "$stderr_file" && -s "$stderr_file" ]]; then
    if grep -qiE 'command not found|No such file or directory' "$stderr_file"; then
      log " ERROR: ${agent_name} CLI is not installed (command not found). Run \`bash scripts/doctor.sh\` to see what is missing."
      return 2
    fi
    if file_contains_auth_failure "$stderr_file"; then
      log " ERROR: ${agent_name} CLI is not authenticated. Run \`${agent_name}\` interactively to log in, then re-run."
      return 2
    fi
  fi

  return 1
}

# R-7 (v1.3 Phase 1): unique run-directory suffix. Timestamp alone collides
# when two runs start in the same second (scripted batches, parallel CI);
# 6 hex chars of entropy make that practically impossible. $RANDOM is 15-bit,
# so two draws are combined.
generate_run_suffix() {
  printf '%s-%06x' "$(date +%Y%m%d-%H%M%S)" "$(( (RANDOM * 32768 + RANDOM) % 16777216 ))"
}

# S-1 (v1.3 Phase 1): remove protocol markers from TASK text before it is
# embedded in a prompt. A task that contains literal [CONTESTED]/[CLARIFY]
# tokens (e.g. a task ABOUT the protocol, or a hostile one) would otherwise
# inject live markers into the bounce loop and skew marker accounting.
# Documented caveat: this is marker hygiene, not a prompt-injection defense.
strip_protocol_markers() {
  printf '%s' "$1" | sed -e 's/\[CONTESTED[^]]*\]//g' -e 's/\[CLARIFY[^]]*\]//g'
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

  # bash-3.2 portable (macOS /bin/bash has no mapfile). IFS= + -r preserves
  # leading whitespace and backslashes; the || clause keeps a final line that
  # lacks a trailing newline.
  local _read_line
  while IFS= read -r _read_line || [[ -n "$_read_line" ]]; do
    lines+=("$_read_line")
  done < "$input_file"

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

  # v1.5 Phase 2 (A-7): token-discipline size caps, mirrored from
  # skills/dev-review/schemas/review-verdict.json (maxItems/maxLength). A verdict
  # that blows past these is unusable verifier output (a wall of text is a failed
  # verdict), so it takes the SAME invalid-verdict path as a malformed one —
  # rejected here, never passed downstream. Kept shell-side too because the claude
  # verifier seat has no --output-schema and never hits the CLI's schema check.
  local -r MAX_ISSUES=5
  local -r MAX_SUMMARY_LEN=320
  local -r MAX_ISSUE_FIELD_LEN=240
  local -r MAX_ITERATION_NOTES_LEN=600

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

    # v1.5 Phase 2 (A-7): size caps (see MAX_* above). Over-cap = invalid verdict.
    jq -e --argjson m "$MAX_ISSUES" '(.issues | length) <= $m' "$json_file" >/dev/null 2>&1 || {
      printf 'verdict exceeded the %s-issue cap' "$MAX_ISSUES"
      return 1
    }
    jq -e --argjson m "$MAX_SUMMARY_LEN" '(.summary | length) <= $m' "$json_file" >/dev/null 2>&1 || {
      printf 'summary exceeded the %s-character cap' "$MAX_SUMMARY_LEN"
      return 1
    }
    jq -e --argjson m "$MAX_ITERATION_NOTES_LEN" 'if has("iteration_notes") then (.iteration_notes | length) <= $m else true end' "$json_file" >/dev/null 2>&1 || {
      printf 'iteration_notes exceeded the %s-character cap' "$MAX_ITERATION_NOTES_LEN"
      return 1
    }
    jq -e --argjson m "$MAX_ISSUE_FIELD_LEN" '[.issues[]? | (.file? // ""), (.line_range? // ""), (.description? // ""), (.suggestion? // "")] | all(.[]; length <= $m)' "$json_file" >/dev/null 2>&1 || {
      printf 'an issue field exceeded the %s-character cap' "$MAX_ISSUE_FIELD_LEN"
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

    # v1.5 Phase 2 (A-7): size caps in the jq-less fallback. Issue count is proxied
    # by the required per-issue "severity" key; summary length uses the extracted
    # value. Same reject-as-invalid contract as the jq branch above.
    local fallback_issue_count=0
    fallback_issue_count=$(grep -o '"severity"[[:space:]]*:' "$json_file" | wc -l | tr -d '\r\n ')
    if (( fallback_issue_count > MAX_ISSUES )); then
      printf 'verdict exceeded the %s-issue cap' "$MAX_ISSUES"
      return 1
    fi
    if (( ${#summary} > MAX_SUMMARY_LEN )); then
      printf 'summary exceeded the %s-character cap' "$MAX_SUMMARY_LEN"
      return 1
    fi
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

# v1.5 Phase 4 (A-5 hardening): fence-AGNOSTIC marker count for the honesty
# gate. count_markers deliberately skips code fences and inline code so a pass
# that QUOTES a marker example is not treated as disagreeing — correct for
# per-pass convergence accounting, but exploitable at the finish line: a live
# marker tucked inside a ``` fence counts 0 there and the run would be
# presented as "converged" with the marker text still in the final document.
# The honesty gate (natural-convergence decision + post-adjudication body
# verdict in co-evolve-bouncer.sh) uses THIS raw count instead: any line
# carrying the literal marker token counts, fenced or not. A fenced survivor
# forces adjudication (the adjudicator may resolve or drop it) or ends the run
# stuck — never silent convergence. Do NOT swap this into per-pass accounting.
count_markers_raw() {
  local file_path="$1"
  local marker="$2"

  # Count TOKEN OCCURRENCES, not lines. The old form did `index($0,marker)>0 →
  # count++`, incrementing once per line even when a line carried two markers
  # (e.g. `[CONTESTED] a  [CONTESTED] b`), which UNDERCOUNTED. The adjudication
  # receipt gate compares report entries against this count (co-evolve-bouncer.sh
  # run_adjudication `entries < pre_markers`), so an undercount let ONE report
  # bullet satisfy the gate for TWO live markers. Walk each line with index() and
  # advance past every match to tally all occurrences. index() (literal match) is
  # used rather than gsub so the marker's `[` and `]` need no ERE escaping — safe
  # across gawk/nawk/mawk. A marker-free document counts 0 either way, so the
  # byte-parity convergence path is unaffected.
  awk -v marker="$marker" '
    BEGIN { count = 0; mlen = length(marker) }
    {
      line = $0
      pos = index(line, marker)
      while (pos > 0) {
        count++
        line = substr(line, pos + mlen)
        pos = index(line, marker)
      }
    }
    END { print count }
  ' "$file_path" | tr -d '\r\n '
}

strip_human_summary() {
  local input_file="$1"
  local output_file="$2"

  # The bounce protocol instructs agents to APPEND a `## HUMAN SUMMARY` section
  # "at the very end" of the document (one line per pass) — it is always the
  # trailing section (see templates/*/bounce-protocol.md rules 7-8). Stripping at
  # the FIRST `^## HUMAN SUMMARY` heading destroyed any document whose BODY
  # legitimately contains that heading (e.g. the protocol docs, or a plan that
  # discusses human summaries) — everything from that point down was deleted.
  # Key on the LAST occurrence instead: the final `## HUMAN SUMMARY` heading and
  # everything after it is the agent-appended trailer; the body above it is
  # preserved verbatim. Two-pass awk (find the last heading's line number, then
  # print only lines before it) keeps this bash-3.2 / macOS-awk portable and
  # byte-identical to the old behavior when there is exactly one (trailing)
  # heading — the only case that changes is a document with an EARLIER body-level
  # heading, which is now kept.
  awk '
    NR==FNR { if ($0 ~ /^## HUMAN SUMMARY/) last=FNR; next }
    last==0 || FNR < last { print }
  ' "$input_file" "$input_file" > "$output_file"
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
  local first_stderr_file="${8:-}"
  local input_words
  local output_words
  local artifact_rc

  # R-1/R-2: classify before accepting. rc 2 = fatal (CLI missing or
  # unauthenticated) — retrying cannot help, abort with the logged message.
  artifact_rc=0
  validate_agent_artifact "$output_file" "$first_stderr_file" "$agent_name" || artifact_rc=$?
  if (( artifact_rc == 2 )); then
    return 1
  fi

  if [[ ! -s "$output_file" ]]; then
    log " ERROR: ${agent_name} returned empty output. Retrying once..."
    "$retry_function" "$prompt_file" "$output_file" "$retry_stderr_file"

    artifact_rc=0
    validate_agent_artifact "$output_file" "$retry_stderr_file" "$agent_name" || artifact_rc=$?
    if (( artifact_rc == 2 )); then
      return 1
    fi
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

# C-4: pick a code-fence backtick run long enough to safely wrap an untrusted
# diff. CommonMark closes a fenced block only on a backtick run at least as long
# as the opener, so a diff line that is itself ``` (or longer) breaks out of a
# bare ```diff fence and the remainder reads as verifier instructions. We find
# the longest backtick run anywhere in the diff and return a fence ONE backtick
# longer (never fewer than 3, so a clean diff keeps the byte-identical ```diff
# fence).
#
# PR#48-M1: single awk pass, not the old grow-the-probe loop. That loop appended
# one backtick to a probe and re-scanned the ENTIRE diff on every step, so a line
# with an N-backtick run cost O(N^2) — measured at 31.6s for a 20k-backtick line,
# >2min at 60k. awk scans each record once (a backtick run never spans a newline,
# so per-record is complete) and gsub-collapses non-backticks so run detection is
# linear even for a diff of many scattered backticks. CRLF-safe: a CR is a
# non-backtick byte that terminates a run just like any other. The fence itself
# is emitted in one shot (sprintf a run of spaces, gsub to backticks) so no
# per-character string growth remains anywhere on the path.
compute_diff_fence() {
  local diff="$1"
  printf '%s' "$diff" | awk '
    {
      line = $0
      gsub(/[^`]/, " ", line)          # non-backticks -> separators
      n = split(line, runs, " ")       # single-space FS collapses runs: only backtick tokens survive
      for (i = 1; i <= n; i++) if (length(runs[i]) > max) max = length(runs[i])
    }
    END {
      len = max + 1
      if (len < 3) len = 3
      # Build the run by doubling (O(len)); gsub over a len-length string is
      # O(len^2) in gawk and dominated the pathological 50k-backtick case.
      fence = "`"
      while (length(fence) < len) fence = fence fence
      printf "%s", substr(fence, 1, len)
    }
  '
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
        delta_status: "computed",
        modified: [ ($B | keys[]) | select(($C[.] // null) != null and $C[.] != $B[.]) ] | sort,
        added:    [ ($C | keys[]) | select(($B[.] // null) == null) ] | sort,
        deleted:  [ ($B | keys[]) | select(($C[.] // null) == null) ] | sort
      }' > "$output"
  else
    # R-4 (v1.3 Phase 1): without jq the delta cannot be computed. The arrays
    # stay empty for shape compatibility, but delta_status="unknown" stops
    # downstream consumers from reading this as "no changes were made".
    log "WARNING: jq unavailable — execute_delta cannot be computed; emitting delta_status=unknown"
    printf '{"delta_status":"unknown","modified":[],"added":[],"deleted":[]}\n' > "$output"
  fi
}

# ---------------------------------------------------------------------------
# v1.3 Phase 3: bounce-state/1.0 writers — the document bouncers' state.json.
# Contract: evals/BOUNCE-RUNNER-CONTRACT.md. jq-backed; when jq is missing
# they log once and write nothing (the bounce scorer's artifact-parsing
# fallback covers that case — a hand-rolled partial JSON writer is worse
# than an honest absence).
# ---------------------------------------------------------------------------

bounce_state_now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

init_bounce_state() {
  local state_file="${1:?state file required}"
  local runner="${2:?runner required}"
  local mode="${3:?mode required}"
  local task="${4:-}"
  local input_type="${5:-}"
  local baseline_file="${6:?baseline file required}"
  local final_file="${7:?final file required}"
  # Optional: which reviewer persona shaped the critique passes
  # (light|adversarial|lens). Additive to bounce-state/1.1 — callers that
  # omit it (agent-bouncer) default to "light", the pre-persona behavior.
  local reviewer_persona="${8:-light}"

  if ! command -v jq >/dev/null 2>&1; then
    log "WARNING: jq unavailable — bounce state.json will not be written (scorer falls back to artifact parsing)"
    return 0
  fi

  jq -n \
    --arg runner "$runner" \
    --arg mode "$mode" \
    --arg task "$task" \
    --arg input_type "$input_type" \
    --arg baseline "$baseline_file" \
    --arg final "$final_file" \
    --arg persona "$reviewer_persona" \
    --arg now "$(bounce_state_now_utc)" \
    '{
      schema: "bounce-state/1.1",
      runner: $runner,
      mode: $mode,
      task: $task,
      input_type: $input_type,
      baseline_file: $baseline,
      final_file: $final,
      reviewer_persona: $persona,
      status: "running",
      convergence_status: null,
      started_at: $now,
      finished_at: null,
      passes: []
    }' > "$state_file"
}

append_bounce_pass() {
  local state_file="${1:?state file required}"
  local pass="${2:?pass number required}"
  local role="${3:?role required}"
  local agent="${4:?agent required}"
  local raw_rel="${5:?raw artifact path required}"
  local clean_rel="${6:?clean artifact path required}"
  local contested="${7:?contested count required}"
  local clarify="${8:?clarify count required}"
  local word_count="${9:?word count required}"

  command -v jq >/dev/null 2>&1 || return 0
  [[ -f "$state_file" ]] || return 0

  local tmp
  tmp=$(mktemp)
  jq \
    --argjson pass "$pass" \
    --arg role "$role" \
    --arg agent "$agent" \
    --arg raw "$raw_rel" \
    --arg clean "$clean_rel" \
    --argjson contested "$contested" \
    --argjson clarify "$clarify" \
    --argjson words "$word_count" \
    '.passes += [{
      pass: $pass,
      role: $role,
      agent: $agent,
      output_raw: $raw,
      output_clean: $clean,
      contested: $contested,
      clarify: $clarify,
      total_markers: ($contested + $clarify),
      word_count: $words
    }]' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

finalize_bounce_state() {
  local state_file="${1:?state file required}"
  local status="${2:?status required}"

  command -v jq >/dev/null 2>&1 || return 0
  [[ -f "$state_file" ]] || return 0

  local tmp
  tmp=$(mktemp)
  jq \
    --arg status "$status" \
    --arg now "$(bounce_state_now_utc)" \
    '.status = $status | .finished_at = $now' \
    "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

# v1.5 Phase 4 (A-5): record the CONVERGENCE outcome, orthogonal to the
# lifecycle `status` field. `status` answers "did the run finish?"
# (complete/aborted); `convergence_status` answers "did the markers actually
# resolve?" (converged/adjudicated/stuck). Kept separate so the scorer's
# existing abort gate is untouched and a `stuck` run is not confused with an
# `aborted` one. See evals/BOUNCE-RUNNER-CONTRACT.md (bounce-state/1.1).
#   converged  — markers hit 0 naturally within the configured passes
#   adjudicated — markers survived; a forced-adjudication pass resolved every
#                 one with a defensible choice recorded in adjudication-report.md
#   stuck      — adjudication could not defensibly resolve every marker; the
#                working document is preserved WITH markers and is NOT clean
# Additive: agent-bouncer.sh does not call this, so its state.json simply omits
# the field and consumers MUST treat a missing value as "unknown/unset".
set_bounce_convergence_status() {
  local state_file="${1:?state file required}"
  local convergence_status="${2:?convergence status required}"

  command -v jq >/dev/null 2>&1 || return 0
  [[ -f "$state_file" ]] || return 0

  local tmp
  tmp=$(mktemp)
  jq \
    --arg cs "$convergence_status" \
    '.convergence_status = $cs' \
    "$state_file" > "$tmp" && mv "$tmp" "$state_file"
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
        completed_at: null,
        status: "pending",
        updated_at: null,
        changed_files: [],
        history: []
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
  "completed_at": null,
  "status": "pending",
  "updated_at": null,
  "changed_files": [],
  "history": []
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

# v1.5: record the phase now STARTING (write_state_phase records completions).
# Sets .current_phase = {name, started_at} and bumps .updated_at so a status
# reader knows which phase the runner is in mid-run. The EOF block clears it
# back to null. Single-writer discipline: called from the runner main flow only
# — there is NO concurrent heartbeat loop, which would race write_state_field's
# read-modify-write. Degrades silently (return 0) when jq is absent, matching
# write_state_phase / write_state_field.
begin_state_phase() {
  local state_path="${1:?state path required}"
  local phase_name="${2:?phase name required}"

  if command -v jq >/dev/null 2>&1; then
    local tmp now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tmp=$(mktemp)
    # FIX-WR-02 idiom: clean up $tmp on jq failure so we don't leak files.
    if jq --arg name "$phase_name" --arg now "$now" \
       '.current_phase = {name: $name, started_at: $now} | .updated_at = $now' \
       "$state_path" > "$tmp"; then
      mv "$tmp" "$state_path"
    else
      rm -f "$tmp"
      log "WARNING: jq failed in begin_state_phase ($phase_name) — state.json unchanged"
    fi
  else
    log "WARNING: jq unavailable — begin_state_phase skipping ($phase_name)"
  fi
}

# v1.5 Phase 4: aggregate per-phase token usage into state.json. Called ONLY
# when CO_EVOLVE_TOKEN_CAPTURE=1 (the runner gates the call), so when the flag
# is off there is no `tokens` key at all — state.json stays byte-identical.
#
# Two evidence sources, both already on disk by the time this runs:
#   1. Claude usage sidecars (`*.usage.json`, written by invoke_claude's gated
#      JSON path). Mapped to a phase via the sidecar's base output filename:
#        .compose-output.md.usage.json   -> compose
#        .bounce-output-N.md.usage.json  -> bounce-NN (zero-padded)
#        execute-output.md.usage.json    -> execute
#        verdict.json.usage.json         -> verify
#   2. Codex token line (R2) harvested read-only from per-phase stderr logs:
#        compose-stderr.log   -> compose
#        pass-N-stderr.log     -> bounce-NN
#        execute-stderr.log    -> execute
#        review-stderr.log     -> verify
#      Format: the literal line `tokens used` immediately followed by a
#      comma-formatted integer. awk grabs the next line and strips commas.
#
# Writes ONE `tokens` block: {phases:{<phase>:{…}}, totals:{…}} and bumps
# .updated_at. Degrades silently when jq is unavailable. The caller removes the
# transient sidecars afterward (state.json is the durable record).
collect_token_usage() {
  local run_dir="${1:?run_dir required}"
  local state_json="${2:?state_json required}"

  command -v jq >/dev/null 2>&1 || {
    log "WARNING: jq unavailable — collect_token_usage skipping"
    return 0
  }
  [[ -f "$state_json" ]] || return 0

  # Build the phases object incrementally as a JSON string.
  local phases_json='{}'
  local tmp

  # --- 1. Claude usage sidecars -------------------------------------------
  # Two globs: the leading-dot one matches compose/bounce sidecars whose base
  # output file is itself dot-prefixed (.compose-output.md.usage.json,
  # .bounce-output-N.md.usage.json) — a plain *.usage.json glob skips dotfiles.
  local sidecar base phase pass
  for sidecar in "$run_dir"/*.usage.json "$run_dir"/.*.usage.json; do
    [[ -e "$sidecar" ]] || continue          # no-glob guard
    base=$(basename "$sidecar")
    base="${base%.usage.json}"               # strip sidecar suffix -> output filename
    case "$base" in
      .compose-output.md) phase="compose" ;;
      execute-output.md)  phase="execute" ;;
      verdict.json)       phase="verify" ;;
      .bounce-output-*.md)
        pass="${base#.bounce-output-}"
        pass="${pass%.md}"
        if [[ "$pass" =~ ^[0-9]+$ ]]; then
          printf -v phase 'bounce-%02d' "$pass"
        else
          phase="bounce-${pass}"
        fi
        ;;
      *) phase="$base" ;;                     # unknown shape: key by raw base
    esac
    # Merge this sidecar's object under .<phase>. Tolerate a malformed sidecar.
    if tmp=$(jq --arg p "$phase" --slurpfile s "$sidecar" \
               '. + {($p): $s[0]}' <<<"$phases_json" 2>/dev/null); then
      phases_json="$tmp"
    fi
  done

  # --- 2. Codex stderr token lines ----------------------------------------
  local stderr_log log_base codex_phase tokens_val
  for stderr_log in "$run_dir"/compose-stderr.log "$run_dir"/execute-stderr.log \
                    "$run_dir"/review-stderr.log "$run_dir"/pass-*-stderr.log; do
    [[ -f "$stderr_log" ]] || continue
    log_base=$(basename "$stderr_log")
    case "$log_base" in
      compose-stderr.log) codex_phase="compose" ;;
      execute-stderr.log) codex_phase="execute" ;;
      review-stderr.log)  codex_phase="verify" ;;
      pass-*-stderr.log)
        pass="${log_base#pass-}"
        pass="${pass%-stderr.log}"
        if [[ "$pass" =~ ^[0-9]+$ ]]; then
          printf -v codex_phase 'bounce-%02d' "$pass"
        else
          codex_phase="bounce-${pass}"
        fi
        ;;
      *) continue ;;
    esac
    # Skip the retry-stderr variants (pass-N-stderr-retry.log won't match the
    # globs above; the primary logs are authoritative for the phase total).
    tokens_val=$(awk '/^tokens used$/{getline; gsub(",",""); print; exit}' "$stderr_log" 2>/dev/null)
    [[ "$tokens_val" =~ ^[0-9]+$ ]] || continue
    # A claude sidecar already claimed this phase only if claude ran it; codex
    # phases never have a sidecar, so this is collision-free in practice. If both
    # somehow exist, the codex entry wins last (rare/diagnostic).
    if tmp=$(jq --arg p "$codex_phase" --argjson t "$tokens_val" \
               '. + {($p): {source: "codex-stderr", total_tokens: $t}}' \
               <<<"$phases_json" 2>/dev/null); then
      phases_json="$tmp"
    fi
  done

  # --- 3. Totals + single write into state.json ----------------------------
  # Totals sum across phases: claude fields from claude-json sidecars, codex
  # tokens from codex-stderr entries. Nulls are treated as 0 in the sums.
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tmp=$(mktemp)
  if jq --argjson phases "$phases_json" --arg now "$now" '
        ($phases | to_entries) as $entries |
        def num($x): ($x // 0);
        {
          phases: $phases,
          totals: {
            claude_input:      ([$entries[] | select(.value.source=="claude-json") | num(.value.input_tokens)] | add // 0),
            claude_output:     ([$entries[] | select(.value.source=="claude-json") | num(.value.output_tokens)] | add // 0),
            claude_cache_read: ([$entries[] | select(.value.source=="claude-json") | num(.value.cache_read_input_tokens)] | add // 0),
            claude_cost_usd:   ([$entries[] | select(.value.source=="claude-json") | num(.value.total_cost_usd)] | add // 0),
            codex_total_tokens:([$entries[] | select(.value.source=="codex-stderr") | num(.value.total_tokens)] | add // 0)
          }
        } as $tokens |
        .tokens = $tokens | .updated_at = $now
      ' "$state_json" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$state_json"
  else
    rm -f "$tmp"
    log "WARNING: jq failed in collect_token_usage — state.json unchanged (no tokens block)"
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

# C-3: portable timeout-runner selection, shared by invoke_agent_with_timeout AND
# the dev-review codex-verify branch. Echoes the first available runner —
# GNU coreutils `timeout` (Linux, Git Bash), `gtimeout` (macOS + brew coreutils),
# then a perl-alarm fallback (perl ships on stock macOS) — or the empty string
# when none exist, leaving the degrade-to-unbounded decision to the caller.
# Extracting this (rather than a second copy at the verify site) closes the same
# copy-paste divergence class that produced C-1 in the auth detectors.
select_timeout_runner() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout'
  elif command -v perl >/dev/null 2>&1; then
    printf 'perl'
  else
    printf ''
  fi
}

# C-3: run a command under the selected timeout runner. $1=runner name (from
# select_timeout_runner, must be non-empty), $2=seconds, rest=command+args.
#   - GNU timeout/gtimeout use --foreground so the SIGTERM reaches the claude/
#     codex child (a plain timeout puts the child in its own pgroup where a
#     SIGTERM to a network-blocked read is easy to miss). This is a deliberate
#     Phase-A-era choice; the leg divergence below (the perl leg kills a process
#     GROUP, these two do not) is intentional, not an oversight.
#   - The perl leg forks+alarms and exits 124 on expiry to match timeout(1).
#     PR#48-M2: the child setpgrp()s into its own process group and, on alarm,
#     we signal the whole group (kill -$pid) — TERM, a short grace, then KILL.
#     Signalling only the direct child (the old `kill "TERM", $pid`) left a
#     `bash -c` wrapper's grandchild (the actual hung codex/claude) orphaned and
#     still running. Unlike the GNU legs we do NOT pass --foreground-equivalent
#     flags; the group kill is what guarantees reach here.
#     PR#48-M3: propagate the child's real disposition. The old
#     `exit(($? >> 8) & 0xff)` reported 0 for a child KILLED BY A SIGNAL outside
#     the alarm path (segfault, external SIGTERM), laundering a crash into
#     success. Mirror the shell convention instead: signal death -> 128+signum.
# The caller is responsible for the empty-runner (degrade) path; an unknown
# runner is a programming error and dies.
run_with_timeout_runner() {
  local runner="$1"
  local seconds="$2"
  shift 2
  case "$runner" in
    timeout|gtimeout)
      "$runner" --foreground "${seconds}s" "$@"
      ;;
    perl)
      perl -e '
        use POSIX ":sys_wait_h";
        my $t = shift @ARGV;
        my $pid = fork();
        if (!defined $pid) { exit 125; }
        if ($pid == 0) {
          setpgrp(0, 0);          # new process group led by this child
          exec @ARGV;
          exit 127;               # exec failed (command not found / not runnable)
        }
        $SIG{ALRM} = sub {
          kill("TERM", -$pid);    # signal the whole group, not just the child
          for (my $i = 0; $i < 50; $i++) {   # ~5s grace, polled at 0.1s
            last if waitpid($pid, WNOHANG) == $pid;
            select(undef, undef, undef, 0.1);
          }
          kill("KILL", -$pid);
          exit 124;
        };
        alarm $t;
        waitpid($pid, 0);
        alarm 0;
        my $st = $?;
        exit(128 + ($st & 127)) if ($st & 127);   # killed by signal
        exit($st >> 8);                            # normal exit code
      ' "$seconds" "$@"
      ;;
    *)
      die "run_with_timeout_runner: unsupported runner '$runner'"
      ;;
  esac
}

# PR#48-M5 (this repo's S-3 lesson: one validator, not a second copy): resolve
# and validate PHASE_TIMEOUT once, shared by invoke_agent_with_timeout AND the
# dev-review codex-verify branch. A 0 or non-numeric value silently disables the
# bound (perl `alarm 0` never fires; GNU `timeout 0` runs unbounded), so it must
# fail fast. Writes the validated integer to the global EFFECTIVE_PHASE_TIMEOUT
# rather than echoing it: `die` must run in the caller's shell, and a
# `$(require_phase_timeout)` command substitution would swallow the exit.
require_phase_timeout() {
  EFFECTIVE_PHASE_TIMEOUT="${PHASE_TIMEOUT:-1800}"
  if ! [[ "$EFFECTIVE_PHASE_TIMEOUT" =~ ^[0-9]+$ ]] || (( EFFECTIVE_PHASE_TIMEOUT < 1 )); then
    die "PHASE_TIMEOUT must be a positive integer (got: $EFFECTIVE_PHASE_TIMEOUT)"
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

  require_phase_timeout
  local effective_timeout="$EFFECTIVE_PHASE_TIMEOUT"

  # C-3: runner selection extracted to select_timeout_runner so the codex-verify
  # branch in dev-review.sh reuses the exact same 3-tier ladder instead of a
  # divergent copy (copy-paste drift produced C-1). Empty => none of the three
  # are on PATH; degrade to unbounded dispatch as before.
  local timeout_runner
  timeout_runner=$(select_timeout_runner)
  if [[ -z "$timeout_runner" ]]; then
    log "WARNING: no timeout(1)/gtimeout/perl found - invoke_agent_with_timeout degrading to direct dispatch"
    invoke_agent "$agent" "$prompt_file" "$output_file" "$stderr_file" "$writable"
    LAST_INVOKE_EXIT_CODE=0
    return 0
  fi

  local exit_code=0
  case "$agent" in
    codex)
      run_with_timeout_runner "$timeout_runner" "$effective_timeout" \
        bash -c 'source "$1"; invoke_codex "$2" "$3" "$4"' _ \
        "${BASH_SOURCE[0]}" "$prompt_file" "$output_file" "$stderr_file" \
        || exit_code=$?
      ;;
    opus)
      run_with_timeout_runner "$timeout_runner" "$effective_timeout" \
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
