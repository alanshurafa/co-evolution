# lab/pel/router/adapter.sh

# bash 5.2 enabled `patsub_replacement` by default: an unescaped `&` in the
# REPLACEMENT of ${var//pat/repl} expands to the matched pattern, corrupting
# any substituted document/task content containing `&`. Restore the literal
# pre-5.2 semantics everywhere this file's substitutions run. (No-op on
# older bash, hence the guard.)
shopt -u patsub_replacement 2>/dev/null || true
# Co-Evolution PEL Router — Haiku adapter (Phase v1.3-adaptive).
#
# SELF-CONTAINED per Phase 4 D-05 pattern: zero import of co-evolution runner
# helpers, classifier subtree, or other proposer adapters. All helpers inline
# so lab/pel/router/** is a clean self-contained subtree.
#
# Sourced by router.sh; not executed standalone.
#
# Required env when run_adapter is called (router.sh sets these):
#   TARGET                    target file path
#   PEL_TIER                  template|policy|code
#   PEL_FLAVOR                bug-catcher|faster-converger|blind-spot-surfacer|general
#   ROUTER_MODEL              Haiku model ID (default: claude-haiku-4-5-20251001)
#
# Stdout contract: raw JSON object {complexity, rationale} from Haiku.
# Stderr: diagnostics only.

# Default ROUTER_MODEL to Haiku 4.5 (mirrors classifier model choice).
: "${ROUTER_MODEL:=claude-haiku-4-5-20251001}"

# Inline die() — matches classifier/adapter.sh:13-17 semantics.
die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

# Inline log_stderr() — stdout reserved for JSON.
log_stderr() {
  printf "%s\n" "$1" >&2
}

# require_claude_cli — mirrors classifier/adapter.sh require_claude_cli.
# Under WSL, probe via cmd.exe since WSL and Windows keep separate auth state.
# On MINGW (Git Bash on Windows), the native `claude` is on PATH and works
# directly — also lets PATH-injected stubs in tests get picked up.
require_claude_cli() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c claude --version >/dev/null 2>&1 \
      || die "claude CLI (Windows side, via cmd.exe) is required but not installed or not authenticated" 2
  else
    command -v claude >/dev/null 2>&1 \
      || die "claude CLI is required but not installed" 2
  fi
}

# strip_markdown_fences <response_file>
#   Edits response_file IN PLACE: strip markdown fence wrappers if present.
#   Mirrors lab/pel/classifier/adapter.sh::strip_markdown_fences (defense
#   against Haiku emitting fenced JSON despite prompt instructions).
strip_markdown_fences() {
  local file="$1"
  head -n 1 "$file" 2>/dev/null | grep -q '^```' || return 0
  local tmp
  tmp=$(mktemp -t router-stripped-XXXXXX)
  sed '/^```[a-zA-Z0-9_-]*[[:space:]]*$/d' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# run_adapter
#   Invokes Haiku with the prompt template + context vars, writes raw response
#   to stdout. Caller (router.sh) handles fence-stripping and JSON parsing.
#
#   Required env (caller sets these):
#     TARGET, PEL_TIER, PEL_FLAVOR, TARGET_SIZE_BYTES, ROUTER_MODEL
run_adapter() {
  require_claude_cli

  local prompt_file output_file stderr_file
  prompt_file=$(mktemp -t router-prompt-XXXXXX)
  output_file=$(mktemp -t router-output-XXXXXX)
  stderr_file=$(mktemp -t router-stderr-XXXXXX)

  # shellcheck disable=SC2064
  trap "rm -f \"$prompt_file\" \"$output_file\" \"$stderr_file\"" RETURN

  # Render prompt by substituting template vars.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local template
  template=$(cat "$script_dir/prompt.md")
  local rendered
  rendered="${template//\{PEL_TIER\}/$PEL_TIER}"
  rendered="${rendered//\{TARGET\}/$TARGET}"
  rendered="${rendered//\{TARGET_SIZE_BYTES\}/$TARGET_SIZE_BYTES}"
  rendered="${rendered//\{PEL_FLAVOR\}/$PEL_FLAVOR}"
  printf "%s" "$rendered" > "$prompt_file"

  log_stderr "INFO: invoking router Haiku (model: $ROUTER_MODEL)"

  local cmd
  # Same WSL-only branch as require_claude_cli — keeps PATH-injected test
  # stubs working on MINGW (Git Bash on Windows).
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1; then
    cmd=(cmd.exe /c claude -p --output-format text --model "$ROUTER_MODEL" --tools "")
  else
    cmd=(claude -p --output-format text --model "$ROUTER_MODEL" --tools "")
  fi

  # Run Haiku. On failure, return non-zero so caller can take fallback path.
  if ! "${cmd[@]}" < "$prompt_file" > "$output_file" 2> "$stderr_file"; then
    log_stderr "ERROR: Haiku call failed; stderr: $(head -c 500 "$stderr_file")"
    return 1
  fi

  # Strip fences, then emit response on stdout.
  strip_markdown_fences "$output_file"
  cat "$output_file"
}
