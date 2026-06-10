#!/usr/bin/env bash
# evals/lib/co-evolution-evals.sh
# Shared library for the Bash eval harness.
# Sourced by: evals/score-run.sh, evals/run-evals.sh, evals/compare-reports.sh, evals/tests/scorer-verification.sh.
# Port of: runners/codex-ps/evals/lib/{Yaml,Report,Fixture}.ps1 (per BASH-EVAL-01, Plan 02-01).
# Dependencies: jq, yq (mikefarah/Go flavor) — see ensure_jq / ensure_yq.
#
# NOTE: no `set -euo pipefail` at top — this file is SOURCED; callers set strictness.
#
# Public API:
#   log, die                                                -- logging helpers (guarded; defined iff not already present)
#   ensure_jq, ensure_yq                                    -- dependency guards (fatal if binary missing)
#   read_yaml_file <path>                                   -- prints JSON on stdout
#   merge_yaml_defaults <defaults_path> <case_path>         -- prints merged JSON (case wins, PS Merge-HashtablesDeep semantics)
#   render_report <template_path> <key=value ...>           -- substitutes {{KEY}} tokens, prints rendered markdown on stdout
#   atomic_json_write <jq_program> <input_path> <out_path>  -- jq to mktemp; mv on success; rm on failure
#   atomic_json_write_stdin <jq_program> <out_path>         -- same, reading stdin (for jq -n / --slurpfile style)
#   load_json_or_sentinel <path> <sentinel_var_name>        -- sets sentinel to 'missing'|'unparseable'|'' (continue-on-bad-verdict)

# Idempotent-source guard: only define log/die if caller hasn't already
# (lib/co-evolution.sh defines the same helpers; library may be sourced in
# either order, or sourced twice, without redefinition errors under set -u).
if ! declare -F log >/dev/null 2>&1; then
  log() {
    local message="${1:-}"
    if [[ -n "${LOG_FILE:-}" ]]; then
      echo "$message" | tee -a "$LOG_FILE"
    else
      echo "$message"
    fi
  }
fi

if ! declare -F die >/dev/null 2>&1; then
  die() {
    local message="${1:-Fatal error}"
    log "ERROR: $message"
    # F-6: honor an optional exit-code (2nd arg); default to 1 when omitted.
    exit "${2:-1}"
  }
fi

# ---------------------------------------------------------------------------
# Dependency guards (T-02-01-05 mitigation upstream: keep YAML/JSON parsing in
# dedicated tools; never eval content as shell)
# ---------------------------------------------------------------------------

ensure_yq() {
  # F-1: delegate to the shared guard in lib/co-evolution.sh (in scope at runtime
  # via the eval-harness callers, which source both libs); rejects the python yq.
  require_mikefarah_yq
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 || die "jq not found. Install jq: 'scoop install jq' (Windows), 'brew install jq' (macOS), 'apt install jq' (Linux)."
}

# ---------------------------------------------------------------------------
# YAML operations (wrap mikefarah/yq; yq output flows only through jq, never shell)
# ---------------------------------------------------------------------------

# read_yaml_file <path> -> JSON on stdout.
# T-02-01-01 mitigation: yq exits non-zero on malformed YAML; we die with a clear
# message rather than letting partial output flow downstream.
read_yaml_file() {
  local path="${1:?read_yaml_file requires a path}"
  ensure_yq
  [[ -f "$path" ]] || die "YAML file not found: $path"
  yq -o=json "$path" || die "Failed to parse YAML: $path"
}

# merge_yaml_defaults <defaults_path> <case_path> -> merged JSON on stdout.
# Deep-merge: defaults under, case over. jq's `*` operator matches PS
# Merge-HashtablesDeep semantics (Yaml.ps1:48-75): hashtables merged recursively,
# non-hashtable values replaced wholesale (lists NOT concatenated).
merge_yaml_defaults() {
  local defaults_path="${1:?merge_yaml_defaults requires a defaults path}"
  local case_path="${2:?merge_yaml_defaults requires a case path}"
  ensure_yq
  ensure_jq
  [[ -f "$defaults_path" ]] || die "Defaults YAML not found: $defaults_path"
  [[ -f "$case_path" ]]     || die "Case YAML not found: $case_path"
  local defaults_json case_json
  defaults_json=$(read_yaml_file "$defaults_path") || die "merge_yaml_defaults: defaults parse failed"
  case_json=$(read_yaml_file "$case_path")         || die "merge_yaml_defaults: case parse failed"
  jq -n --argjson d "$defaults_json" --argjson c "$case_json" '$d * $c' \
    || die "merge_yaml_defaults: jq deep-merge failed"
}

# ---------------------------------------------------------------------------
# Report rendering (PS Report.ps1 analog)
# NOTE: token syntax is {{KEY}} (double braces) — differs from lib/co-evolution.sh::fill_template
# which uses {KEY} single-brace. Do NOT unify — PS template is canonical and uses double braces.
# T-02-01-04 mitigation: substitute one key at a time with pure parameter expansion;
# do NOT re-scan the rendered output for more placeholders (prevents value-content
# containing "{{KEY}}" from being re-substituted in a second pass).
# ---------------------------------------------------------------------------

render_report() {
  local template_path="${1:?render_report requires a template path}"
  shift
  [[ -f "$template_path" ]] || die "Template file not found: $template_path"
  local rendered
  rendered=$(<"$template_path")
  local pair key value
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    # Parameter expansion: literal {{KEY}} -> value.
    # Braces escaped with backslash so they match literally (not globbed).
    rendered="${rendered//\{\{$key\}\}/$value}"
  done
  printf '%s' "$rendered"
}

# ---------------------------------------------------------------------------
# Atomic JSON writes (PS Set-Content analog; mimics lib/co-evolution.sh:870-895)
# Per D-03 jq is mandatory; drop the `command -v jq` conditional guard, keep
# the mktemp -> mv atomicity. T-02-01-03 mitigation: mktemp creates 0600-perm
# random-named tmp file. T-02-01-06 mitigation: capture jq stderr into $err and
# report it in the die message so silent failures are impossible.
# ---------------------------------------------------------------------------

atomic_json_write() {
  local jq_program="${1:?atomic_json_write requires a jq program}"
  local input_path="${2:?atomic_json_write requires an input path}"
  local output_path="${3:?atomic_json_write requires an output path}"
  ensure_jq
  [[ -f "$input_path" ]] || die "atomic_json_write: input not found: $input_path"
  local tmp err
  tmp=$(mktemp)
  # 2>&1 inside command substitution conflates stdout and stderr; acceptable
  # on the error path (jq failure means we abort; there is no meaningful stdout
  # to preserve). Simpler than a separate tmp.err file; matches the plan spec.
  if err=$(jq "$jq_program" "$input_path" 2>&1 >"$tmp"); then
    mv "$tmp" "$output_path"
    return 0
  fi
  rm -f "$tmp"
  die "atomic_json_write: jq failed: $err"
}

atomic_json_write_stdin() {
  local jq_program="${1:?atomic_json_write_stdin requires a jq program}"
  local output_path="${2:?atomic_json_write_stdin requires an output path}"
  ensure_jq
  local tmp err
  tmp=$(mktemp)
  if err=$(jq "$jq_program" 2>&1 >"$tmp"); then
    mv "$tmp" "$output_path"
    return 0
  fi
  rm -f "$tmp"
  die "atomic_json_write_stdin: jq failed: $err"
}

# ---------------------------------------------------------------------------
# Verdict-or-sentinel loader (score-run.ps1:89-97 analog).
# Scorer needs continue-on-bad-verdict semantics: malformed verdict.json must
# NOT abort the run — set a sentinel and let the scorer emit verify_accuracy=FAIL.
# Caller passes the NAME of a variable; we assign to it via `printf -v`.
# Values: 'missing' (file absent), 'unparseable' (not valid JSON), '' (ok).
# ---------------------------------------------------------------------------

load_json_or_sentinel() {
  local path="${1:?load_json_or_sentinel requires a path}"
  local sentinel_var="${2:?load_json_or_sentinel requires a sentinel variable name}"
  ensure_jq
  if [[ ! -f "$path" ]]; then
    printf -v "$sentinel_var" 'missing'
    return 0
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    printf -v "$sentinel_var" 'unparseable'
    return 0
  fi
  printf -v "$sentinel_var" ''
  return 0
}

# ---------------------------------------------------------------------------
# Self-test entry point (runs only when invoked directly, not when sourced).
# Detection: ${BASH_SOURCE[0]} == $0 means "executed", not "sourced".
# Strict-mode is set INSIDE this block so sourcing the library stays clean.
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --self-test)
      set -euo pipefail
      SELFTEST_FAILURES=0
      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
      REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
      selftest_fail() { echo "FAIL: $1" >&2; SELFTEST_FAILURES=$((SELFTEST_FAILURES + 1)); }

      # Test 1: ensure_jq / ensure_yq succeed on a system where both are installed.
      ensure_jq || selftest_fail "ensure_jq"
      ensure_yq || selftest_fail "ensure_yq"

      # Test 2: read_yaml_file on defaults.yaml should expose the canonical min_word_count threshold (120).
      json=$(read_yaml_file "$REPO_ROOT/evals/cases/defaults.yaml")
      echo "$json" | jq -e '.expectations.plan_quality.min_word_count == 120' >/dev/null \
        || selftest_fail "read_yaml_file: min_word_count mismatch"

      # Test 3: merge_yaml_defaults preserves inherited defaults AND adds case-specific keys.
      # 01-trivial-task overrides min_word_count to 40, so the merged shape should show 40,
      # but min_jaccard (untouched in the case) should remain the defaults value (0.5).
      # Adds coverage for the "case wins + defaults survive in untouched keys" contract.
      merged=$(merge_yaml_defaults "$REPO_ROOT/evals/cases/defaults.yaml" "$REPO_ROOT/evals/cases/01-trivial-task.yaml")
      echo "$merged" | jq -e '.expectations.plan_quality.min_word_count == 40' >/dev/null \
        || selftest_fail "merge_yaml_defaults: case override lost (expected min_word_count=40)"
      echo "$merged" | jq -e '.expectations.execution_fidelity.min_jaccard == 0.5' >/dev/null \
        || selftest_fail "merge_yaml_defaults: defaults lost for untouched key (expected min_jaccard=0.5)"
      echo "$merged" | jq -e 'has("id")' >/dev/null \
        || selftest_fail "merge_yaml_defaults: case id missing"

      # Test 4: render_report substitutes supplied tokens, leaves unsupplied ones literal.
      out=$(render_report "$REPO_ROOT/evals/report-template.md" TIMESTAMP=2026-04-17)
      echo "$out" | grep -q '2026-04-17' || selftest_fail "render_report: TIMESTAMP not substituted"
      if echo "$out" | grep -q '{{TIMESTAMP}}'; then
        selftest_fail "render_report: literal {{TIMESTAMP}} still present"
      fi
      # Unsubstituted placeholder remains literal (explicit-only expansion semantics).
      echo "$out" | grep -q '{{CASE_TABLE}}' || selftest_fail "render_report: untouched placeholders should remain literal"

      # Test 5a: atomic_json_write fails closed on invalid input (YAML isn't JSON).
      # Suppress both stdout and stderr of the subshell — we're asserting the failure
      # path; the ERROR line from `die` would otherwise pollute self-test stdout.
      tmpout=$(mktemp)
      rm -f "$tmpout"  # delete; function should not recreate on failure
      if ( atomic_json_write '.expectations' "$REPO_ROOT/evals/cases/defaults.yaml" "$tmpout" ) >/dev/null 2>&1; then
        selftest_fail "atomic_json_write: should die on YAML input (jq needs JSON)"
      fi
      [[ ! -f "$tmpout" ]] || selftest_fail "atomic_json_write: output file leaked on failure path"

      # Test 5b: atomic_json_write succeeds on valid JSON input.
      tmpin=$(mktemp)
      echo '{"a":1,"b":2}' > "$tmpin"
      tmpout=$(mktemp)
      atomic_json_write '.a' "$tmpin" "$tmpout" || selftest_fail "atomic_json_write: failed on valid input"
      [[ "$(cat "$tmpout")" == "1" ]] || selftest_fail "atomic_json_write: content mismatch"
      rm -f "$tmpin" "$tmpout"

      # Test 5c: atomic_json_write_stdin round-trip.
      tmpout=$(mktemp)
      echo '{"x":42}' | atomic_json_write_stdin '.x' "$tmpout" || selftest_fail "atomic_json_write_stdin: failed on valid input"
      [[ "$(cat "$tmpout")" == "42" ]] || selftest_fail "atomic_json_write_stdin: content mismatch"
      rm -f "$tmpout"

      # Test 6: load_json_or_sentinel transitions.
      # 6a: YAML is not valid JSON -> unparseable.
      unparseable_state=''
      load_json_or_sentinel "$REPO_ROOT/evals/cases/defaults.yaml" unparseable_state
      [[ "$unparseable_state" == "unparseable" ]] || selftest_fail "load_json_or_sentinel: YAML should trigger unparseable sentinel (got '$unparseable_state')"
      # 6b: Missing file -> missing.
      tmp_missing="$REPO_ROOT/does-not-exist-selftest-$$.json"
      missing_state='pre'
      load_json_or_sentinel "$tmp_missing" missing_state
      [[ "$missing_state" == "missing" ]] || selftest_fail "load_json_or_sentinel: missing path should trigger missing sentinel (got '$missing_state')"
      # 6c: Valid JSON -> empty sentinel.
      tmp_valid=$(mktemp)
      echo '{"ok":true}' > "$tmp_valid"
      valid_state='pre'
      load_json_or_sentinel "$tmp_valid" valid_state
      [[ -z "$valid_state" ]] || selftest_fail "load_json_or_sentinel: valid JSON should leave sentinel empty (got '$valid_state')"
      rm -f "$tmp_valid"

      if (( SELFTEST_FAILURES == 0 )); then
        echo "ALL SELFTESTS PASSED"
        exit 0
      fi
      echo "FAILED: $SELFTEST_FAILURES selftest(s)" >&2
      exit 1
      ;;
    *)
      echo "usage: $0 --self-test" >&2
      exit 2
      ;;
  esac
fi
