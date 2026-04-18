#!/usr/bin/env bash
# lab/pel/proposer/template/proposer.sh
# Co-Evolution PEL Template-Tier Mutation Proposer — public entry point (Phase 5 PEL-02).
#
# Consumes an eval-failure report + a target template path + a classifier
# flavor pick. Emits a single-file, single-target, apply-checked unified diff
# to stdout against exactly ONE skills/dev-review/templates/*.md file (plus
# the tests/fixtures/templates/*.md hermetic-testing alias per D-14).
#
# Usage:
#   bash proposer.sh "<optional task hint>"
#
# Argv:
#   $1  OPTIONAL free-form task hint (may be empty per D-04). Coarse bias to
#       the mutation direction; never an override of the flavor pick.
#
# Environment (caller-sets-before-invocation per D-02):
#   PEL_EVAL_REPORT     REQUIRED — readable path to a Phase-2-scorer JSON report
#                       (must resolve within REPO_ROOT per T-05-05)
#   PEL_TEMPLATE_PATH   REQUIRED — readable .md file under skills/dev-review/templates/
#                       or tests/fixtures/templates/ (D-14 hermetic alias)
#   PEL_FLAVOR          REQUIRED — bug-catcher|faster-converger|blind-spot-surfacer|general
#   PROPOSER_MODEL      claude model ID matching ^[a-zA-Z0-9_.-]+$ (default claude-opus-4-7)
#                       Override for debugging only — contract is frozen in v1.2.
#
# Output (stdout):
#   Single unified diff per D-08. Applyable via `git apply --check` at REPO_ROOT.
#   All diagnostics route to stderr.
#
# Exit codes (D-07 fail-fast):
#   0 success
#   1 input validation failure (missing env var, invalid PEL_FLAVOR, invalid
#     PROPOSER_MODEL, path traversal, out-of-prefix PEL_TEMPLATE_PATH)
#   2 claude CLI missing / auth failure / Opus call non-zero / empty response
#   3 malformed diff (not applyable via git apply --check) — D-10
#   4 single-file constraint violation (>1 file or non-template path) — D-09
#
# Self-contained per D-05: the ONLY source statement is the sibling
# `source "$SCRIPT_DIR/adapter.sh"` below. No lib/co-evolution.sh, no
# lab/pel/classifier/**, no runner internals.
#
# Security posture:
#   - T-05-01 (argv/env injection): TASK_HINT captured as opaque data via
#     "${1:-}"; exported to adapter for bash parameter-expansion substitution
#     into prompt.md — never concatenated into a shell command or eval'd.
#   - T-05-02 (diff injection / path escape): D-09 gate rejects diffs outside
#     skills/dev-review/templates/ AND tests/fixtures/templates/ prefixes.
#   - T-05-03 (PROPOSER_MODEL shell-metachar): validate_proposer_model called
#     immediately after source — covers both normal path AND any early exit.
#   - T-05-04 (LLM response as data): diff captured via command substitution
#     (no eval). Validation gate is `git apply --check -` (read-only subprocess).
#   - T-05-05 (fixture path traversal): resolve_path + REPO_ROOT containment
#     check before any file read of caller-supplied paths.

set -euo pipefail

# --- Argv: optional task hint (D-04 — empty allowed) ---
# Do NOT use ${1:?usage} — that would die on missing $1 and violate D-04.
TASK_HINT="${1:-}"

# --- Self-locating: sibling adapter.sh is the only sourced file (D-05) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# REPO_ROOT ascends four levels: template -> proposer -> pel -> lab -> repo root.
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# --- D-03 required-env presence validation: missing = caller bug, die exit 1 ---
# Check presence for ALL three required env vars first (before any filesystem
# or content validation) so error messages route to the user's first mistake.
if [[ -z "${PEL_EVAL_REPORT:-}" ]]; then
  printf "ERROR: PEL_EVAL_REPORT is required and must point to a readable eval-failure JSON file\n" >&2
  exit 1
fi
if [[ -z "${PEL_TEMPLATE_PATH:-}" ]]; then
  printf "ERROR: PEL_TEMPLATE_PATH is required and must point to a readable template .md file\n" >&2
  exit 1
fi
if [[ -z "${PEL_FLAVOR:-}" ]]; then
  printf "ERROR: PEL_FLAVOR is required (one of bug-catcher, faster-converger, blind-spot-surfacer, general)\n" >&2
  exit 1
fi

# --- PEL_FLAVOR whitelist (T-05-01 mitigation) ---
# Pure string check — no filesystem work yet, so bad flavor surfaces before
# any file-readability errors (matches plan verifier expectation for the
# "wrong-flavor + nonexistent-file" negative-path test case).
case "$PEL_FLAVOR" in
  bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
  *)
    printf "ERROR: invalid PEL_FLAVOR: %s (must be one of bug-catcher, faster-converger, blind-spot-surfacer, general)\n" "$PEL_FLAVOR" >&2
    exit 1
    ;;
esac

# --- D-03 readability checks (after presence + flavor validation) ---
if [[ ! -r "$PEL_EVAL_REPORT" ]]; then
  printf "ERROR: PEL_EVAL_REPORT '%s' is not readable\n" "$PEL_EVAL_REPORT" >&2
  exit 1
fi
if [[ ! -r "$PEL_TEMPLATE_PATH" ]]; then
  printf "ERROR: PEL_TEMPLATE_PATH '%s' is not readable\n" "$PEL_TEMPLATE_PATH" >&2
  exit 1
fi

# --- Path resolver helper: portable realpath with python3 fallback ---
# GNU realpath -m exists on Linux + Git Bash; macOS ships BSD realpath (same
# semantics for our use). python3 is a universal fallback (available on all
# three target platforms per CLAUDE.md).
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

# --- T-05-05 path sandboxing: PEL_EVAL_REPORT must resolve inside REPO_ROOT ---
PEL_EVAL_REPORT_ABS=$(resolve_path "$PEL_EVAL_REPORT")
if [[ -z "$PEL_EVAL_REPORT_ABS" ]]; then
  printf "ERROR: could not resolve PEL_EVAL_REPORT path: %s\n" "$PEL_EVAL_REPORT" >&2
  exit 1
fi
case "$PEL_EVAL_REPORT_ABS" in
  "$REPO_ROOT"/*) ;;
  *)
    printf "ERROR: PEL_EVAL_REPORT must resolve to a path inside REPO_ROOT (%s); got: %s\n" "$REPO_ROOT" "$PEL_EVAL_REPORT_ABS" >&2
    exit 1
    ;;
esac

# --- T-05-02 + T-05-05 path sandboxing: PEL_TEMPLATE_PATH ---
PEL_TEMPLATE_PATH_ABS=$(resolve_path "$PEL_TEMPLATE_PATH")
if [[ -z "$PEL_TEMPLATE_PATH_ABS" ]]; then
  printf "ERROR: could not resolve PEL_TEMPLATE_PATH: %s\n" "$PEL_TEMPLATE_PATH" >&2
  exit 1
fi
case "$PEL_TEMPLATE_PATH_ABS" in
  "$REPO_ROOT"/*) ;;
  *)
    printf "ERROR: PEL_TEMPLATE_PATH must resolve to a path inside REPO_ROOT (%s); got: %s\n" "$REPO_ROOT" "$PEL_TEMPLATE_PATH_ABS" >&2
    exit 1
    ;;
esac

# Assert .md suffix (prevents attacks like PEL_TEMPLATE_PATH pointing at a
# shell script under a similar name).
case "$PEL_TEMPLATE_PATH_ABS" in
  *.md) ;;
  *)
    printf "ERROR: PEL_TEMPLATE_PATH must resolve to a .md file under skills/dev-review/templates/ or tests/fixtures/templates/; got: %s\n" "$PEL_TEMPLATE_PATH_ABS" >&2
    exit 1
    ;;
esac

# Assert allowed prefix: skills/dev-review/templates/ OR tests/fixtures/templates/ (D-14)
PEL_TEMPLATE_PATH_REL="${PEL_TEMPLATE_PATH_ABS#"$REPO_ROOT"/}"
case "$PEL_TEMPLATE_PATH_REL" in
  skills/dev-review/templates/*|tests/fixtures/templates/*) ;;
  *)
    printf "ERROR: PEL_TEMPLATE_PATH must resolve to a .md file under skills/dev-review/templates/ or tests/fixtures/templates/; got: %s\n" "$PEL_TEMPLATE_PATH_REL" >&2
    exit 1
    ;;
esac

# --- PROPOSER_MODEL default (D-06) ---
: "${PROPOSER_MODEL:=claude-opus-4-7}"

# --- Load the self-contained adapter (D-05 — sibling only) ---
# The adapter defines die(), log_stderr(), validate_proposer_model(),
# compose_prompt(), invoke_opus(), capture_diff(), run_adapter(), and friends.
# This is the ONLY source statement in the file per D-05 invariant.
# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# --- T-05-03 PROPOSER_MODEL validation (before any claude invocation) ---
# validate_proposer_model is provided by adapter.sh (just sourced).
validate_proposer_model "$PROPOSER_MODEL"

# --- Export env for the adapter's run_adapter() ---
# adapter.sh's compose_prompt uses PEL_TEMPLATE_PATH_REL for the {TEMPLATE_PATH}
# substitution AND reads template CONTENT from PEL_TEMPLATE_PATH_ABS (the
# canonical absolute form).
export TASK_HINT
export PEL_FLAVOR
export PEL_EVAL_REPORT="$PEL_EVAL_REPORT_ABS"
export PEL_TEMPLATE_PATH_ABS
export PEL_TEMPLATE_PATH_REL
export PROPOSER_MODEL

# --- Call adapter: captures Opus diff to a variable ---
# diff_text captures adapter.sh's stdout. command substitution trims trailing
# newlines — that's fine for git apply --check (accepts either form).
diff_text=$(run_adapter)

# --- D-09 gate: single-file + path-prefix check ---
# Parse diff headers. Count unique file targets. If != 1 -> exit 4.
# Extract via awk: lines starting with "--- " or "+++ ", field 2, strip a/|b/
# prefix, sort -u.
file_targets=$(printf "%s\n" "$diff_text" \
  | awk '/^--- / || /^\+\+\+ / { print $2 }' \
  | sed -E 's|^[ab]/||' \
  | grep -v '^/dev/null$' \
  | sort -u)

target_count=$(printf "%s\n" "$file_targets" | grep -c '.' || true)
if [[ "$target_count" -ne 1 ]]; then
  printf "ERROR: D-09 violation: diff touches %s files; v1.2 single-file constraint requires exactly 1\n" "$target_count" >&2
  printf "file targets:\n%s\n" "$file_targets" >&2
  exit 4
fi

single_target=$(printf "%s" "$file_targets" | head -n1)
case "$single_target" in
  skills/dev-review/templates/*|tests/fixtures/templates/*) ;;
  *)
    printf "ERROR: D-09 violation: diff target '%s' is outside allowed template prefixes (skills/dev-review/templates/ or tests/fixtures/templates/)\n" "$single_target" >&2
    exit 4
    ;;
esac

# --- D-10 gate: git apply --check dry-run ---
# Must be run from REPO_ROOT so relative paths in the diff resolve correctly.
apply_err=$(mktemp -t proposer-apply-err-XXXXXX)
# shellcheck disable=SC2064
trap "rm -f \"$apply_err\"" EXIT

if ! printf "%s" "$diff_text" | (cd "$REPO_ROOT" && git apply --check - 2>"$apply_err"); then
  printf "ERROR: D-10 violation: diff is malformed or does not apply cleanly\n" >&2
  printf "git apply --check stderr (first 500 bytes):\n" >&2
  head -c 500 "$apply_err" >&2
  printf "\n" >&2
  exit 3
fi

# --- All gates pass: emit diff to stdout ---
printf "%s" "$diff_text"
exit 0
