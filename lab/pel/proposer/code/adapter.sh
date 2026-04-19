# lab/pel/proposer/code/adapter.sh
# Co-Evolution PEL Code-Tier Mutation Proposer — Opus adapter (Phase 7 PEL-04).
#
# SELF-CONTAINED per D-12: no source/import of lib/co-evolution.sh,
# lab/pel/classifier, lab/pel/proposer/template, lab/pel/proposer/policy, or
# any other directory outside lab/pel/proposer/code/. All helpers are defined
# inline so lab/pel/proposer/code/** is a clean sibling-isolated module.
#
# Sourced by proposer.sh; not executed standalone.
#
# Required env when run_adapter is called (proposer.sh sets these):
#   TASK_HINT                optional task hint (may be empty per D-18)
#   PEL_FLAVOR               bug-catcher|faster-converger|blind-spot-surfacer|general
#   PEL_CODE_FEEDBACK        canonical absolute path to readable eval-failure JSON
#   PEL_CODE_TARGET_ABS      canonical absolute path to target shell file
#   PEL_CODE_TARGET          repo-root-relative form of the code path (used in diff headers)
#   CODE_PROPOSER_MODEL      Opus model ID (validated by validate_proposer_model)
#   DIFF_BUDGET              integer line budget (default 20 per D-06)
#
# Stdout contract: raw diff bytes captured from Opus (proposer.sh runs the
# D-07 pre-flight gates + sandbox + canary).
# Stderr: diagnostics only.

# Default CODE_PROPOSER_MODEL to Opus 4.7 per D-11 (overrideable via env).
: "${CODE_PROPOSER_MODEL:=claude-opus-4-7}"

# Default DIFF_BUDGET per D-06 (proposer.sh also sets this; belt-and-suspenders).
: "${DIFF_BUDGET:=20}"

# Inline die() — matches the runner-helper die() semantics but stays local so
# D-12 self-containment holds. Second arg is optional exit code (default 1).
# Callers pass distinct exit categories per D-21.
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

# Inline log_stderr() for stderr diagnostics — stdout is reserved for diff
# output per D-19.
log_stderr() {
  printf "%s\n" "$1" >&2
}

# CLI availability check — shape mirrors the sibling-tier adapter's pattern
# (re-implemented inline; NOT imported — D-12 self-containment).
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

# Auth-failure regex — semantic twin of the runner helper's equivalent regex
# (re-implemented inline here so D-12 self-containment holds; NOT imported).
# Returns 0 if file exists AND contains an auth-failure marker.
file_contains_auth_failure() {
  local file_path="$1"
  [[ -s "$file_path" ]] || return 1
  grep -qiE "Failed to authenticate|authentication_error|Not authenticated|Unauthorized|login required|Please run .* login" "$file_path"
}

# CODE_PROPOSER_MODEL validator — T-07-03 mitigation. Rejects shell
# metacharacters BEFORE the value is ever passed to claude --model. Allowed
# charset is the superset of current and future Anthropic model IDs (letters,
# digits, dots, hyphens, underscores).
validate_proposer_model() {
  local model="$1"
  [[ -n "$model" ]] || die "CODE_PROPOSER_MODEL is empty" 1
  [[ "$model" =~ ^[a-zA-Z0-9_.-]+$ ]] \
    || die "invalid CODE_PROPOSER_MODEL: $model (must match [A-Za-z0-9_.-]+)" 1
}

# compose_prompt <prompt_md_path> <eval_report_file> <code_file> <out_file>
#   Reads prompt.md, substitutes the 6 placeholders {TASK_HINT}, {FLAVOR},
#   {CODE_TARGET}, {CODE_CONTENT}, {EVAL_REPORT_JSON}, {DIFF_BUDGET} via bash
#   parameter expansion, writes composed prompt to out_file. Does NOT import
#   fill_template from the lib/ runner helpers (D-12 self-containment).
#
#   T-07-04 defense: eval report bytes and code bytes are introduced ONLY via
#   ${...//\{PLACEHOLDER\}/$value} parameter expansion and then written with
#   printf '%s' — no eval, no concatenation into a command, no shell re-parsing
#   of the data content.
compose_prompt() {
  local prompt_md="$1"
  local eval_report_file="$2"
  local code_file="$3"
  local out_file="$4"
  local template
  template=$(cat "$prompt_md") || die "Cannot read prompt template: $prompt_md" 1

  local eval_report_content
  eval_report_content=$(cat "$eval_report_file") || die "Cannot read eval report: $eval_report_file" 1

  local code_content
  code_content=$(cat "$code_file") || die "Cannot read target code file: $code_file" 1

  local filled
  filled="${template//\{TASK_HINT\}/$TASK_HINT}"
  filled="${filled//\{FLAVOR\}/$PEL_FLAVOR}"
  filled="${filled//\{CODE_TARGET\}/$PEL_CODE_TARGET}"
  filled="${filled//\{DIFF_BUDGET\}/$DIFF_BUDGET}"
  filled="${filled//\{EVAL_REPORT_JSON\}/$eval_report_content}"
  filled="${filled//\{CODE_CONTENT\}/$code_content}"
  printf "%s" "$filled" > "$out_file"
}

# invoke_opus <prompt_file> <output_file> <stderr_file>
#   Shells out to claude CLI with CODE_PROPOSER_MODEL. Stdin = prompt file,
#   stdout captured to output_file, stderr captured to stderr_file.
#   Proposer is stateless + read-only — all mutation tools disallowed
#   (T-07-04 defense-in-depth: even if prompt injection succeeds, the subagent
#   has no write/exec tools).
#   D-14: no `|| true` suffix. Non-zero propagates to caller for die decision.
invoke_opus() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local model="${CODE_PROPOSER_MODEL:-claude-opus-4-7}"
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

# capture_diff <output_file>
#   Echoes the raw file contents to stdout (trimmed of leading/trailing blank
#   lines). Does NOT validate diff shape here — that's proposer.sh's job (D-07
#   gate chain runs in proposer.sh for clean separation of adapter (I/O) vs
#   orchestrator (policy)).
#
#   T-07-04 defense: output is treated as opaque bytes; there is no eval, no
#   command substitution on the content. Proposer.sh's git apply --check and
#   canary are the trusted gates.
capture_diff() {
  local output_file="$1"
  # Emit raw content with leading/trailing TRULY-EMPTY lines trimmed via awk.
  # CRITICAL: the regex must be ^$ (empty only), NOT ^[[:space:]]*$ — in a
  # unified diff a context line representing an originally-empty line in the
  # file appears as a single space + newline. That line IS whitespace-only but
  # it's meaningful hunk content; trimming it breaks the hunk line count and
  # `git apply` rejects with "corrupt patch at line N". A truly empty line
  # (no leading space at all) never legitimately appears in a unified diff
  # hunk body, so only trimming those is safe.
  awk '
    BEGIN { started = 0 }
    {
      if (!started) {
        if ($0 ~ /^$/) next
        started = 1
      }
      buf[NR] = $0
      last = NR
    }
    END {
      # Trim trailing truly-empty lines (see CRITICAL note above).
      while (last > 0 && buf[last] ~ /^$/) last--
      for (i = 1; i <= last; i++) {
        if (i in buf) print buf[i]
      }
    }
  ' "$output_file"
}

# run_adapter
#   End-to-end Opus invocation: validate model, require CLI, compose prompt,
#   call Opus, check for auth failure, validate response non-empty, echo raw
#   diff to stdout for proposer.sh to capture + validate via D-07 gates.
#
#   Assumes caller (proposer.sh) has already:
#     - set TASK_HINT, PEL_FLAVOR, PEL_CODE_FEEDBACK (canonical abs),
#       PEL_CODE_TARGET_ABS (canonical abs), PEL_CODE_TARGET (repo-rel),
#       DIFF_BUDGET
#     - validated all env vars are present + paths are sandboxed
#     - validated PEL_CODE_TARGET is on allowlist.txt
#     - called validate_proposer_model "$CODE_PROPOSER_MODEL" already
#       (proposer.sh runs this immediately after sourcing to cover both paths)
run_adapter() {
  # Belt-and-suspenders: validate model again in case run_adapter is invoked
  # without the pre-source validation step. T-07-03 defense.
  validate_proposer_model "$CODE_PROPOSER_MODEL"

  require_claude_cli

  # Temp file triplet with trap cleanup.
  local prompt_file output_file stderr_file
  prompt_file=$(mktemp -t proposer-code-prompt-XXXXXX)
  output_file=$(mktemp -t proposer-code-output-XXXXXX)
  stderr_file=$(mktemp -t proposer-code-stderr-XXXXXX)

  # shellcheck disable=SC2064
  # Intentional early expansion so the paths are bound at trap-registration
  # time (cleanup must work even if run_adapter dies mid-flight).
  trap "rm -f \"$prompt_file\" \"$output_file\" \"$stderr_file\"" EXIT

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Compose the prompt: reads content from PEL_CODE_TARGET_ABS (canonical)
  # and substitutes PEL_CODE_TARGET into the {CODE_TARGET} placeholder so the
  # emitted diff uses the repo-relative path.
  compose_prompt "$script_dir/prompt.md" "$PEL_CODE_FEEDBACK" "$PEL_CODE_TARGET_ABS" "$prompt_file"

  log_stderr "INFO: invoking Opus code-tier proposer (model: $CODE_PROPOSER_MODEL, flavor: $PEL_FLAVOR, budget: $DIFF_BUDGET)"

  # Run Opus. D-14 fail-fast: no `|| true` — capture exit code, die with
  # distinct category (2) on any non-zero.
  if ! invoke_opus "$prompt_file" "$output_file" "$stderr_file"; then
    local rc=$?
    if file_contains_auth_failure "$stderr_file"; then
      die "Opus auth failed; run \"claude login\" and retry" 2
    fi
    log_stderr "DEBUG: Opus stderr (first 500 bytes):"
    head -c 500 "$stderr_file" >&2
    printf "\n" >&2
    die "Opus call failed with exit code $rc" 2
  fi

  # Output file must be non-empty (silence from Opus = treat as CLI failure).
  if [[ ! -s "$output_file" ]]; then
    log_stderr "DEBUG: Opus stderr (first 500 bytes):"
    head -c 500 "$stderr_file" >&2
    printf "\n" >&2
    die "Opus returned an empty response" 2
  fi

  # Emit raw diff to stdout. proposer.sh captures this via command
  # substitution and runs the D-07 pre-flight gate chain (parse -> single-file
  # -> allowlist -> budget -> git apply --check) followed by sandbox + canary.
  capture_diff "$output_file"
}

# Guard against direct execution.
# If someone runs this file directly (instead of sourcing from proposer.sh),
# print a clear message and exit. This file is a library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf "ERROR: adapter.sh is a library sourced by proposer.sh; do not execute directly\n" >&2
  exit 1
fi
