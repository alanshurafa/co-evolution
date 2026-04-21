# lab/pel/router/adapter.sh
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
require_claude_cli() {
  if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" == "MINGW"* ]]; then
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

# Placeholder run_adapter — Task 3 will fill this in.
# This skeleton just exists so router.sh can source and reference run_adapter
# without exploding during Task 1's commit.
run_adapter() {
  die "run_adapter not yet implemented (Task 3)" 99
}
