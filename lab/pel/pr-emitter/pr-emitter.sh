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
# Section A.0: PEL invocation start time (consumed by Section K telemetry).
# Use ms-resolution if available; fall back to seconds*1000 for portability.
# ---------------------------------------------------------------------------
PEL_START_MS=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")

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
# TODO(v1.3): --yes parsed but not consumed yet — the interactive preflight
# cost-estimate prompt is deferred. Keep the flag plumbed through dev-review
# and co-evolve-bouncer so the v1.2 surface stays stable; wire it when the
# prompt lands in v1.3. Tracked by WR-01 from Phase 8 REVIEW.md.
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

# ---------------------------------------------------------------------------
# Cleanup registry — Plan 02 chains multiple cleanup steps (dry-stub,
# emitter workdir, emitter scoring sandbox). We register a single EXIT trap
# that invokes the accumulated cleanup function.
# ---------------------------------------------------------------------------
DRY_STUB_BIN=""
EMITTER_WORKDIR=""
EMITTER_SANDBOX=""
EMITTER_BODY_FILE=""
# WR-06: track branch name that was created so dry-run cleanup can delete it.
# Real runs (non-dry) keep the branch so `gh pr create` has something to point
# at; only dry-run leaves a branch that would otherwise orphan.
BRANCH_CREATED=""

emitter_cleanup_all() {
  # Order: sandbox (git worktree remove) → workdir → dry-stub → body-file.
  if [[ -n "$EMITTER_SANDBOX" && -d "$EMITTER_SANDBOX" ]]; then
    "${REAL_GIT:-git}" -C "$REPO_ROOT" worktree remove --force "$EMITTER_SANDBOX" 2>/dev/null || true
    rm -rf "$EMITTER_SANDBOX" 2>/dev/null || true
  fi
  [[ -n "$EMITTER_WORKDIR" ]] && rm -rf "$EMITTER_WORKDIR" 2>/dev/null || true
  [[ -n "$DRY_STUB_BIN"   ]] && rm -rf "$DRY_STUB_BIN"   2>/dev/null || true
  [[ -n "$EMITTER_BODY_FILE" && -f "$EMITTER_BODY_FILE" ]] && rm -f "$EMITTER_BODY_FILE" 2>/dev/null || true
  # WR-06: drop the branch ref on dry-run so user invocations don't pollute
  # refs/heads/pel/<tier>/<hash> over time. Real runs keep the branch.
  if [[ -n "$BRANCH_CREATED" && "${CO_EVOLVE_DRY_RUN:-}" == "1" ]]; then
    "${REAL_GIT:-git}" -C "$REPO_ROOT" branch -D "$BRANCH_CREATED" >/dev/null 2>&1 || true
  fi
}
trap emitter_cleanup_all EXIT

if [[ "$DRY_RUN" == "true" || "${CO_EVOLVE_DRY_RUN:-}" == "1" ]]; then
  export CO_EVOLVE_DRY_RUN=1
  DRY_STUB_BIN=$(mktemp -d -t co-evolve-dry-XXXXXX)
  cat > "$DRY_STUB_BIN/gh" <<'DRYSTUB'
#!/usr/bin/env bash
# PATH-shadowed gh stub for --dry-run.
printf 'DRY-RUN: gh %s\n' "$*" >&2
# Log full argv to GH_ARGS_MARKER BEFORE any shift-based body-file extraction
# so grep-against-argv assertions see the whole invocation.
if [[ -n "${GH_ARGS_MARKER:-}" ]]; then
  printf 'called: %s\n' "$*" >> "$GH_ARGS_MARKER"
fi
# Capture --body-file content to GH_BODY_SINK when present (simulation harness
# sets this env var so per-scenario body can be asserted via grep).
if [[ "$*" == *"--body-file"* ]]; then
  body_path=""
  prev=""
  for a in "$@"; do
    if [[ "$prev" == "--body-file" ]]; then
      body_path="$a"
      break
    fi
    prev="$a"
  done
  if [[ -n "$body_path" && -n "${GH_BODY_SINK:-}" && -f "$body_path" ]]; then
    cp "$body_path" "$GH_BODY_SINK" 2>/dev/null || true
  fi
fi
# Drain any leftover stdin so callers don't block on pipes.
if [[ ! -t 0 ]]; then cat >/dev/null; fi
printf 'https://github.com/REPO/pull/0 (dry-run stub)\n'
DRYSTUB
  chmod +x "$DRY_STUB_BIN/gh"
  export PATH="$DRY_STUB_BIN:$PATH"
  log_stderr "INFO: --dry-run active — gh stubbed at $DRY_STUB_BIN/gh"
fi

# ---------------------------------------------------------------------------
# Section A: require_tools — Exit 2 on missing (env problem, not caller-input).
# Resolved at startup so later PATH-shadowing doesn't affect canonical tool
# locations except where intentional (dry-run gh shim, git shim).
# ---------------------------------------------------------------------------
require_tools() {
  local tool
  for tool in jq git sha1sum; do
    command -v "$tool" >/dev/null 2>&1 \
      || die "required tool not found: $tool" 2
  done
  # gh is only strictly required when not in dry-run. In dry-run we stubbed it
  # above; require_tools would otherwise fail on hosts without gh installed.
  if [[ "$DRY_RUN" != "true" && "${CO_EVOLVE_DRY_RUN:-}" != "1" ]]; then
    command -v gh >/dev/null 2>&1 \
      || die "required tool not found: gh (install from https://cli.github.com)" 2
  fi
}
require_tools

# ---------------------------------------------------------------------------
# Section B: Classifier invocation (stdout JSON per Phase 4 D-08 schema).
# Env-var discipline per lab/pel/README.md:27-30 — "never inherit from user
# shell". We set explicitly from parsed argv / defaults.
# ---------------------------------------------------------------------------
export PEL_BOUNCE_STEP="${PEL_BOUNCE_STEP:-unknown}"
export PEL_PHASE_TYPE="${PEL_PHASE_TYPE:-unknown}"
if [[ -n "$FLAVOR_OVERRIDE" ]]; then
  export PEL_FLAVOR_OVERRIDE="$FLAVOR_OVERRIDE"
fi

log_stderr "INFO: invoking classifier for tier=$resolved_tier target=$TARGET"
classifier_rc=0
classifier_json=$(bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "${TASK:-mutate $TARGET}") \
  || classifier_rc=$?
if [[ "$classifier_rc" -ne 0 ]]; then
  die "classifier failed (exit $classifier_rc); see stderr" "$classifier_rc"
fi

flavor=$(printf '%s' "$classifier_json" | jq -r '.flavor')
rationale=$(printf '%s' "$classifier_json" | jq -r '.rationale')
classifier_override=$(printf '%s' "$classifier_json" | jq -r '.override')
log_stderr "INFO: classifier picked flavor=$flavor override=$classifier_override"

# ---------------------------------------------------------------------------
# Section C: PEL_EVAL_REPORT fixture selection.
# Default to the most recent evals report; hard-fail if none available.
# ---------------------------------------------------------------------------
if [[ -z "${PEL_EVAL_REPORT:-}" ]]; then
  # WR-02: `find -printf` is GNU-only; BSD find on macOS silently produces empty
  # output. Match the detection pattern already used in lib/co-evolution.sh
  # list_available_lab_modes (find --version | grep GNU).
  if find --version 2>/dev/null | grep -q GNU; then
    latest_report=$(find "$REPO_ROOT/evals/reports" -maxdepth 2 -name 'raw-scores.json' -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr | head -1 | awk '{print $2}')
  else
    # BSD fallback — stat emits mtime separately. Try BSD `stat -f %m` first,
    # fall back to GNU `stat -c %Y` for unusual hybrid environments.
    latest_report=$(find "$REPO_ROOT/evals/reports" -maxdepth 2 -name 'raw-scores.json' 2>/dev/null \
      | while read -r f; do
          printf '%s %s\n' "$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)" "$f"
        done \
      | sort -nr | head -1 | awk '{print $2}')
  fi
  if [[ -n "$latest_report" && -f "$latest_report" ]]; then
    export PEL_EVAL_REPORT="$latest_report"
    log_stderr "INFO: using PEL_EVAL_REPORT default: $PEL_EVAL_REPORT"
  else
    die "PEL_EVAL_REPORT env var not set and no default report under evals/reports/.

To unblock, choose ONE of:
  1. Run a real eval cycle:
       bash evals/run-evals.sh
     (produces evals/reports/<timestamp>/raw-scores.json that this emitter will then auto-detect)

  2. Use a test fixture to validate the pipeline without running real evals:
       PEL_EVAL_REPORT=tests/fixtures/pr-emitter/template-feedback.json bash co-evolve-bouncer.sh --lab pel-proposer --target ...
     Available tier fixtures: tests/fixtures/pr-emitter/{template,policy,code}-feedback.json

  3. Point at an existing raw-scores.json elsewhere on disk:
       PEL_EVAL_REPORT=/abs/path/to/raw-scores.json bash co-evolve-bouncer.sh --lab pel-proposer --target ..." 1
  fi
fi

# PEL_FEEDBACK is the router-visible alias for PEL_EVAL_REPORT. Set it here
# (right after Section C resolves the path) so Section D.0 can pass it to the
# router — fixes the bug where Section D.0 used to run before PEL_FEEDBACK
# was bound, causing the router to fail silently on every real invocation.
export PEL_FEEDBACK="$PEL_EVAL_REPORT"

# ---------------------------------------------------------------------------
# Section D.0: Adaptive router (v1.3 — picks complexity tier + model).
# Runs BETWEEN Section C (eval-report resolution) and Section D (proposer
# dispatch). Skipped entirely if PEL_NO_ADAPTIVE=1. Best-effort: router
# failure or missing/non-JSON output falls back to current hardcoded behavior
# (PROPOSER_MODEL stays as "opus" default in the proposer adapters).
# ---------------------------------------------------------------------------
if [[ "${PEL_NO_ADAPTIVE:-0}" != "1" ]]; then
  log_stderr "INFO: invoking adaptive router for tier=$resolved_tier"

  # Export inputs the router expects. PEL_FEEDBACK is already set above.
  export TARGET PEL_TIER="$resolved_tier" PEL_FLAVOR="$flavor"

  # Time the router call so telemetry has a real router_duration_ms value.
  router_start_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")

  router_json=""
  if router_json=$(bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null) && [[ -n "$router_json" ]]; then
    router_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    ROUTER_DURATION_MS=$((router_end_ms - router_start_ms))

    chosen_model=$(printf '%s' "$router_json" | jq -r '.model')
    chosen_complexity=$(printf '%s' "$router_json" | jq -r '.complexity')
    fallback_model=$(printf '%s' "$router_json" | jq -r '.fallback_model')
    # I-1: thinking_budget end-to-end. Router emits "harder" on COMPLEX; null
    # otherwise. Proposer adapter prompt-injects "Think harder before
    # responding." when THINKING_BUDGET=harder (no claude CLI flag dep).
    thinking_budget=$(printf '%s' "$router_json" | jq -r '.thinking_budget // "null"')

    # Export PROPOSER_MODEL so the proposer adapter picks it up.
    case "$resolved_tier" in
      template) export PROPOSER_MODEL="$chosen_model" ;;
      code)     export CODE_PROPOSER_MODEL="$chosen_model" ;;
      policy)   ;;  # policy uses Haiku — router decision N/A but logged
    esac
    export FALLBACK_MODEL="$fallback_model"
    if [[ "$thinking_budget" != "null" && -n "$thinking_budget" ]]; then
      export THINKING_BUDGET="$thinking_budget"
    else
      unset THINKING_BUDGET 2>/dev/null || true
    fi

    log_stderr "INFO: router picked complexity=$chosen_complexity model=$chosen_model${THINKING_BUDGET:+ thinking=$THINKING_BUDGET}"
  else
    router_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    ROUTER_DURATION_MS=$((router_end_ms - router_start_ms))
    log_stderr "WARN: router invocation failed; falling back to default model"
    chosen_complexity="UNKNOWN"
    chosen_model="opus"  # the existing default
  fi
else
  log_stderr "INFO: PEL_NO_ADAPTIVE=1 — adaptive router skipped"
  chosen_complexity="DISABLED"
  chosen_model="opus"  # the existing default
  ROUTER_DURATION_MS=0  # router not invoked; record zero so telemetry is honest
fi

# ---------------------------------------------------------------------------
# Section D: Invoke proposer + capture stdout diff.
# Uses a PATH-injected git shim to snapshot state.json before the proposer's
# trap EXIT handler removes the sandbox worktree (D-09). Does NOT modify any
# proposer.sh — this shim lives in the emitter's workdir only.
# ---------------------------------------------------------------------------
EMITTER_WORKDIR=$(mktemp -d -t pel-emitter-work-XXXXXX)
STATE_SNAPSHOT="$EMITTER_WORKDIR/proposer-state.json"
EMITTER_BIN="$EMITTER_WORKDIR/bin"
mkdir -p "$EMITTER_BIN"

# Resolve the real git BEFORE we shadow it with our shim on PATH.
REAL_GIT=$(command -v git)
export REAL_GIT STATE_SNAPSHOT

cat > "$EMITTER_BIN/git" <<'GITSHIM'
#!/usr/bin/env bash
# PATH-injected git shim — intercepts `git [-C ...] worktree remove --force <sandbox>`
# to copy the sandbox's state.json to $STATE_SNAPSHOT before delegation to real git.
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" == "worktree" ]] && [[ "${args[i+1]:-}" == "remove" ]]; then
    last_idx=$((${#args[@]} - 1))
    sbox="${args[last_idx]}"
    if [[ -d "$sbox" && -f "$sbox/state.json" && -n "${STATE_SNAPSHOT:-}" ]]; then
      cp "$sbox/state.json" "$STATE_SNAPSHOT" 2>/dev/null || true
    fi
    break
  fi
done
exec "$REAL_GIT" "$@"
GITSHIM
chmod +x "$EMITTER_BIN/git"

TARGET_ABS="$REPO_ROOT/$TARGET"

proposer_rc=0
case "$resolved_tier" in
  template)
    export PEL_EVAL_REPORT
    export PEL_TEMPLATE_PATH="$TARGET_ABS"
    export PEL_FLAVOR="$flavor"
    proposer_output=$(PATH="$EMITTER_BIN:$PATH" bash "$REPO_ROOT/lab/pel/proposer/template/proposer.sh" "${TASK:-mutate $TARGET}") || proposer_rc=$?
    ;;
  policy)
    export PEL_FEEDBACK="$PEL_EVAL_REPORT"
    export PEL_POLICY_PATH="$TARGET_ABS"
    export PEL_FLAVOR="$flavor"
    # Policy proposer's adapter enforces that the LLM-returned `.policy_path`
    # equals PEL_POLICY_PATH verbatim (Phase 6 adapter.sh:179-183). Callers
    # whose LLM output uses repo-relative paths must supply PEL_POLICY_PATH
    # repo-relative as well. The emitter passes the absolute path here; its
    # stub/real LLM must return the same absolute form.
    proposer_output=$(PATH="$EMITTER_BIN:$PATH" bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "${TASK:-mutate $TARGET}") || proposer_rc=$?
    ;;
  code)
    export PEL_CODE_FEEDBACK="$PEL_EVAL_REPORT"
    export PEL_CODE_TARGET="$TARGET"
    export PEL_FLAVOR="$flavor"
    proposer_output=$(PATH="$EMITTER_BIN:$PATH" bash "$REPO_ROOT/lab/pel/proposer/code/proposer.sh" "${TASK:-mutate $TARGET}") || proposer_rc=$?
    ;;
esac

log_stderr "INFO: proposer exited rc=$proposer_rc (tier=$resolved_tier)"

# ---------------------------------------------------------------------------
# Section E: Failure policy branches (D-15 canary-failed → diagnostic PR;
# D-16 all other non-zero proposer exits → abort).
# ---------------------------------------------------------------------------
CANARY_FAILED_MODE=false
case "$proposer_rc" in
  0) : ;;
  7)
    log_stderr "INFO: proposer exit 7 (canary-failed) — creating [CANARY-FAILED] diagnostic PR (D-15)"
    CANARY_FAILED_MODE=true
    ;;
  *)
    log_stderr "ERROR: proposer exit $proposer_rc (non-canary failure) — aborting, no PR"
    exit "$proposer_rc"
    ;;
esac

# ---------------------------------------------------------------------------
# Section F: Parse state.json snapshot (code tier only — template/policy have
# no state.json contract). Fall back to minimal metadata if snapshot absent.
# ---------------------------------------------------------------------------
diff_content="$proposer_output"
diff_lines=0
diff_budget=0
canary_result="n/a (non-code tier)"

if [[ -f "$STATE_SNAPSHOT" ]]; then
  # WR-08: `jq -r '... // 0'` emits the raw string form — if state.json has a
  # non-numeric value or is corrupted mid-write, `-eq 0` below errors under
  # set -e ([[: "null": syntax error). Normalize via a shell-level numeric
  # check so non-integers fall back to 0 deterministically.
  diff_lines_raw=$(jq -r '.diff_lines // 0' "$STATE_SNAPSHOT" 2>/dev/null || echo 0)
  [[ "$diff_lines_raw" =~ ^[0-9]+$ ]] && diff_lines="$diff_lines_raw" || diff_lines=0
  diff_budget_raw=$(jq -r '.diff_budget // 0' "$STATE_SNAPSHOT" 2>/dev/null || echo 0)
  [[ "$diff_budget_raw" =~ ^[0-9]+$ ]] && diff_budget="$diff_budget_raw" || diff_budget=0
  if [[ "$resolved_tier" == "code" ]]; then
    canary_passed=$(jq -r '.canary.passed // false' "$STATE_SNAPSHOT" 2>/dev/null || echo false)
    # IN-06: `jq -r '... // "none"'` applies the fallback when the left side is
    # null or false. For accepted state.json, `canary.failed_at` is JSON null,
    # so this returns "none". We only read $canary_failed_at below when the
    # canary actually failed (real scenario name present) — so the "none" vs
    # "null" difference is never user-visible.
    canary_failed_at=$(jq -r '.canary.failed_at // "none"' "$STATE_SNAPSHOT" 2>/dev/null || echo none)
    if [[ "$canary_passed" == "true" ]]; then
      canary_result="PASS (all 5 scenarios)"
    else
      canary_result="FAIL at scenario: $canary_failed_at"
    fi
  fi
else
  if [[ "$resolved_tier" == "code" ]]; then
    log_stderr "WARN: state.json snapshot missing; falling back to minimal metadata"
  fi
fi

# Derive diff_lines from the captured diff content when state.json did not
# supply it (template/policy have no state.json; code has it but keep the
# fallback defensive in case the shim misses the interception).
if [[ "$diff_lines" -eq 0 ]] && [[ -n "$diff_content" ]]; then
  diff_lines=$(printf '%s\n' "$diff_content" | grep -cE '^\+[^+]|^-[^-]' || true)
fi

# ---------------------------------------------------------------------------
# Section G: Emitter-owned scoring sandbox (D-08) + apply mutation.
# Skip scoring when CANARY_FAILED_MODE=true (no valid mutation to score).
# Template/code tiers apply unified diffs via `git apply`; policy tier applies
# JSON-delta mutations via `yq -i` per mutation.
# ---------------------------------------------------------------------------
if [[ "$CANARY_FAILED_MODE" == "false" ]]; then
  EMITTER_SANDBOX=$(mktemp -d -t pel-score-sandbox-XXXXXX)
  rmdir "$EMITTER_SANDBOX"  # git worktree wants non-existent target
  if ! "$REAL_GIT" -C "$REPO_ROOT" worktree add --detach "$EMITTER_SANDBOX" HEAD >/dev/null 2>&1; then
    die "emitter scoring sandbox creation failed" 8
  fi
  log_stderr "INFO: emitter sandbox created: $EMITTER_SANDBOX"

  case "$resolved_tier" in
    template|code)
      printf '%s\n' "$diff_content" | (cd "$EMITTER_SANDBOX" && "$REAL_GIT" apply --whitespace=nowarn -) \
        || die "diff failed to apply in emitter sandbox (inconsistent with proposer's apply)" 3
      ;;
    policy)
      policy_sandbox_path="$EMITTER_SANDBOX/$TARGET"
      # F-1: require mikefarah/Go yq v4 (the python yq is not compatible).
      if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -qi mikefarah; then
        die "mikefarah/yq (Go yq v4+) required for policy-tier mutation apply; the python 'yq' is not compatible (install from https://github.com/mikefarah/yq)" 2
      fi
      # Iterate the mutations array, applying each key=new pair via yq -i.
      # Process substitution keeps the loop in the parent shell so `die` exits
      # the whole script, not just the pipeline's subshell (WR-03).
      while IFS= read -r mutation; do
        key=$(printf '%s' "$mutation" | jq -r '.key')
        new_val=$(printf '%s' "$mutation" | jq -r '.new')

        # CR-01 defense-in-depth: re-enforce the 6-knob enumeration from
        # lab/pel/README.md:343-355 at the emitter trust boundary. The
        # policy proposer's bounds.jq enforces this upstream, but the
        # emitter reads attacker-controllable proposer stdout and must
        # not depend on upstream validation.
        case "$key" in
          retry_cap|marker_semantics|writable_phase_default|arbitrate_threshold|max_passes|flavor_weights) ;;
          *) die "policy mutation rejected: key '$key' not in enumerated knob set" 5 ;;
        esac

        # Belt-and-braces: reject shell/yq metacharacters in key (should be
        # impossible given case-match, but cheap to re-assert).
        [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
          || die "policy mutation rejected: key '$key' contains disallowed characters" 5

        # Quote scalar values when they are strings so yq writes them verbatim;
        # numeric/boolean new values flow through unquoted.
        if printf '%s' "$new_val" | jq -e 'type == "number" or type == "boolean"' >/dev/null 2>&1; then
          yq -i ".$key = $new_val" "$policy_sandbox_path" \
            || die "yq mutation failed for key=$key new=$new_val" 3
        else
          # Use yq's env-var indirection (strenv) to bypass shell-quoting the
          # value into the expression — yq's documented safe-interpolation idiom.
          VAL="$new_val" yq -i ".$key = strenv(VAL)" "$policy_sandbox_path" \
            || die "yq mutation failed for key=$key" 3
        fi
      done < <(printf '%s\n' "$diff_content" | jq -c '.mutations[]')
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Section H: Eval cache + scorer invocation + budget (D-05 + D-18 + D-19).
# Cache key = fixture_hash + scripts_hash + worktree_hash + optional dirty_hash.
# Including worktree_hash/dirty_hash is load-bearing: before/after runs share
# REPO_ROOT but have different applied state, so they must hash differently.
# ---------------------------------------------------------------------------
CACHE_DIR="$REPO_ROOT/.co-evolve-cache/evals"
mkdir -p "$CACHE_DIR"

compute_cache_key() {
  local report_path="$1" worktree_dir="$2"
  local scripts_dir="$REPO_ROOT/evals"
  local fixture_hash scripts_hash worktree_hash dirty_hash
  fixture_hash=$(sha1sum "$report_path" | awk '{print $1}')
  # WR-07: hash the full eval-runtime surface, not just *.sh. The scorer reads
  # cases/*.yaml, fixtures/*.json, fixtures/*.md — any of which change the
  # output the cache stores. Maxdepth 3 to cover evals/cases + evals/fixtures.
  scripts_hash=$(find "$scripts_dir" -maxdepth 3 -type f \
    \( -name '*.sh' -o -name '*.yaml' -o -name '*.json' -o -name '*.md' \) \
    -exec sha1sum {} + 2>/dev/null \
    | sort | sha1sum | awk '{print $1}')
  worktree_hash=$("$REAL_GIT" -C "$worktree_dir" rev-parse HEAD 2>/dev/null \
    | awk '{print substr($0,1,12)}')
  worktree_hash="${worktree_hash:-nohead}"
  dirty_hash=""
  if ! "$REAL_GIT" -C "$worktree_dir" diff --quiet 2>/dev/null; then
    dirty_hash=$("$REAL_GIT" -C "$worktree_dir" diff 2>/dev/null | sha1sum | awk '{print substr($1,1,12)}')
  fi
  printf '%s-%s-%s%s' "$fixture_hash" "$scripts_hash" "$worktree_hash" "${dirty_hash:+-$dirty_hash}"
}

BUDGET_CENTS=$(( BUDGET_USD * 100 ))
spent_cents=0
COST_PER_SCORER_RUN_CENTS=50

run_scorer_cached() {
  local label="$1" report_path="$2" worktree_dir="$3"
  local key cache_file
  key=$(compute_cache_key "$report_path" "$worktree_dir")
  cache_file="$CACHE_DIR/$key.json"

  if [[ -f "$cache_file" ]]; then
    log_stderr "INFO: eval cache hit: $label ($cache_file)"
    cat "$cache_file"
    return 0
  fi

  if (( spent_cents + COST_PER_SCORER_RUN_CENTS > BUDGET_CENTS )); then
    die "emitter eval budget exhausted (\$$BUDGET_USD cap; override with --budget)" 6
  fi
  spent_cents=$(( spent_cents + COST_PER_SCORER_RUN_CENTS ))
  log_stderr "INFO: eval cache miss: $label"

  local tmp_out scores_file marker
  tmp_out=$(mktemp)
  # IN-03: `find -newer` compares mtime at 1-second resolution on HFS+ and some
  # NTFS mounts, so a fast scorer run can produce a raw-scores.json in the same
  # second as the marker and `-newer` may miss it. Create a dedicated marker
  # file and age it by 1s BEFORE invoking the scorer so any scorer output is
  # unambiguously newer. The scorer's stdout still goes to $tmp_out (for error
  # diagnosis); the marker is only used as the -newer reference.
  marker=$(mktemp)
  touch -d '1 second ago' "$marker" 2>/dev/null \
    || touch -t "$(date -u -v-1S +%Y%m%d%H%M.%S 2>/dev/null || date -u -d '1 second ago' +%Y%m%d%H%M.%S 2>/dev/null)" "$marker" 2>/dev/null \
    || true
  # Bug #5 fix: run-evals.sh exits 1 whenever ANY case robust-fails (see
  # evals/run-evals.sh:380-386). That's "scored successfully, some cases in
  # the FAIL band" — valid data for the PR body. Only a MISSING raw-scores.json
  # means the scorer itself crashed. Capture exit code, then let the file-
  # presence check decide fatality.
  # Test hook (hermetic gate only): PEL_RUN_EVALS_OVERRIDE points at a stub
  # run-evals.sh so tests can exercise exit-code branches without burning
  # real LLM quota. Never set in production.
  local run_evals_script="$REPO_ROOT/evals/run-evals.sh"
  [[ -n "${PEL_RUN_EVALS_OVERRIDE:-}" ]] && run_evals_script="$PEL_RUN_EVALS_OVERRIDE"
  local run_evals_exit=0
  (cd "$worktree_dir" && bash "$run_evals_script") >"$tmp_out" 2>&1 \
    || run_evals_exit=$?
  scores_file=$(find "$worktree_dir/evals/reports" -maxdepth 2 -name raw-scores.json -newer "$marker" 2>/dev/null | head -1)
  if [[ -z "$scores_file" || ! -f "$scores_file" ]]; then
    log_stderr "ERROR: scorer produced no raw-scores.json for $label (run-evals exit $run_evals_exit)"
    log_stderr "ERROR: scorer stderr tail for $label:"
    tail -30 "$tmp_out" >&2 || true
    rm -f "$tmp_out" "$marker"
    die "scorer did not produce raw-scores.json for $label" 2
  fi
  if (( run_evals_exit != 0 )); then
    log_stderr "INFO: run-evals.sh exit $run_evals_exit for $label — treating as scored-with-fails (raw-scores.json present)"
  fi
  rm -f "$tmp_out" "$marker"
  cp "$scores_file" "$cache_file"
  cat "$cache_file"
}

if [[ "$CANARY_FAILED_MODE" == "false" ]]; then
  log_stderr "INFO: scoring pipeline (before + after)"
  eval_before_json=$(run_scorer_cached "before" "$PEL_EVAL_REPORT" "$REPO_ROOT")
  eval_after_json=$(run_scorer_cached "after"  "$PEL_EVAL_REPORT" "$EMITTER_SANDBOX")

  eval_before_text=$(printf '%s' "$eval_before_json" | jq -c '.aggregate // {}' 2>/dev/null || printf '{}')
  eval_after_text=$(printf  '%s' "$eval_after_json"  | jq -c '.aggregate // {}' 2>/dev/null || printf '{}')

  eval_delta_text=$(printf '%s\n%s' "$eval_before_json" "$eval_after_json" | jq -s -r '
    (.[0].aggregate // {}) as $b | (.[1].aggregate // {}) as $a
    | ([($b | keys[]), ($a | keys[])] | unique) as $keys
    | $keys[] as $k
    | "| \($k) | \($b[$k] // "n/a") | \($a[$k] // "n/a") | \((($a[$k] // 0) - ($b[$k] // 0)) | tostring) |"
  ' 2>/dev/null || printf '| — | — | — | — |')
else
  eval_before_text="(scoring skipped: canary-failed)"
  eval_after_text="(scoring skipped: canary-failed)"
  eval_delta_text="| — | — | — | canary-failed |"
fi

# ---------------------------------------------------------------------------
# Section I: render_pr_body — D-20 bash parameter-expansion substitution.
# No eval. Diff content (which may contain {, }, $, backticks) passes through
# verbatim. For policy tier, pretty-print the JSON delta for readability.
# ---------------------------------------------------------------------------
render_pr_body() {
  local template_path="$REPO_ROOT/lab/pel/pr-emitter/pr-body-template.md"
  local rendered
  rendered=$(cat "$template_path")

  local def_ref=""
  if [[ "$resolved_tier" == "code" ]]; then
    def_ref="Related: closes Phase 7 DEF-07-01 stdout-leak in Phase 8 Plan 01."
  fi

  local rendered_diff="$diff_content"
  if [[ "$resolved_tier" == "policy" ]]; then
    rendered_diff=$(printf '%s' "$diff_content" | jq '.' 2>/dev/null || printf '%s' "$diff_content")
  fi

  # WR-05: compute a fence length longer than any consecutive backtick run in
  # the diff so a malicious proposer cannot escape the fenced block. Default 3
  # (standard ```); scan for longest run of backticks in the content and use
  # max(3, run+1). `grep -oE '\`{3,}' ... | awk '{print length}'` would be
  # fragile with escaped backticks in a heredoc, so we do it inline.
  local max_fence_len=3
  local longest_run
  longest_run=$(printf '%s' "$rendered_diff" | grep -oE '`+' 2>/dev/null | awk '{print length}' | sort -n | tail -1)
  longest_run="${longest_run:-0}"
  if (( longest_run >= max_fence_len )); then
    max_fence_len=$((longest_run + 1))
  fi
  local fence=""
  local i=0
  while (( i < max_fence_len )); do fence="$fence"'`'; i=$((i + 1)); done

  rendered="${rendered//\{\{fence\}\}/$fence}"
  rendered="${rendered//\{\{tier\}\}/$resolved_tier}"
  rendered="${rendered//\{\{target\}\}/$TARGET}"
  rendered="${rendered//\{\{flavor\}\}/$flavor}"
  rendered="${rendered//\{\{classifier_rationale\}\}/$rationale}"
  rendered="${rendered//\{\{diff\}\}/$rendered_diff}"
  rendered="${rendered//\{\{diff_lines\}\}/$diff_lines}"
  rendered="${rendered//\{\{diff_budget\}\}/$diff_budget}"
  rendered="${rendered//\{\{eval_before\}\}/$eval_before_text}"
  rendered="${rendered//\{\{eval_after\}\}/$eval_after_text}"
  rendered="${rendered//\{\{eval_delta\}\}/$eval_delta_text}"
  rendered="${rendered//\{\{canary_result\}\}/$canary_result}"
  rendered="${rendered//\{\{timestamp\}\}/$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  rendered="${rendered//\{\{def_07_01_ref\}\}/$def_ref}"

  printf '%s' "$rendered"
}

# ---------------------------------------------------------------------------
# Section J: Branch name + commit + gh pr create (D-11 + D-13 + D-17).
# ---------------------------------------------------------------------------
if [[ -z "$PR_BRANCH" ]]; then
  short_hash=$(printf '%s' "$diff_content" | sha1sum | awk '{print substr($1,1,7)}')
  if [[ -z "$short_hash" ]]; then
    # sha1sum fallback — use git hash-object on the diff.
    short_hash=$(printf '%s' "$diff_content" | "$REAL_GIT" hash-object --stdin | awk '{print substr($0,1,7)}')
  fi
  PR_BRANCH="pel/$resolved_tier/$short_hash"
fi
# Validate branch name against a git-ref safe subset before handing to gh.
[[ "$PR_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] \
  || die "invalid --pr-branch (must match [A-Za-z0-9][A-Za-z0-9._/-]*): $PR_BRANCH" 1

# If canary-failed skipped sandbox creation, make a fresh sandbox now so we
# have somewhere clean to branch/push from.
if [[ "$CANARY_FAILED_MODE" == "true" ]] && [[ -z "$EMITTER_SANDBOX" ]]; then
  EMITTER_SANDBOX=$(mktemp -d -t pel-score-sandbox-XXXXXX)
  rmdir "$EMITTER_SANDBOX"
  "$REAL_GIT" -C "$REPO_ROOT" worktree add --detach "$EMITTER_SANDBOX" HEAD >/dev/null 2>&1 \
    || die "emitter scoring sandbox creation failed" 8
fi

if [[ "$CANARY_FAILED_MODE" == "true" ]]; then
  PR_TITLE="[CANARY-FAILED] pel($resolved_tier): $TARGET"
else
  # IN-05: `head -c` cuts at bytes and can land mid-UTF-8 codepoint, producing
  # mojibake in the PR title. `cut -c` counts characters. Newline/whitespace
  # collapse happens first so `cut -c1-50` operates on a single-line stream.
  rationale_subject=$(printf '%s' "$rationale" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-50)
  PR_TITLE="pel($resolved_tier): $rationale_subject"
fi

PR_BODY=$(render_pr_body)
EMITTER_BODY_FILE=$(mktemp)
printf '%s' "$PR_BODY" > "$EMITTER_BODY_FILE"

# Create branch + commit + push from the sandbox worktree only (D-12).
(cd "$EMITTER_SANDBOX" && "$REAL_GIT" checkout -b "$PR_BRANCH") >/dev/null 2>&1 \
  || die "failed to create branch $PR_BRANCH in emitter sandbox" 8
# WR-06: record branch name for cleanup trap. Real runs keep the branch so
# `gh pr create` has something to point at; dry-run cleanup will delete it.
BRANCH_CREATED="$PR_BRANCH"
if [[ "$CANARY_FAILED_MODE" == "false" ]]; then
  (
    cd "$EMITTER_SANDBOX"
    "$REAL_GIT" add -A
    "$REAL_GIT" -c user.email=pel@co-evolve -c user.name=pel-emitter \
      commit -m "$PR_TITLE" --no-verify >/dev/null
  ) || die "failed to commit mutation in emitter sandbox" 8
else
  # WR-04: [CANARY-FAILED] branch has no mutation commit (Section G skipped the
  # apply block). GitHub rejects PRs where head and base have no commit
  # difference ("No commits between master and pel/...") — so create an empty
  # diagnostic commit. The substantive diff + state live in the PR body.
  (
    cd "$EMITTER_SANDBOX"
    "$REAL_GIT" -c user.email=pel@co-evolve -c user.name=pel-emitter \
      commit --allow-empty -m "$PR_TITLE" --no-verify >/dev/null
  ) || die "failed to create diagnostic commit in canary-failed sandbox" 8
fi
# Push the branch. In dry-run the gh stub short-circuits PR creation but the
# push still runs against origin — which would fail in hermetic sim. Skip push
# when CO_EVOLVE_DRY_RUN=1 so hermetic simulations don't hit the network.
if [[ "${CO_EVOLVE_DRY_RUN:-}" != "1" ]]; then
  (cd "$EMITTER_SANDBOX" && "$REAL_GIT" push origin "$PR_BRANCH") \
    || die "git push failed before gh pr create" 9
fi

# IN-02: keep gh stderr out of pr_url so our stdout contract (Draft PR URL)
# stays clean when gh emits warnings (auth refresh, rate-limit soft hints) or
# the dry-run stub prints its DRY-RUN: marker. Capture gh stderr to a file,
# forward it to our own stderr (success or failure), and keep pr_url pure.
gh_stderr=$(mktemp)
gh_rc=0
pr_url=$(gh pr create --draft --base master --head "$PR_BRANCH" \
  --title "$PR_TITLE" --body-file "$EMITTER_BODY_FILE" 2>"$gh_stderr") || gh_rc=$?
# Forward gh's stderr to our stderr so callers (and simulations) still see
# DRY-RUN markers / warnings. On failure also cap at 500 bytes for diagnosis.
if [[ "$gh_rc" -ne 0 ]]; then
  log_stderr "gh stderr:"
  head -c 500 "$gh_stderr" >&2
  printf '\n' >&2
  rm -f "$gh_stderr"
  die "gh pr create failed post-scoring" 9
fi
cat "$gh_stderr" >&2
rm -f "$gh_stderr"
# Defensive: trim to first line only in case gh emits trailing whitespace.
pr_url=$(printf '%s' "$pr_url" | head -n1)

printf '%s\n' "$pr_url"
log_stderr "INFO: PR drafted: $pr_url"

# ---------------------------------------------------------------------------
# Section K: Append routing telemetry (best-effort; never fail PEL on a
# logging error). Outer `|| true` ensures telemetry write never propagates
# a failure that could mask a successful PR creation.
# ---------------------------------------------------------------------------
{
  telemetry_dir="$REPO_ROOT/.co-evolve"
  mkdir -p "$telemetry_dir" 2>/dev/null || true
  telemetry_file="$telemetry_dir/router-history.jsonl"

  # I-2: fallback_fired is exported by proposer adapters when they detect
  # the claude --fallback-model signature in stderr. Default false if the
  # proposer adapter didn't set it (e.g., policy tier uses Haiku + no fallback).
  fallback_fired="${FALLBACK_FIRED:-false}"

  # Compute total PEL duration from the start marker set in Section A.0.
  pel_end_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
  PEL_DURATION_MS=$((pel_end_ms - ${PEL_START_MS:-$pel_end_ms}))

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg run_id "${TIMESTAMP:-unknown}" \
    --arg target "$TARGET" \
    --arg pel_tier "$resolved_tier" \
    --arg flavor "$flavor" \
    --arg complexity "${chosen_complexity:-UNKNOWN}" \
    --arg model_chosen "${chosen_model:-opus}" \
    --argjson fallback_fired "$fallback_fired" \
    --argjson router_duration_ms "${ROUTER_DURATION_MS:-0}" \
    --argjson total_pel_duration_ms "${PEL_DURATION_MS:-0}" \
    --arg user_override "${PEL_COMPLEXITY_OVERRIDE:-}" \
    '{
      ts: $ts,
      run_id: $run_id,
      target: $target,
      pel_tier: $pel_tier,
      flavor: $flavor,
      complexity: $complexity,
      model_chosen: $model_chosen,
      fallback_fired: $fallback_fired,
      router_duration_ms: $router_duration_ms,
      total_pel_duration_ms: $total_pel_duration_ms,
      user_override: (if $user_override == "" then null else $user_override end)
    }' >> "$telemetry_file" 2>/dev/null || true
} || true

exit 0
