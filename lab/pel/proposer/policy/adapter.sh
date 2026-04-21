# lab/pel/proposer/policy/adapter.sh
# Co-Evolution PEL Policy-Tier Mutation Proposer — Haiku adapter (Phase 6 PEL-03).
#
# SELF-CONTAINED per D-08: no import of lib/co-evolution.sh. All helpers are
# defined inline so lab/pel/proposer/policy/** is a clean Phase 7 allowlist-
# exclusion glob.
#
# Does NOT import fill_template from the lib/ runner helpers — self-containment
# mirrors the Phase 4 classifier precedent.
#
# Sourced by proposer.sh; not executed standalone.
#
# Required env when run_adapter is called (proposer.sh sets these):
#   TASK_HINT                 optional task hint (from $1 in proposer.sh; may be empty)
#   PEL_FEEDBACK              path to eval-failure JSON
#   PEL_POLICY_PATH           path to target policy YAML
#   PEL_FLAVOR                one of bug-catcher|faster-converger|blind-spot-surfacer|general
#   POLICY_PROPOSER_MODEL     Haiku model ID (validated by validate_proposer_model)

# Inline die() — matches lib/co-evolution.sh:13-17 semantics but stays local.
# Second arg optional (default 1) so callers can signal distinct fail-fast
# categories per D-09 (1=input, 2=cli/auth, 3=response shape, 4/5=bounds).
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

# Inline log_stderr() for stderr diagnostics — stdout stays reserved for JSON (D-10).
log_stderr() {
  printf "%s\n" "$1" >&2
}

# CLI availability check (mirrors Phase 4 D-05 pattern).
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

# POLICY_PROPOSER_MODEL validator — T-06-03 mitigation. Rejects shell
# metacharacters BEFORE the value is ever passed to claude --model. Allowed
# charset is the superset of current and future Anthropic model IDs.
validate_proposer_model() {
  local model="$1"
  [[ -n "$model" ]] || die "POLICY_PROPOSER_MODEL is empty" 1
  [[ "$model" =~ ^[a-zA-Z0-9_.-]+$ ]] \
    || die "invalid POLICY_PROPOSER_MODEL: $model (must match [A-Za-z0-9_.-]+)" 1
}

# invoke_haiku <prompt_file> <output_file> <stderr_file>
#   Shells out to claude CLI with POLICY_PROPOSER_MODEL. Stdin = prompt file,
#   stdout captured to output_file, stderr captured to stderr_file.
#
#   Proposer is stateless + read-only — all mutation tools disallowed
#   (T-06-01 defense-in-depth: even if prompt injection succeeds, the subagent
#   has no write/exec tools).
#
#   D-09: no `|| true` suffix. Non-zero propagates to caller for die decision.
invoke_haiku() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local model="${POLICY_PROPOSER_MODEL:-claude-haiku-4-5-20251001}"
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
#   Reads prompt.md, substitutes {POLICY_YAML}/{EVAL_FEEDBACK}/{FLAVOR} with the
#   contents of the caller-supplied files + flavor string. Writes to out_file.
#
#   Uses inline bash parameter expansion (never eval). T-06-01 defense: untrusted
#   inputs (PEL_FEEDBACK contents, PEL_POLICY_PATH contents, PEL_FLAVOR) are
#   introduced ONLY via ${template//\{TOKEN\}/$VALUE} and then written with
#   printf '%s' — no shell expansion downstream.
compose_prompt() {
  local prompt_md="$1"
  local out_file="$2"
  local template
  template=$(cat "$prompt_md") || die "Cannot read prompt template: $prompt_md" 1

  local policy_body feedback_body
  policy_body=$(cat "$PEL_POLICY_PATH")   || die "Cannot read PEL_POLICY_PATH: $PEL_POLICY_PATH" 1
  feedback_body=$(cat "$PEL_FEEDBACK")    || die "Cannot read PEL_FEEDBACK: $PEL_FEEDBACK" 1

  local filled
  filled="${template//\{POLICY_YAML\}/$policy_body}"
  filled="${filled//\{EVAL_FEEDBACK\}/$feedback_body}"
  filled="${filled//\{FLAVOR\}/$PEL_FLAVOR}"

  # Optional task-hint suffix (only when the caller passed a non-empty $1)
  if [[ -n "${TASK_HINT:-}" ]]; then
    filled="${filled}

Additional task hint from caller: ${TASK_HINT}"
  fi

  printf "%s" "$filled" > "$out_file"
}

# validate_delta_response <response_file>
#   Asserts the response contains a single JSON object with the D-10 delta
#   schema: mutations[] (length 1..3), each with string .key + present .new;
#   non-empty .rationale; .flavor matching $PEL_FLAVOR; .policy_path matching
#   $PEL_POLICY_PATH.
#
#   Dies exit 3 on any schema failure after dumping first 500 bytes of the
#   response to stderr so a debugging human can see what Haiku emitted.
validate_delta_response() {
  local response_file="$1"

  command -v jq >/dev/null 2>&1 \
    || die "jq is required to validate Haiku response but is not installed" 2

  # Top-level schema. Bug #9 fix: flavor + policy_path are known to the caller
  # (PEL_FLAVOR, PEL_POLICY_PATH env vars) so they're optional in Haiku's output.
  # If Haiku returns them they must match (validation below); if Haiku omits
  # them, emit_delta injects the env-var values.
  jq -e 'type == "object" and has("mutations") and has("rationale")' "$response_file" >/dev/null 2>&1 || {
    log_stderr "DEBUG: Haiku response head (first 500 bytes):"
    head -c 500 "$response_file" >&2
    printf "\n" >&2
    die "Haiku response missing required top-level fields (mutations, rationale)" 3
  }

  # mutations: array length 1..3.
  jq -e '.mutations | type == "array" and (length >= 1) and (length <= 3)' "$response_file" >/dev/null 2>&1 || {
    log_stderr "DEBUG: Haiku response head (first 500 bytes):"
    head -c 500 "$response_file" >&2
    printf "\n" >&2
    die "Haiku response .mutations must be an array of length 1..3" 3
  }

  # Each mutation has string .key and a .new field present.
  jq -e '.mutations | all((.key | type == "string") and has("new"))' "$response_file" >/dev/null 2>&1 || {
    log_stderr "DEBUG: Haiku response head (first 500 bytes):"
    head -c 500 "$response_file" >&2
    printf "\n" >&2
    die "Haiku response .mutations[*] must each have a string .key and a .new field" 3
  }

  # Non-empty rationale.
  jq -e '.rationale | type == "string" and length > 0' "$response_file" >/dev/null 2>&1 \
    || die "Haiku response .rationale must be a non-empty string" 3

  # flavor: optional in Haiku output. If present, must be a legal token AND
  # match PEL_FLAVOR verbatim. If absent, emit_delta injects PEL_FLAVOR.
  if jq -e 'has("flavor")' "$response_file" >/dev/null 2>&1; then
    local flavor
    flavor=$(jq -r ".flavor" "$response_file")
    case "$flavor" in
      bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
      *)
        die "Haiku returned invalid flavor: $flavor (expected one of bug-catcher, faster-converger, blind-spot-surfacer, general)" 3
        ;;
    esac
    if [[ "$flavor" != "$PEL_FLAVOR" ]]; then
      die "Haiku returned flavor=$flavor but PEL_FLAVOR=$PEL_FLAVOR; values must match" 3
    fi
  else
    log_stderr "INFO: Haiku omitted .flavor; will inject PEL_FLAVOR=$PEL_FLAVOR"
  fi

  # policy_path: optional. If present, must match PEL_POLICY_PATH.
  if jq -e 'has("policy_path")' "$response_file" >/dev/null 2>&1; then
    local echoed_policy
    echoed_policy=$(jq -r ".policy_path" "$response_file")
    if [[ "$echoed_policy" != "$PEL_POLICY_PATH" ]]; then
      die "Haiku returned policy_path=$echoed_policy but PEL_POLICY_PATH=$PEL_POLICY_PATH; values must match" 3
    fi
  else
    log_stderr "INFO: Haiku omitted .policy_path; will inject PEL_POLICY_PATH=$PEL_POLICY_PATH"
  fi
}

# emit_delta <response_file>
#   Reads the validated response, pipes through `jq -c .` for canonical
#   single-line JSON. This is the ONLY function that writes to stdout
#   (D-10) — everything else routes through log_stderr or dies to stderr.
emit_delta() {
  local response_file="$1"
  # Bug #9 fix: inject flavor + policy_path from env when Haiku omitted them.
  # validate_response() already guaranteed any present values match env vars,
  # so injecting is always safe and keeps the downstream delta shape stable.
  jq -c --arg flavor "$PEL_FLAVOR" --arg policy_path "$PEL_POLICY_PATH" \
    '. + {flavor: (.flavor // $flavor), policy_path: (.policy_path // $policy_path)}' \
    "$response_file"
}

# run_adapter
#   End-to-end orchestration: validate model, require claude CLI, compose
#   prompt, call Haiku, validate response, emit delta to stdout.
#
#   Assumes caller (proposer.sh) has already:
#     - validated PEL_FEEDBACK, PEL_POLICY_PATH, PEL_FLAVOR envs
#     - validated both paths are readable and inside REPO_ROOT
#     - set POLICY_PROPOSER_MODEL (default claude-haiku-4-5-20251001)
run_adapter() {
  # Validate model string BEFORE ever passing to claude --model (T-06-03).
  validate_proposer_model "$POLICY_PROPOSER_MODEL"

  require_claude_cli

  # Temp file triplet with trap cleanup (mirrors Phase 4 classifier adapter).
  local prompt_file output_file stderr_file
  prompt_file=$(mktemp -t policy-prompt-XXXXXX)
  output_file=$(mktemp -t policy-output-XXXXXX)
  stderr_file=$(mktemp -t policy-stderr-XXXXXX)

  # shellcheck disable=SC2064
  # Intentional early expansion so the paths are bound at trap-registration time.
  trap "rm -f \"$prompt_file\" \"$output_file\" \"$stderr_file\"" EXIT

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  compose_prompt "$script_dir/prompt.md" "$prompt_file"

  log_stderr "INFO: invoking Haiku (model: $POLICY_PROPOSER_MODEL, flavor: $PEL_FLAVOR)"

  # Run Haiku. D-09 fail-fast: no `|| true` — capture exit code, die with
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

  # Response must be valid JSON matching D-10 schema. Dies exit 3 otherwise.
  validate_delta_response "$output_file"

  # Emit canonical single-line JSON to stdout (D-10).
  emit_delta "$output_file"
}

# Guard against direct execution.
# If someone runs this file directly (instead of sourcing from proposer.sh),
# print a clear message and exit. This file is a library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf "ERROR: adapter.sh is a library sourced by proposer.sh; do not execute directly\n" >&2
  exit 1
fi
