#!/usr/bin/env bash
# lab/pel/proposer/code/proposer.sh
# Co-Evolution PEL Code-Tier Mutation Proposer — public entry point (Phase 7 PEL-04).
#
# Consumes an eval-failure report + a target shell file + a classifier flavor
# pick. Emits a single-file, budget-capped, sandbox-validated, canary-proven
# unified diff to stdout against EXACTLY ONE of the three allowlisted shell
# scripts (lib/co-evolution.sh, dev-review/codex/dev-review.sh,
# agent-bouncer/agent-bouncer.sh per D-04).
#
# Usage:
#   bash proposer.sh "<optional task hint>"
#
# Argv:
#   $1  OPTIONAL free-form task hint (may be empty per D-18). Coarse bias to
#       the mutation direction; never an override of the flavor pick.
#
# Environment (caller-sets-before-invocation per D-16):
#   PEL_CODE_FEEDBACK    REQUIRED — readable Phase-2-scorer JSON report
#                        (must resolve within REPO_ROOT per T-07-05)
#   PEL_CODE_TARGET      REQUIRED — relative path on allowlist.txt
#                        (T-07-02 pre-flight allowlist gate)
#   PEL_FLAVOR           REQUIRED — bug-catcher|faster-converger|blind-spot-surfacer|general
#   CODE_PROPOSER_MODEL  claude model ID matching ^[a-zA-Z0-9_.-]+$ (default claude-opus-4-7)
#                        Override for debugging only — contract is frozen in v1.2.
#   DIFF_BUDGET          integer line budget (default 20 per D-06)
#
# Output (stdout):
#   Single unified diff per D-19. Applyable via `git apply --check` at REPO_ROOT,
#   canary-proven safe inside a sandbox worktree. All diagnostics route to stderr.
#
# Side effects:
#   state.json written to the sandbox worktree root per D-20. Phase 8's PR
#   emitter reads this BEFORE cleanup. The sandbox worktree is removed in the
#   trap EXIT handler after the diff is emitted to stdout.
#
# Exit codes (D-21 taxonomy):
#   0 success (diff emitted, canary passed, state.json written)
#   1 input validation failure (missing env var, invalid PEL_FLAVOR, invalid
#     CODE_PROPOSER_MODEL, path traversal, invalid DIFF_BUDGET, non-existent
#     PEL_CODE_TARGET file)
#   2 claude CLI missing / auth failure / Opus call non-zero / empty response
#   3 malformed diff (not applyable via git apply --check) — pre-flight gate 5
#   4 single-file constraint violation (>1 file) — pre-flight gate 2
#   5 allowlist violation (diff target not on allowlist.txt) — pre-flight gate 3
#   6 diff budget exceeded (>DIFF_BUDGET lines changed) — pre-flight gate 4
#   7 canary failed (mutation applied in sandbox but runner broke; state.json
#     has canary.failed_at set)
#   8 sandbox setup failed (git worktree add failed)
#
# Self-contained per D-12: the ONLY source statement is the sibling
# `source "$SCRIPT_DIR/adapter.sh"` below. Zero import of the runner helpers,
# the sibling classifier subtree, or any other directory outside this one.
#
# Security posture:
#   - T-07-01 (argv/env injection via $1): TASK_HINT="${1:-}" captures $1 as
#     opaque data; exported to adapter for bash parameter-expansion into
#     prompt.md — never concatenated into a shell command or eval'd. PEL_FLAVOR
#     passes a strict whitelist case match. PEL_CODE_TARGET is validated against
#     allowlist.txt via grep -Fxq before any use.
#   - T-07-02 (diff injection targeting frozen paths): D-07 pre-flight gates
#     parse diff headers + allowlist-check the single target BEFORE sandbox
#     creation; a diff targeting a non-allowlisted path exits 5 without touching
#     disk.
#   - T-07-03 (CODE_PROPOSER_MODEL shell-metachar): validate_proposer_model
#     called immediately after sourcing adapter.sh. Rejects anything outside
#     [A-Za-z0-9_.-]+.
#   - T-07-04 (LLM response as data): diff captured via command substitution
#     (no eval). Five pre-flight gates run before any mutation reaches the
#     sandbox; canary runs AFTER application to verify runner integrity.
#   - T-07-05 (fixture path traversal): resolve_path + REPO_ROOT containment
#     check on PEL_CODE_FEEDBACK before any file read.
#   - T-07-06 (sandbox escape): git worktree provides filesystem isolation;
#     canary runs inside sandbox; live checkout is never cd'd into for mutation.

set -euo pipefail

# --- Argv: optional task hint (D-18 — empty allowed) -------------------------
# Do NOT use ${1:?usage} — that would die on missing $1 and violate D-18.
TASK_HINT="${1:-}"

# --- Self-locating: sibling adapter.sh is the only sourced file (D-12) -------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# REPO_ROOT ascends four levels: code -> proposer -> pel -> lab -> repo root.
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# --- D-17 required-env presence validation: missing = caller bug, die exit 1 --
# Check presence for ALL three required env vars first (before any filesystem
# or content validation) so error messages route to the user's first mistake.
if [[ -z "${PEL_CODE_FEEDBACK:-}" ]]; then
  printf "ERROR: PEL_CODE_FEEDBACK is required and must point to a readable eval-failure JSON file\n" >&2
  exit 1
fi
if [[ -z "${PEL_CODE_TARGET:-}" ]]; then
  printf "ERROR: PEL_CODE_TARGET is required and must be a relative path on lab/pel/proposer/code/allowlist.txt\n" >&2
  exit 1
fi
if [[ -z "${PEL_FLAVOR:-}" ]]; then
  printf "ERROR: PEL_FLAVOR is required (one of bug-catcher, faster-converger, blind-spot-surfacer, general)\n" >&2
  exit 1
fi

# --- PEL_FLAVOR whitelist (T-07-01 mitigation) -------------------------------
# Pure string check — no filesystem work yet, so bad flavor surfaces before
# any file-readability errors.
case "$PEL_FLAVOR" in
  bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
  *)
    printf "ERROR: invalid PEL_FLAVOR: %s (must be one of bug-catcher, faster-converger, blind-spot-surfacer, general)\n" "$PEL_FLAVOR" >&2
    exit 1
    ;;
esac

# --- PEL_CODE_TARGET allowlist check (D-04, D-05, T-07-02) --------------------
# The allowlist IS the frozen-surface enforcement mechanism. grep -Fxq requires
# an exact full-line match; any variant path (trailing slash, absolute form,
# ../ relative) fails the gate. This runs BEFORE any filesystem check on
# PEL_CODE_FEEDBACK so a frozen-target attempt surfaces as an allowlist
# violation, not a stale-feedback-path error.
if ! grep -Fxq "$PEL_CODE_TARGET" "$SCRIPT_DIR/allowlist.txt"; then
  printf "ERROR: PEL_CODE_TARGET '%s' is not on the code-tier allowlist (lab/pel/proposer/code/allowlist.txt)\n" "$PEL_CODE_TARGET" >&2
  exit 1
fi

# --- D-17 readability check on PEL_CODE_FEEDBACK (after allowlist) -----------
if [[ ! -r "$PEL_CODE_FEEDBACK" ]]; then
  printf "ERROR: PEL_CODE_FEEDBACK '%s' is not readable\n" "$PEL_CODE_FEEDBACK" >&2
  exit 1
fi

# --- Path resolver helper: portable realpath with python3 fallback ------------
# GNU realpath -m exists on Linux + Git Bash; macOS ships BSD realpath (same
# semantics for our use). python3 is a universal fallback per CLAUDE.md.
resolve_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p"
  else
    # Last-resort: cd + pwd (requires path to exist; our inputs must be
    # readable so this is OK in practice).
    (cd "$(dirname "$p")" 2>/dev/null && printf "%s/%s\n" "$(pwd)" "$(basename "$p")")
  fi
}

# --- T-07-05 path sandboxing: PEL_CODE_FEEDBACK must resolve inside REPO_ROOT -
PEL_CODE_FEEDBACK_ABS=$(resolve_path "$PEL_CODE_FEEDBACK")
if [[ -z "$PEL_CODE_FEEDBACK_ABS" ]]; then
  printf "ERROR: could not resolve PEL_CODE_FEEDBACK path: %s\n" "$PEL_CODE_FEEDBACK" >&2
  exit 1
fi
case "$PEL_CODE_FEEDBACK_ABS" in
  "$REPO_ROOT"/*) ;;
  *)
    printf "ERROR: PEL_CODE_FEEDBACK must resolve to a path inside REPO_ROOT (%s); got: %s\n" "$REPO_ROOT" "$PEL_CODE_FEEDBACK_ABS" >&2
    exit 1
    ;;
esac

# PEL_CODE_TARGET must be a readable file inside REPO_ROOT. Compose the
# absolute path from REPO_ROOT + relative target (the allowlist stores
# repo-relative paths; accepting anything else is an escape hatch we do not
# want).
PEL_CODE_TARGET_ABS="$REPO_ROOT/$PEL_CODE_TARGET"
if [[ ! -r "$PEL_CODE_TARGET_ABS" ]]; then
  printf "ERROR: PEL_CODE_TARGET '%s' is not readable at %s\n" "$PEL_CODE_TARGET" "$PEL_CODE_TARGET_ABS" >&2
  exit 1
fi

# --- Defaults for overrideable env vars ---------------------------------------
: "${CODE_PROPOSER_MODEL:=claude-opus-4-7}"
: "${DIFF_BUDGET:=20}"

# Validate DIFF_BUDGET is a positive integer (not a shell-injection vector).
if ! [[ "$DIFF_BUDGET" =~ ^[0-9]+$ ]] || (( DIFF_BUDGET < 1 )); then
  printf "ERROR: invalid DIFF_BUDGET: %s (must be a positive integer)\n" "$DIFF_BUDGET" >&2
  exit 1
fi

# --- Load the self-contained adapter (D-12 — sibling only) -------------------
# The adapter defines die(), log_stderr(), validate_proposer_model(),
# compose_prompt(), invoke_opus(), capture_diff(), run_adapter(), and friends.
# This is the ONLY source statement in the file per D-12 invariant.
# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# --- T-07-03 CODE_PROPOSER_MODEL validation (before any claude invocation) ---
# validate_proposer_model is provided by adapter.sh (just sourced).
validate_proposer_model "$CODE_PROPOSER_MODEL"

# --- Export env for the adapter's run_adapter() -------------------------------
# adapter.sh's compose_prompt uses PEL_CODE_TARGET for the {CODE_TARGET}
# substitution AND reads code CONTENT from PEL_CODE_TARGET_ABS (the canonical
# absolute form).
export TASK_HINT
export PEL_FLAVOR
export PEL_CODE_FEEDBACK="$PEL_CODE_FEEDBACK_ABS"
export PEL_CODE_TARGET
export PEL_CODE_TARGET_ABS
export CODE_PROPOSER_MODEL
export DIFF_BUDGET

# --- Call adapter: captures Opus diff to a variable ---------------------------
# diff_text captures adapter.sh's stdout. command substitution trims trailing
# newlines — fine for git apply --check (accepts either form).
diff_text=$(run_adapter)

# ============================================================================
# D-07 pre-flight gates: parse -> single-file -> allowlist -> budget -> apply
# ============================================================================

# --- Gate 1: parse diff headers, extract file targets -------------------------
# Extract via awk: lines starting with "--- " or "+++ ", field 2, strip a/|b/
# prefix, sort -u.
file_targets=$(printf "%s\n" "$diff_text" \
  | awk '/^--- / || /^\+\+\+ / { print $2 }' \
  | sed -E 's|^[ab]/||' \
  | grep -v '^/dev/null$' \
  | sort -u)

target_count=$(printf "%s\n" "$file_targets" | grep -c '.' || true)

# --- Gate 2: single-file check (exit 4) --------------------------------------
if [[ "$target_count" -ne 1 ]]; then
  printf "ERROR: single-file constraint violation: diff touches %s files; v1.2 requires exactly 1\n" "$target_count" >&2
  printf "file targets:\n%s\n" "$file_targets" >&2
  exit 4
fi

single_target=$(printf "%s" "$file_targets" | head -n1)

# --- Gate 3: allowlist check on extracted target (exit 5) --------------------
# The LLM's emitted diff target must itself be on the allowlist. Defense in
# depth: even though PEL_CODE_TARGET was already allowlist-checked, a misbehaved
# Opus could ignore the prompt and emit a diff against a different file.
if ! grep -Fxq "$single_target" "$SCRIPT_DIR/allowlist.txt"; then
  printf "ERROR: allowlist violation: diff targets '%s' which is not on the code-tier allowlist\n" "$single_target" >&2
  exit 5
fi

# Also confirm the LLM's target matches the caller's PEL_CODE_TARGET (extra
# belt). A drift here is a prompt-follow failure, not strictly a security
# issue, but we want proposer output to be predictable.
if [[ "$single_target" != "$PEL_CODE_TARGET" ]]; then
  printf "ERROR: allowlist violation: diff targets '%s' but PEL_CODE_TARGET was '%s'\n" "$single_target" "$PEL_CODE_TARGET" >&2
  exit 5
fi

# --- Gate 4: diff budget check (exit 6) --------------------------------------
# Count lines starting with + or - in the diff body, EXCLUDING the --- and +++
# header lines (and @@ hunk headers, which don't start with + or -).
diff_lines=$(printf "%s\n" "$diff_text" \
  | awk '/^[+-]/ && !/^(---|\+\+\+)/ { n++ } END { print n+0 }')

if (( diff_lines > DIFF_BUDGET )); then
  printf "ERROR: diff budget exceeded: %s lines changed (budget: %s)\n" "$diff_lines" "$DIFF_BUDGET" >&2
  exit 6
fi

# --- Gate 5: git apply --check dry-run (exit 3) ------------------------------
# Must be run from REPO_ROOT so relative paths in the diff resolve correctly.
apply_err=$(mktemp -t proposer-code-apply-err-XXXXXX)
# shellcheck disable=SC2064
trap "rm -f \"$apply_err\"" EXIT

# Use --whitespace=nowarn so Windows Git Bash (which typically has
# autocrlf=true) doesn't reject LF-only proposer diffs against CRLF on-disk
# files.
if ! printf "%s\n" "$diff_text" | (cd "$REPO_ROOT" && git apply --check --whitespace=nowarn - 2>"$apply_err"); then
  printf "ERROR: malformed diff: does not apply cleanly via git apply --check\n" >&2
  printf "git apply --check stderr (first 500 bytes):\n" >&2
  head -c 500 "$apply_err" >&2
  printf "\n" >&2
  exit 3
fi

# ============================================================================
# Sandbox setup (D-01, D-02, D-03): git worktree add HEAD, trap cleanup
# ============================================================================

# Create the sandbox path. git worktree add requires a non-existent target,
# so we use mktemp -u to generate the path without creating it.
SANDBOX_PATH=$(mktemp -d "${TMPDIR:-/tmp}/pel-code-sandbox-XXXXXX")
# mktemp -d creates the directory; remove it so `git worktree add` can create
# its own.
rmdir "$SANDBOX_PATH"

# Build the canary failure guard early so cleanup runs on any exit path.
# The cleanup invokes `git worktree remove --force` (via git -C REPO_ROOT) to
# tear down the sandbox created by `git worktree add` above.
cleanup_sandbox() {
  # Defense in depth: `git worktree remove --force` AND rm -rf, either on its
  # own is insufficient (worktree remove fails if the metadata is inconsistent;
  # rm -rf leaves git's bookkeeping dangling).
  git -C "$REPO_ROOT" worktree remove --force "$SANDBOX_PATH" 2>/dev/null || true
  rm -rf "$SANDBOX_PATH" 2>/dev/null || true
  rm -f "$apply_err" 2>/dev/null || true
}
# shellcheck disable=SC2064
trap "cleanup_sandbox" EXIT

# D-01, D-02: create detached-HEAD worktree from current state. Fail-closed
# per D-01: if git worktree add fails, die exit 8 (never fall back to
# mutating the live checkout).
if ! git -C "$REPO_ROOT" worktree add --detach "$SANDBOX_PATH" HEAD >/dev/null 2>"$apply_err"; then
  printf "ERROR: sandbox setup failed: git worktree add returned non-zero\n" >&2
  printf "git worktree stderr (first 500 bytes):\n" >&2
  head -c 500 "$apply_err" >&2
  printf "\n" >&2
  exit 8
fi

# ============================================================================
# Apply diff in sandbox (D-03) — live checkout is never touched
# ============================================================================
# If this fails (shouldn't happen since --check passed, but defense in depth),
# die exit 3.
if ! printf "%s\n" "$diff_text" | (cd "$SANDBOX_PATH" && git apply --whitespace=nowarn - 2>"$apply_err"); then
  printf "ERROR: sandbox apply failed (diff passed pre-flight but git apply in sandbox failed)\n" >&2
  printf "git apply stderr (first 500 bytes):\n" >&2
  head -c 500 "$apply_err" >&2
  printf "\n" >&2
  exit 3
fi

# ============================================================================
# Canary (D-08, D-09, D-10)
# ============================================================================
log_stderr "INFO: running canary against sandbox $SANDBOX_PATH"

# Run canary with +e (don't let set -e abort on scenario failure — we need the
# exit code for state.json). Map canary exit 1-5 -> scenario name for
# diagnostics + state.json.
canary_rc=0
bash "$SCRIPT_DIR/canary.sh" "$SANDBOX_PATH" >&2 || canary_rc=$?

# Timestamp for state.json (ISO-8601 UTC).
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if (( canary_rc != 0 )); then
  # Map canary exit code to scenario name.
  case "$canary_rc" in
    1) failed_scenario="source-survives" ;;
    2) failed_scenario="helper-signatures" ;;
    3) failed_scenario="agent-bounce" ;;
    4) failed_scenario="dev-review-plan-only" ;;
    5) failed_scenario="one-eval-case" ;;
    *) failed_scenario="unknown" ;;
  esac

  # Write state.json with canary-failed outcome per D-20. Phase 8's PR emitter
  # reads this BEFORE cleanup — so we write it before the trap removes the
  # worktree.
  cat > "$SANDBOX_PATH/state.json" <<STATE_JSON
{
  "outcome": "canary-failed",
  "exit_code": 7,
  "target": "$PEL_CODE_TARGET",
  "flavor": "$PEL_FLAVOR",
  "diff_lines": $diff_lines,
  "diff_budget": $DIFF_BUDGET,
  "canary": {"passed": false, "scenarios": 5, "failed_at": "$failed_scenario"},
  "sandbox_path": "$SANDBOX_PATH",
  "timestamp": "$timestamp"
}
STATE_JSON

  printf "ERROR: canary failed at scenario '%s' (canary exit %s); proposer exit 7\n" "$failed_scenario" "$canary_rc" >&2
  exit 7
fi

# ============================================================================
# State.json with outcome=accepted (D-20)
# ============================================================================
cat > "$SANDBOX_PATH/state.json" <<STATE_JSON
{
  "outcome": "accepted",
  "exit_code": 0,
  "target": "$PEL_CODE_TARGET",
  "flavor": "$PEL_FLAVOR",
  "diff_lines": $diff_lines,
  "diff_budget": $DIFF_BUDGET,
  "canary": {"passed": true, "scenarios": 5, "failed_at": null},
  "sandbox_path": "$SANDBOX_PATH",
  "timestamp": "$timestamp"
}
STATE_JSON

# ============================================================================
# Emit diff to stdout (D-19) — trap EXIT cleans up the worktree after
# ============================================================================
printf "%s\n" "$diff_text"
exit 0
