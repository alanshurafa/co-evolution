# lab/pel/classifier/adapter.sh
# Co-Evolution PEL Mode Classifier — Haiku adapter (Phase 4 PEL-01).
#
# SELF-CONTAINED per D-05: no source/import of lib/co-evolution.sh. All helpers
# are defined inline so lab/pel/classifier/** is a clean Phase 7 allowlist-
# exclusion glob (D-11).
#
# Sourced by classifier.sh; not executed standalone.
#
# Required env when run_adapter is called (classifier.sh sets these):
#   TASK                 task string (from $1 in classifier.sh)
#   PEL_BOUNCE_STEP      ∈ {compose, bounce, execute, verify, unknown}
#   PEL_PHASE_TYPE       ∈ {scoping, implementation, verification, unknown}
#   CLASSIFIER_MODEL     Haiku model ID (validated by validate_classifier_model)

# Inline die() — matches lib/co-evolution.sh:13-17 semantics but stays local.
# Second arg is optional exit code (default 1) so callers can signal distinct
# fail-fast categories per D-07 (1=input, 2=cli/auth, 3=response shape).
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

# Inline log_stderr() for stderr diagnostics — stdout stays reserved for JSON (D-08).
log_stderr() {
  printf "%s\n" "$1" >&2
}

# CLI availability check (mirrors dev-review/codex/dev-review.sh:154-163).
# Under WSL, probe via cmd.exe since WSL and Windows keep separate auth state.
require_claude_cli() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c claude --version >/dev/null 2>&1 \
      || die "claude CLI (Windows side, via cmd.exe) is required but not installed or not authenticated" 2
  else
    command -v claude >/dev/null 2>&1 \
      || die "claude CLI is required but not installed" 2
  fi
}

# Auth-failure regex (mirrors lib/co-evolution.sh:402-408).
# Returns 0 if file exists AND contains an auth-failure marker.
file_contains_auth_failure() {
  local file_path="$1"
  [[ -s "$file_path" ]] || return 1
  grep -qiE "Failed to authenticate|authentication_error|Not authenticated|Unauthorized|login required|Please run .* login" "$file_path"
}

# CLASSIFIER_MODEL validator — T-04-04 mitigation. Rejects shell metacharacters
# BEFORE the value is ever passed to claude --model. Allowed charset is the
# superset of current and future Anthropic model IDs (letters, digits, dots,
# hyphens, underscores).
validate_classifier_model() {
  local model="$1"
  [[ -n "$model" ]] || die "CLASSIFIER_MODEL is empty" 1
  [[ "$model" =~ ^[a-zA-Z0-9_.-]+$ ]] \
    || die "invalid CLASSIFIER_MODEL: $model (must match [A-Za-z0-9_.-]+)" 1
}

# invoke_haiku <prompt_file> <output_file> <stderr_file>
#   Shells out to claude CLI with CLASSIFIER_MODEL. Stdin = prompt file,
#   stdout captured to output_file, stderr captured to stderr_file.
#   Classifier is stateless + read-only — all mutation tools disallowed (T-04-01
#   defense-in-depth: even if prompt injection succeeds, the subagent has no
#   write/exec tools).
#   D-07: no `|| true` suffix. Non-zero propagates to caller for die decision.
invoke_haiku() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local model="${CLASSIFIER_MODEL:-claude-haiku-4-5-20251001}"
  local -a cmd
  local -a tool_flags

  tool_flags=(--disallowedTools "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch")

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$model" "${tool_flags[@]}")
  else
    cmd=(claude -p --output-format text --model "$model" "${tool_flags[@]}")
  fi

  "${cmd[@]}" < "$prompt_file" > "$output_file" 2>"$stderr_file"
}

# compose_prompt <prompt_md_path> <out_file>
#   Reads prompt.md, substitutes {TASK}/{BOUNCE_STEP}/{PHASE_TYPE}, writes to out_file.
#   Uses inline bash parameter expansion (agent-bouncer/agent-bouncer.sh:111-119 pattern).
#   Does NOT import fill_template from the lib/ runner helpers (D-05 self-containment).
#
#   T-04-01 defense: the task string is introduced ONLY via ${...//\{TASK\}/$TASK}
#   and then written with printf '%s' — no eval, no concatenation into a command.
compose_prompt() {
  local prompt_md="$1"
  local out_file="$2"
  local template
  template=$(cat "$prompt_md") || die "Cannot read prompt template: $prompt_md" 1
  local filled
  filled="${template//\{TASK\}/$TASK}"
  filled="${filled//\{BOUNCE_STEP\}/$PEL_BOUNCE_STEP}"
  filled="${filled//\{PHASE_TYPE\}/$PEL_PHASE_TYPE}"
  printf "%s" "$filled" > "$out_file"
}

# validate_haiku_response <response_file>
#   Asserts file contains a single JSON object with flavor + rationale fields
#   AND a legal flavor value. Dies exit 3 on any failure (D-07 response-shape
#   category), after dumping first 500 bytes of the response to stderr so a
#   debugging human can see what Haiku emitted.
validate_haiku_response() {
  local response_file="$1"

  command -v jq >/dev/null 2>&1 \
    || die "jq is required to validate Haiku response but is not installed" 2

  # Schema check: must be object with required fields.
  jq -e 'type == "object" and has("flavor") and has("rationale")' "$response_file" >/dev/null 2>&1 || {
    log_stderr "DEBUG: Haiku response head (first 500 bytes):"
    head -c 500 "$response_file" >&2
    printf "\n" >&2
    die "Haiku response was not a valid JSON object matching classifier schema" 3
  }

  # Flavor value check: must be one of the four legal strings.
  local flavor
  flavor=$(jq -r ".flavor" "$response_file")
  case "$flavor" in
    bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
    *)
      die "Haiku returned invalid flavor: $flavor (expected one of bug-catcher, faster-converger, blind-spot-surfacer, general)" 3
      ;;
  esac
}

# emit_classification <flavor> <rationale> <override_bool>
#   Prints canonical classifier JSON to STDOUT using jq -n --arg for safety.
#   This is the ONLY function that writes to stdout (D-08) — everything else
#   in this file routes through log_stderr or dies to stderr.
#
#   jq -n --arg escapes embedded quotes/backslashes in the LLM-generated
#   rationale automatically, so no schema corruption regardless of model output.
emit_classification() {
  local flavor="$1"
  local rationale="$2"
  local is_override="$3"  # "true" or "false" (bash string, converted to JSON bool)

  local override_json
  if [[ "$is_override" == "true" ]]; then
    override_json=true
  else
    override_json=false
  fi

  jq -n \
    --arg flavor "$flavor" \
    --arg rationale "$rationale" \
    --argjson override "$override_json" \
    --arg model "$CLASSIFIER_MODEL" \
    --arg task "$TASK" \
    --arg bounce_step "$PEL_BOUNCE_STEP" \
    --arg phase_type "$PEL_PHASE_TYPE" \
    '{flavor: $flavor, rationale: $rationale, override: $override, model: $model,
      inputs: {task: $task, bounce_step: $bounce_step, phase_type: $phase_type}}'
}

# run_adapter
#   End-to-end Haiku invocation: validate env, compose prompt, call Haiku,
#   validate response, extract fields, emit canonical JSON.
#
#   Assumes caller (classifier.sh) has already:
#     - set TASK, PEL_BOUNCE_STEP, PEL_PHASE_TYPE, CLASSIFIER_MODEL
#     - determined override path is NOT in effect (override handled before adapter runs)
run_adapter() {
  # Validate model string BEFORE ever passing to claude --model (T-04-04).
  validate_classifier_model "$CLASSIFIER_MODEL"

  require_claude_cli

  # Temp file triplet with trap cleanup (mirrors agent-bouncer/agent-bouncer.sh:52-77).
  local prompt_file output_file stderr_file
  prompt_file=$(mktemp -t classifier-prompt-XXXXXX)
  output_file=$(mktemp -t classifier-output-XXXXXX)
  stderr_file=$(mktemp -t classifier-stderr-XXXXXX)

  # shellcheck disable=SC2064
  # Intentional early expansion so the paths are bound at trap-registration
  # time (cleanup must work even if run_adapter dies mid-flight).
  trap "rm -f \"$prompt_file\" \"$output_file\" \"$stderr_file\"" EXIT

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  compose_prompt "$script_dir/prompt.md" "$prompt_file"

  log_stderr "INFO: invoking Haiku (model: $CLASSIFIER_MODEL)"

  # Run Haiku. D-07 fail-fast: no `|| true` — capture exit code, die with
  # distinct category (2) on any non-zero.
  if ! invoke_haiku "$prompt_file" "$output_file" "$stderr_file"; then
    local rc=$?
    if file_contains_auth_failure "$stderr_file"; then
      die "Haiku auth failed; run \"claude login\" and retry" 2
    fi
    log_stderr "DEBUG: Haiku stderr (first 500 bytes):"
    head -c 500 "$stderr_file" >&2
    printf "\n" >&2
    die "Haiku call failed with exit code $rc" 2
  fi

  # T-04-02: response must be valid JSON with legal flavor. Dies exit 3 otherwise.
  validate_haiku_response "$output_file"

  local flavor rationale
  flavor=$(jq -r ".flavor" "$output_file")
  rationale=$(jq -r ".rationale" "$output_file")

  emit_classification "$flavor" "$rationale" "false"
}

# Guard against direct execution.
# If someone runs this file directly (instead of sourcing from classifier.sh),
# print a clear message and exit. This file is a library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf "ERROR: adapter.sh is a library sourced by classifier.sh; do not execute directly\n" >&2
  exit 1
fi
