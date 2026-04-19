#!/usr/bin/env bash
# lab/pel/pr-emitter/pr-emitter.sh
# Phase 8 Plan 01 — PR emitter skeleton.
#
# Usage (invoked via wrapper — co-evolve --lab pel-proposer OR dev-review --lab pel-proposer):
#   pr-emitter.sh --target FILE [--tier TIER] [--pr-branch NAME] [--dry-run]
#                 [--budget USD] [--yes] [--flavor NAME] [-- TASK]
#
# Argv (forwarded by the wrapper's dispatch_lab_mode rebuild):
#   --target FILE      file to mutate (required)
#   --tier TIER        override tier auto-detect (template|policy|code)
#   --pr-branch NAME   override default pel/<tier>/<short-hash> branch name
#   --dry-run          stub gh via CO_EVOLVE_DRY_RUN=1 + PATH shadow
#   --budget USD       scoring budget cap (default 25; exit 6 on exhaustion)
#   --yes              skip interactive preflight cost-estimate prompt
#   --flavor NAME      override classifier (maps to PEL_FLAVOR_OVERRIDE)
#   --                 argv terminator; $TASK follows as single positional
#
# Env vars honored:
#   CO_EVOLVE_DRY_RUN=1    equivalent to --dry-run (wrapper sets this)
#   PEL_FLAVOR_OVERRIDE    classifier override (Plan 02 wires this)
#   TMPDIR                 sandbox + dry-stub location (defaults to /tmp)
#
# Output (Plan 02):
#   stdout: draft PR URL from gh pr create (or dry-run stub URL)
#   stderr: progress + rationale logs
#
# Output (Plan 01 skeleton):
#   stderr marker: "INFO: scoring not implemented yet (Plan 02)"
#   exit 0 (so Plan 02 replaces the stub linearly)
#
# Exit codes (D-17 taxonomy — extends Phase 7's 0-8 with 9 and 10):
#   0  success (PR draft created; or Plan 01 skeleton scoring stub)
#   1  input validation failure (missing --target, bad --tier override, etc.)
#   2  classifier or proposer propagated exit 2 (CLI/auth)
#   3  malformed diff propagated from proposer
#   4  multi-file violation propagated from proposer
#   5  allowlist violation propagated from proposer
#   6  EMITTER eval budget exhausted during scoring (distinct from proposer's
#      DIFF_BUDGET exit 6 — log message disambiguates)
#   7  canary-failed PR created as [CANARY-FAILED] diagnostic (D-15)
#   8  sandbox setup failed (either proposer's or emitter's)
#   9  NEW: gh pr create failed post-scoring (D-17)
#  10  NEW: tier auto-detect hard-error — ambiguous, no-match, or mixed-tier
#      glob (D-17)
#
# Self-containment invariant (D-07): zero source/import of lib/co-evolution.sh,
# classifier, or any proposer's internals. Cross-module communication happens
# via documented stdout contracts (proposer diff -> emitter) and filesystem
# handoffs (proposer state.json -> emitter reads before cleanup). Per D-06,
# the two-file module is pr-emitter.sh + pr-body-template.md — no sibling
# adapter is required because there is NO LLM call.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# pr-emitter -> pel -> lab -> REPO_ROOT (3 levels)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ---------------------------------------------------------------------------
# Inline helpers (D-07 self-containment — do NOT source lib/co-evolution.sh)
# ---------------------------------------------------------------------------

die() {
  printf "ERROR: %s\n" "${1:-Fatal error}" >&2
  exit "${2:-1}"
}

log_stderr() {
  printf "%s\n" "$1" >&2
}

# ---------------------------------------------------------------------------
# Argv parsing — own copy of the 7 flags (dispatch exec'd us directly, not
# through co-evolve-bouncer's parser). Defaults + parser follow the same
# shape as the wrapper edits in Task 2.
# ---------------------------------------------------------------------------

TARGET=""
TIER=""
PR_BRANCH=""
DRY_RUN=false
BUDGET_USD="25"
AUTO_YES=false
FLAVOR_OVERRIDE=""
TASK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -gt 1 ]] || die "--target requires a value" 1
      TARGET="$2"
      shift 2
      ;;
    --tier)
      [[ $# -gt 1 ]] || die "--tier requires a value" 1
      case "$2" in
        template|policy|code) TIER="$2" ;;
        *) die "--tier must be template|policy|code (got: $2)" 1 ;;
      esac
      shift 2
      ;;
    --pr-branch)
      [[ $# -gt 1 ]] || die "--pr-branch requires a value" 1
      PR_BRANCH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --budget)
      [[ $# -gt 1 ]] || die "--budget requires a value" 1
      [[ "$2" =~ ^[0-9]+$ ]] || die "--budget must be a positive integer (got: $2)" 1
      BUDGET_USD="$2"
      shift 2
      ;;
    --yes)
      AUTO_YES=true
      shift
      ;;
    --flavor)
      [[ $# -gt 1 ]] || die "--flavor requires a value" 1
      case "$2" in
        bug-catcher|faster-converger|blind-spot-surfacer|general) FLAVOR_OVERRIDE="$2" ;;
        *) die "--flavor must be one of bug-catcher|faster-converger|blind-spot-surfacer|general (got: $2)" 1 ;;
      esac
      shift 2
      ;;
    --)
      shift
      TASK="$*"
      break
      ;;
    -*)
      die "unknown flag: $1" 1
      ;;
    *)
      if [[ -z "$TASK" ]]; then
        TASK="$1"
      else
        TASK="$TASK $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || die "--target is required for --lab pel-proposer" 1

# ---------------------------------------------------------------------------
# detect_tier — D-04 rule table. Fail-closed on ambiguous / no-match / mixed-
# tier globs (exit 10). See .planning/phases/08-pr-emitter-scoring/08-PATTERNS.md
# §"Tier auto-detect rule table" for the binding rule table.
# ---------------------------------------------------------------------------

detect_tier() {
  local target="$1"
  case "$target" in
    skills/dev-review/templates/*.md|tests/fixtures/templates/*.md)
      printf 'template'
      return 0 ;;
    lab/pel/proposer/policy/policy.yaml)
      printf 'policy'
      return 0 ;;
  esac
  # Code-tier: exact-line match in allowlist.txt
  if grep -Fxq "$target" "$REPO_ROOT/lab/pel/proposer/code/allowlist.txt"; then
    printf 'code'
    return 0
  fi
  die "tier auto-detect: no rule matches '$target' (D-04 hard-error)" 10
}

# ---------------------------------------------------------------------------
# Resolve tier — if $TIER is set (override), log and use it; otherwise call
# detect_tier. Make the auto-detect failure explicit so exit 10 propagates.
# ---------------------------------------------------------------------------

if [[ -n "$TIER" ]]; then
  auto_tier="$(detect_tier "$TARGET" 2>/dev/null)" || auto_tier="(n/a, would be hard-error)"
  log_stderr "tier override: $TIER (auto-detect would have been: $auto_tier)"
  resolved_tier="$TIER"
else
  resolved_tier="$(detect_tier "$TARGET")" || exit $?
fi
log_stderr "INFO: resolved tier: $resolved_tier for target $TARGET"

# ---------------------------------------------------------------------------
# PATH-shadowed gh stub (dry-run posture). Scaffolded in Plan 01; Plan 02
# will extend this path to actually run scoring + gh pr create through it.
#
# Reference pattern: lab/pel/proposer/code/canary.sh:44-78 (PATH-injected stubs
# for claude + codex). Same posture here for gh.
# ---------------------------------------------------------------------------

if [[ "$DRY_RUN" == "true" || "${CO_EVOLVE_DRY_RUN:-}" == "1" ]]; then
  export CO_EVOLVE_DRY_RUN=1
  DRY_STUB_BIN=$(mktemp -d -t co-evolve-dry-XXXXXX)
  cat > "$DRY_STUB_BIN/gh" <<'DRYSTUB'
#!/usr/bin/env bash
# PATH-shadowed gh stub for --dry-run.
printf 'DRY-RUN: gh %s\n' "$*" >&2
if [[ ! -t 0 ]]; then cat >&2; fi
printf 'https://github.com/REPO/pull/0 (dry-run stub)\n'
DRYSTUB
  chmod +x "$DRY_STUB_BIN/gh"
  export PATH="$DRY_STUB_BIN:$PATH"
  # Cleanup on exit — Plan 02 will extend this.
  trap 'rm -rf "$DRY_STUB_BIN" 2>/dev/null || true' EXIT
  log_stderr "INFO: --dry-run active — gh stubbed at $DRY_STUB_BIN/gh"
fi

# ---------------------------------------------------------------------------
# Scoring stub (Plan 01 ends here)
#
# Plan 01: scoring + PR body rendering + gh pr create are Plan 02's scope.
# Emit a marker so live smoke confirms dispatch + argv parsing + tier detect
# work, and Plan 02 replaces this block with real scoring + emission.
# ---------------------------------------------------------------------------

log_stderr "INFO: scoring not implemented yet (Plan 02)"
log_stderr "  target=$TARGET tier=$resolved_tier dry_run=$DRY_RUN budget=\$$BUDGET_USD flavor_override=${FLAVOR_OVERRIDE:-<none>}"
exit 0
